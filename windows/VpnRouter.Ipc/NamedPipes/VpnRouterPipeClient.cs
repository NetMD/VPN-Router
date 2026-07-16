using System.IO.Pipes;
using System.Text.Json;

namespace VpnRouter.Ipc.NamedPipes;

public sealed class VpnRouterPipeClient(string serverName = ".")
{
    public async Task<IpcResponseEnvelope> SendAsync<TPayload>(
        IpcCommandKind command,
        TPayload payload,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        await using var pipe = new NamedPipeClientStream(
            serverName,
            VpnRouterPipeNames.ServicePipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous);

        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);

        await pipe.ConnectAsync(timeoutSource.Token);

        await using var writer = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
        using var reader = new StreamReader(pipe, leaveOpen: true);

        var request = new IpcRequestEnvelope(
            command,
            JsonSerializer.SerializeToElement(payload, VpnRouterIpcJson.Options));

        var requestJson = JsonSerializer.Serialize(request, VpnRouterIpcJson.Options);
        await writer.WriteLineAsync(requestJson.AsMemory(), timeoutSource.Token);

        var responseJson = await reader.ReadLineAsync(timeoutSource.Token);
        if (string.IsNullOrWhiteSpace(responseJson))
        {
            return new IpcResponseEnvelope(false, "The service returned an empty response.");
        }

        return JsonSerializer.Deserialize<IpcResponseEnvelope>(responseJson, VpnRouterIpcJson.Options)
            ?? new IpcResponseEnvelope(false, "The service returned an invalid response.");
    }
}
