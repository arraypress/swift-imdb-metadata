//
//  Title.swift
//  IMDbMetadata
//

import Foundation

/// A film, show or game.
public struct Title: Sendable, Codable, Equatable, Identifiable {

    /// The `tt…` id — the one Plex, Radarr, Trakt and Letterboxd all key on.
    public let id: String
    public let title: String
    public let kind: TitleKind
    /// First year. Nil for something announced but undated.
    public let year: Int?
    /// Last year of a finished series. Nil for a film, or one still running.
    public let endYear: Int?
    /// Top-billed names, as IMDb writes them: "Timothée Chalamet, Zendaya".
    public let stars: String?
    /// Poster, at IMDb's own size. Nil when there isn't one.
    public let posterURL: URL?
    /// IMDb's popularity rank. Lower is more popular; useful for ordering
    /// results, meaningless as an absolute.
    public let rank: Int?

    /// The page a person would open.
    public var url: URL { URL(string: "https://www.imdb.com/title/\(id)/")! }

    public init(id: String, title: String, kind: TitleKind, year: Int?, endYear: Int?,
                stars: String?, posterURL: URL?, rank: Int?) {
        self.id = id
        self.title = title
        self.kind = kind
        self.year = year
        self.endYear = endYear
        self.stars = stars
        self.posterURL = posterURL
        self.rank = rank
    }
}

/// A person.
public struct Person: Sendable, Codable, Equatable, Identifiable {

    /// The `nm…` id.
    public let id: String
    public let name: String
    /// What IMDb leads with: "Actor, A Complete Unknown (2024)".
    public let knownFor: String?
    public let photoURL: URL?
    public let rank: Int?

    public var url: URL { URL(string: "https://www.imdb.com/name/\(id)/")! }

    public init(id: String, name: String, knownFor: String?, photoURL: URL?, rank: Int?) {
        self.id = id
        self.name = name
        self.knownFor = knownFor
        self.photoURL = photoURL
        self.rank = rank
    }
}
