import Foundation
import Testing
@testable import VPNRouterProfilePolicy

@Suite
struct ProfileRenamePolicyTests {
    @Test
    func renameTrimsNameAndPreservesIdentityAndSecretReference() throws {
        let id = UUID()
        let originalUpdatedAt = Date(timeIntervalSince1970: 100)
        let renamedAt = Date(timeIntervalSince1970: 200)
        let records = [
            TestProfile(
                id: id,
                displayName: "Original",
                updatedAt: originalUpdatedAt,
                secretReference: "keychain:\(id.uuidString)"
            )
        ]

        let renamed = try ProfileRenamePolicy.renaming(
            records,
            id: id,
            displayName: "  Renamed  ",
            updatedAt: renamedAt
        )

        #expect(renamed.count == 1)
        #expect(renamed[0].id == id)
        #expect(renamed[0].displayName == "Renamed")
        #expect(renamed[0].updatedAt == renamedAt)
        #expect(renamed[0].secretReference == records[0].secretReference)
    }

    @Test
    func renameChangesOnlyTheTargetRecord() throws {
        let first = TestProfile.make(displayName: "First")
        let second = TestProfile.make(displayName: "Second")
        let renamedAt = Date(timeIntervalSince1970: 300)

        let renamed = try ProfileRenamePolicy.renaming(
            [first, second],
            id: second.id,
            displayName: "Updated",
            updatedAt: renamedAt
        )

        #expect(renamed[0] == first)
        #expect(renamed[1].displayName == "Updated")
        #expect(renamed[1].id == second.id)
        #expect(renamed[1].secretReference == second.secretReference)
    }

    @Test
    func renameRejectsWhitespaceOnlyNameWithoutChangingRecords() {
        let record = TestProfile.make(displayName: "Original")

        #expect(throws: ProfileRenamePolicyError.emptyDisplayName) {
            try ProfileRenamePolicy.renaming(
                [record],
                id: record.id,
                displayName: " \n\t ",
                updatedAt: Date()
            )
        }
    }

    @Test
    func renameRejectsMissingProfile() {
        let record = TestProfile.make(displayName: "Original")

        #expect(throws: ProfileRenamePolicyError.profileNotFound) {
            try ProfileRenamePolicy.renaming(
                [record],
                id: UUID(),
                displayName: "Renamed",
                updatedAt: Date()
            )
        }
    }
}

private struct TestProfile: ProfileRenameRecord, Equatable {
    let id: UUID
    var displayName: String
    var updatedAt: Date
    let secretReference: String

    static func make(displayName: String) -> TestProfile {
        let id = UUID()
        return TestProfile(
            id: id,
            displayName: displayName,
            updatedAt: Date(timeIntervalSince1970: 100),
            secretReference: "keychain:\(id.uuidString)"
        )
    }
}
