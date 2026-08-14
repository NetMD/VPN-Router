#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPIKE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PRODUCTS_ROOT=${1:-"$SPIKE_ROOT/DerivedData/Build/Products/Debug"}
HOST_PLIST="$PRODUCTS_ROOT/AppRoutingSpikeHost.app/Contents/Info.plist"
EXTENSION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :AppRoutingSpikeExtensionIdentifier' "$HOST_PLIST")"
EXTENSION_PLIST="$PRODUCTS_ROOT/AppRoutingSpikeHost.app/Contents/Library/SystemExtensions/$EXTENSION_IDENTIFIER.systemextension/Contents/Info.plist"
SELECTED_PLIST="$PRODUCTS_ROOT/AppRoutingSpikeSelectedTrafficHarness.app/Contents/Info.plist"
CONTROL_PLIST="$PRODUCTS_ROOT/AppRoutingSpikeControlTrafficHarness.app/Contents/Info.plist"

for plist in "$HOST_PLIST" "$EXTENSION_PLIST" "$SELECTED_PLIST" "$CONTROL_PLIST"; do
  if [ ! -f "$plist" ]; then
    echo "생성 plist 검사 실패: 필요한 산출물이 없습니다." >&2
    exit 1
  fi
  plutil -lint "$plist" >/dev/null
done
read_key() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

[ "$(read_key "$SELECTED_PLIST" SpikeHarnessRole)" = "selectedApp" ]
[ "$(read_key "$CONTROL_PLIST" SpikeHarnessRole)" = "controlApp" ]

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

provider_class=$(read_key "$EXTENSION_PLIST" "NetworkExtension:NEProviderClasses:'com.apple.networkextension.app-proxy'")
provider_module=${provider_class%.*}
provider_type=${provider_class##*.}
extension_executable=$(read_key "$EXTENSION_PLIST" CFBundleExecutable)
extension_binary=$(dirname "$EXTENSION_PLIST")/MacOS/$extension_executable
[ -f "$extension_binary" ]
expected_runtime_name="_TtC${#provider_module}${provider_module}${#provider_type}${provider_type}"
strings "$extension_binary" | grep -Fqx "$expected_runtime_name"

echo "생성 plist 검사 통과: 번들 식별자, Mach service, 공급자 클래스 연결이 일치합니다."
