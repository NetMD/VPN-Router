namespace VpnRouter.Core.Rules;

public static class DomainRuleExpander
{
    private static readonly IReadOnlyDictionary<string, string[]> RelatedDomains =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["youtube.com"] =
            [
                "www.youtube.com",
                "googlevideo.com",
                "ytimg.com",
                "youtubei.googleapis.com",
                "ggpht.com",
                "youtube-nocookie.com"
            ],
            ["netflix.com"] =
            [
                "www.netflix.com",
                "nflxvideo.net",
                "nflximg.net",
                "nflximg.com",
                "nflxso.net",
                "nflxext.com"
            ]
        };

    public static IReadOnlyList<DomainRule> Expand(IReadOnlyList<DomainRule> rules)
    {
        var expanded = new List<DomainRule>(rules);
        var domains = rules
            .Select(rule => rule.Domain)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var rule in rules.Where(rule => rule.Enabled))
        {
            foreach (var mapping in RelatedDomains)
            {
                if (!MatchesRoot(rule.Domain, mapping.Key))
                {
                    continue;
                }

                foreach (var relatedDomain in mapping.Value)
                {
                    if (domains.Add(relatedDomain))
                    {
                        expanded.Add(new DomainRule(
                            Guid.NewGuid(),
                            rule.ProfileId,
                            relatedDomain,
                            IncludeSubdomains: true,
                            Enabled: true,
                            CreatedAt: rule.CreatedAt));
                    }
                }
            }
        }

        return expanded;
    }

    private static bool MatchesRoot(string domain, string root) =>
        string.Equals(domain, root, StringComparison.OrdinalIgnoreCase)
        || domain.EndsWith("." + root, StringComparison.OrdinalIgnoreCase);
}
