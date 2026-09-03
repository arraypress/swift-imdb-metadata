//
//  IMDbMetadataTests.swift
//  IMDbMetadata
//
//  Offline. The network shape is exercised by decoding recorded responses;
//  the index is built from a synthetic TSV whose answers are known.
//

import Compression
import Foundation
import XCTest
@testable import IMDbMetadata

final class SuggestionURLTests: XCTestCase {

    func testTheShardLetterIsALiteral() {
        // Measured against the live endpoint: x, d and z return identical
        // results for the same query, so it is not a shard key. A literal
        // avoids inventing rules for a query starting with a digit, an
        // accent or a quote.
        XCTAssertEqual(Suggestion.url(for: "dune")?.absoluteString,
                       "https://v3.sg.media-imdb.com/suggestion/x/dune.json")
        XCTAssertEqual(Suggestion.url(for: "9")?.path, "/suggestion/x/9.json")
    }

    func testScopesPickDifferentPaths() {
        XCTAssertEqual(Suggestion.url(for: "x", scope: .titles)?.path, "/suggestion/titles/x/x.json")
        XCTAssertEqual(Suggestion.url(for: "x", scope: .names)?.path, "/suggestion/names/x/x.json")
    }

    func testAwkwardQueriesAreEncoded() {
        let url = Suggestion.url(for: "spider-man: no way home")
        XCTAssertEqual(url?.absoluteString.hasSuffix("spider-man%3A%20no%20way%20home.json"), true)
        XCTAssertNotNil(Suggestion.url(for: "l'auberge espagnole"))
        XCTAssertNotNil(Suggestion.url(for: "amélie"))
    }

    func testAnEmptyQueryHasNoURL() {
        XCTAssertNil(Suggestion.url(for: ""))
        XCTAssertNil(Suggestion.url(for: "   "))
    }
}

final class SuggestionDecodingTests: XCTestCase {

    /// A recorded entry, keys and all, exactly as IMDb returns them.
    private let breakingBad: [String: Any] = [
        "id": "tt0903747", "l": "Breaking Bad", "q": "TV series", "qid": "tvSeries",
        "rank": 42, "s": "Bryan Cranston, Aaron Paul", "y": 2008, "yr": "2008-2013",
        "i": ["imageUrl": "https://m.media-amazon.com/images/M/x.jpg", "height": 1500, "width": 1021],
    ]

    func testATitleDecodes() throws {
        let title = try XCTUnwrap(Suggestion.title(from: breakingBad))
        XCTAssertEqual(title.id, "tt0903747")
        XCTAssertEqual(title.kind, .tvSeries)
        XCTAssertEqual(title.year, 2008)
        XCTAssertEqual(title.endYear, 2013)
        XCTAssertEqual(title.url.absoluteString, "https://www.imdb.com/title/tt0903747/")
    }

    func testARunningSeriesHasNoEndYear() {
        // "2008-" is what IMDb sends for something still going, so the end
        // is optional even when the range is present.
        var running = breakingBad
        running["yr"] = "2008-"
        XCTAssertNil(Suggestion.title(from: running)?.endYear)
    }

    func testAFilmHasNoRangeAtAll() {
        var film = breakingBad
        film["yr"] = nil
        film["qid"] = "movie"
        let title = Suggestion.title(from: film)
        XCTAssertEqual(title?.kind, .movie)
        XCTAssertNil(title?.endYear)
    }

    func testAnUnknownTypeIsNotDropped() {
        // A type IMDb invents later must still come back as a result, or the
        // tool quietly loses titles.
        var odd = breakingBad
        odd["qid"] = "interactiveHologram"
        XCTAssertEqual(Suggestion.title(from: odd)?.kind, .other)
    }

    func testAPersonIsNotATitleAndViceVersa() {
        let person: [String: Any] = ["id": "nm3154303", "l": "Timothée Chalamet",
                                     "s": "Actor, A Complete Unknown (2024)", "rank": 281]
        XCTAssertNil(Suggestion.title(from: person), "an nm id is not a title")
        XCTAssertNil(Suggestion.person(from: breakingBad), "a tt id is not a person")
        XCTAssertEqual(Suggestion.person(from: person)?.url.absoluteString,
                       "https://www.imdb.com/name/nm3154303/")
    }

    func testAnEntryWithNoIdIsSkipped() {
        XCTAssertNil(Suggestion.title(from: ["l": "Nameless"]))
    }
}

final class RatingsIndexTests: XCTestCase {

    private let tsv = """
        tconst\taverageRating\tnumVotes
        tt0000001\t5.7\t2229
        tt0000002\t5.4\t324
        tt0111161\t9.3\t3000000
        tt1160419\t8.5\t900000
        tt9916880\t7.5\t12
        """

    private func index(from text: String) throws -> RatingsIndex {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ratings-\(UUID().uuidString).idx")
        try RatingsIndex.build(from: Data(text.utf8)).write(to: file)
        return try RatingsIndex(at: file)
    }

