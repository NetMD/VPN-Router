using System.Net;
using VpnRouter.Core.Routing;

namespace VpnRouter.Networking.Abstractions;

public interface IRouteManager
{
    Task<IReadOnlyList<RouteEntry>> AddHostRoutesAsync(
        IReadOnlyDictionary<string, IReadOnlyList<IPAddress>> domainIps,
        Guid profileId,
        int interfaceIndex,
        CancellationToken cancellationToken);

    Task<int> RemoveExpiredRoutesAsync(Guid profileId, CancellationToken cancellationToken);

    Task RemoveManagedRoutesAsync(Guid profileId, CancellationToken cancellationToken);

    Task<bool> HasManagedRoutesAsync(CancellationToken cancellationToken);

    Task RemoveAllManagedRoutesAsync(CancellationToken cancellationToken);
}
