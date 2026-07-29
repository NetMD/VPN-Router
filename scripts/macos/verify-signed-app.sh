#!/bin/zsh

set -euo pipefail

SCRIPT_NAME=${0:t}

usage() {
    print -u2 "Usage: ${SCRIPT_NAME} [--mode development|distribution|adhoc-test] [--notarized] /path/to/VPNRouter.app"
}

MODE=distribution
REQUIRE_NOTARIZATION=0

while (( $# > 0 )); do
    case "$1" in
    --mode)
        (( $# >= 2 )) || {
            usage
            exit 2
        }
        MODE=$2
        shift 2
        ;;
    --notarized)
        REQUIRE_NOTARIZATION=1
        shift
        ;;
    --help)
        usage
        exit 0
        ;;
    -*)
        usage
        exit 2
        ;;
    *)
        break
        ;;
    esac
done

if [[ "${MODE}" != development && "${MODE}" != distribution && "${MODE}" != adhoc-test ]]; then
    usage
    exit 2
fi

if (( $# != 1 )); then
    usage
    exit 2
fi

if [[ "${MODE}" != distribution && "${REQUIRE_NOTARIZATION}" == 1 ]]; then
    print -u2 "Notarization verification is available only in distribution mode."
    exit 2
fi

for tool in awk codesign jq lipo plutil spctl xcrun; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        print -u2 "Required tool is missing: ${tool}"
        exit 1
    fi
done

APP_PATH=${1:A}
PACKET_TUNNEL_PATH="${APP_PATH}/Contents/PlugIns/PacketTunnel.appex"
DNS_PROXY_PATH="${APP_PATH}/Contents/Library/SystemExtensions/com.simple.VPNRouter.DNSProxyExtension.systemextension"
EXPECTED_VERSION=${VPNROUTER_PRODUCT_VERSION:-0.1.0}
EXPECTED_BUILD=${VPNROUTER_BUILD_NUMBER:-1}
EXPECTED_MINIMUM_MACOS=${VPNROUTER_MINIMUM_MACOS_VERSION:-15.0}

if [[ ! -d "${APP_PATH}" ]]; then
    print -u2 "VPN Router app bundle was not found."
    exit 1
fi

for bundle_path in "${PACKET_TUNNEL_PATH}" "${DNS_PROXY_PATH}"; do
    if [[ ! -d "${bundle_path}" ]]; then
        print -u2 "A required Network Extension is missing from the app bundle."
        exit 1
    fi
done

WORK_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/vpnrouter-signature-verify.XXXXXX")
trap 'rm -rf "${WORK_DIR}"' EXIT

HOST_ENTITLEMENTS="${WORK_DIR}/host-entitlements.plist"
PACKET_ENTITLEMENTS="${WORK_DIR}/packet-entitlements.plist"
DNS_ENTITLEMENTS="${WORK_DIR}/dns-entitlements.plist"

bundle_value() {
    local bundle_path=$1
    local key=$2
    plutil -extract "${key}" raw "${bundle_path}/Contents/Info.plist"
}

require_bundle_value() {
    local bundle_path=$1
    local key=$2
    local expected=$3
    local label=$4
    local actual
    actual=$(bundle_value "${bundle_path}" "${key}")
    if [[ "${actual}" != "${expected}" ]]; then
        print -u2 "${label} metadata does not match the release contract."
        exit 1
    fi
}

verify_minimum_macos() {
    local binary_path=$1
    local label=$2
    local actual
    actual=$(xcrun vtool -show-build "${binary_path}" |
        awk '$1 == "minos" { print $2; exit }')
    if [[ "${actual}" != "${EXPECTED_MINIMUM_MACOS}" ]]; then
        print -u2 "${label} minimum macOS does not match the release contract."
        exit 1
    fi
}

verify_arm64() {
    local binary_path=$1
    local label=$2
    local architectures
    architectures=$(lipo -archs "${binary_path}")
    if [[ " ${architectures} " != *" arm64 "* ]]; then
        print -u2 "${label} does not contain the required arm64 architecture."
        exit 1
    fi
}

extract_entitlements() {
    local bundle_path=$1
    local output_path=$2
    if ! codesign -d --entitlements :- "${bundle_path}" >"${output_path}" 2>/dev/null; then
        print -u2 "Could not read a required bundle's signed entitlements."
        exit 1
    fi
    plutil -lint "${output_path}" >/dev/null
}

require_entitlement() {
    local plist_path=$1
    local expression=$2
    local label=$3
    if ! plutil -convert json -o - "${plist_path}" |
        jq -e "${expression}" >/dev/null 2>&1; then
        print -u2 "${label} entitlement contract is not satisfied."
        exit 1
    fi
}

signature_details() {
    codesign -dvvv "$1" 2>&1 || true
}

verify_signature_kind() {
    local bundle_path=$1
    local label=$2
    local details
    details=$(signature_details "${bundle_path}")

    case "${MODE}" in
    adhoc-test)
        if [[ "${details}" != *"Signature=adhoc"* ]]; then
            print -u2 "${label} is not an ad hoc test fixture."
            exit 1
        fi
        ;;
    development)
        if [[ "${details}" == *"Signature=adhoc"* ]] ||
            [[ "${details}" != *"Authority=Apple Development:"* &&
                "${details}" != *"Authority=Developer ID Application:"* ]]; then
            print -u2 "${label} is not signed for owner-operated development testing."
            exit 1
        fi
        ;;
    distribution)
        if [[ "${details}" != *"Authority=Developer ID Application:"* ]] ||
            [[ "${details}" != *"flags="*"runtime"* ]]; then
            print -u2 "${label} is not a hardened Developer ID Application signature."
            exit 1
        fi
        ;;
    esac
}

