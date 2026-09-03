//
//  TitleKind.swift
//  IMDbMetadata
//

import Foundation

/// What a title is.
///
/// IMDb's own vocabulary, kept verbatim rather than collapsed to film/TV: the
/// difference between a series, a mini-series and an episode is exactly what
/// a caller sorting a library needs, and `video` versus `movie` is the
/// difference between a straight-to-video release and a cinema one.
public enum TitleKind: String, Sendable, Codable, CaseIterable {
    case movie
    case tvSeries
    case tvMiniSeries
    case tvEpisode
    case tvSpecial
    case tvMovie
    case tvShort
    case short
    case video
    case videoGame
    case musicVideo
    case podcastSeries
    case podcastEpisode
    /// Anything IMDb starts returning that this does not name yet.
    case other

    /// Maps IMDb's `qid`, which is not always one of the documented values.
    public init(qid: String?) {
        self = qid.flatMap { TitleKind(rawValue: $0) } ?? .other
    }

    /// Whether this is something you watch rather than play or listen to.
    public var isWatchable: Bool {
        self != .videoGame && self != .podcastSeries && self != .podcastEpisode
    }
}
