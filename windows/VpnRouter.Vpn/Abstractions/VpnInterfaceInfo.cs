using System.Net;

namespace VpnRouter.Vpn.Abstractions;

public sealed record VpnInterfaceInfo(int InterfaceIndex, string InterfaceName, IReadOnlyList<IPAddress> Addresses);
