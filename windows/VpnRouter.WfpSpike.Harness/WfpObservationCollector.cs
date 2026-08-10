using System.Text.Json;
using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike.Harness;

public sealed class WfpObservationCollector(int firstCase, int lastCase)
{
    private int _nextCase = firstCase;
    private bool _ready;

    public void MarkReady()
    {
        if (_ready) throw new InvalidOperationException();
        _ready = true;
    }

    public WfpSpikeCaseResult Accept(string json)
    {
        if (!_ready || _nextCase > lastCase) throw new WfpSpikeException(WfpSpikeResultCode.OWNER_ABORTED);
        using var document = JsonDocument.Parse(json);
        if (!OwnerHarnessRunner.HasOnlyProperties(document.RootElement, "caseId", "outcome", "failureCode"))
            throw new WfpSpikeException(WfpSpikeResultCode.OWNER_ABORTED);
        var value = JsonSerializer.Deserialize(json, HarnessJsonContext.Default.WfpObservationInput)
            ?? throw new WfpSpikeException(WfpSpikeResultCode.OWNER_ABORTED);
        var expected = $"M-{_nextCase:000}";
        if (!string.Equals(value.CaseId, expected, StringComparison.Ordinal) || !IsValidCombination(value.Outcome, value.FailureCode))
            throw new WfpSpikeException(WfpSpikeResultCode.OWNER_ABORTED);
        _nextCase++;
        return new(value.CaseId, value.Outcome, value.FailureCode, DateTimeOffset.UtcNow);
    }

    public static bool IsValidCombination(WfpSpikeOutcome outcome, WfpSpikeResultCode code) => outcome switch
    {
        WfpSpikeOutcome.PASS => code == WfpSpikeResultCode.NONE,
        WfpSpikeOutcome.FAIL => code != WfpSpikeResultCode.NONE,
        WfpSpikeOutcome.NOT_RUN => code is WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE or WfpSpikeResultCode.OWNER_ABORTED or WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE,
        _ => false
    };
}
