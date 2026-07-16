using System.Text.Json;

namespace VpnRouter.Ipc.NamedPipes;

public sealed record IpcRequestEnvelope(IpcCommandKind Command, JsonElement Payload);

public sealed record IpcResponseEnvelope(bool Success, string Message, JsonElement? Payload = null);
