using VpnRouter.Core.Rules;

namespace VpnRouter.Networking.Abstractions;

public interface IDnsProxyController
{
    Task StartAsync(IReadOnlyList<DomainRule> rules, CancellationToken cancellationToken);

    Task StopAsync(CancellationToken cancellationToken);
}
