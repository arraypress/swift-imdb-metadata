//
//  Rating.swift
//  IMDbMetadata
//

import Foundation

/// A title's IMDb rating, out of the local index.
public struct Rating: Sendable, Codable, Equatable {

    /// The `tt…` id of the title being rated.
    public let id: String
    /// 1.0–10.0, to one decimal place — which is all IMDb publishes.
    public let average: Double
    /// How many people voted. A high score on few votes means little.
    public let votes: Int

    public init(id: String, average: Double, votes: Int) {
        self.id = id
        self.average = average
        self.votes = votes
    }
}
