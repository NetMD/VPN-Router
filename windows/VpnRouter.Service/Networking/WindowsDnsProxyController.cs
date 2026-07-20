using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;
using Microsoft.Extensions.Options;
using VpnRouter.Core.Rules;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Service.Configuration;

namespace VpnRouter.Service.Networking;

public sealed class WindowsDnsProxyController(
    IOptions<VpnRouterFeatureOptions> options,
    IRouteManager routeManager,
    ILogger<WindowsDnsProxyController> logger) : IDnsProxyController
{
    private const int SioUdpConnectionReset = -1744830452;
    private const string OwnershipTestSuffix = ".vpnrouter-self-test.invalid";
    private static readonly IPAddress OwnershipTestAddress = IPAddress.Parse("127.255.53.53");
    private readonly object _gate = new();
    private readonly object _routeBatchGate = new();
    private readonly SemaphoreSlim _observationGate = new(1, 1);
    private readonly DynamicRouteAccumulator _pendingRoutes = new();
    private TaskCompletionSource? _pendingRouteCompletion;
    private CancellationTokenSource? _cts;
    private Task? _proxyTask;
    private Task? _routeMaintenanceTask;
    private Task? _ownershipMonitorTask;
    private TaskCompletionSource<Exception>? _fatalFailure;
    private IReadOnlyList<DomainRule> _rules = [];
    private int _listenPort = 53535;
    private IPAddress _upstreamDnsServer = IPAddress.Parse("1.1.1.1");
    private Guid _profileId;
    private int _interfaceIndex;
    private readonly string _observationsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "dns-observations.json");

    public async Task StartAsync(
        IReadOnlyList<DomainRule> rules,
        IPAddress? upstreamDnsServer,
        Guid profileId,
        int interfaceIndex,
        CancellationToken cancellationToken)
    {
        var startedNewListener = false;
        lock (_gate)
        {
            if (_proxyTask is { IsCompleted: false })
            {
                _rules = rules;
            }
            else
            {
                _rules = rules;
                _listenPort = options.Value.EnableWindowsDnsMutation ? 53 : 53535;
                _upstreamDnsServer = upstreamDnsServer ?? FindSystemDnsServer() ?? IPAddress.Parse("1.1.1.1");
                _profileId = profileId;
                _interfaceIndex = interfaceIndex;
                var listener = CreateExclusiveListener(_listenPort);
                DisableUdpConnectionReset(listener);
                _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                _fatalFailure = new TaskCompletionSource<Exception>(TaskCreationOptions.RunContinuationsAsynchronously);
                _proxyTask = Task.Run(() => RunProxyAsync(listener, _cts.Token), CancellationToken.None);
                _routeMaintenanceTask = Task.Run(() => RunRouteMaintenanceAsync(_cts.Token), CancellationToken.None);
                startedNewListener = true;
            }
        }

        try
        {
            await VerifyListenerOwnershipAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            if (startedNewListener)
            {
                await StopAsync(CancellationToken.None);
            }

            throw new InvalidOperationException(
                "VPN Router가 로컬 DNS 응답을 안전하게 소유하지 못했습니다. " +
                "DNS 보호, 광고 차단, 보안 또는 다른 VPN 프로그램의 DNS 기능을 직접 끈 뒤 다시 시도해 주세요. " +
                "VPN Router는 해당 프로그램을 자동으로 종료하지 않습니다.",
                ex);
        }

        if (startedNewListener)
        {
            lock (_gate)
            {
                if (_cts is not null)
                {
                    _ownershipMonitorTask = Task.Run(
                        () => RunOwnershipMonitorAsync(_cts.Token),
                        CancellationToken.None);
                }
            }
        }

        logger.LogInformation(
            "DNS proxy prototype started on 127.0.0.1:{ListenPort} for {RuleCount} rule(s). Upstream={UpstreamDnsServer}. Windows DNS mutation enabled={DnsMutationEnabled}.",
            _listenPort,
            rules.Count,
            _upstreamDnsServer,
            options.Value.EnableWindowsDnsMutation);
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        CancellationTokenSource? cts;
        Task? proxyTask;
        Task? routeMaintenanceTask;
        Task? ownershipMonitorTask;

        lock (_gate)
        {
            cts = _cts;
            proxyTask = _proxyTask;
            routeMaintenanceTask = _routeMaintenanceTask;
            ownershipMonitorTask = _ownershipMonitorTask;
            _cts = null;
            _proxyTask = null;
            _routeMaintenanceTask = null;
            _ownershipMonitorTask = null;
            _fatalFailure = null;
        }

        if (cts is null || proxyTask is null)
        {
            return;
        }

        await cts.CancelAsync();
        try
        {
            await Task.WhenAll(
                    proxyTask,
                    routeMaintenanceTask ?? Task.CompletedTask,
                    ownershipMonitorTask ?? Task.CompletedTask)
                .WaitAsync(TimeSpan.FromSeconds(2), cancellationToken);
        }
        catch (OperationCanceledException)
        {
        }
        catch (TimeoutException)
        {
            logger.LogWarning("DNS proxy prototype did not stop within timeout.");
        }
        finally
        {
            cts.Dispose();
        }
    }

    public Task<Exception> WaitForFatalFailureAsync(CancellationToken cancellationToken)
    {
        Task<Exception> failureTask;
        lock (_gate)
        {
            failureTask = _fatalFailure?.Task
                ?? Task.FromException<Exception>(new InvalidOperationException("The DNS proxy is not running."));
        }

        return failureTask.WaitAsync(cancellationToken);
    }

    private async Task RunProxyAsync(UdpClient listener, CancellationToken cancellationToken)
    {
        using (listener)
        {
            await RunProxyLoopAsync(listener, cancellationToken);
        }
    }

    private async Task RunProxyLoopAsync(UdpClient listener, CancellationToken cancellationToken)
    {

        while (!cancellationToken.IsCancellationRequested)
        {
            UdpReceiveResult request;
            try
            {
                request = await listener.ReceiveAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (SocketException ex)
            {
                logger.LogWarning(ex, "DNS proxy receive failed; continuing to listen.");
                continue;
            }

            _ = Task.Run(async () =>
            {
                try
                {
                    var query = DnsQueryParser.TryParse(request.Buffer);
                    if (query is not null && query.Domain.EndsWith(OwnershipTestSuffix, StringComparison.OrdinalIgnoreCase))
                    {
                        var ownershipResponse = DnsQueryParser.CreateIpv4Response(request.Buffer, OwnershipTestAddress);
                        await SendResponseAsync(listener, ownershipResponse, request.RemoteEndPoint, cancellationToken);
                        return;
                    }

                    var isMatched = query is not null && IsMatched(query.Domain);
                    if (isMatched)
                    {
                        await RecordObservationAsync(query!, cancellationToken);
                        if (string.Equals(query!.QueryType, "AAAA", StringComparison.OrdinalIgnoreCase))
                        {
                            var emptyResponse = DnsQueryParser.CreateEmptyNoErrorResponse(request.Buffer);
                            await SendResponseAsync(listener, emptyResponse, request.RemoteEndPoint, cancellationToken);
                            return;
                        }
                    }

                    using var upstream = new UdpClient();
                    await upstream.SendAsync(request.Buffer, new IPEndPoint(_upstreamDnsServer, 53), cancellationToken);
                    using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                    timeoutSource.CancelAfter(TimeSpan.FromSeconds(5));
                    var response = await upstream.ReceiveAsync(timeoutSource.Token);
                    if (isMatched && query is not null)
                    {
                        var addresses = DnsQueryParser.ParseIpv4Answers(response.Buffer);
                        if (addresses.Count > 0)
                        {
                            await QueueRouteBatchAsync(query.Domain, addresses, cancellationToken);
                        }
                    }
                    await SendResponseAsync(listener, response.Buffer, request.RemoteEndPoint, cancellationToken);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogWarning(ex, "DNS proxy prototype failed to process query.");
                }
            }, cancellationToken);
        }
    }

    private async Task RunRouteMaintenanceAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromMinutes(1), cancellationToken);
                await routeManager.RemoveExpiredRoutesAsync(_profileId, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Expired route cleanup failed; it will be retried on the next maintenance interval.");
            }
        }
    }

    private async Task RunOwnershipMonitorAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
                await VerifyListenerOwnershipAsync(cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "VPN Router lost ownership of the local DNS response path.");
                lock (_gate)
                {
                    _fatalFailure?.TrySetResult(ex);
                }

                break;
            }
        }
    }

    private static async Task SendResponseAsync(
        UdpClient listener,
        byte[] response,
        IPEndPoint remoteEndPoint,
        CancellationToken cancellationToken)
    {
        await listener.Client.SendToAsync(
            response,
            SocketFlags.None,
            remoteEndPoint,
            cancellationToken);
    }

    private static void DisableUdpConnectionReset(UdpClient listener)
    {
        if (OperatingSystem.IsWindows())
        {
            listener.Client.IOControl((IOControlCode)SioUdpConnectionReset, [0, 0, 0, 0], null);
        }
    }

    private static UdpClient CreateExclusiveListener(int port)
    {
        var listener = new UdpClient(AddressFamily.InterNetwork);
        try
        {
            listener.ExclusiveAddressUse = true;
            listener.Client.Bind(new IPEndPoint(IPAddress.Loopback, port));
            return listener;
        }
        catch
        {
            listener.Dispose();
            throw;
        }
    }

    private async Task VerifyListenerOwnershipAsync(CancellationToken cancellationToken)
    {
        var transactionId = (ushort)Random.Shared.Next(ushort.MaxValue + 1);
        var domain = $"{Guid.NewGuid():N}{OwnershipTestSuffix}";
        var query = DnsQueryParser.CreateQuery(domain, transactionId, queryType: 1);

        using var client = new UdpClient(AddressFamily.InterNetwork);
        await client.SendAsync(query, new IPEndPoint(IPAddress.Loopback, _listenPort), cancellationToken);
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(TimeSpan.FromSeconds(2));
        var response = await client.ReceiveAsync(timeoutSource.Token);

        if (response.Buffer.Length < 2
            || response.Buffer[0] != query[0]
            || response.Buffer[1] != query[1]
            || !DnsQueryParser.ParseIpv4Answers(response.Buffer).Contains(OwnershipTestAddress))
        {
            throw new InvalidDataException("The local DNS ownership response did not come from VPN Router.");
        }
    }

    private static IPAddress? FindSystemDnsServer()
    {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(networkInterface =>
                networkInterface.OperationalStatus == OperationalStatus.Up
                && networkInterface.NetworkInterfaceType is not NetworkInterfaceType.Loopback
                && networkInterface.NetworkInterfaceType is not NetworkInterfaceType.Tunnel)
            .SelectMany(networkInterface => networkInterface.GetIPProperties().DnsAddresses)
            .FirstOrDefault(address =>
                address.AddressFamily == AddressFamily.InterNetwork
                && !IPAddress.IsLoopback(address));
    }

    private bool IsMatched(string domain)
    {
        var rules = _rules;
        return rules.Any(rule =>
            rule.Enabled
            && (string.Equals(rule.Domain, domain, StringComparison.OrdinalIgnoreCase)
                || (rule.IncludeSubdomains && domain.EndsWith("." + rule.Domain, StringComparison.OrdinalIgnoreCase))));
    }

    private async Task QueueRouteBatchAsync(
        string domain,
        IReadOnlyList<IPAddress> addresses,
        CancellationToken cancellationToken)
    {
        Task batchTask;
        lock (_routeBatchGate)
        {
            _pendingRoutes.Add(domain, addresses);
            if (_pendingRouteCompletion is null)
            {
                _pendingRouteCompletion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                _ = RunRouteBatchAsync(_pendingRouteCompletion, cancellationToken);
            }

            batchTask = _pendingRouteCompletion.Task;
        }

        try
        {
            await batchTask.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken);
        }
        catch (TimeoutException)
        {
            throw new TimeoutException(
                "Dynamic route batch exceeded the DNS response wait limit; the matched DNS response was withheld.");
        }
    }

    private async Task RunRouteBatchAsync(TaskCompletionSource completion, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromMilliseconds(100), cancellationToken);

            Dictionary<string, IReadOnlyList<IPAddress>> batch;
            lock (_routeBatchGate)
            {
                batch = _pendingRoutes.Drain();
                _pendingRouteCompletion = null;
            }

            await routeManager.AddHostRoutesAsync(batch, _profileId, _interfaceIndex, cancellationToken);
            completion.TrySetResult();
        }
        catch (OperationCanceledException)
        {
            completion.TrySetCanceled(cancellationToken);
        }
        catch (Exception ex)
        {
            completion.TrySetException(ex);
        }
    }

    private async Task RecordObservationAsync(DnsQuery query, CancellationToken cancellationToken)
    {
        await _observationGate.WaitAsync(cancellationToken);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_observationsPath)!);
            var observation = new DnsObservation(DateTimeOffset.UtcNow, query.Domain, query.QueryType);
            await File.AppendAllTextAsync(
                _observationsPath,
                JsonSerializer.Serialize(observation) + Environment.NewLine,
                cancellationToken);
        }
        finally
        {
            _observationGate.Release();
        }
    }

    private sealed record DnsObservation(DateTimeOffset ObservedAt, string Domain, string QueryType);
}

