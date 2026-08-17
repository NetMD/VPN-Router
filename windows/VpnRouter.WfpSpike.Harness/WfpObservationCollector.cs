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

    // 판정 계약을 여기에 다시 적지 않고 한 곳(WfpVerdictContract)에 위임합니다 (설계 C-1 · R-02).
    // 공개 이름과 서명은 그대로 둡니다 — OwnerHarnessRunner 와 집중 시험이 이 이름으로 부릅니다.
    public static bool IsValidCombination(WfpSpikeOutcome outcome, WfpSpikeResultCode code) =>
        WfpVerdictContract.IsValidCombination(outcome, code);
}
