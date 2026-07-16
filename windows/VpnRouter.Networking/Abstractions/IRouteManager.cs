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

    Task RemoveManagedRoutesAsync(Guid profileId, CancellationToken cancellationToken);
}