public sealed record DnsQuery(string Domain, string QueryType);

public sealed class DynamicRouteAccumulator
{
    private readonly object _gate = new();
    private Dictionary<string, HashSet<IPAddress>> _routes = new(StringComparer.OrdinalIgnoreCase);

    public void Add(string domain, IReadOnlyList<IPAddress> addresses)
    {
        lock (_gate)
        {
            if (!_routes.TryGetValue(domain, out var pendingAddresses))
            {
                pendingAddresses = [];
                _routes[domain] = pendingAddresses;
            }

            pendingAddresses.UnionWith(addresses);
        }
    }

    public Dictionary<string, IReadOnlyList<IPAddress>> Drain()
    {
        lock (_gate)
        {
            var batch = _routes.ToDictionary(
                pair => pair.Key,
                pair => (IReadOnlyList<IPAddress>)pair.Value.ToArray(),
                StringComparer.OrdinalIgnoreCase);
            _routes = new Dictionary<string, HashSet<IPAddress>>(StringComparer.OrdinalIgnoreCase);
            return batch;
        }
    }
}

public static class DnsQueryParser
{
    private const byte QueryResponseMask = 0x80;
    private const byte RecursionAvailableMask = 0x80;

    public static DnsQuery? TryParse(byte[] packet)
    {
        if (packet.Length < 14)
        {
            return null;
        }

        var offset = 12;
        var labels = new List<string>();

        while (offset < packet.Length)
        {
            var length = packet[offset++];
            if (length == 0)
            {
                break;
            }

            if (offset + length > packet.Length)
            {
                return null;
            }

            labels.Add(System.Text.Encoding.ASCII.GetString(packet, offset, length));
            offset += length;
        }

        if (labels.Count == 0 || offset + 4 > packet.Length)
        {
            return null;
        }

        var qtype = (packet[offset] << 8) | packet[offset + 1];
        var queryType = qtype switch
        {
            1 => "A",
            28 => "AAAA",
            _ => qtype.ToString()
        };

        return new DnsQuery(string.Join('.', labels), queryType);
    }

