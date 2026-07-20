using System.Net;
using VpnRouter.Core.Rules;

namespace VpnRouter.Networking.Abstractions;

public interface IDnsProxyController
{
    Task StartAsync(
        IReadOnlyList<DomainRule> rules,
        IPAddress? upstreamDnsServer,
        Guid profileId,
        int interfaceIndex,
        CancellationToken cancellationToken);

    Task StopAsync(CancellationToken cancellationToken);

    Task<Exception> WaitForFatalFailureAsync(CancellationToken cancellationToken);
}
