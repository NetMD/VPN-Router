import Foundation

struct DNSAddressObservation: Equatable {
    let domain: String
    let address: String
    let ttl: UInt32
}

enum DNSMessageParser {
    static func emptyAAAAResponse(
        for data: Data,
        matching targetDomains: Set<String>
    ) throws -> Data? {
        guard data.count >= 12 else {
            throw DNSMessageParserError.truncated
        }

        let flags = try readUInt16(data, at: 2)
        guard flags & 0x8000 != 0 else {
            return nil
        }
        let questionCount = try readUInt16(data, at: 4)
        guard questionCount == 1 else {
            return nil
        }

        var offset = 12
        let questionName = try readName(data, offset: &offset)
        let questionType = try readUInt16(data, at: offset)
        let questionClass = try readUInt16(data, at: offset + 2)
        guard questionType == 28,
              questionClass == 1,
              matches(questionName, targets: targetDomains) else {
            return nil
        }

        var response = Data()
        appendUInt16(try readUInt16(data, at: 0), to: &response)
        let responseFlags = (flags | 0x8080) & 0xfdf0
        appendUInt16(responseFlags, to: &response)
        appendUInt16(1, to: &response)
        appendUInt16(0, to: &response)
        appendUInt16(0, to: &response)
        appendUInt16(0, to: &response)
        appendName(questionName, to: &response)
        appendUInt16(28, to: &response)
        appendUInt16(1, to: &response)
        return response
    }

    static func addressObservations(
        in data: Data,
        matching targetDomains: Set<String>
    ) throws -> [DNSAddressObservation] {
        guard data.count >= 12 else {
            throw DNSMessageParserError.truncated
        }

        let flags = try readUInt16(data, at: 2)
        guard flags & 0x8000 != 0, flags & 0x000f == 0 else {
            return []
        }

        let questionCount = Int(try readUInt16(data, at: 4))
        let answerCount = Int(try readUInt16(data, at: 6))
        guard questionCount <= 64, answerCount <= 512 else {
            throw DNSMessageParserError.countLimitExceeded
        }

        var offset = 12
        var matchingQuestions = Set<String>()
        for _ in 0..<questionCount {
            let name = try readName(data, offset: &offset)
            try advance(&offset, by: 4, in: data)
            if matches(name, targets: targetDomains) {
                matchingQuestions.insert(name)
            }
        }

        guard !matchingQuestions.isEmpty else {
            return []
        }

        var records: [DNSResourceRecord] = []
        records.reserveCapacity(answerCount)
        for _ in 0..<answerCount {
            let owner = try readName(data, offset: &offset)
            let type = try readUInt16(data, at: offset)
            let recordClass = try readUInt16(data, at: offset + 2)
            let ttl = try readUInt32(data, at: offset + 4)
            let dataLength = Int(try readUInt16(data, at: offset + 8))
            try advance(&offset, by: 10, in: data)
            let dataOffset = offset
            try advance(&offset, by: dataLength, in: data)

            switch (type, recordClass, dataLength) {
            case (1, 1, 4):
                let octets = data[dataOffset..<(dataOffset + 4)]
                records.append(DNSResourceRecord(
                    owner: owner,
                    ttl: ttl,
                    value: .ipv4(octets.map(String.init).joined(separator: "."))
                ))
            case (5, 1, _):
                var nameOffset = dataOffset
                let canonicalName = try readName(data, offset: &nameOffset)
                records.append(DNSResourceRecord(
                    owner: owner,
                    ttl: ttl,
                    value: .canonicalName(canonicalName)
                ))
            default:
                continue
            }
        }

        var eligibleNames = Dictionary(
            uniqueKeysWithValues: matchingQuestions.map { ($0, UInt32.max) }
        )
        for _ in 0..<16 {
            var changed = false
            for record in records {
                guard let ownerTTL = eligibleNames[record.owner],
                      case .canonicalName(let canonicalName) = record.value else {
                    continue
                }
                let effectiveTTL = min(ownerTTL, record.ttl)
                if eligibleNames[canonicalName].map({ effectiveTTL > $0 }) ?? true {
                    eligibleNames[canonicalName] = effectiveTTL
                    changed = true
                }
            }
            if !changed {
                break
            }
        }

        return records.compactMap { record in
            guard let inheritedTTL = eligibleNames[record.owner],
                  case .ipv4(let address) = record.value else {
                return nil
            }
            return DNSAddressObservation(
                domain: record.owner,
                address: address,
                ttl: min(inheritedTTL, record.ttl)
            )
        }
    }

    private static func matches(_ domain: String, targets: Set<String>) -> Bool {
        targets.contains { target in
            domain == target || domain.hasSuffix(".\(target)")
        }
    }

    private static func readName(_ data: Data, offset: inout Int) throws -> String {
        var cursor = offset
        var continuationOffset: Int?
        var visitedPointers = Set<Int>()
        var labels: [String] = []
        var encodedLength = 0

        for _ in 0..<128 {
            guard cursor < data.count else {
                throw DNSMessageParserError.truncated
            }
            let length = Int(data[cursor])

            if length == 0 {
                cursor += 1
                offset = continuationOffset ?? cursor
                return labels.joined(separator: ".").lowercased()
            }

            if length & 0xc0 == 0xc0 {
                guard cursor + 1 < data.count else {
                    throw DNSMessageParserError.truncated
                }
                let pointer = ((length & 0x3f) << 8) | Int(data[cursor + 1])
                guard pointer < data.count, visitedPointers.insert(pointer).inserted else {
                    throw DNSMessageParserError.invalidCompressionPointer
                }
                continuationOffset = continuationOffset ?? cursor + 2
                cursor = pointer
                continue
            }

            guard length & 0xc0 == 0, length <= 63 else {
                throw DNSMessageParserError.invalidLabel
            }
            cursor += 1
            guard cursor + length <= data.count else {
                throw DNSMessageParserError.truncated
            }
            encodedLength += length + 1
            guard encodedLength <= 255,
                  let label = String(data: data[cursor..<(cursor + length)], encoding: .ascii),
                  !label.isEmpty else {
                throw DNSMessageParserError.invalidLabel
            }
            labels.append(label)
            cursor += length
        }

        throw DNSMessageParserError.invalidName
    }

    private static func readUInt16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw DNSMessageParserError.truncated
        }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw DNSMessageParserError.truncated
        }
        return UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func advance(_ offset: inout Int, by count: Int, in data: Data) throws {
        guard count >= 0, offset >= 0, offset + count <= data.count else {
            throw DNSMessageParserError.truncated
        }
        offset += count
    }

    private static func appendName(_ name: String, to data: inout Data) {
        for label in name.split(separator: ".") {
            data.append(UInt8(label.utf8.count))
            data.append(contentsOf: label.utf8)
        }
        data.append(0)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xff))
    }
}

private struct DNSResourceRecord {
    enum Value {
        case ipv4(String)
        case canonicalName(String)
    }

    let owner: String
    let ttl: UInt32
    let value: Value
}

enum DNSMessageParserError: Error {
    case truncated
    case countLimitExceeded
    case invalidCompressionPointer
    case invalidLabel
    case invalidName
}
