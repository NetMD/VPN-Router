namespace VpnRouter.Networking.Abstractions;

public interface IDnsSettingsManager
{
    Task PointActiveAdaptersToLocalProxyAsync(CancellationToken cancellationToken);
}
