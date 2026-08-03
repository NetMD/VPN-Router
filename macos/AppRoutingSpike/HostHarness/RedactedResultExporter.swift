import Foundation

public enum RedactedResultExportError: Error, Equatable, LocalizedError {
    case emptyResults
    case pathTooLong
    case fileTooLarge
    case invalidFailureCode
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .emptyResults:
            return "내보낼 가려진 결과가 없습니다."
        case .pathTooLong:
            return "내보내기 경로가 너무 깁니다. 다른 위치를 선택해 주세요."
        case .fileTooLarge:
            return "가려진 결과가 내보내기 크기 제한을 넘었습니다."
        case .invalidFailureCode:
            return "가려진 실패 코드를 확인하지 못했습니다."
        case .writeFailed:
            return "가려진 결과를 저장하지 못했습니다."
        }
    }
}

public struct RedactedResultExporter: Sendable {
    private let encoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func encodedData(for results: [RedactedFlowResult]) throws -> Data {
        guard !results.isEmpty else {
            throw RedactedResultExportError.emptyResults
        }
        guard results.allSatisfy({ result in
            result.failureCode.map(isAllowedFailureCode) ?? true
        }) else {
            throw RedactedResultExportError.invalidFailureCode
        }
        let data = try encoder.encode(results)
        guard data.count <= SpikeLimits.maximumExportBytes else {
            throw RedactedResultExportError.fileTooLarge
        }
        return data
    }

    public func export(_ results: [RedactedFlowResult], to destination: URL) throws {
        guard destination.path.utf8.count <= SpikeLimits.maximumExportPathBytes else {
            throw RedactedResultExportError.pathTooLong
        }
        let data = try encodedData(for: results)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw RedactedResultExportError.writeFailed
        }
    }

    private func isAllowedFailureCode(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= SpikeLimits.maximumJSONStringBytes else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            (97...122).contains(Int(scalar.value))
                || (48...57).contains(Int(scalar.value))
                || scalar.value == 45
        } && !value.hasPrefix("-") && !value.hasSuffix("-")
    }
}
