using System.Runtime.InteropServices;

namespace VpnRouter.WfpSpike.Native;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDisplayData
{
    public nint Name;
    public nint Description;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeFwpmSession
{
    public Guid SessionKey;
    public NativeDisplayData DisplayData;
    public uint Flags;
    public uint TransactionWaitTimeoutMilliseconds;
    public uint ProcessId;
    public nint Sid;
    public nint Username;
    public int KernelMode;
}

internal sealed class NativeSessionBuffer : IDisposable
{
    private nint _structure;
    private nint _name;
    private nint _description;

    public NativeSessionBuffer()
    {
        _name = Marshal.StringToHGlobalUni("VPN Router WFP Spike");
        _description = Marshal.StringToHGlobalUni("owner=VpnRouter.WfpSpike; schema=1");
        var session = new NativeFwpmSession
        {
            DisplayData = new NativeDisplayData { Name = _name, Description = _description },
            Flags = 1 // FWPM_SESSION_FLAG_DYNAMIC
        };
        _structure = Marshal.AllocHGlobal(Marshal.SizeOf<NativeFwpmSession>());
        Marshal.StructureToPtr(session, _structure, false);
    }

    public nint Pointer => _structure;

    public void Dispose()
    {
        var structure = Interlocked.Exchange(ref _structure, 0);
        if (structure != 0) Marshal.FreeHGlobal(structure);
        var name = Interlocked.Exchange(ref _name, 0);
        if (name != 0) Marshal.FreeHGlobal(name);
        var description = Interlocked.Exchange(ref _description, 0);
        if (description != 0) Marshal.FreeHGlobal(description);
    }
}
