namespace VpnRouter.Networking.Abstractions;

public interface INetworkSnapshotStore
{
    Task SaveCurrentAsync(CancellationToken cancellationToken);

    Task RestoreAsync(CancellationToken cancellationToken);
}
