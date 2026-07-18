using System.Diagnostics;
using System.Text;

namespace VpnRouter.Service.Networking;

public sealed class PersistentPowerShellRunner(ILogger logger) : IAsyncDisposable
{
    private const string ResponsePrefix = "__VPNROUTER__";
    private readonly SemaphoreSlim _gate = new(1, 1);
    private Process? _process;
    private long _requestId;

    public int? ProcessId => _process is { HasExited: false } process ? process.Id : null;

    public async Task RunAsync(string command, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var process = EnsureStarted();
            var requestId = Interlocked.Increment(ref _requestId).ToString(System.Globalization.CultureInfo.InvariantCulture);
            var payload = Convert.ToBase64String(Encoding.UTF8.GetBytes(command));

            await process.StandardInput.WriteLineAsync($"{requestId}|{payload}".AsMemory(), cancellationToken);
            await process.StandardInput.FlushAsync(cancellationToken);

            while (true)
            {
                var line = await process.StandardOutput.ReadLineAsync(cancellationToken);
                if (line is null)
                {
                    throw new InvalidOperationException("The persistent PowerShell route worker exited before returning a result.");
                }

                var parts = line.Split('|', 4);
                if (parts.Length < 3 || parts[0] != ResponsePrefix || parts[1] != requestId)
                {
                    continue;
                }

                if (parts[2] == "OK")
                {
                    return;
                }

                var message = parts.Length == 4 && parts[3].Length > 0
                    ? Encoding.UTF8.GetString(Convert.FromBase64String(parts[3]))
                    : "Unknown PowerShell route worker error.";
                throw new InvalidOperationException(message.Trim());
            }
        }
        catch
        {
            StopWorker();
            throw;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        await _gate.WaitAsync();
        try
        {
            StopWorker();
        }
        finally
        {
            _gate.Release();
            _gate.Dispose();
        }
    }

    private Process EnsureStarted()
    {
        if (_process is { HasExited: false })
        {
            return _process;
        }

        StopWorker();
        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            },
            EnableRaisingEvents = true
        };
        process.StartInfo.ArgumentList.Add("-NoLogo");
        process.StartInfo.ArgumentList.Add("-NoProfile");
        process.StartInfo.ArgumentList.Add("-NonInteractive");
        process.StartInfo.ArgumentList.Add("-ExecutionPolicy");
        process.StartInfo.ArgumentList.Add("Bypass");
        process.StartInfo.ArgumentList.Add("-Command");
        process.StartInfo.ArgumentList.Add(WorkerScript);

        if (!process.Start())
        {
            process.Dispose();
            throw new InvalidOperationException("Failed to start the persistent PowerShell route worker.");
        }

        process.ErrorDataReceived += (_, args) =>
        {
            if (!string.IsNullOrWhiteSpace(args.Data))
            {
                logger.LogWarning("PowerShell route worker stderr: {Error}", args.Data);
            }
        };
        process.BeginErrorReadLine();
        _process = process;
        logger.LogInformation("Started persistent PowerShell route worker with process ID {ProcessId}.", process.Id);
        return process;
    }

    private void StopWorker()
    {
        var process = _process;
        _process = null;
        if (process is null)
        {
            return;
        }

        try
        {
            process.StandardInput.Close();
            if (!process.WaitForExit(2000))
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(2000);
            }
        }
        catch (InvalidOperationException)
        {
        }
        finally
        {
            process.Dispose();
        }
    }

    private const string WorkerScript = """
        while (($line = [Console]::In.ReadLine()) -ne $null) {
            $separator = $line.IndexOf('|')
            if ($separator -lt 1) { continue }
            $requestId = $line.Substring(0, $separator)
            try {
                $payload = $line.Substring($separator + 1)
                $command = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
                & ([ScriptBlock]::Create($command))
                [Console]::Out.WriteLine("__VPNROUTER__|$requestId|OK|")
            }
            catch {
                $message = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($_ | Out-String)))
                [Console]::Out.WriteLine("__VPNROUTER__|$requestId|ERROR|$message")
            }
            [Console]::Out.Flush()
        }
        """;
}