require_bundle_value "${APP_PATH}" CFBundleIdentifier com.simple.VPNRouter "Host App"
require_bundle_value "${PACKET_TUNNEL_PATH}" CFBundleIdentifier com.simple.VPNRouter.PacketTunnel "Packet Tunnel"
require_bundle_value "${DNS_PROXY_PATH}" CFBundleIdentifier com.simple.VPNRouter.DNSProxyExtension "DNS Proxy System Extension"

for bundle_path in "${APP_PATH}" "${PACKET_TUNNEL_PATH}" "${DNS_PROXY_PATH}"; do
    require_bundle_value "${bundle_path}" CFBundleShortVersionString "${EXPECTED_VERSION}" "Nested bundle"
    require_bundle_value "${bundle_path}" CFBundleVersion "${EXPECTED_BUILD}" "Nested bundle"
done

HOST_BINARY="${APP_PATH}/Contents/MacOS/VPNRouter"
PACKET_BINARY="${PACKET_TUNNEL_PATH}/Contents/MacOS/PacketTunnel"
DNS_BINARY="${DNS_PROXY_PATH}/Contents/MacOS/com.simple.VPNRouter.DNSProxyExtension"

verify_minimum_macos "${HOST_BINARY}" "Host App"
verify_minimum_macos "${PACKET_BINARY}" "Packet Tunnel"
verify_minimum_macos "${DNS_BINARY}" "DNS Proxy System Extension"
verify_arm64 "${HOST_BINARY}" "Host App"
verify_arm64 "${PACKET_BINARY}" "Packet Tunnel"
verify_arm64 "${DNS_BINARY}" "DNS Proxy System Extension"

for bundle_path in "${PACKET_TUNNEL_PATH}" "${DNS_PROXY_PATH}" "${APP_PATH}"; do
    if ! codesign --verify --strict --all-architectures "${bundle_path}" >/dev/null 2>&1; then
        print -u2 "A required bundle signature is invalid."
        exit 1
    fi
done
if ! codesign --verify --deep --strict --all-architectures "${APP_PATH}" >/dev/null 2>&1; then
    print -u2 "The nested app signature chain is invalid."
    exit 1
fi

verify_signature_kind "${APP_PATH}" "Host App"
verify_signature_kind "${PACKET_TUNNEL_PATH}" "Packet Tunnel"
verify_signature_kind "${DNS_PROXY_PATH}" "DNS Proxy System Extension"

