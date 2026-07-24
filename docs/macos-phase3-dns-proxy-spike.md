# macOS Phase 3 DNS Proxy spike

Last updated: 2026-07-24 KST

## Decision gate

Phase 3 determines whether a DNS Proxy can observe changing DNS answers and update
the existing Packet Tunnel route plan without breaking unrelated DNS, another
security product, or tunnel recovery.

This is an experiment, not yet product architecture. Do not enable a provider that
cannot forward both UDP and TCP DNS safely. Never stop, disable, or reconfigure a
third-party DNS, ad-blocking, antivirus, security, or VPN product.

## Confirmed Apple constraints

- `NEDNSProxyProvider` takes responsibility for system DNS flows, including UDP and
  TCP port 53 flows.
- On macOS, Apple supports a DNS Proxy provider as a **system extension** beginning
  with macOS 10.15. It is not added to the existing Packet Tunnel app-extension
  target.
- A directly distributed system extension uses the
  `dns-proxy-systemextension` Network Extension entitlement. The containing app also
  needs permission to install system extensions and matching provisioning.
- `NEDNSProxyManager` requires the Network Extensions capability with DNS Proxy
  selected.

Primary references:

- [DNS proxy provider](https://developer.apple.com/documentation/networkextension/dns-proxy-provider)
- [NEDNSProxyManager](https://developer.apple.com/documentation/networkextension/nednsproxymanager)
- [TN3134: Network Extension provider deployment](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)
- [Network Extensions entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)

## Current architecture impact

The current signed proof embeds `PacketTunnel.appex`. Phase 3 must keep that native
Packet Tunnel implementation isolated and add a separate DNS Proxy system extension
only if signing and provisioning succeed.

The checkpoint-B development target follows Xcode's current Network Extension system
extension template and requests `dns-proxy`. Before Developer ID distribution, use a
separate distribution entitlement/provisioning setup with
`dns-proxy-systemextension`; do not substitute the distribution entitlement into the
development checkpoint without matching provisioning.

Do not add DNS Proxy entitlement values speculatively to committed signing files.
First confirm that the owner's Developer Team can provision:

1. the containing app with System Extension installation and DNS Proxy management;
2. a separate system-extension identifier with `dns-proxy-systemextension`; and
3. the existing Packet Tunnel identifier without regressing its signed launch.

The host app contains a read-only **DNS Proxy 권한 확인** action in Diagnostics. It
calls only `loadFromPreferences`; it does not save, remove, or enable a DNS Proxy
configuration.

## Signed checkpoint A: preference access

1. Build and launch the host app with the existing owner-selected Team.
2. Open **진단**.
3. Select **DNS Proxy 권한 확인**.
4. Record only the user-facing success or error and its error domain/code. Do not
   attach provisioning profiles or private Team identifiers.
5. If access fails, enable the DNS Proxy capability for the host identifier in
   Xcode/developer provisioning and repeat.

Passing this checkpoint proves only preference access. It does not prove that a DNS
Proxy system extension can be installed or that DNS traffic is visible.

Result on 2026-07-24 KST: passed. The signed host app read DNS Proxy preferences,
reported that a VPN Router configuration existed, and reported that it was not
enabled. No preference was saved, removed, or enabled by the probe.

## Signed checkpoint B: system extension activation

After checkpoint A passes:

1. In Xcode, select the same owner-approved Team for the new
   `DNSProxyExtension` target.
2. Change its example bundle identifier to the signed host identifier plus
   `.DNSProxyExtension`. It must match the identifier derived by
   `TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier`.
3. Confirm the host target has System Extension installation and DNS Proxy
   capabilities, and the new target has DNS Proxy plus the shared App Group.
4. Require an explicit diagnostic action before requesting
   `OSSystemExtensionRequest.activationRequest`.
5. Build and run the signed host app, then select **진단 → DNS Proxy System
   Extension 활성화**.
6. Approve the extension in System Settings if macOS requests approval.
7. Record the user-facing activation result or its error domain/code without
   recording private Team or provisioning data.
8. Do not enable the DNS Proxy configuration until safe forwarding is implemented.

The repository includes the checkpoint-B target and explicit activation action.
Activation alone does not save or enable an `NEDNSProxyManager` configuration.

First activation finding on 2026-07-24 KST: NetworkExtension category validation
rejected the system extension because `NEMachServiceName` was based on the provider
bundle identifier rather than prefixed by an App Group in the signed extension
entitlements. The invalid staged copy was automatically removed. The Info.plist now
uses the shared App Group as the Mach service prefix.

Checkpoint-B result on 2026-07-24 KST: passed after the Mach service correction.
The owner approved the signed system extension, macOS reported it as
`activated enabled`, and the host app reported that the DNS Proxy configuration
remained disabled. No DNS flows were intercepted during this checkpoint.

## Signed checkpoint C: forwarding and coexistence

The forwarding spike must:

1. forward UDP and TCP DNS without changing query or response payloads;
2. retain only target-domain, answer-address, TTL, timestamp, and aggregate failure
   diagnostics;
3. never retain unrelated domain history or full DNS payloads;
4. send bounded, schema-versioned route observations to the Packet Tunnel;
5. stop the VPN through Network Extension if required ownership is lost;
6. remove only VPN Router-owned preferences during cleanup; and
7. be tested with existing DNS/security software enabled, without altering it.

If the system extension cannot be provisioned, cannot coexist, or cannot forward
reliably, Phase 3 ends with an explicit decision to retain pre-resolved routes.

### Checkpoint-C implementation status

The forwarding candidate has been exercised with signed DNS traffic:

- UDP DNS datagrams are forwarded to their original endpoints through bounded,
  per-query Network.framework connections.
- TCP flows are copied in both directions with completion-driven flow control, and
  length-prefixed DNS responses are inspected without modifying their payloads.
- Forwarded connections inherit the original flow metadata to prevent recursive
  interception and preserve provider-chain context.
- The host sends only saved, normalized, product-expanded target domains to the
  provider through the App Group-prefixed `NEMachServiceName` XPC service.
- The provider retains only schema-versioned target domain, IPv4 address,
  observation time, bounded expiry, and aggregate counters in memory. It does not
  log or retain DNS payloads or unrelated questions.
- The response parser rejects malformed or excessive messages, follows bounded
  CNAME chains, and uses the shorter CNAME/A TTL.
- The host merges active observations into the installed static plan, deduplicates
  IPv4 destinations, enforces a combined 512-route limit, and sends a
  schema-versioned `replace-routes` message to the Packet Tunnel.
- A diagnostic-only 15-second loop refreshes the observed set while both providers
  are active. The earliest usable observation TTL bounds the whole plan, so the
  Packet Tunnel disconnects if refresh stops.

The current Network.framework flow-endpoint implementation requires macOS 15 or
later. The application target's macOS 14 candidate minimum remains provisional;
on macOS 14 the provider refuses to start rather than accepting flows it cannot
forward with the same metadata-preserving path.

The host now provides that explicit diagnostic enable action and a separate
immediate-disable action. It verifies the provider bundle identifier before every
mutation, refuses to alter an unknown configuration, and removes preferences only
as an emergency fallback after confirming they belong to VPN Router. Enabling still
requires a user confirmation warning that another DNS/security product must not be
active. The UI reports only aggregate observation counts and timestamps. Disabling
the proxy while Packet Tunnel remains connected reapplies a fresh static plan; if
that fails or the provider message times out, VPN Router stops its own tunnel.

### First signed UDP attempt

The first explicit diagnostic activation reached the provider configuration
success state, but a bounded UDP DNS query received no response. Testing stopped
after that first failure. The owner used the immediate-disable action, the VPN
Router configuration became inactive, and a follow-up system DNS query succeeded.
No third-party extension or DNS preference was modified.

Unified logging did not expose enough provider detail to distinguish provider
startup, flow opening, and upstream forwarding. Before another activation, the
extension now records only aggregate runtime event counts plus the last error
domain/code in the VPN Router App Group. It does not record query names, endpoints,
addresses, or payloads in these runtime diagnostics.

### Final signed checkpoint-C results

Signed development builds on the real Mac verified:

- UDP forwarding: a controlled A query returned four answers.
- TCP forwarding: a forced TCP A query returned four answers and diagnostics
  recorded one accepted TCP flow.
- Aggregate forwarding run: 15 responses delivered with zero forwarding failures.
- XPC diagnostics: the host received bounded observations from the root-owned
  system extension without using a cross-user App Group preferences file.
- Simultaneous providers: Packet Tunnel remained connected with 33 selected routes,
  while UDP and TCP DNS both succeeded and the control address remained on `en6`.
- Dynamic route update: known media subdomain queries added 22 observed routes;
  the system `utun` route count increased from 29 to 52 without moving the control
  address off `en6`.
- Automatic TTL refresh: over approximately 85 seconds, the VPN remained connected
  while its system route count changed between 40 and 60 as observations appeared
  and expired.
- Fail-safe: a deliberately too-short first plan expired and disconnected the
  Packet Tunnel, removed its routes, and left normal DNS healthy.
- Proxy shutdown: disabling DNS Proxy while Packet Tunnel remained connected
  rebuilt the static plan and reduced the system route count from 74 to 31 without
  disconnecting.
- Final cleanup: disabling both providers left VPN Router disconnected, its tested
  `utun` route count at zero, its Packet Tunnel process stopped, and normal DNS
  healthy.
- Provider-message timeout: signed build 11 returned normal Packet Tunnel
  diagnostics through the new five-second guarded request path, reporting 27
  applied routes, fail-safe enabled, and seven IPv6 bypass-risk domains.

No third-party DNS, security, or VPN product was stopped, disabled, or reconfigured.
Two non-VPN Router system extensions remained activated during the tests; their
declared provider types included App Proxy and Packet Tunnel. This is baseline
coexistence evidence, not a complete compatibility matrix.

## Phase 3 product decision

Keep static pre-resolution as the default macOS MVP architecture. Retain the DNS
Proxy path as an explicit development diagnostic and continue hardening it after
Phase 3; do not enable it automatically in a consumer build yet.

The signed spike proves that the native DNS Proxy architecture is technically
viable for system UDP/TCP DNS, dynamic IPv4 discovery, Packet Tunnel route updates,
TTL-bounded fail-safe behavior, and clean provider teardown on this development Mac.
It does not yet prove all release conditions:

- Developer ID distribution provisioning for `dns-proxy-systemextension` remains
  unverified.
- The forwarding implementation currently raises the effective minimum to macOS 15,
  while the app's earlier candidate minimum was macOS 14.
- Browser DNS-over-HTTPS, encrypted DNS profiles, Private Relay behavior, captive
  portals, and an actually connected second VPN were not tested.
- Losing DNS ownership during an active session is not yet monitored continuously.
- Dynamic refresh currently depends on the host app's diagnostic loop; the
  Packet Tunnel fail-safe disconnects when refresh stops, but this is not yet a
  seamless consumer lifecycle.
- The route plan remains IPv4-only, so matching IPv6 traffic can bypass the tunnel.

Until those items are resolved, the supported product behavior remains bounded
pre-resolved IPv4 `/32` routes with the existing refresh and expiry policy, plus a
clear IPv6 and rotating-DNS limitation. The DNS Proxy code must remain behind
explicit diagnostic controls and must never alter another product.
