using System.Runtime.InteropServices;

namespace VpnRouter.WfpSpike.Native;

internal static partial class NativeMethods
{
    [LibraryImport("Fwpuclnt.dll", EntryPoint = "FwpmGetAppIdFromFileName0", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial uint FwpmGetAppIdFromFileName0(string fileName, out nint appId);

    [LibraryImport("Fwpuclnt.dll", EntryPoint = "FwpmFreeMemory0")]
    internal static partial void FwpmFreeMemory0(ref nint memory);

    [LibraryImport("Fwpuclnt.dll", EntryPoint = "FwpmEngineOpen0")]
    internal static partial uint FwpmEngineOpen0(nint serverName, uint authnService, nint authIdentity, nint session, out nint engineHandle);

    [LibraryImport("Fwpuclnt.dll", EntryPoint = "FwpmEngineClose0")]
    internal static partial uint FwpmEngineClose0(nint engineHandle);

    [LibraryImport("Fwpuclnt.dll", EntryPoint = "FwpmConnectionPolicyAdd0")]
    internal static partial uint FwpmConnectionPolicyAdd0(nint engineHandle, nint connectionPolicy, uint ipVersion, ulong weight, uint conditionCount, nint conditions, nint securityDescriptor);

    [LibraryImport("Fwpuclnt.dll", EntryPoint = "FwpmConnectionPolicyDeleteByKey0")]
    internal static partial uint FwpmConnectionPolicyDeleteByKey0(nint engineHandle, in Guid policyKey);

    [LibraryImport("Iphlpapi.dll", EntryPoint = "ConvertInterfaceIndexToLuid")]
    internal static partial uint ConvertInterfaceIndexToLuid(uint interfaceIndex, out ulong interfaceLuid);

    [LibraryImport("Iphlpapi.dll", EntryPoint = "ConvertInterfaceLuidToIndex")]
    internal static partial uint ConvertInterfaceLuidToIndex(in ulong interfaceLuid, out uint interfaceIndex);

    [LibraryImport("Userenv.dll", EntryPoint = "DeriveAppContainerSidFromAppContainerName", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial int DeriveAppContainerSidFromAppContainerName(string appContainerName, out nint sid);

    [LibraryImport("Advapi32.dll", EntryPoint = "IsValidSid")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool IsValidSid(nint sid);

    [LibraryImport("Advapi32.dll", EntryPoint = "EqualSid")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool EqualSid(nint firstSid, nint secondSid);

    [LibraryImport("Advapi32.dll", EntryPoint = "FreeSid")]
    internal static partial nint FreeSid(nint sid);

    [LibraryImport("Kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", StringMarshalling = StringMarshalling.Utf16, SetLastError = true)]
    internal static partial uint GetFinalPathNameByHandle(nint file, [Out] char[] path, uint pathLength, uint flags);

    [LibraryImport("KernelBase.dll", EntryPoint = "GetPackagesByPackageFamily", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial int GetPackagesByPackageFamily(string packageFamilyName, ref uint count, nint packageFullNames, ref uint bufferLength, nint buffer);
}
