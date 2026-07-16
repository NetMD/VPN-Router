using System.Net;
using VpnRouter.Core.Routing;
using VpnRouter.Core.Rules;
using VpnRouter.Networking.Abstractions;

namespace VpnRouter.Networking;

public sealed class NoopDnsProxyController : IDnsProxyController
{
    public Task StartAsync(IReadOnlyList<DomainRule> rules, CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}

public sealed class NoopNetworkSnapshotStore : INetworkSnapshotStore
{
    public Task SaveCurrentAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }

    public Task RestoreAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}

public sealed class NoopRouteManager : IRouteManager
{
    public Task<IReadOnlyList<RouteEntry>> AddHostRoutesAsync(
        IReadOnlyDictionary<string, IReadOnlyList<IPAddress>> domainIps,
        Guid profileId,
        int interfaceIndex,
        CancellationToken cancellationToken)
    {
        return Task.FromResult<IReadOnlyList<RouteEntry>>(Array.Empty<RouteEntry>());
    }

    public Task RemoveManagedRoutesAsync(Guid profileId, CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}
