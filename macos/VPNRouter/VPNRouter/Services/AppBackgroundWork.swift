import Foundation

enum AppBackgroundWork {
    private static let staticRoutePlanHistory = StaticRoutePlanHistoryStore()

    static func loadProfiles() async throws -> [ProfileMetadata] {
        try await run {
            try ProfileStore().loadProfiles()
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    static func loadSharedSiteDomains() async throws -> [String] {
        try await run {
            let store = try DomainRuleStore()
            try migrateLegacyProfileSiteRulesIfNeeded(store: store)
            return try store.loadRules(profileId: DomainRuleStore.sharedSiteRulesProfileId)
                .filter(\.enabled)
                .map { DomainRuleExpander.normalize($0.domain) }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    static func importProfile(
        from fileURL: URL,
        displayName: String
    ) async throws -> (profile: ProfileMetadata, profiles: [ProfileMetadata]) {
        try await run {
            let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let configText = try String(contentsOf: fileURL, encoding: .utf8)
            let store = try ProfileStore()
            let profile = try ProfileImportService(profileStore: store).importProfile(
                displayName: displayName,
                configText: configText
            )
            let profiles = try store.loadProfiles()
                .sorted { $0.updatedAt > $1.updatedAt }
            return (profile, profiles)
        }
    }

    static func deleteProfile(id: UUID) async throws -> [ProfileMetadata] {
        try await run {
            let remainingProfiles = try ProfileStore().deleteProfile(id: id)
                .sorted { $0.updatedAt > $1.updatedAt }
            try KeychainSecretStore().deletePrivateKey(profileId: id)
            return remainingProfiles
        }
    }

    static func renameProfile(
        id: UUID,
        displayName: String
    ) async throws -> [ProfileMetadata] {
        try await run {
            try ProfileStore().renameProfile(id: id, displayName: displayName)
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    static func replaceRulesAndBuildPlan(domains: [String]) async throws -> DomainRoutePlan {
        let freshPlan = try await run {
            let store = try DomainRuleStore()
            let service = DomainRoutePlanService(ruleStore: store)
            _ = try service.replaceRules(
                profileId: DomainRuleStore.sharedSiteRulesProfileId,
                domains: domains
            )
            return try service.buildPlan(profileId: DomainRuleStore.sharedSiteRulesProfileId)
        }
        return try await staticRoutePlanHistory.merge(freshPlan)
    }

    static func buildSharedRoutePlan() async throws -> DomainRoutePlan {
        let freshPlan = try await run {
            let store = try DomainRuleStore()
            try migrateLegacyProfileSiteRulesIfNeeded(store: store)
            let rules = try store.loadRules(profileId: DomainRuleStore.sharedSiteRulesProfileId)
            guard !rules.isEmpty else {
                throw TunnelConfigurationError.noRouteRules
            }
            return try DomainRoutePlanService(ruleStore: store)
                .buildPlan(profileId: DomainRuleStore.sharedSiteRulesProfileId)
        }
        return try await staticRoutePlanHistory.merge(freshPlan)
    }

    private static func migrateLegacyProfileSiteRulesIfNeeded(
        store: DomainRuleStore
    ) throws {
        guard try store.loadRules(
            profileId: DomainRuleStore.sharedSiteRulesProfileId
        ).isEmpty else {
            return
        }

        let legacyDomains = try store.loadRules()
            .filter {
                $0.profileId != DomainRuleStore.sharedSiteRulesProfileId
                    && $0.enabled
            }
            .map { DomainRuleExpander.normalize($0.domain) }
        guard !legacyDomains.isEmpty else {
            return
        }

        _ = try DomainRoutePlanService(ruleStore: store).replaceRules(
            profileId: DomainRuleStore.sharedSiteRulesProfileId,
            domains: legacyDomains
        )
    }

    private static func run<Value>(
        _ work: @escaping () throws -> Value
    ) async throws -> Value {
        try await Task.detached(priority: .userInitiated) {
            try work()
        }.value
    }
}

private actor StaticRoutePlanHistoryStore {
    private var history = StaticRoutePlanHistory()

    func merge(_ freshPlan: DomainRoutePlan) throws -> DomainRoutePlan {
        try history.merge(freshPlan: freshPlan)
    }
}
