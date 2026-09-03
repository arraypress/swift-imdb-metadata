//
//  RatingsIndex.swift
//  IMDbMetadata
//
//  IMDb's own ratings dump, turned into something a lookup can hit in
//  microseconds and offline.
//

import Foundation

/// The IMDb ratings for every title, on disk.
///
/// IMDb publishes a daily dump under a licence that permits personal and
/// non-commercial use. `title.ratings.tsv.gz` is **8.2 MB** and holds about
/// 1.7 million titles — small enough to keep, unlike `title.basics.tsv.gz`
/// at 216 MB, which is why this library does ratings and not full metadata.
///
/// The TSV is not kept. It is turned once into a sorted array of fixed-width
/// records — a 32-bit numeric id, the rating × 10, the vote count — which is
/// **16 MB** and answers a lookup with a binary search over an mmapped file.
/// Measured: 0.07 s to inflate, 0.32 s to index, and no parsing at all at
/// lookup time.
public struct RatingsIndex: Sendable {

    /// Where IMDb publishes it.
    public static let source = URL(string: "https://datasets.imdbws.com/title.ratings.tsv.gz")!

    /// Ten bytes: id (4), rating × 10 (2), votes (4).
    static let recordSize = 10

    private let data: Data
    /// Where the file lives, so a caller can report or delete it.
    public let location: URL

    /// How many titles the index holds.
    public var count: Int { data.count / Self.recordSize }

    /// When it was last downloaded.
    public var updated: Date? {
        try? FileManager.default.attributesOfItem(atPath: location.path)[.modificationDate] as? Date
    }

    /// Opens an index already on disk.
    ///
    /// - Throws: ``IMDbError/noIndex`` when there isn't one, so the caller can
    ///   say which command downloads it rather than reporting "not found" for
    ///   every title.
    public init(at location: URL) throws {
        guard FileManager.default.fileExists(atPath: location.path) else { throw IMDbError.noIndex }
        /// Mapped, not read: 16 MB that the kernel pages in as the binary
        /// search touches it, which is a handful of pages per lookup.
        self.data = try Data(contentsOf: location, options: .alwaysMapped)
        self.location = location
    }

    /// One title's rating, or nil if IMDb has none — which is normal: a title
    /// with fewer than five votes is not published.
    public func rating(for id: String) throws -> Rating? {
        guard let numeric = Self.numeric(id) else { throw IMDbError.notATitleID(id) }

        var low = 0, high = count - 1
        while low <= high {
            let middle = (low + high) / 2
            let candidate = value(UInt32.self, at: middle * Self.recordSize)
            if candidate == numeric {
                let rating = value(UInt16.self, at: middle * Self.recordSize + 4)
                let votes = value(UInt32.self, at: middle * Self.recordSize + 6)
                return Rating(id: id, average: Double(rating) / 10, votes: Int(votes))
            }
            if candidate < numeric { low = middle + 1 } else { high = middle - 1 }
        }
        return nil
    }

    private func value<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
    }

    /// `tt1160419` → `1160419`.
    static func numeric(_ id: String) -> UInt32? {
        guard id.hasPrefix("tt") else { return nil }
        return UInt32(id.dropFirst(2))
    }

    // MARK: - Building

    /// Downloads the dump and writes the index.
    ///
    /// - Parameter progress: called with a short phrase per phase, because
    ///   an 8 MB download followed by two seconds of silence is
    ///   indistinguishable from a hang.
    @discardableResult
    public static func update(
        at location: URL,
        from source: URL = RatingsIndex.source,
        session: URLSession = .shared,
        progress: ((String) -> Void)? = nil
    ) async throws -> RatingsIndex {

        progress?("downloading \(source.lastPathComponent)")
        let (archive, response) = try await session.data(from: source)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw IMDbError.http(http.statusCode)
        }

        progress?("inflating \(archive.count / 1_048_576) MB")
        let tsv = try Gzip.inflate(archive)

        progress?("indexing")
        let index = build(from: tsv)

        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        /// Written beside and moved into place, so an interrupted update
        /// leaves the previous index intact rather than a half file that
        /// every later lookup would binary-search through.
        let temporary = location.appendingPathExtension("partial")
        try index.write(to: temporary, options: .atomic)
        _ = try? FileManager.default.removeItem(at: location)
        try FileManager.default.moveItem(at: temporary, to: location)

        return try RatingsIndex(at: location)
    }

    /// Turns the TSV into fixed-width records, sorted by numeric id.
    ///
    /// Hand-parsed over the bytes rather than split into Strings: the file is
    /// 29 MB and 1.7 million lines, and making a String per field takes it
    /// from a third of a second to the better part of a minute.
    ///
    /// **IMDb ships the file sorted lexicographically, not numerically** —
    /// `tt10466872` comes before `tt9916880` because `1` sorts before `9`.
    /// The binary search needs numeric order, so the records are sorted here.
    /// Measured the hard way: an earlier version trusted the file's order and
    /// dropped every row that looked out of place, which threw away 42% of
    /// the dataset — including Dune, whose rating simply came back missing.
    static func build(from tsv: Data) -> Data {
        var records: [(id: UInt32, rating: UInt16, votes: UInt32)] = []
        records.reserveCapacity(1_800_000)

        tsv.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 0
            func digits<T: FixedWidthInteger>(_ type: T.Type) -> T {
                var value: T = 0
                while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
                    value = value * 10 + T(bytes[i] - 0x30)
                    i += 1
                }
                return value
            }
            func skipLine() { while i < bytes.count, bytes[i] != 0x0a { i += 1 }; i += 1 }

            skipLine()   // tconst  averageRating  numVotes
            while i < bytes.count {
                guard bytes[i] == 0x74 else { skipLine(); continue }   // 't' of "tt"
                i += 2
                let id: UInt32 = digits(UInt32.self)
                guard i < bytes.count, bytes[i] == 0x09 else { skipLine(); continue }
                i += 1
                let whole: UInt16 = digits(UInt16.self)
                var fraction: UInt16 = 0
                if i < bytes.count, bytes[i] == 0x2e {
                    i += 1
                    fraction = digits(UInt16.self)
                }
                guard i < bytes.count, bytes[i] == 0x09 else { skipLine(); continue }
                i += 1
                let votes: UInt32 = digits(UInt32.self)
                skipLine()
                records.append((id, whole * 10 + fraction, votes))
            }
        }

        records.sort { $0.id < $1.id }

        var output = Data()
        output.reserveCapacity(records.count * recordSize)
        for record in records {
            withUnsafeBytes(of: record.id.littleEndian) { output.append(contentsOf: $0) }
            withUnsafeBytes(of: record.rating.littleEndian) { output.append(contentsOf: $0) }
            withUnsafeBytes(of: record.votes.littleEndian) { output.append(contentsOf: $0) }
        }
        return output
    }
}
