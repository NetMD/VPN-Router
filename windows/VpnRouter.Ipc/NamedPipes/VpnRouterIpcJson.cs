using System.Text.Json;
using System.Text.Json.Serialization;

namespace VpnRouter.Ipc.NamedPipes;

public static class VpnRouterIpcJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
        PropertyNameCaseInsensitive = true,
        WriteIndented = false
    };
}