    public static byte[] CreateEmptyNoErrorResponse(byte[] queryPacket)
    {
        if (queryPacket.Length < 12)
        {
            throw new ArgumentException("DNS query packet is too short.", nameof(queryPacket));
        }

        var response = queryPacket.ToArray();
        response[2] |= QueryResponseMask;
        response[3] |= RecursionAvailableMask;
        response[3] &= 0xF0;

        response[6] = 0;
        response[7] = 0;
        response[8] = 0;
        response[9] = 0;
        response[10] = 0;
        response[11] = 0;

        return response;
    }

    public static byte[] CreateQuery(string domain, ushort transactionId, ushort queryType)
    {
        var labels = domain.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (labels.Length == 0 || labels.Any(label => label.Length is 0 or > 63))
        {
            throw new ArgumentException("DNS query domain contains an invalid label.", nameof(domain));
        }

        using var stream = new MemoryStream();
        stream.WriteByte((byte)(transactionId >> 8));
        stream.WriteByte((byte)transactionId);
        stream.Write([0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
        foreach (var label in labels)
        {
            var encoded = System.Text.Encoding.ASCII.GetBytes(label);
            stream.WriteByte((byte)encoded.Length);
            stream.Write(encoded);
        }

        stream.WriteByte(0);
        stream.WriteByte((byte)(queryType >> 8));
        stream.WriteByte((byte)queryType);
        stream.Write([0x00, 0x01]);
        return stream.ToArray();
    }

    public static byte[] CreateIpv4Response(byte[] queryPacket, IPAddress address)
    {
        var addressBytes = address.GetAddressBytes();
        if (addressBytes.Length != 4)
        {
            throw new ArgumentException("An IPv4 address is required.", nameof(address));
        }

        if (TryParse(queryPacket) is null)
        {
            throw new ArgumentException("A valid DNS query packet is required.", nameof(queryPacket));
        }

        var response = new byte[queryPacket.Length + 16];
        queryPacket.CopyTo(response, 0);
        response[2] |= QueryResponseMask;
        response[3] |= RecursionAvailableMask;
        response[3] &= 0xF0;
        response[6] = 0;
        response[7] = 1;
        response[8] = 0;
        response[9] = 0;
        response[10] = 0;
        response[11] = 0;

        var offset = queryPacket.Length;
        byte[] answer =
        [
            0xC0, 0x0C,
            0x00, 0x01,
            0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x04,
            addressBytes[0], addressBytes[1], addressBytes[2], addressBytes[3]
        ];
        answer.CopyTo(response, offset);
        return response;
    }

    public static IReadOnlyList<IPAddress> ParseIpv4Answers(byte[] packet)
    {
        if (packet.Length < 12)
        {
            return [];
        }

        var questionCount = ReadUInt16(packet, 4);
        var answerCount = ReadUInt16(packet, 6);
        var offset = 12;

        for (var i = 0; i < questionCount; i++)
        {
            if (!TrySkipName(packet, ref offset) || offset + 4 > packet.Length)
            {
                return [];
            }

            offset += 4;
        }

        var addresses = new List<IPAddress>();
        for (var i = 0; i < answerCount; i++)
        {
            if (!TrySkipName(packet, ref offset) || offset + 10 > packet.Length)
            {
                break;
            }

            var type = ReadUInt16(packet, offset);
            var recordClass = ReadUInt16(packet, offset + 2);
            var dataLength = ReadUInt16(packet, offset + 8);
            offset += 10;
            if (offset + dataLength > packet.Length)
            {
                break;
            }

            if (type == 1 && recordClass == 1 && dataLength == 4)
            {
                addresses.Add(new IPAddress(packet.AsSpan(offset, 4)));
            }

            offset += dataLength;
        }

        return addresses.Distinct().ToArray();
    }

    private static bool TrySkipName(byte[] packet, ref int offset)
    {
        while (offset < packet.Length)
        {
            var length = packet[offset++];
            if (length == 0)
            {
                return true;
            }

            if ((length & 0xC0) == 0xC0)
            {
                if (offset >= packet.Length)
                {
                    return false;
                }

                offset++;
                return true;
            }

            if (length > 63 || offset + length > packet.Length)
            {
                return false;
            }

            offset += length;
        }

        return false;
    }

    private static int ReadUInt16(byte[] packet, int offset) =>
        (packet[offset] << 8) | packet[offset + 1];
}
