using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike;

public sealed record LiveApplyDecision(bool ApplyLiveWfp, WfpSpikeResultCode ResultCode);

public static class LiveApplyGate
{
    public static LiveApplyDecision Evaluate(bool hasExplicitApplyOption, bool isAdministrator, bool automatedGatePassed)
    {
        if (!hasExplicitApplyOption) return new(false, WfpSpikeResultCode.EXPLICIT_OPTION_REQUIRED);
        if (!isAdministrator) return new(false, WfpSpikeResultCode.ADMIN_REQUIRED);
        if (!automatedGatePassed) return new(false, WfpSpikeResultCode.AUTOMATED_GATE_FAILED);
        return new(true, WfpSpikeResultCode.NONE);
    }

    public static bool IsElevatedAdministrator()
    {
        if (!OperatingSystem.IsWindows()) return false;
        try
        {
            using var identity = WindowsIdentity.GetCurrent(TokenAccessLevels.Query);
            if (!GetTokenInformation(identity.AccessToken, TokenInformationClass.TokenElevation,
                    out var elevation, Marshal.SizeOf<TokenElevation>(), out _))
            {
                return false;
            }
            return elevation.TokenIsElevated != 0;
        }
        catch
        {
            return false;
        }
    }

    private enum TokenInformationClass { TokenElevation = 20 }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenElevation { public int TokenIsElevated; }

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(
        SafeAccessTokenHandle tokenHandle,
        TokenInformationClass tokenInformationClass,
        out TokenElevation tokenInformation,
        int tokenInformationLength,
        out int returnLength);
}
