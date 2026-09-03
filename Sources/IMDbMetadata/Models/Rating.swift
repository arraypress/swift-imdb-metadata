//
//  Rating.swift
//  IMDbMetadata
//

import Foundation

/// A title's IMDb rating, out of the local index.
public struct Rating: Sendable, Codable, Equatable {

    public let id: String
    /// 1.0–10.0, to one decimal place — which is all IMDb publishes.
    public let average: Double
    public let votes: Int

    public init(id: String, average: Double, votes: Int) {
        self.id = id
        self.average = average
        self.votes = votes
    }
}
