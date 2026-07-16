using System.IO.Pipes;
using System.Text.Json;
using VpnRouter.Ipc.NamedPipes;

namespace VpnRouter.Service.Ipc;

public sealed class NamedPipeIpcServer(
    IpcCommandHandler commandHandler,
    ILogger<NamedPipeIpcServer> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Named pipe IPC server listening on {PipeName}.", VpnRouterPipeNames.ServicePipeName);

        while (!stoppingToken.IsCancellationRequested)
        {
            await using var pipe = NamedPipeServerStreamAcl.Create(
                VpnRouterPipeNames.ServicePipeName,
                PipeDirection.InOut,
                NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Message,
                PipeOptions.Asynchronous,
                inBufferSize: 0,
                outBufferSize: 0,
                NamedPipeSecurityFactory.CreateServicePipeSecurity());

            try
            {
                await pipe.WaitForConnectionAsync(stoppingToken);
                await HandleConnectionAsync(pipe, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "IPC connection failed.");
            }
        }
    }

    private async Task HandleConnectionAsync(NamedPipeServerStream pipe, CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(pipe, leaveOpen: true);
        await using var writer = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };

        var requestJson = await reader.ReadLineAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(requestJson))
        {
            await WriteResponseAsync(writer, new IpcResponseEnvelope(false, "Empty IPC request."), cancellationToken);
            return;
        }

        IpcResponseEnvelope response;
        try
        {
            var request = JsonSerializer.Deserialize<IpcRequestEnvelope>(requestJson, VpnRouterIpcJson.Options);
            response = request is null
                ? new IpcResponseEnvelope(false, "Invalid IPC request.")
                : await commandHandler.HandleAsync(request, cancellationToken);
        }
        catch (JsonException ex)
        {
            logger.LogWarning(ex, "Invalid IPC JSON.");
            response = new IpcResponseEnvelope(false, "Invalid IPC JSON.");
        }

        await WriteResponseAsync(writer, response, cancellationToken);
    }

    private static Task WriteResponseAsync(
        StreamWriter writer,
        IpcResponseEnvelope response,
        CancellationToken cancellationToken)
    {
        var responseJson = JsonSerializer.Serialize(response, VpnRouterIpcJson.Options);
        return writer.WriteLineAsync(responseJson.AsMemory(), cancellationToken);
    }
}
