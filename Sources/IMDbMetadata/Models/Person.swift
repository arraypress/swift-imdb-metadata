//
//  Person.swift
//  IMDbMetadata
//

//

import Foundation

/// A person.
public struct Person: Sendable, Codable, Equatable, Identifiable {

    /// The `nm…` id.
    public let id: String
    /// Their name as IMDb spells it.
    public let name: String
    /// What IMDb leads with: "Actor, A Complete Unknown (2024)".
    public let knownFor: String?
    /// Their headshot, when IMDb has one.
    public let photoURL: URL?
    /// Position in the list this came from, counting from 1.
    public let rank: Int?

    /// Their IMDb page.
    public var url: URL { URL(string: "https://www.imdb.com/name/\(id)/")! }

    public init(id: String, name: String, knownFor: String?, photoURL: URL?, rank: Int?) {
        self.id = id
        self.name = name
        self.knownFor = knownFor
        self.photoURL = photoURL
        self.rank = rank
    }
}
