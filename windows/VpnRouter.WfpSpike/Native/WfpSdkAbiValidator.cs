using System.Diagnostics.CodeAnalysis;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Security.Cryptography;
using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike.Native;

public static class WfpSdkAbiValidator
{
    [DoesNotReturn]
    private static void Fail(string stage)
    {
        Console.Error.WriteLine($"ABI_FAILURE:{stage}");
        throw new WfpSpikeException(WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE);
    }

    private static readonly IReadOnlyDictionary<string, Type> ManagedLayouts = new Dictionary<string, Type>(StringComparer.Ordinal)
    {
        ["FWPM_PROVIDER_CONTEXT3"] = typeof(NativeProviderContext),
        ["FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0"] = typeof(NativeConnectionPolicySettings),
        ["FWPM_NETWORK_CONNECTION_POLICY_SETTING0"] = typeof(NativeConnectionPolicySetting),
        ["FWPM_FILTER_CONDITION0"] = typeof(NativeFilterCondition),
        ["FWP_VALUE0"] = typeof(NativeValue),
        ["FWP_CONDITION_VALUE0"] = typeof(NativeConditionValue),
        ["FWP_BYTE_BLOB"] = typeof(NativeByteBlob),
        ["FWPM_SESSION0"] = typeof(NativeFwpmSession),
        ["NET_LUID"] = typeof(ulong)
    };
    private static readonly IReadOnlyDictionary<string, string[]> OffsetFields = new Dictionary<string, string[]>(StringComparer.Ordinal)
    {
        ["FWPM_PROVIDER_CONTEXT3"] = [nameof(NativeProviderContext.ProviderContextKey), nameof(NativeProviderContext.DisplayData), nameof(NativeProviderContext.Flags), nameof(NativeProviderContext.ProviderKey), nameof(NativeProviderContext.ProviderData), nameof(NativeProviderContext.Type), nameof(NativeProviderContext.NetworkConnectionPolicy), nameof(NativeProviderContext.ProviderContextId)],
        ["FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0"] = [nameof(NativeConnectionPolicySettings.Count), nameof(NativeConnectionPolicySettings.Settings)],
        ["FWPM_NETWORK_CONNECTION_POLICY_SETTING0"] = [nameof(NativeConnectionPolicySetting.Type), nameof(NativeConnectionPolicySetting.Value)],
        ["FWPM_FILTER_CONDITION0"] = [nameof(NativeFilterCondition.FieldKey), nameof(NativeFilterCondition.MatchType), nameof(NativeFilterCondition.ConditionValue)],
        ["FWP_VALUE0"] = [nameof(NativeValue.Type), nameof(NativeValue.Value)],
        ["FWP_CONDITION_VALUE0"] = [nameof(NativeConditionValue.Type), nameof(NativeConditionValue.Value)],
        ["FWP_BYTE_BLOB"] = [nameof(NativeByteBlob.Size), nameof(NativeByteBlob.Data)],
        ["FWPM_SESSION0"] = [nameof(NativeFwpmSession.SessionKey), nameof(NativeFwpmSession.DisplayData), nameof(NativeFwpmSession.Flags), nameof(NativeFwpmSession.TransactionWaitTimeoutMilliseconds), nameof(NativeFwpmSession.ProcessId), nameof(NativeFwpmSession.Sid), nameof(NativeFwpmSession.Username), nameof(NativeFwpmSession.KernelMode)]
    };
    private static readonly string[] RequiredExports =
    [
        "Fwpuclnt.dll:FwpmGetAppIdFromFileName0",
        "Fwpuclnt.dll:FwpmFreeMemory0",
        "Fwpuclnt.dll:FwpmEngineOpen0",
        "Fwpuclnt.dll:FwpmEngineClose0",
        "Fwpuclnt.dll:FwpmConnectionPolicyAdd0",
        "Fwpuclnt.dll:FwpmConnectionPolicyDeleteByKey0",
        "Iphlpapi.dll:ConvertInterfaceIndexToLuid",
        "Iphlpapi.dll:ConvertInterfaceLuidToIndex"
        ,"Userenv.dll:DeriveAppContainerSidFromAppContainerName"
        ,"Advapi32.dll:IsValidSid"
        ,"Advapi32.dll:EqualSid"
        ,"Advapi32.dll:FreeSid"
    ];

