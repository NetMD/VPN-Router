using Microsoft.UI.Xaml;
using System;
using System.Linq;
using System.Threading;

namespace VpnRouter;

public partial class App : Application
{
    private readonly AppSingleInstanceCoordinator _singleInstance = new();
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        if (!_singleInstance.TryAcquire())
        {
            try
            {
                await _singleInstance.SignalExistingInstanceAsync(CancellationToken.None);
            }
            catch
            {
                // The first process may still be creating its activation pipe.
            }

            Exit();
            return;
        }

        _window = new MainWindow(GetExpectedPayloadIdentity());
        _window.Activate();
        _singleInstance.StartListening(() =>
        {
            _window.DispatcherQueue.TryEnqueue(() => _window.Activate());
        });
    }

    private static string? GetExpectedPayloadIdentity()
    {
        const string prefix = "--vpnrouter-payload-id=";
        var argument = Environment.GetCommandLineArgs()
            .FirstOrDefault(value => value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
        return argument is null ? null : argument[prefix.Length..];
    }
}
