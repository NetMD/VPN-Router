# VPN Router for macOS

VPN Router imports a user-supplied WireGuard profile and sends only selected
websites through that tunnel. Other traffic keeps using the Mac's normal network.

## Current dogfood scope

- Apple Silicon Mac
- macOS 15 or later
- WireGuard profiles only
- selected-site IPv4 `/32` split routes
- YouTube and Netflix media-domain expansion
- five-minute refresh with fifteen-minute rotating-answer retention and expiry
- a separate DNS Proxy system extension that has passed signed development
  testing for dynamic A observations and target AAAA filtering
- Korean consumer UI

The checked-in consumer Connect flow still starts with static pre-resolution, but
the owner-approved parity target is to make the proven DNS Proxy path mandatory
before the app reports `Connected`. That promotion and its new signed acceptance
matrix are the next implementation milestone. Until they pass, this repository
does not claim Windows/macOS feature parity or a public macOS release.

Signed development tests have covered target UDP/TCP AAAA filtering, dynamic
route updates, and a Tailscale/no-exit-node transition fail-safe. General
encrypted-DNS environments, Developer ID distribution, notarization,
clean-machine installation, automatic updates, and App Store distribution remain
unsupported or unverified.

## Privacy and safety

- Private keys are stored in Keychain.
- Profile metadata contains only sanitized WireGuard configuration.
- Troubleshooting exports contain bounded status and counts. They exclude raw
  configurations, keys, domains, IP addresses, DNS payloads, and free-form tunnel
  logs.
- VPN Router changes only its own Network Extension preferences.
- It never disables or reconfigures another VPN, DNS, ad-blocking, antivirus, or
  security product.

Do not attach a WireGuard `.conf` or an unreviewed system log to a bug report.

## Data locations

- Profile metadata: Application Support under the VPN Router app container
- Site rules: Application Support under the VPN Router app container
- Private keys: macOS Keychain
- Active routes and tunnel state: Network Extension lifecycle

Deleting an imported profile removes its metadata and Keychain private key. The
shared site list remains available for another profile.

## Recovery

1. Open **진단** and choose **시스템 상태 다시 불러오기**.
2. If connected, choose **연결 해제** and confirm normal browsing works.
3. If the installed VPN preference is stale, choose **설치 구성 제거** while
   disconnected. This removes only the VPN Router-owned macOS VPN preference and
   keeps imported profiles and sites.
4. Save a redacted troubleshooting file from **진단** if the problem persists.

VPN Router does not provide a shell recovery script because routes and DNS state
are owned by Network Extension and should disappear with its lifecycle.

## Local verification

Run:

```bash
scripts/macos/verify-release.sh
```

The script builds the WireGuard Go bridge and an unsigned arm64 Release app with
version `0.1.0`, build `1`, and a macOS 15 deployment target. It verifies the
embedded Packet Tunnel and prints the bridge checksum. An unsigned build proves
only compilation and packaging; it cannot validate Network Extension activation.

Signed dogfooding must be run from the owner's Xcode signing configuration on a
real Mac. Never commit the Developer Team identifier or local signing settings.

Codex resuming on the Mac should start with
`docs/macos-next-session.md` at the repository root.
