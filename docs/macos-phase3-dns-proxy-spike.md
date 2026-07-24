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

The first forwarding candidate is implemented but has not yet been enabled or
validated with signed DNS traffic:

- UDP DNS datagrams are forwarded to their original endpoints through bounded,
  per-query Network.framework connections.
- TCP flows are copied in both directions with completion-driven flow control, and
  length-prefixed DNS responses are inspected without modifying their payloads.
- Forwarded connections inherit the original flow metadata to prevent recursive
  interception and preserve provider-chain context.
- The host publishes only saved, normalized, product-expanded target domains to
  the shared App Group.
- The provider retains only schema-versioned target domain, IPv4 address,
  observation time, and bounded expiry. It does not log or retain DNS payloads or
  unrelated questions.
- The response parser rejects malformed or excessive messages, follows bounded
  CNAME chains, and uses the shorter CNAME/A TTL.

The current Network.framework flow-endpoint implementation requires macOS 15 or
later. The application target's macOS 14 candidate minimum remains provisional;
on macOS 14 the provider refuses to start rather than accepting flows it cannot
forward with the same metadata-preserving path.

Passing unit tests and an unsigned build do not prove live forwarding. The next
checkpoint is a signed, explicitly enabled diagnostic test covering ordinary UDP
DNS, forced TCP DNS, provider stop/restart, and unchanged unrelated connectivity.
The host now provides that explicit diagnostic enable action and a separate
immediate-disable action. It verifies the provider bundle identifier before every
mutation, refuses to alter an unknown configuration, and removes preferences only
as an emergency fallback after confirming they belong to VPN Router. Enabling still
requires a user confirmation warning that another DNS/security product must not be
active. The UI reports only aggregate observation counts and timestamps.

The DNS Proxy configuration remains disabled until the updated signed build is
installed and the diagnostic test is deliberately started.

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
