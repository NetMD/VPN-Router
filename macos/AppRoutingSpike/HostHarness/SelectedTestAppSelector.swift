import AppKit
import Foundation
import Security
import UniformTypeIdentifiers

@MainActor
public final class SelectedTestAppSelector: SelectedTestAppSelecting {
    private var pendingIdentity: SelectedTestAppIdentity?

    public init() {}

    public func selectSignedApplication() async throws -> Bool {
        clear()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.message = "서명된 공개 시험용 앱을 지정해 주세요. 식별자는 실행 요청 뒤 즉시 지워집니다."

        guard panel.runModal() == .OK, let applicationURL = panel.url else {
            return false
        }
        pendingIdentity = try identity(for: applicationURL)
        return true
    }

    public func consumeIdentity() throws -> SelectedTestAppIdentity {
        guard let identity = pendingIdentity else {
            throw SpikeHostServiceError.selectedApplicationUnavailable
        }
        pendingIdentity = nil
        return identity
    }

    public func clear() {
        pendingIdentity = nil
    }

    private func identity(for url: URL) throws -> SelectedTestAppIdentity {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else {
            throw SpikeHostServiceError.invalidSelectedApplication
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [String: Any],
        let signingIdentifier = values[kSecCodeInfoIdentifier as String] as? String,
        let teamIdentifier = values[kSecCodeInfoTeamIdentifier as String] as? String,
        !signingIdentifier.isEmpty,
        !teamIdentifier.isEmpty,
        signingIdentifier.utf8.count <= SpikeLimits.maximumSigningIdentifierBytes,
        teamIdentifier.utf8.count <= SpikeLimits.maximumTeamIdentifierBytes else {
            throw SpikeHostServiceError.invalidSelectedApplication
        }
        return SelectedTestAppIdentity(
            signingIdentifier: signingIdentifier,
            teamIdentifier: teamIdentifier
        )
    }
}