    // SDK 헤더를 포함해 별도로 빌드한 x64 probe가 만든 증거가 없으면 live 경계를 열지 않습니다.
    public static void ValidateOrThrow()
    {
        var abiStage = "PLATFORM";
        if (!OperatingSystem.IsWindows() || RuntimeInformation.ProcessArchitecture != Architecture.X64)
            Fail("PLATFORM");

        abiStage = "EXPORTS";
        foreach (var item in RequiredExports)
        {
            var parts = item.Split(':', 2);
            if (!NativeLibrary.TryLoad(parts[0], out var library))
                Fail("EXPORT_LIBRARY");
            try
            {
                if (!NativeLibrary.TryGetExport(library, parts[1], out _))
                    Fail("EXPORT_SYMBOL");
            }
            finally { NativeLibrary.Free(library); }
        }

        var evidencePath = Path.Combine(AppContext.BaseDirectory, "wfp-sdk-abi-x64.json");
        if (!File.Exists(evidencePath))
            Fail("EVIDENCE_FILE");

        try
        {
            abiStage = "EVIDENCE_JSON";
            using var document = JsonDocument.Parse(File.ReadAllBytes(evidencePath));
            var root = document.RootElement;
            abiStage = "EVIDENCE_IDENTITY";
            if (root.GetProperty("schemaVersion").GetInt32() != 1 ||
                !string.Equals(root.GetProperty("architecture").GetString(), "x64", StringComparison.Ordinal) ||
                !root.TryGetProperty("sdkHeaderSha256", out var hash) ||
                !string.Equals(hash.GetString(), ComputeInstalledSdkHeaderHash(), StringComparison.OrdinalIgnoreCase) ||
                !root.TryGetProperty("probeSourceSha256", out var sourceHash) ||
                !string.Equals(sourceHash.GetString(), ComputeFileHash(Path.Combine(AppContext.BaseDirectory, "WfpSdkAbiProbe.cpp")), StringComparison.OrdinalIgnoreCase) ||
                !root.TryGetProperty("probeBinarySha256", out var binaryHash) ||
                !string.Equals(binaryHash.GetString(), ComputeFileHash(Path.Combine(AppContext.BaseDirectory, "WfpSdkAbiProbe.exe")), StringComparison.OrdinalIgnoreCase))
                Fail("EVIDENCE_IDENTITY");

            var layouts = root.GetProperty("layouts");
            abiStage = "LAYOUTS";
            foreach (var (name, type) in ManagedLayouts)
            {
                if (!layouts.TryGetProperty(name, out var nativeLayout) ||
                    nativeLayout.GetProperty("size").GetInt32() != Marshal.SizeOf(type))
                    Fail($"LAYOUT_SIZE_{name}");
                if (!OffsetFields.TryGetValue(name, out var fields)) continue;
                var nativeOffsets = nativeLayout.GetProperty("offsets");
                foreach (var field in fields)
                    if (!nativeOffsets.TryGetProperty(field, out var nativeOffset) ||
                        nativeOffset.GetInt32() != Marshal.OffsetOf(type, field).ToInt32())
                        Fail($"LAYOUT_OFFSET_{name}_{field}");
            }
            var constants = root.GetProperty("constants");
            abiStage = "CONSTANTS";
            if (constants.GetProperty("NextHopInterface").GetUInt32() != WfpNativeConstants.NextHopInterface ||
                constants.GetProperty("Uint64").GetUInt32() != WfpNativeConstants.Uint64 ||
                constants.GetProperty("ByteBlob").GetUInt32() != WfpNativeConstants.ByteBlob ||
                constants.GetProperty("Sid").GetUInt32() != WfpNativeConstants.Sid ||
                constants.GetProperty("MatchEqual").GetUInt32() != WfpNativeConstants.MatchEqual ||
                constants.GetProperty("NetworkConnectionPolicyContext").GetUInt32() != WfpNativeConstants.NetworkConnectionPolicyContext ||
                !Guid.TryParse(constants.GetProperty("AleAppId").GetString(), out var appId) || appId != WfpNativeConstants.AleAppId ||
                !Guid.TryParse(constants.GetProperty("AlePackageId").GetString(), out var packageId) || packageId != WfpNativeConstants.AlePackageId)
                Fail("CONSTANTS");
        }
        catch (WfpSpikeException) { throw; }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"ABI_FAILURE:{abiStage}:{ex.GetType().Name}");
            throw new WfpSpikeException(WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE);
        }
    }

    public static string ComputeInstalledSdkHeaderHash()
    {
        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        var includeRoot = Path.Combine(programFilesX86, "Windows Kits", "10", "Include");
        var versionRoot = Directory.GetDirectories(includeRoot).OrderByDescending(Path.GetFileName, StringComparer.Ordinal).FirstOrDefault()
            ?? throw new WfpSpikeException(WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE);
        var relativePaths = new[] { "shared\\fwpmtypes.h", "shared\\fwptypes.h", "shared\\netioapi.h", "shared\\ifdef.h", "um\\fwpmu.h", "um\\userenv.h" };
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var relativePath in relativePaths)
        {
            var name = System.Text.Encoding.UTF8.GetBytes(relativePath.Replace('\\', '/'));
            hash.AppendData(name);
            hash.AppendData(File.ReadAllBytes(Path.Combine(versionRoot, relativePath)));
        }
        return Convert.ToHexString(hash.GetHashAndReset());
    }

    public static string ComputeFileHash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
}