    func testLookupsFindTheRightRating() throws {
        let index = try index(from: tsv)
        XCTAssertEqual(index.count, 5)
        XCTAssertEqual(try index.rating(for: "tt0111161"), Rating(id: "tt0111161", average: 9.3, votes: 3_000_000))
        XCTAssertEqual(try index.rating(for: "tt0000002")?.average, 5.4)
        XCTAssertEqual(try index.rating(for: "tt9916880")?.votes, 12)
    }

    func testATitleWithNoRatingIsNilNotAnError() throws {
        // Normal: IMDb does not publish a rating below five votes.
        XCTAssertNil(try index(from: tsv).rating(for: "tt0000003"))
    }

    func testARatingWithNoDecimalPointIsRead() throws {
        // IMDb writes 10 rather than 10.0 for a perfect score.
        let index = try index(from: "h\th\th\ntt0000010\t10\t50\n")
        XCTAssertEqual(try index.rating(for: "tt0000010")?.average, 10)
    }

    func testSomethingThatIsNotATitleIDIsRefused() throws {
        let index = try index(from: tsv)
        XCTAssertThrowsError(try index.rating(for: "nm3154303"))
        XCTAssertThrowsError(try index.rating(for: "The Shawshank Redemption"))
    }

    func testTheFilesLexicographicOrderIsResorted() throws {
        // IMDb ships the dump sorted as TEXT, so tt10466872 comes before
        // tt9916880 — 1 before 9. The binary search needs numeric order.
        // An earlier version trusted the file and dropped what looked out of
        // place, which threw away 42% of the dataset and made Dune's rating
        // simply vanish. Every row must survive, in numeric order.
        let index = try index(from: """
            tconst\taverageRating\tnumVotes
            tt0000001\t5.7\t2229
            tt10466872\t7.0\t100
            tt1160419\t8.0\t1087868
            tt9916880\t7.5\t12
            """)
        XCTAssertEqual(index.count, 4)
        XCTAssertEqual(try index.rating(for: "tt9916880")?.average, 7.5)
        XCTAssertEqual(try index.rating(for: "tt1160419")?.votes, 1_087_868)
        XCTAssertEqual(try index.rating(for: "tt10466872")?.average, 7)
        XCTAssertEqual(try index.rating(for: "tt0000001")?.average, 5.7)
    }

    func testAMissingIndexSaysSoRatherThanReportingNoRatings() {
        XCTAssertThrowsError(try RatingsIndex(at: URL(fileURLWithPath: "/nowhere/ratings.idx"))) { error in
            guard case IMDbError.noIndex = error else { return XCTFail("got \(error)") }
        }
    }

    func testMalformedLinesAreSkippedNotFatal() throws {
        let index = try index(from: "h\th\th\ngarbage\ntt0000004\t4.0\t8\n\ntt0000006\tnotanumber\n")
        XCTAssertEqual(try index.rating(for: "tt0000004")?.average, 4)
    }
}

final class GzipTests: XCTestCase {

    /// Wraps raw deflate in a gzip container, the way a server does.
    private func gzip(_ text: String, filename: String? = nil) -> Data {
        let source = Data(text.utf8)
        var deflated = Data(count: source.count + 1024)
        let written = deflated.withUnsafeMutableBytes { destination in
            source.withUnsafeBytes { from in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!,
                                          source.count + 1024,
                                          from.bindMemory(to: UInt8.self).baseAddress!, source.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        var out = Data([0x1f, 0x8b, 0x08, filename == nil ? 0x00 : 0x08, 0, 0, 0, 0, 0, 0x03])
        if let filename { out.append(Data(filename.utf8)); out.append(0) }
        out.append(deflated.prefix(written))
        var crc = UInt32(0).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        var size = UInt32(source.count).littleEndian
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }

    func testItInflates() throws {
        let text = String(repeating: "tt0000001\t5.7\t2229\n", count: 500)
        XCTAssertEqual(String(decoding: try Gzip.inflate(gzip(text)), as: UTF8.self), text)
    }

    func testTheOptionalFilenameFieldIsSkipped() throws {
        // IMDb's dumps carry one, and a fixed ten-byte header would inflate
        // garbage instead of failing.
        let text = String(repeating: "row\n", count: 400)
        XCTAssertEqual(String(decoding: try Gzip.inflate(gzip(text, filename: "title.ratings.tsv")), as: UTF8.self), text)
    }

    func testAnHTMLErrorPageIsRefusedRatherThanInflated() {
        // What a caller actually gets when the dataset host is down: a 200
        // with an error page. Without the magic-number check it would come
        // back as an empty index.
        let page = Data("<!doctype html><html><body>503</body></html>".utf8)
        XCTAssertThrowsError(try Gzip.inflate(page)) { error in
            guard case IMDbError.corruptDownload = error else { return XCTFail("got \(error)") }
        }
    }

    func testATruncatedArchiveIsRefused() {
        let full = gzip(String(repeating: "row\n", count: 400))
        XCTAssertThrowsError(try Gzip.inflate(full.prefix(full.count / 2)))
    }
}
