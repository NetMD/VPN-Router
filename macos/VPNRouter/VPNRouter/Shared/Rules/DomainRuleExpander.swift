import Foundation

enum DomainRuleExpander {
    private nonisolated static let relatedDomains: [String: [String]] = [
        "youtube.com": [
            "googlevideo.com",
            "ytimg.com",
            "youtubei.googleapis.com",
            "ggpht.com",
            "youtube-nocookie.com"
        ],
        "netflix.com": [
            "nflxvideo.net",
            "nflximg.net",
            "nflximg.com",
            "nflxso.net",
            "nflxext.com"
        ]
    ]

    nonisolated static func expand(_ rules: [DomainRule]) -> [DomainRule] {
        var expanded = rules
        var domains = Set(rules.map { normalize($0.domain) })

        for rule in rules where rule.enabled {
            let domain = normalize(rule.domain)

            for (root, relatedDomains) in Self.relatedDomains where matchesRoot(domain, root: root) {
                for relatedDomain in relatedDomains where domains.insert(relatedDomain).inserted {
                    expanded.append(DomainRule(
                        profileId: rule.profileId,
                        domain: relatedDomain,
                        includeSubdomains: true,
                        enabled: true,
                        createdAt: rule.createdAt
                    ))
                }
            }
        }

        return expanded
    }

    nonisolated static func normalize(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private nonisolated static func matchesRoot(_ domain: String, root: String) -> Bool {
        domain == root || domain.hasSuffix(".\(root)")
    }
}