extract_entitlements "${APP_PATH}" "${HOST_ENTITLEMENTS}"
extract_entitlements "${PACKET_TUNNEL_PATH}" "${PACKET_ENTITLEMENTS}"
extract_entitlements "${DNS_PROXY_PATH}" "${DNS_ENTITLEMENTS}"

require_entitlement "${HOST_ENTITLEMENTS}" \
    '."com.apple.developer.networking.networkextension" | contains(["dns-proxy", "packet-tunnel-provider"])' \
    "Host App Network Extension"
require_entitlement "${HOST_ENTITLEMENTS}" \
    '."com.apple.developer.system-extension.install" == true' \
    "Host App System Extension install"
require_entitlement "${HOST_ENTITLEMENTS}" \
    '."com.apple.security.application-groups" | contains(["group.com.simple.vpnrouter.shared"])' \
    "Host App application group"
require_entitlement "${HOST_ENTITLEMENTS}" \
    '."com.apple.security.files.user-selected.read-write" == true' \
    "Host App diagnostic export"
require_entitlement "${HOST_ENTITLEMENTS}" \
    '."com.apple.security.network.client" == true' \
    "Host App network client"
require_entitlement "${HOST_ENTITLEMENTS}" \
    '."keychain-access-groups" | any(endswith("com.simple.VPNRouter.shared"))' \
    "Host App Keychain group"

require_entitlement "${PACKET_ENTITLEMENTS}" \
    '."com.apple.developer.networking.networkextension" | contains(["packet-tunnel-provider"])' \
    "Packet Tunnel provider"
require_entitlement "${PACKET_ENTITLEMENTS}" \
    '."com.apple.security.application-groups" | contains(["group.com.simple.vpnrouter.shared"])' \
    "Packet Tunnel application group"
require_entitlement "${PACKET_ENTITLEMENTS}" \
    '."com.apple.security.network.client" == true and ."com.apple.security.network.server" == true' \
    "Packet Tunnel network access"
require_entitlement "${PACKET_ENTITLEMENTS}" \
    '."keychain-access-groups" | any(endswith("com.simple.VPNRouter.shared"))' \
    "Packet Tunnel Keychain group"

require_entitlement "${DNS_ENTITLEMENTS}" \
    '."com.apple.developer.networking.networkextension" | contains(["dns-proxy"])' \
    "DNS Proxy provider"
require_entitlement "${DNS_ENTITLEMENTS}" \
    '."com.apple.security.application-groups" | contains(["group.com.simple.vpnrouter.shared"])' \
    "DNS Proxy application group"
require_entitlement "${DNS_ENTITLEMENTS}" \
    '."com.apple.security.network.client" == true' \
    "DNS Proxy network client"

HOST_KEYCHAIN_GROUP=$(plutil -convert json -o - "${HOST_ENTITLEMENTS}" |
    jq -r '."keychain-access-groups"[0]')
PACKET_KEYCHAIN_GROUP=$(plutil -convert json -o - "${PACKET_ENTITLEMENTS}" |
    jq -r '."keychain-access-groups"[0]')
if [[ "${HOST_KEYCHAIN_GROUP}" != "${PACKET_KEYCHAIN_GROUP}" ]]; then
    print -u2 "Host App and Packet Tunnel do not share the same signed Keychain group."
    exit 1
fi

if (( REQUIRE_NOTARIZATION == 1 )); then
    if ! xcrun stapler validate "${APP_PATH}" >/dev/null 2>&1; then
        print -u2 "The notarization ticket is missing or invalid."
        exit 1
    fi
    if ! spctl --assess --type execute "${APP_PATH}" >/dev/null 2>&1; then
        print -u2 "Gatekeeper rejected the app."
        exit 1
    fi
fi

case "${MODE}" in
adhoc-test)
    print "Verified ad hoc signing fixture structure. This is not signed runtime or release evidence."
    ;;
development)
    print "Verified owner-signed development app structure and entitlements."
    ;;
distribution)
    if (( REQUIRE_NOTARIZATION == 1 )); then
        print "Verified hardened Developer ID signatures, entitlements, notarization, and Gatekeeper assessment."
    else
        print "Verified hardened Developer ID signatures and entitlements. Notarization was not requested."
    fi
    ;;
esac
