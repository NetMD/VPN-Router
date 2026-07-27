# VPN Router repository guidance

Read the platform handoff before starting platform-specific work:

- Windows: `docs/windows-next-session.md`, `docs/windows-mvp-handoff.md`,
  `docs/windows-mvp-progress.md`, and `docs/windows-release-hardening.md`
- macOS: `docs/macos-mvp-handoff.md`
- Release scope: `docs/v0.1.0-release-plan.md`

Platform networking implementations must remain native and isolated. Share product
semantics, domain-expansion rules, test cases, and diagnostic schemas where useful,
but do not force Windows service, DNS, route, WireGuard, UI, or packaging code into
the macOS implementation.

Never read, print, commit, or attach a raw WireGuard `.conf` or private key unless
the user explicitly authorizes that exact operation. Use sanitized fixtures with
fake keys for tests. Never disable, stop, or reconfigure third-party DNS, ad-blocking,
antivirus, security, or VPN products automatically.

On a Mac, begin with the environment inventory and Phase 0 in
`docs/macos-mvp-handoff.md`. Do not claim that a Network Extension works based only
on compilation; Packet Tunnel activation, routing, DNS behavior, disconnect, and
recovery require tests on a real signed macOS build.
