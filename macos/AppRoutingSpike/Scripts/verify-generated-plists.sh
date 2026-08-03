#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPIKE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PRODUCTS_ROOT=${1:-"$SPIKE_ROOT/DerivedData/Build/Products/Debug"}
HOST_PLIST="$PRODUCTS_ROOT/AppRoutingSpikeHost.app/Contents/Info.plist"
EXTENSION_PLIST="$PRODUCTS_ROOT/AppRoutingSpikeHost.app/Contents/Library/SystemExtensions/AppRoutingSpikeTransparentProxy.systemextension/Contents/Info.plist"

for plist in "$HOST_PLIST" "$EXTENSION_PLIST"; do
  plutil -lint "$plist" >/dev/null
done

read_key() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

host_identifier=$(read_key "$HOST_PLIST" CFBundleIdentifier)
extension_identifier=$(read_key "$EXTENSION_PLIST" CFBundleIdentifier)
declared_extension_identifier=$(read_key "$HOST_PLIST" AppRoutingSpikeExtensionIdentifier)
host_mach_service=$(read_key "$HOST_PLIST" AppRoutingSpikeMachServiceName)
extension_mach_service=$(read_key "$EXTENSION_PLIST" SpikeMachServiceName)
network_extension_mach_service=$(read_key "$EXTENSION_PLIST" NetworkExtension:NEMachServiceName)
declared_host_identifier=$(read_key "$EXTENSION_PLIST" SpikeHostBundleIdentifier)
read_key "$EXTENSION_PLIST" SpikeExpectedTeamIdentifier >/dev/null

[ "$declared_extension_identifier" = "$extension_identifier" ]
[ "$declared_host_identifier" = "$host_identifier" ]
[ "$host_mach_service" = "$extension_mach_service" ]
[ "$host_mach_service" = "$network_extension_mach_service" ]
[ "$(read_key "$HOST_PLIST" CFBundlePackageType)" = "APPL" ]
[ "$(read_key "$EXTENSION_PLIST" CFBundlePackageType)" = "SYSX" ]

echo "생성 plist 검사 통과: 번들 식별자와 Mach service 연결이 일치합니다."
