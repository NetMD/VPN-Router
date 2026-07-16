namespace VpnRouter.Core.Rules;

public sealed record DomainRule(
    Guid Id,
    Guid ProfileId,
    string Domain,
    bool IncludeSubdomains,
    bool Enabled,
    DateTimeOffset CreatedAt);
