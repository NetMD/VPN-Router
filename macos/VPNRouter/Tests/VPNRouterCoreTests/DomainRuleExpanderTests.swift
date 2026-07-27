import XCTest
@testable import VPNRouterCore

final class DomainRuleExpanderTests: XCTestCase {
    private let profileId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testNormalizeTrimsWhitespaceDotsAndCase() {
        XCTAssertEqual(DomainRuleExpander.normalize("  .WWW.YouTube.COM.\n"), "www.youtube.com")
    }

    func testYouTubeRootAndSubdomainExpandToMediaDomains() {
        for domain in ["youtube.com", "WWW.YouTube.com"] {
            let expanded = DomainRuleExpander.expand([makeRule(domain: domain)])
            let domains = Set(expanded.map { DomainRuleExpander.normalize($0.domain) })

            XCTAssertTrue(domains.isSuperset(of: [
                "youtube.com" == DomainRuleExpander.normalize(domain) ? "youtube.com" : "www.youtube.com",
                "www.youtube.com",
                "googlevideo.com",
                "ytimg.com",
                "youtubei.googleapis.com",
                "ggpht.com",
                "youtube-nocookie.com"
            ]))
        }
    }

    func testMediaRootsIncludeConcreteWebHostsForStaticResolution() {
        let expanded = DomainRuleExpander.expand([
            makeRule(domain: "youtube.com"),
            makeRule(domain: "netflix.com")
        ])
        let domains = Set(expanded.map { DomainRuleExpander.normalize($0.domain) })

        XCTAssertTrue(domains.contains("www.youtube.com"))
        XCTAssertTrue(domains.contains("www.netflix.com"))
    }

    func testNetflixExpansionDoesNotDuplicateExistingRelatedRule() {
        let expanded = DomainRuleExpander.expand([
            makeRule(domain: "netflix.com"),
            makeRule(domain: "nflxvideo.net")
        ])

        XCTAssertEqual(
            expanded.filter { DomainRuleExpander.normalize($0.domain) == "nflxvideo.net" }.count,
            1
        )
    }

    func testDisabledMediaRuleDoesNotExpand() {
        let expanded = DomainRuleExpander.expand([makeRule(domain: "youtube.com", enabled: false)])

        XCTAssertEqual(expanded.count, 1)
    }

    private func makeRule(domain: String, enabled: Bool = true) -> DomainRule {
        DomainRule(
            profileId: profileId,
            domain: domain,
            includeSubdomains: true,
            enabled: enabled,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
