namespace VpnRouter.WfpSpike.Contracts;

/// <summary>
/// 판정 계약을 담는 한 곳입니다 (설계 §2.1 · §2.2 C# 거울).
///
/// outcome 네 값마다 허용하는 실패 코드를 <b>정확한 값 묶음</b>으로 적습니다.
/// "실패가 아님", "코드가 비어 있지 않음" 같은 느슨한 조건은 쓰지 않습니다 —
/// 그런 조건은 값이 하나 늘어나는 순간 조용히 통과합니다.
///
/// 으뜸 출처는 <c>scripts/windows/fixtures/wfp-spike/verdict-contract.json</c> 파일이고
/// 이 클래스는 그 거울입니다. 두 자리가 같은지는 집중 시험이 기계로 대조합니다
/// (<c>MatchesVerdictContractFixture</c>). 목록을 넓혀야 하면 파일과 이 클래스 두 곳만 고칩니다.
/// </summary>
public static class WfpVerdictContract
{
    /// <summary>기대한 관찰이 실제로 나왔다.</summary>
    public static IReadOnlySet<WfpSpikeResultCode> PassCodes { get; } =
        new HashSet<WfpSpikeResultCode> { WfpSpikeResultCode.NONE };

    /// <summary>쟀는데 기대와 달랐다. "재서 답이 나왔으나 틀림"만 여기 들어갑니다.</summary>
    public static IReadOnlySet<WfpSpikeResultCode> FailCodes { get; } =
        new HashSet<WfpSpikeResultCode>
        {
            WfpSpikeResultCode.UNEXPECTED_INTERFACE,
            WfpSpikeResultCode.DNS_APP_ID_NOT_PROPAGATED
        };

    /// <summary>실행하지 않았다.</summary>
    public static IReadOnlySet<WfpSpikeResultCode> NotRunCodes { get; } =
        new HashSet<WfpSpikeResultCode>
        {
            WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE,
            WfpSpikeResultCode.OWNER_ABORTED,
            WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE
        };

    /// <summary>실행했으나 결론을 내지 못했다. "재서 틀림"에 쓰는 두 코드는 여기 들어오지 않습니다.</summary>
    public static IReadOnlySet<WfpSpikeResultCode> InconclusiveCodes { get; } =
        new HashSet<WfpSpikeResultCode>
        {
            WfpSpikeResultCode.NEW_CONNECTION_NOT_OBSERVED,
            WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE
        };

    /// <summary>outcome → 허용 실패 코드 묶음. 목록에 없는 outcome 은 아무 코드도 허용하지 않습니다.</summary>
    public static IReadOnlyDictionary<WfpSpikeOutcome, IReadOnlySet<WfpSpikeResultCode>> FailureCodesByOutcome { get; } =
        new Dictionary<WfpSpikeOutcome, IReadOnlySet<WfpSpikeResultCode>>
        {
            [WfpSpikeOutcome.PASS] = PassCodes,
            [WfpSpikeOutcome.FAIL] = FailCodes,
            [WfpSpikeOutcome.NOT_RUN] = NotRunCodes,
            [WfpSpikeOutcome.INCONCLUSIVE] = InconclusiveCodes
        };

    /// <summary>
    /// outcome 과 실패 코드의 짝이 계약에 들어 있는지 봅니다.
    /// 목록에 없는 outcome (나중에 값이 늘어난 경우 포함) 은 <c>false</c> 입니다 — 조용히 통과하지 않습니다.
    /// </summary>
    public static bool IsValidCombination(WfpSpikeOutcome outcome, WfpSpikeResultCode code) =>
        FailureCodesByOutcome.TryGetValue(outcome, out var allowed) && allowed.Contains(code);
}
