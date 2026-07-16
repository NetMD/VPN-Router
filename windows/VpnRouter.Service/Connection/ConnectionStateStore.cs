using VpnRouter.Ipc.Contracts;

namespace VpnRouter.Service.Connection;

public sealed class ConnectionStateStore
{
    private readonly object _gate = new();
    private readonly List<string> _recentMessages = ["Service started."];
    private ConnectionStateKind _state = ConnectionStateKind.Disconnected;
    private Guid? _activeProfileId;

    public ConnectionStateDto Snapshot()
    {
        lock (_gate)
        {
            return new ConnectionStateDto(_state, _activeProfileId, _recentMessages.ToArray());
        }
    }

    public void SetConnecting(Guid profileId, int ruleCount)
    {
        SetState(ConnectionStateKind.Connecting, profileId, $"Connecting with {ruleCount} site rule(s).");
    }

    public void SetConnected(Guid profileId, int ruleCount)
    {
        SetState(ConnectionStateKind.Connected, profileId, $"Connected. {ruleCount} site(s) will use VPN.");
    }

    public void SetDisconnecting(Guid profileId)
    {
        SetState(ConnectionStateKind.Disconnecting, profileId, "Disconnecting.");
    }

    public void SetDisconnected(string message)
    {
        SetState(ConnectionStateKind.Disconnected, null, message);
    }

    public void SetRestoringNetwork(string reason)
    {
        SetState(ConnectionStateKind.RestoringNetwork, _activeProfileId, $"Restoring network settings. Reason: {reason}");
    }

    public void SetFailed(string message)
    {
        SetState(ConnectionStateKind.Failed, _activeProfileId, message);
    }

    public void AddMessage(string message)
    {
        lock (_gate)
        {
            AddMessageCore(message);
        }
    }

    private void SetState(ConnectionStateKind state, Guid? activeProfileId, string message)
    {
        lock (_gate)
        {
            _state = state;
            _activeProfileId = activeProfileId;
            AddMessageCore(message);
        }
    }

    private void AddMessageCore(string message)
    {
        _recentMessages.Insert(0, $"{DateTimeOffset.Now:HH:mm:ss} {message}");

        if (_recentMessages.Count > 20)
        {
            _recentMessages.RemoveRange(20, _recentMessages.Count - 20);
        }
    }
}
