namespace VpnRouter.Service.Recovery;

public sealed class StartupRecoveryGate
{
    private readonly TaskCompletionSource _ready = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public bool IsRecovering { get; private set; } = true;
    public bool Succeeded { get; private set; }
    public string? FailureMessage { get; private set; }

    public Task WaitUntilReadyAsync(CancellationToken cancellationToken) =>
        _ready.Task.WaitAsync(cancellationToken);

    public void Complete()
    {
        Succeeded = true;
        IsRecovering = false;
        _ready.TrySetResult();
    }

    public void Fail(string message)
    {
        FailureMessage = message;
        IsRecovering = false;
        _ready.TrySetResult();
    }
}
