using System.Runtime.InteropServices;
using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike.Native;

internal static class WfpNativeConstants
{
    public const uint NextHopInterface = 1;
    public const uint Uint64 = 4;
    public const uint ByteBlob = 12;
    public const uint Sid = 13;
    public const uint MatchEqual = 0;
    public const uint NetworkConnectionPolicyContext = 13;
    public static readonly Guid AleAppId = new("d78e1e87-8644-4ea5-9437-d809ecefc971");
    public static readonly Guid AlePackageId = new("71bc78fa-f17c-4997-a602-6abb261f351c");
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeByteBlob { public uint Size; public nint Data; }
[StructLayout(LayoutKind.Sequential)]
internal struct NativeValue { public uint Type; public nint Value; }
[StructLayout(LayoutKind.Sequential)]
internal struct NativeConditionValue { public uint Type; public nint Value; }
[StructLayout(LayoutKind.Sequential)]
internal struct NativeFilterCondition { public Guid FieldKey; public uint MatchType; public NativeConditionValue ConditionValue; }
[StructLayout(LayoutKind.Sequential)]
internal struct NativeConnectionPolicySetting { public uint Type; public NativeValue Value; }
[StructLayout(LayoutKind.Sequential)]
internal struct NativeConnectionPolicySettings { public uint Count; public nint Settings; }
[StructLayout(LayoutKind.Sequential)]
internal struct NativeProviderContext
{
    public Guid ProviderContextKey;
    public NativeDisplayData DisplayData;
    public uint Flags;
    public nint ProviderKey;
    public NativeByteBlob ProviderData;
    public uint Type;
    public nint NetworkConnectionPolicy;
    public ulong ProviderContextId;
}

internal sealed class NativePolicyBuffer : IDisposable
{
    private readonly List<nint> _allocations = [];

    public NativePolicyBuffer(WfpPolicyPlan plan, IWfpIdentityLease identity, Guid key)
    {
        var displayName = AllocateString($"VPN Router {plan.IpVersion} app routing");
        var displayDescription = AllocateString("owner=VpnRouter.WfpSpike; schema=1");
        var luid = Allocate(plan.InterfaceLuid);
        var setting = Allocate(new NativeConnectionPolicySetting
        {
            Type = WfpNativeConstants.NextHopInterface,
            Value = new NativeValue { Type = WfpNativeConstants.Uint64, Value = luid }
        });
        var settings = Allocate(new NativeConnectionPolicySettings { Count = 1, Settings = setting });
        ConnectionPolicy = Allocate(new NativeProviderContext
        {
            ProviderContextKey = key,
            DisplayData = new NativeDisplayData { Name = displayName, Description = displayDescription },
            Type = WfpNativeConstants.NetworkConnectionPolicyContext,
            NetworkConnectionPolicy = settings
        });
        FilterCondition = Allocate(new NativeFilterCondition
        {
            FieldKey = identity.Kind == WfpAppIdentityKind.DesktopAppId ? WfpNativeConstants.AleAppId : WfpNativeConstants.AlePackageId,
            MatchType = WfpNativeConstants.MatchEqual,
            ConditionValue = new NativeConditionValue
            {
                Type = identity.Kind == WfpAppIdentityKind.DesktopAppId ? WfpNativeConstants.ByteBlob : WfpNativeConstants.Sid,
                Value = identity.Value
            }
        });
    }

    public nint ConnectionPolicy { get; }
    public nint FilterCondition { get; }

    private nint AllocateString(string value)
    {
        var pointer = Marshal.StringToHGlobalUni(value);
        _allocations.Add(pointer);
        return pointer;
    }

    private nint Allocate<T>(T value) where T : struct
    {
        var pointer = Marshal.AllocHGlobal(Marshal.SizeOf<T>());
        Marshal.StructureToPtr(value, pointer, false);
        _allocations.Add(pointer);
        return pointer;
    }

    public void Dispose()
    {
        for (var i = _allocations.Count - 1; i >= 0; i--) Marshal.FreeHGlobal(_allocations[i]);
        _allocations.Clear();
    }
}
