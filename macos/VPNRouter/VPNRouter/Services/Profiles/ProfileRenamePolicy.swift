import Foundation

public nonisolated protocol ProfileRenameRecord {
    associatedtype ID: Equatable

    var id: ID { get }
    var displayName: String { get set }
    var updatedAt: Date { get set }
}

public nonisolated enum ProfileRenamePolicy {
    public static func renaming<Record: ProfileRenameRecord>(
        _ records: [Record],
        id: Record.ID,
        displayName: String,
        updatedAt: Date
    ) throws -> [Record] {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProfileRenamePolicyError.emptyDisplayName
        }

        var renamedRecords = records
        guard let index = renamedRecords.firstIndex(where: { $0.id == id }) else {
            throw ProfileRenamePolicyError.profileNotFound
        }

        renamedRecords[index].displayName = normalizedName
        renamedRecords[index].updatedAt = updatedAt
        return renamedRecords
    }
}

public nonisolated enum ProfileRenamePolicyError: LocalizedError, Equatable {
    case emptyDisplayName
    case profileNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            return "프로필 이름은 비워 둘 수 없습니다."
        case .profileNotFound:
            return "이름을 변경할 프로필을 찾지 못했습니다."
        }
    }
}
