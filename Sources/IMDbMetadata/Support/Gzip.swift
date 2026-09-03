//
//  Gzip.swift
//  IMDbMetadata
//
//  Inflating a .gz with what the system already has.
//

import Compression
import Foundation

/// Gzip decompression through Apple's `Compression` framework.
///
/// `COMPRESSION_ZLIB` is raw DEFLATE, so the gzip wrapper is stripped here:
/// a ten-byte header, optional extra/name/comment fields selected by the flag
/// byte, then the deflate stream, then an eight-byte trailer. No dependency
/// and no `Process`; 8.6 MB inflates to 29.9 MB in about 0.07 s.
public enum Gzip {

    /// Inflates one gzip member.
    public static func inflate(_ data: Data) throws -> Data {
        var index = data.startIndex

        func byte() throws -> UInt8 {
            guard index < data.endIndex else { throw IMDbError.corruptDownload("ran off the end of the header") }
            defer { index = data.index(after: index) }
            return data[index]
        }

        guard data.count > 18 else { throw IMDbError.corruptDownload("too short to be a gzip file") }
        guard try byte() == 0x1f, try byte() == 0x8b else {
            throw IMDbError.corruptDownload("no gzip magic — the server may have sent an error page")
        }
        guard try byte() == 0x08 else { throw IMDbError.corruptDownload("not deflate-compressed") }

        let flags = try byte()
        index = data.index(index, offsetBy: 6)                 // mtime, XFL, OS
        if flags & 0b0000_0100 != 0 {                          // FEXTRA
            let length = Int(try byte()) | Int(try byte()) << 8
            index = data.index(index, offsetBy: length)
        }
        if flags & 0b0000_1000 != 0 { while try byte() != 0 {} }   // FNAME
        if flags & 0b0001_0000 != 0 { while try byte() != 0 {} }   // FCOMMENT
        if flags & 0b0000_0010 != 0 { index = data.index(index, offsetBy: 2) }   // FHCRC

        let trailerStart = data.index(data.endIndex, offsetBy: -8)
        guard index < trailerStart else { throw IMDbError.corruptDownload("no deflate stream") }
        let deflated = data[index..<trailerStart]

        /// The trailer's ISIZE is the uncompressed length modulo 2^32 —
        /// exactly the buffer to allocate, so nothing is guessed or grown.
        /// A member over 4 GB would wrap; IMDb's are 30 MB.
        let size = data[data.index(data.endIndex, offsetBy: -4)...]
            .enumerated()
            .reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        guard size > 0 else { throw IMDbError.corruptDownload("the archive says it is empty") }

        var output = Data(count: Int(size))
        let written = output.withUnsafeMutableBytes { destination -> Int in
            deflated.withUnsafeBytes { source -> Int in
                guard let to = destination.bindMemory(to: UInt8.self).baseAddress,
                      let from = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(to, Int(size), from, deflated.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == Int(size) else {
            throw IMDbError.corruptDownload("inflated \(written) bytes, the trailer promised \(size)")
        }
        return output
    }
}
