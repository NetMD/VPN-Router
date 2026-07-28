# VpnRouter.Installer

Installer placeholder.

Evaluate WiX Toolset vs. MSIX plus service bootstrapper after the privileged
Windows Service is installable and the WinUI app exists.

The installer must explicitly offer:

- `Current user`: per-user storage and authorization limited to that user.
- `All users`: machine-wide registration with deliberate service, data, ACL,
  upgrade, repair, and removal behavior for every supported local user.

Do not silently convert the current-user-only portable model into an all-users
installation.
