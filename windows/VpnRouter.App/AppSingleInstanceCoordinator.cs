using System;
using System.IO.Pipes;
using System.Threading;
using System.Threading.Tasks;

namespace VpnRouter;

internal sealed class AppSingleInstanceCoordinator : IDisposable
{
    private const string MutexName = @"Local\VpnRouter.App.SingleInstance";
    private const string ActivationPipeName = "VpnRouter.App.Activate";
    private readonly CancellationTokenSource _cancellation = new();
    private Mutex? _mutex;
    private bool _ownsMutex;

    public bool TryAcquire()
    {
        _mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        _ownsMutex = createdNew;
        return createdNew;
    }

    public async Task SignalExistingInstanceAsync(CancellationToken cancellationToken)
    {
        await using var pipe = new NamedPipeClientStream(
            ".",
            ActivationPipeName,
            PipeDirection.Out,
            PipeOptions.Asynchronous);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(2));
        await pipe.ConnectAsync(timeout.Token);
        await pipe.WriteAsync(new byte[] { 1 }, timeout.Token);
        await pipe.FlushAsync(timeout.Token);
    }

    public void StartListening(Action activateWindow)
    {
        _ = Task.Run(async () =>
        {
            while (!_cancellation.IsCancellationRequested)
            {
                try
                {
                    await using var pipe = new NamedPipeServerStream(
                        ActivationPipeName,
                        PipeDirection.In,
                        maxNumberOfServerInstances: 1,
                        PipeTransmissionMode.Byte,
                        PipeOptions.Asynchronous);
                    await pipe.WaitForConnectionAsync(_cancellation.Token);
                    var buffer = new byte[1];
                    _ = await pipe.ReadAsync(buffer, _cancellation.Token);
                    activateWindow();
                }
                catch (OperationCanceledException) when (_cancellation.IsCancellationRequested)
                {
                    break;
                }
                catch
                {
                    await Task.Delay(100, _cancellation.Token);
                }
            }
        });
    }

    public void Dispose()
    {
        _cancellation.Cancel();
        _cancellation.Dispose();
        if (_ownsMutex)
        {
            _mutex?.ReleaseMutex();
        }

        _mutex?.Dispose();
    }
}
