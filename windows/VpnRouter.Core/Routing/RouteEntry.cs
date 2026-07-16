using System.Net;

namespace VpnRouter.Core.Routing;

public sealed record RouteEntry(
    IPAddress Ip,
    string Domain,
    Guid ProfileId,
    DateTimeOffset ExpiresAt,
    int InterfaceIndex,
    string AddedBy);
