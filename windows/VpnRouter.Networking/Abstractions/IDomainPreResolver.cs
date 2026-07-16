using System.Net;
using VpnRouter.Core.Rules;

namespace VpnRouter.Networking.Abstractions;

public interface IDomainPreResolver
{
    Task<IReadOnlyDictionary<string, IReadOnlyList<IPAddress>>> ResolveAsync(
        IReadOnlyList<DomainRule> rules,
        CancellationToken cancellationToken);
}
