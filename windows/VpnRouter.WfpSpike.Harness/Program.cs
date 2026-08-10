using System.Text.Json;
using VpnRouter.WfpSpike.Contracts;
using VpnRouter.WfpSpike.Harness;

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};
var result = await OwnerHarnessRunner.RunAsync(args, cancellation.Token);
var json = JsonSerializer.Serialize(result, HarnessJsonContext.Default.WfpSpikeResult);
Console.WriteLine(json);

Environment.ExitCode = result.CleanupFailureCode is WfpSpikeResultCode.NONE or WfpSpikeResultCode.EXPLICIT_OPTION_REQUIRED ? 0 : 2;
