#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h:h}
PROJECT_DIR="${REPOSITORY_ROOT}/macos/VPNRouter"
DERIVED_DATA_PATH=${VPNROUTER_DERIVED_DATA_PATH:-/private/tmp/vpnrouter-release-verify}
PRODUCT_VERSION=${VPNROUTER_PRODUCT_VERSION:-0.1.0}
BUILD_NUMBER=${VPNROUTER_BUILD_NUMBER:-1}
MINIMUM_MACOS_VERSION=${VPNROUTER_MINIMUM_MACOS_VERSION:-15.0}
PRODUCTS_DIR="${DERIVED_DATA_PATH}/Build/Products/Release"
WIREGUARD_GO_DIR="${PROJECT_DIR}/Vendor/wireguard-apple/Sources/WireGuardKitGo"
GO_BINARY=${VPNROUTER_GO_BINARY:-$(command -v go 2>/dev/null || true)}
SIGNED_APP_VERIFIER="${SCRIPT_DIR}/verify-signed-app.sh"

for tool in ar awk codesign ditto lipo xcodebuild xcrun make plutil shasum; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        print -u2 "Required tool is missing: ${tool}"
        exit 1
    fi
done

if [[ -z "${GO_BINARY}" || ! -x "${GO_BINARY}" ]]; then
    print -u2 "Required Go compiler is missing. Install Go or set VPNROUTER_GO_BINARY."
    exit 1
fi
export PATH="${GO_BINARY:h}:${PATH}"
"${GO_BINARY}" version

mkdir -p "${PRODUCTS_DIR}"

make -C "${WIREGUARD_GO_DIR}" \
    ARCHS=arm64 \
    PLATFORM_NAME=macosx \
    SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
    CONFIGURATION_BUILD_DIR="${PRODUCTS_DIR}" \
    CONFIGURATION_TEMP_DIR="${DERIVED_DATA_PATH}/Build/Intermediates.noindex/WireGuardGo" \
    DEPLOYMENT_TARGET_CLANG_FLAG_NAME=mmacosx-version-min \
    DEPLOYMENT_TARGET_CLANG_ENV_NAME=MACOSX_DEPLOYMENT_TARGET \
    MACOSX_DEPLOYMENT_TARGET="${MINIMUM_MACOS_VERSION}" \
    build

xcodebuild \
    -project "${PROJECT_DIR}/VPNRouter.xcodeproj" \
    -scheme VPNRouter \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET="${MINIMUM_MACOS_VERSION}" \
    MARKETING_VERSION="${PRODUCT_VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    SWIFT_COMPILATION_MODE=wholemodule \
    SWIFT_OPTIMIZATION_LEVEL=-O \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="${PRODUCTS_DIR}/VPNRouter.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
PACKET_TUNNEL_PATH="${APP_PATH}/Contents/PlugIns/PacketTunnel.appex"
DNS_PROXY_PATH="${APP_PATH}/Contents/Library/SystemExtensions/com.simple.VPNRouter.DNSProxyExtension.systemextension"
WIREGUARD_ARCHIVE="${PRODUCTS_DIR}/libwg-go.a"

test -d "${APP_PATH}"
test "$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}")" = "${PRODUCT_VERSION}"
test "$(plutil -extract CFBundleVersion raw "${INFO_PLIST}")" = "${BUILD_NUMBER}"
test -d "${PACKET_TUNNEL_PATH}"
test -d "${DNS_PROXY_PATH}"

verify_minimum_macos() {
    local binary_path=$1
    local label=$2
    local actual_version
    actual_version=$(xcrun vtool -show-build "${binary_path}" |
        awk '$1 == "minos" { print $2; exit }')
    if [[ "${actual_version}" != "${MINIMUM_MACOS_VERSION}" ]]; then
        print -u2 "${label} minimum macOS mismatch: expected ${MINIMUM_MACOS_VERSION}, got ${actual_version:-missing}"
        exit 1
    fi
}

verify_minimum_macos "${APP_PATH}/Contents/MacOS/VPNRouter" "Host App"
verify_minimum_macos \
    "${PACKET_TUNNEL_PATH}/Contents/MacOS/PacketTunnel" \
    "Packet Tunnel"
verify_minimum_macos \
    "${DNS_PROXY_PATH}/Contents/MacOS/com.simple.VPNRouter.DNSProxyExtension" \
    "DNS Proxy System Extension"

ARCHIVE_INSPECTION_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/vpnrouter-wg-inspect.XXXXXX")
trap 'rm -rf "${ARCHIVE_INSPECTION_DIR}"' EXIT
lipo "${WIREGUARD_ARCHIVE}" \
    -thin arm64 \
    -output "${ARCHIVE_INSPECTION_DIR}/libwg-go-arm64.a"
(
    cd "${ARCHIVE_INSPECTION_DIR}"
    ar -x libwg-go-arm64.a go.o 000000.o
)
verify_minimum_macos "${ARCHIVE_INSPECTION_DIR}/go.o" "WireGuard Go object"
verify_minimum_macos "${ARCHIVE_INSPECTION_DIR}/000000.o" "WireGuard CGO object"

SIGNING_FIXTURE="${ARCHIVE_INSPECTION_DIR}/VPNRouter.app"
ditto "${APP_PATH}" "${SIGNING_FIXTURE}"
codesign \
    --force \
    --sign - \
    --timestamp=none \
    --entitlements "${PROJECT_DIR}/DNSProxyExtension/DNSProxyExtension.entitlements" \
    "${SIGNING_FIXTURE}/Contents/Library/SystemExtensions/com.simple.VPNRouter.DNSProxyExtension.systemextension" \
    >/dev/null 2>&1
codesign \
    --force \
    --sign - \
    --timestamp=none \
    --entitlements "${PROJECT_DIR}/PacketTunnel/PacketTunnel.entitlements" \
    "${SIGNING_FIXTURE}/Contents/PlugIns/PacketTunnel.appex" \
    >/dev/null 2>&1
codesign \
    --force \
    --sign - \
    --timestamp=none \
    --entitlements "${PROJECT_DIR}/VPNRouter/VPNRouter.entitlements" \
    "${SIGNING_FIXTURE}" \
    >/dev/null 2>&1
"${SIGNED_APP_VERIFIER}" --mode adhoc-test "${SIGNING_FIXTURE}"

print "Verified unsigned Release build: ${APP_PATH}"
print "Version: ${PRODUCT_VERSION} (${BUILD_NUMBER})"
print "Minimum macOS: ${MINIMUM_MACOS_VERSION}"
shasum -a 256 "${WIREGUARD_ARCHIVE}"
print "This build is compile/package evidence only. Network Extension activation requires a signed archive."
