# VPN Router platform parity contract

Last updated: 2026-07-29 KST

## Owner decision

Windows and macOS must provide the same user-visible routing and safety
semantics. Their native implementations remain isolated: Windows keeps its
service, local DNS proxy, route APIs, DPAPI, UAC, IPC, and portable launcher;
macOS keeps SwiftUI, Keychain, Network Extension, Packet Tunnel, DNS Proxy, XPC,
and Apple signing/provisioning.

The Windows dashboard is the product UI reference for information hierarchy,
plain-language status, visual density, and primary actions. macOS must reproduce
that product experience with native SwiftUI controls and macOS accessibility,
windowing, keyboard, and appearance behavior rather than copying XAML.

## Required common behavior

| Capability | Required user-visible result |
|---|---|
| Profile lifecycle | Import, sanitize, rename, select, validate, and delete a WireGuard profile without exposing its private key. |
| Secret storage | Store private keys only in the platform-native protected store; never include them in metadata, logs, diagnostics, or payloads. |
| Site rules | Normalize root domains, include subdomains, and apply the same YouTube and Netflix media/CDN expansion set. |
| Dynamic discovery | Observe target A answers used by real traffic and add IPv4 host routes without requiring a reconnect. |
| Route lifetime | Refresh every five minutes where applicable, retain distinct rotating answers for their original fifteen-minute lifetime, and expire them individually. |
| Route bound | Reject a combined static/dynamic plan above 512 unique IPv4 host routes before partial mutation. |
| IPv6 protection | Return empty successful target AAAA answers while preserving target A and unrelated AAAA behavior. |
| Normal traffic | Keep the system default route and unrelated traffic on the primary network. |
| Encrypted DNS | Detect supported browser policy, warn or block when ownership cannot be proven, and never change browser or Private Relay settings automatically. |
| DNS ownership | Prove the actual response path before reporting Connected and monitor it continuously while connected. |
| Fail-safe | On DNS ownership, provider, or relevant second-VPN transition loss, stop only VPN Router, remove its routes/DNS state, and leave the other product unchanged. |
| Lifecycle | Derive state from the privileged/native backend, survive UI relaunch, and recover VPN Router-owned state after failure or restart. |
| Diagnostics | Export only schema-versioned bounded counts, states, timestamps, and failure codes; never raw domains, addresses, DNS payloads, configurations, keys, or unrestricted logs. |
| Captive portals | Require portal sign-in while VPN Router is disconnected; no automatic portal mutation is part of `v0.1.0`. |

## macOS parity rule

The macOS consumer build must promote the proven DNS Proxy path from a
Debug-only diagnostic feature to the supported connection path. Static
pre-resolution may bootstrap a connection internally, but the UI must remain
`Connecting` until the owned DNS Proxy is enabled, configured, reachable over
XPC, filtering target AAAA responses, and supplying dynamic observations.

If those conditions cannot be established, the consumer build must fail the
connection and clean up VPN Router-owned state. It must not silently report a
reduced static connection as equivalent to Windows. A static-only mode may remain
available in development diagnostics or as an explicitly labeled limited mode,
but it does not satisfy platform parity.

## UI parity rule

Both platforms use the same five product areas:

1. Home
2. VPN Profiles
3. VPN Sites
4. Troubleshooting
5. Settings

The Home screen leads with connection state, selected profile, selected-site
summary, one primary Connect/Disconnect action, and recent plain-language
status. Technical route, DNS, provider, and entitlement details stay in
Troubleshooting. Recovery and destructive actions remain separate and clearly
labeled.

macOS should adopt the Windows layout hierarchy, restrained light surfaces,
coral accent, compact navigation, and reduced diagnostic density while retaining
native menu commands, resizable layouts, keyboard focus, VoiceOver, increased
contrast, reduced motion, and the existing Automatic/Light/Dark appearance
choice.

## Evidence required before claiming parity

- Signed real-Mac Packet Tunnel and DNS Proxy activation.
- Target UDP and TCP A/AAAA behavior plus unrelated controls.
- Dynamic CDN observations producing live route updates.
- Fifteen-minute rotating-answer retention and 512-route rejection.
- Default/control route preservation.
- DNS ownership-loss cleanup.
- Another-VPN stable coexistence and transition fail-safe.
- Host relaunch, provider termination, sleep/wake, network change, disconnect,
  and restart recovery.
- Redacted diagnostics and profile/Keychain lifecycle checks.
- The corresponding Windows matrix remains passing.

Compilation, unsigned Network Extension builds, or static pre-resolution alone
do not satisfy this contract.
