using System.Text.Json;

namespace VpnRouter.Service.Recovery;

public sealed class ConnectionRecoveryStateStore
{
    private readonly string _markerPath;

    public ConnectionRecoveryStateStore()
        : this(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VpnRouter",
            "active-connection.json"))
    {
    }

    internal ConnectionRecoveryStateStore(string markerPath)
    {
        _markerPath = Path.GetFullPath(markerPath);
    }

    public bool HasActiveMarker => File.Exists(_markerPath);

    public async Task MarkActiveAsync(Guid profileId, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_markerPath)!);
        var marker = new ActiveConnectionMarker(profileId, DateTimeOffset.UtcNow);
        await File.WriteAllTextAsync(
            _markerPath,
            JsonSerializer.Serialize(marker, new JsonSerializerOptions { WriteIndented = true }),
            cancellationToken);
    }

    public Task ClearAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (File.Exists(_markerPath))
        {
            File.Delete(_markerPath);
        }

        return Task.CompletedTask;
    }

    private sealed record ActiveConnectionMarker(Guid ProfileId, DateTimeOffset StartedAt);
}
