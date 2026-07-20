import Foundation

nonisolated struct DomainRoutePlanService {
    private nonisolated let ruleStore: DomainRuleStore
    private nonisolated let resolver: any DomainResolving

    init(
        ruleStore: DomainRuleStore,
        resolver: any DomainResolving = SystemDomainResolver()
    ) {
        self.ruleStore = ruleStore
        self.resolver = resolver
    }

    func buildPlan(profileId: UUID) throws -> DomainRoutePlan {
        let rules = try ruleStore.loadRules(profileId: profileId)
        let expandedDomains = DomainRuleExpander.expand(rules)
            .filter(\.enabled)
            .map { DomainRuleExpander.normalize($0.domain) }
        let resolvedAddresses = try resolver.resolveIPv4Addresses(for: expandedDomains)

        return try DomainRoutePlanner.buildPlan(
            rules: rules,
            resolvedAddresses: resolvedAddresses
        )
    }

    func buildPlan(
        profileId: UUID,
        resolvedAddresses: [ResolvedDomainAddress]
    ) throws -> DomainRoutePlan {
        let rules = try ruleStore.loadRules(profileId: profileId)
        return try DomainRoutePlanner.buildPlan(
            rules: rules,
            resolvedAddresses: resolvedAddresses
        )
    }

    func replaceRules(
        profileId: UUID,
        domains: [String],
        includeSubdomains: Bool = true,
        now: Date = Date()
    ) throws -> [DomainRule] {
        let normalizedDomains = Array(Set(domains.map(DomainRuleExpander.normalize))).sorted()
        let newRules = normalizedDomains.map { domain in
            DomainRule(
                profileId: profileId,
                domain: domain,
                includeSubdomains: includeSubdomains,
                enabled: true,
                createdAt: now
            )
        }

        let existingRules = try ruleStore.loadRules()
            .filter { $0.profileId != profileId }
        let allRules = existingRules + newRules
        try ruleStore.saveRules(allRules)
        return newRules
    }
}
