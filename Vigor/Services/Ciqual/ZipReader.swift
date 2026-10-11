import Compression
import Foundation

/// Lecteur ZIP minimal (méthodes « stocké » et « deflate ») pour ouvrir l'archive XML de la table CIQUAL
/// sans dépendance externe. Le deflate est décodé par le framework Compression d'Apple.
enum ZipReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError {
        case notAZip, unsupported(String), corrupted

        var errorDescription: String? {
            switch self {
            case .notAZip: "Ce fichier n'est pas une archive ZIP."
            case .unsupported(let name): "Compression non prise en charge pour \(name)."
            case .corrupted: "Archive ZIP endommagée."
            }
        }
    }

    static func entries(in bytes: [UInt8]) throws -> [Entry] {
        // Fin du répertoire central : signature 0x06054b50, cherchée depuis la fin.
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var index = bytes.count - 22
        let lowerBound = max(0, bytes.count - 65_557)
        while index >= lowerBound {
            if u32(bytes, index) == 0x0605_4b50 { eocd = index; break }
            index -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(u16(bytes, eocd + 10))
        var offset = Int(u32(bytes, eocd + 16))

        var result: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x0201_4b50 else { throw ZipError.corrupted }
            let method = u16(bytes, offset + 10)
            let compressed = Int(u32(bytes, offset + 20))
            let uncompressed = Int(u32(bytes, offset + 24))
            let nameLength = Int(u16(bytes, offset + 28))
            let extraLength = Int(u16(bytes, offset + 30))
            let commentLength = Int(u16(bytes, offset + 32))
            let localOffset = Int(u32(bytes, offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.corrupted }
            let nameBytes = Array(bytes[(offset + 46)..<(offset + 46 + nameLength)])
            let name = String(decoding: nameBytes, as: UTF8.self)
            result.append(Entry(name: name, method: method, compressedSize: compressed,
                                uncompressedSize: uncompressed, localHeaderOffset: localOffset))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    static func extract(_ entry: Entry, from bytes: [UInt8]) throws -> Data {
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, u32(bytes, header) == 0x0403_4b50 else { throw ZipError.corrupted }
        let nameLength = Int(u16(bytes, header + 26))
        let extraLength = Int(u16(bytes, header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { throw ZipError.corrupted }

        switch entry.method {
        case 0:
            return Data(bytes[start..<(start + entry.compressedSize)])
        case 8:
            var output = [UInt8](repeating: 0, count: max(entry.uncompressedSize, 1))
            let written = bytes.withUnsafeBufferPointer { source -> Int in
                output.withUnsafeMutableBufferPointer { destination -> Int in
                    compression_decode_buffer(destination.baseAddress!, entry.uncompressedSize,
                                              source.baseAddress! + start, entry.compressedSize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written > 0 else { throw ZipError.corrupted }
            return Data(output.prefix(written))
        default:
            throw ZipError.unsupported(entry.name)
        }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
