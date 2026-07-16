namespace VpnRouter.Ipc.Contracts;

public sealed record ConnectionStateDto(
    ConnectionStateKind State,
    Guid? ActiveProfileId,
    IReadOnlyList<string> RecentMessages);

public enum ConnectionStateKind
{
    Disconnected = 0,
    Connecting = 1,
    Connected = 2,
    Disconnecting = 3,
    RestoringNetwork = 4,
    Failed = 5
}
