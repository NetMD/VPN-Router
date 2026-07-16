using System.Net;
using VpnRouter.Core.Rules;
using VpnRouter.Networking.Abstractions;

namespace VpnRouter.Service.Networking;

public sealed class SystemDomainPreResolver(ILogger<SystemDomainPreResolver> logger) : IDomainPreResolver
{
    public async Task<IReadOnlyDictionary<string, IReadOnlyList<IPAddress>>> ResolveAsync(
        IReadOnlyList<DomainRule> rules,
        CancellationToken cancellationToken)
    {
        var results = new Dictionary<string, IReadOnlyList<IPAddress>>(StringComparer.OrdinalIgnoreCase);

        foreach (var rule in rules.Where(rule => rule.Enabled))
        {
            try
            {
                var addresses = await Dns.GetHostAddressesAsync(rule.Domain, cancellationToken);
                var ipv4Addresses = addresses
                    .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    .Distinct()
                    .ToArray();

                results[rule.Domain] = ipv4Addresses;
                logger.LogInformation("Pre-resolved {Domain} to {AddressCount} IPv4 address(es).", rule.Domain, ipv4Addresses.Length);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Failed to pre-resolve {Domain}.", rule.Domain);
                results[rule.Domain] = [];
            }
        }

        return results;
    }
}
