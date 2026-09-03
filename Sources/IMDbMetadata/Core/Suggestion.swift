//
//  Suggestion.swift
//  IMDbMetadata
//
//  IMDb's own type-ahead endpoint. Keyless, and the only part of IMDb that
//  answers without an account.
//

import Foundation

/// Searching IMDb.
///
/// This is the endpoint imdb.com's own search box calls, so it is fast, it is
/// keyless, and it returns the `tt…` ids that Plex, Radarr, Trakt and
/// Letterboxd all key on — which TMDB's ids are not.
///
/// It is a *type-ahead*: eight results, ranked by popularity, with no paging
/// and no filters. For a deep catalogue search with cast, crew and budgets,
/// `tmdb-fetch` is the other tool, and it needs a free key.
public enum Suggestion {

    /// What to look for.
    public enum Scope: String, Sendable, CaseIterable {
        /// Titles and people together.
        case all
        case titles
        case names

        var pathComponent: String {
            switch self {
            case .all: return ""
            case .titles: return "titles/"
            case .names: return "names/"
            }
        }
    }

    /// Titles matching a query — or, given a `tt…` id, that exact title.
    ///
    /// Passing an id works because the endpoint indexes them, which is how
    /// this library looks a title up without scraping a page.
    public static func titles(
        _ query: String,
        session: URLSession = .shared
    ) async throws -> [Title] {
        try await entries(query, scope: .titles, session: session).compactMap(title(from:))
    }

    /// People matching a query.
    public static func names(
        _ query: String,
        session: URLSession = .shared
    ) async throws -> [Person] {
        try await entries(query, scope: .names, session: session).compactMap(person(from:))
    }

    /// Both, in IMDb's own order of relevance.
    public static func everything(
        _ query: String,
        session: URLSession = .shared
    ) async throws -> (titles: [Title], people: [Person]) {
        let found = try await entries(query, scope: .all, session: session)
        return (found.compactMap(title(from:)), found.compactMap(person(from:)))
    }

    // MARK: - The request

    /// The URL for a query.
    ///
    /// The single letter after `suggestion` looks like a shard key and is
    /// **ignored** — measured: `x`, `d` and `z` return identical results for
    /// the same query. A literal `x` is used rather than the first character,
    /// which would need its own rules for a query starting with a digit,
    /// an accent or a quote.
    public static func url(for query: String, scope: Scope = .all) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://v3.sg.media-imdb.com/suggestion/\(scope.pathComponent)x/\(encoded).json")
    }

    private static func entries(
        _ query: String,
        scope: Scope,
        session: URLSession
    ) async throws -> [[String: Any]] {
        guard let url = url(for: query, scope: scope) else { throw IMDbError.noResults(query) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw IMDbError.http(http.statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["d"] as? [[String: Any]] else {
            throw IMDbError.unreadable("the results list")
        }
        return entries
    }

    // MARK: - Decoding

    /// IMDb's abbreviated keys, spelled out.
    ///
    /// `id` · `l` title · `q` long type · `qid` type · `y` year · `yr` year
    /// range · `s` stars or credit · `rank` popularity · `i` image.
    static func title(from entry: [String: Any]) -> Title? {
        guard let id = entry["id"] as? String, id.hasPrefix("tt"),
              let name = entry["l"] as? String else { return nil }
        /// `yr` is "2008-2013" for a finished series and "2008-" for a
        /// running one, so the end is optional even when the range is there.
        let years = (entry["yr"] as? String)?.split(separator: "-", omittingEmptySubsequences: false)
        return Title(
            id: id,
            title: name,
            kind: TitleKind(qid: entry["qid"] as? String),
            year: entry["y"] as? Int,
            endYear: years.flatMap { $0.count > 1 ? Int($0[1]) : nil },
            stars: entry["s"] as? String,
            posterURL: ((entry["i"] as? [String: Any])?["imageUrl"] as? String).flatMap(URL.init(string:)),
            rank: entry["rank"] as? Int)
    }

    static func person(from entry: [String: Any]) -> Person? {
        guard let id = entry["id"] as? String, id.hasPrefix("nm"),
              let name = entry["l"] as? String else { return nil }
        return Person(
            id: id,
            name: name,
            knownFor: entry["s"] as? String,
            photoURL: ((entry["i"] as? [String: Any])?["imageUrl"] as? String).flatMap(URL.init(string:)),
            rank: entry["rank"] as? Int)
    }
}
