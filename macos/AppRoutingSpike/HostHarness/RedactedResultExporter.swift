import Foundation
import Darwin

public enum RedactedResultExportError: Error, Equatable, LocalizedError {
    case emptyResults
    case pathTooLong
    case fileTooLarge
    case invalidFailureCode
    case invalidReport
    case writeFailed
    case unsafeDestination

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
        case .invalidReport:
            return "가려진 검증 보고서 구성을 확인하지 못했습니다."
        case .writeFailed:
            return "가려진 결과를 저장하지 못했습니다."
        case .unsafeDestination:
            return "안전한 내보내기 위치를 확인하지 못했습니다."
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

    public func encodedData(for report: RedactedValidationReport) throws -> Data {
        guard !report.results.isEmpty else {
            throw RedactedResultExportError.emptyResults
        }
        guard report.results.allSatisfy({ result in
            result.failureCode.map(isAllowedFailureCode) ?? true
        }) else {
            throw RedactedResultExportError.invalidFailureCode
        }
        guard report.schemaVersion == SpikeLimits.schemaVersion,
              report.validationSummaries.count == ValidationAxis.allCases.count,
              Set(report.validationSummaries.map(\.validationAxis)) == Set(ValidationAxis.allCases)
        else {
            throw RedactedResultExportError.invalidReport
        }
        let data = try encoder.encode(report)
        guard data.count <= SpikeLimits.maximumExportBytes else {
            throw RedactedResultExportError.fileTooLarge
        }
        return data
    }

    public func export(_ report: RedactedValidationReport, to destination: URL) throws {
        guard destination.path.utf8.count <= SpikeLimits.maximumExportPathBytes else {
            throw RedactedResultExportError.pathTooLong
        }
        let parent = destination.deletingLastPathComponent()
        let parentValues = try? parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let destinationValues = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard parentValues?.isDirectory == true,
              parentValues?.isSymbolicLink != true,
              destinationValues?.isSymbolicLink != true else {
            throw RedactedResultExportError.unsafeDestination
        }
        let data = try encodedData(for: report)
        try writeAtomicallyWithoutFollowingLinks(data, to: destination, parent: parent)
    }

    private func writeAtomicallyWithoutFollowingLinks(
        _ data: Data,
        to destination: URL,
        parent: URL
    ) throws {
        var template = Array(
            parent.appendingPathComponent(".vpn-router-export.XXXXXX").path.utf8CString
        )
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw RedactedResultExportError.writeFailed }
        let temporary = URL(fileURLWithPath: String(cString: template))
        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        defer { close(descriptor) }

        do {
            guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
                throw RedactedResultExportError.writeFailed
            }
            try data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: offset),
                        buffer.count - offset
                    )
                    guard written > 0 else { throw RedactedResultExportError.writeFailed }
                    offset += written
                }
            }
            guard fsync(descriptor) == 0 else { throw RedactedResultExportError.writeFailed }
            let renameResult = temporary.withUnsafeFileSystemRepresentation { source in
                destination.withUnsafeFileSystemRepresentation { target in
                    rename(source, target)
                }
            }
            guard renameResult == 0 else { throw RedactedResultExportError.writeFailed }
            shouldRemoveTemporary = false
        } catch let error as RedactedResultExportError {
            throw error
        } catch {
            throw RedactedResultExportError.writeFailed
        }
    }

    private func isAllowedFailureCode(_ value: String) -> Bool {
        SpikeFailureCode(rawValue: value) != nil
    }
}
