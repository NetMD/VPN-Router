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

for tool in xcodebuild xcrun make plutil shasum; do
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
    SWIFT_COMPILATION_MODE=incremental \
    SWIFT_OPTIMIZATION_LEVEL=-O \
    'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sil-perf-optzns' \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="${PRODUCTS_DIR}/VPNRouter.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

test -d "${APP_PATH}"
test "$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}")" = "${PRODUCT_VERSION}"
test "$(plutil -extract CFBundleVersion raw "${INFO_PLIST}")" = "${BUILD_NUMBER}"
test -d "${APP_PATH}/Contents/PlugIns/PacketTunnel.appex"

print "Verified unsigned Release build: ${APP_PATH}"
print "Version: ${PRODUCT_VERSION} (${BUILD_NUMBER})"
print "Minimum macOS: ${MINIMUM_MACOS_VERSION}"
shasum -a 256 "${PRODUCTS_DIR}/libwg-go.a"
print "This build is compile/package evidence only. Network Extension activation requires a signed archive."
