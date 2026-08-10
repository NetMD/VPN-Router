using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike.Native;

public static class WfpNativeApiFactory
{
    public static IWfpNativeApi CreateLive()
    {
        WfpSdkAbiValidator.ValidateOrThrow();
        return new WfpNativeApi();
    }
}
