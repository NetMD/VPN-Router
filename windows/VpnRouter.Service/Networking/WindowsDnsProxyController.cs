using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using Microsoft.Extensions.Options;
using VpnRouter.Core.Rules;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Service.Configuration;

namespace VpnRouter.Service.Networking;

public sealed class WindowsDnsProxyController(
    IOptions<VpnRouterFeatureOptions> options,
    ILogger<WindowsDnsProxyController> logger) : IDnsProxyController
{
    private readonly object _gate = new();
    private CancellationTokenSource? _cts;
    private Task? _proxyTask;
    private IReadOnlyList<DomainRule> _rules = [];
    private int _listenPort = 53535;
    private readonly string _observationsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "dns-observations.json");

    public Task StartAsync(IReadOnlyList<DomainRule> rules, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (_proxyTask is { IsCompleted: false })
            {
                _rules = rules;
                return Task.CompletedTask;
            }

            _rules = rules;
            _listenPort = options.Value.EnableWindowsDnsMutation ? 53 : 53535;
            _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            _proxyTask = Task.Run(() => RunProxyAsync(_cts.Token), CancellationToken.None);
        }

        logger.LogInformation(
            "DNS proxy prototype started on 127.0.0.1:{ListenPort} for {RuleCount} rule(s). Windows DNS mutation enabled={DnsMutationEnabled}.",
            _listenPort,
            rules.Count,
            options.Value.EnableWindowsDnsMutation);
        return Task.CompletedTask;
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        CancellationTokenSource? cts;
        Task? proxyTask;

        lock (_gate)
        {
            cts = _cts;
            proxyTask = _proxyTask;
            _cts = null;
            _proxyTask = null;
        }

        if (cts is null || proxyTask is null)
        {
            return;
        }

        await cts.CancelAsync();
        try
        {
            await proxyTask.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken);
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

    private async Task RunProxyAsync(CancellationToken cancellationToken)
    {
        using var listener = new UdpClient(new IPEndPoint(IPAddress.Loopback, _listenPort));
        using var upstream = new UdpClient();

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

            _ = Task.Run(async () =>
            {
                try
                {
                    var query = DnsQueryParser.TryParse(request.Buffer);
                    if (query is not null && IsMatched(query.Domain))
                    {
                        await RecordObservationAsync(query, cancellationToken);
                        if (string.Equals(query.QueryType, "AAAA", StringComparison.OrdinalIgnoreCase))
                        {
                            var emptyResponse = DnsQueryParser.CreateEmptyNoErrorResponse(request.Buffer);
                            await listener.SendAsync(emptyResponse, emptyResponse.Length, request.RemoteEndPoint);
                            return;
                        }
                    }

                    await upstream.SendAsync(request.Buffer, new IPEndPoint(IPAddress.Parse("1.1.1.1"), 53), cancellationToken);
                    var response = await upstream.ReceiveAsync(cancellationToken);
                    await listener.SendAsync(response.Buffer, response.Buffer.Length, request.RemoteEndPoint);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogWarning(ex, "DNS proxy prototype failed to process query.");
                }
            }, cancellationToken);
        }
    }

    private bool IsMatched(string domain)
    {
        var rules = _rules;
        return rules.Any(rule =>
            rule.Enabled
            && (string.Equals(rule.Domain, domain, StringComparison.OrdinalIgnoreCase)
                || (rule.IncludeSubdomains && domain.EndsWith("." + rule.Domain, StringComparison.OrdinalIgnoreCase))));
    }

    private async Task RecordObservationAsync(DnsQuery query, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_observationsPath)!);
        var observation = new DnsObservation(DateTimeOffset.UtcNow, query.Domain, query.QueryType);
        await File.AppendAllTextAsync(_observationsPath, JsonSerializer.Serialize(observation) + Environment.NewLine, cancellationToken);
    }

    private sealed record DnsObservation(DateTimeOffset ObservedAt, string Domain, string QueryType);
}

public sealed record DnsQuery(string Domain, string QueryType);

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
}
