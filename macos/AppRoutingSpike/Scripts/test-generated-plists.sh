#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vpn-router-plist-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

if "$SCRIPT_DIR/verify-generated-plists.sh" "$TEST_ROOT" >/dev/null 2>&1; then
  echo "생성 plist 자체 검사 실패: 산출물이 없는데 통과했습니다." >&2
  exit 1
fi

echo "생성 plist 자체 검사 통과: 산출물 누락을 실패로 처리합니다."
