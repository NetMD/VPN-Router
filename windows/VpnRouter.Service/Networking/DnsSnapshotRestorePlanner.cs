using System.Text.Json;

namespace VpnRouter.Service.Networking;

internal static class DnsSnapshotRestorePlanner
{
    internal static IReadOnlyList<DnsSnapshotEntry> ParseEntries(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        var elements = document.RootElement.ValueKind == JsonValueKind.Array
            ? document.RootElement.EnumerateArray().ToArray()
            : [document.RootElement];

        return elements
            .Where(element => element.TryGetProperty("InterfaceIndex", out _))
            .Select(element =>
            {
                var interfaceIndex = element.GetProperty("InterfaceIndex").GetInt32();
                var addressFamily = element.TryGetProperty("AddressFamily", out var familyElement)
                    ? familyElement.ToString()
                    : string.Empty;
                var serverAddresses = element.TryGetProperty("ServerAddresses", out var addressesElement)
                    ? ReadServerAddresses(addressesElement)
                    : [];
                var isAutomatic = element.TryGetProperty("IsAutomatic", out var automaticElement)
                    && automaticElement.ValueKind is JsonValueKind.True or JsonValueKind.False
                        ? automaticElement.GetBoolean()
                        : (bool?)null;

                return new DnsSnapshotEntry(interfaceIndex, addressFamily, serverAddresses, isAutomatic);
            })
            .ToArray();
    }

    internal static string? BuildRestoreCommand(DnsSnapshotEntry entry)
    {
        if (!IsIpv4(entry.AddressFamily))
        {
            return null;
        }

        if (entry.IsAutomatic == true || entry.ServerAddresses.Count == 0)
        {
            return $"Set-DnsClientServerAddress -InterfaceIndex {entry.InterfaceIndex} -ResetServerAddresses";
        }

        return $"Set-DnsClientServerAddress -InterfaceIndex {entry.InterfaceIndex} -ServerAddresses @({string.Join(",", entry.ServerAddresses.Select(ToPowerShellString))})";
    }

    private static IReadOnlyList<string> ReadServerAddresses(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Array => element.EnumerateArray()
                .Select(item => item.GetString())
                .Where(item => !string.IsNullOrWhiteSpace(item))
                .Select(item => item!)
                .ToArray(),
            JsonValueKind.String => string.IsNullOrWhiteSpace(element.GetString()) ? [] : [element.GetString()!],
            _ => []
        };
    }

    private static bool IsIpv4(string addressFamily)
    {
        return string.Equals(addressFamily, "IPv4", StringComparison.OrdinalIgnoreCase)
            || string.Equals(addressFamily, "2", StringComparison.OrdinalIgnoreCase)
            || string.Equals(addressFamily, "InterNetwork", StringComparison.OrdinalIgnoreCase);
    }

    private static string ToPowerShellString(string value) => $"'{value.Replace("'", "''")}'";
}

internal sealed record DnsSnapshotEntry(
    int InterfaceIndex,
    string AddressFamily,
    IReadOnlyList<string> ServerAddresses,
    bool? IsAutomatic);
