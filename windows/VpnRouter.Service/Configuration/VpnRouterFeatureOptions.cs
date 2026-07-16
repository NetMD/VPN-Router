namespace VpnRouter.Service.Configuration;

public sealed class VpnRouterFeatureOptions
{
    public const string SectionName = "VpnRouter:Features";

    public bool EnableWireGuardActivation { get; init; }

    public bool EnableWindowsDnsMutation { get; init; }

    public bool EnableWindowsRouteMutation { get; init; }
}
