namespace VpnRouter.Ipc.Contracts;

public static class VpnRouterProtocol
{
    public const int CurrentVersion = 1;
}

public sealed record BackendInformationDto(
    int ProtocolVersion,
    string ProductVersion,
    string PayloadIdentity);

public sealed record BackendCompatibilityResult(bool IsCompatible, string Message);

public static class BackendCompatibility
{
    public static BackendCompatibilityResult Validate(
        BackendInformationDto backend,
        string expectedProductVersion,
        string? expectedPayloadIdentity)
    {
        if (backend.ProtocolVersion != VpnRouterProtocol.CurrentVersion)
        {
            return new BackendCompatibilityResult(
                false,
                $"Backend protocol {backend.ProtocolVersion} is incompatible with required protocol {VpnRouterProtocol.CurrentVersion}.");
        }

        if (!string.Equals(backend.ProductVersion, expectedProductVersion, StringComparison.OrdinalIgnoreCase))
        {
            return new BackendCompatibilityResult(
                false,
                $"Backend version {backend.ProductVersion} does not match app version {expectedProductVersion}.");
        }

        if (!string.IsNullOrWhiteSpace(expectedPayloadIdentity)
            && !string.Equals(backend.PayloadIdentity, expectedPayloadIdentity, StringComparison.OrdinalIgnoreCase))
        {
            return new BackendCompatibilityResult(
                false,
                "A stale backend from a different portable payload is already running.");
        }

        return new BackendCompatibilityResult(true, "Backend is compatible.");
    }
}

public sealed record PortableCacheCleanupResponse(int RemovedCacheCount, int RetainedCacheCount);
