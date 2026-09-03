//
//  IMDbError.swift
//  IMDbMetadata
//

import Foundation

public enum IMDbError: Error, LocalizedError, Equatable {

    /// Nothing matched.
    case noResults(String)
    /// The endpoint answered with something other than 200.
    case http(Int)
    /// The response no longer looks like what this reads.
    case unreadable(String)
    /// A ratings lookup before the index has been downloaded.
    case noIndex
    /// The archive did not inflate.
    case corruptDownload(String)
    /// Not a `tt…` id.
    case notATitleID(String)

    public var errorDescription: String? {
        switch self {
        case let .noResults(query): return "nothing on IMDb for \(query)"
        case let .http(code): return "IMDb suggestion API returned \(code)"
        case let .unreadable(what): return "could not read \(what) from IMDb's response"
        case .noIndex: return "the ratings index has not been downloaded yet"
        case let .corruptDownload(why): return "the ratings archive did not inflate: \(why)"
        case let .notATitleID(value): return "\(value) is not an IMDb title id (tt followed by digits)"
        }
    }
}
