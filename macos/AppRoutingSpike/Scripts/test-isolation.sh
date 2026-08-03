#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/app-routing-isolation.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

git -C "$TEST_ROOT" init -q
git -C "$TEST_ROOT" config user.email "spike-test@example.invalid"
git -C "$TEST_ROOT" config user.name "Spike Test"
mkdir -p "$TEST_ROOT/macos/AppRoutingSpike" "$TEST_ROOT/windows"
cp "$SCRIPT_DIR/../.gitignore" "$TEST_ROOT/macos/AppRoutingSpike/.gitignore"
mkdir -p \
  "$TEST_ROOT/macos/AppRoutingSpike/DerivedData/Build" \
  "$TEST_ROOT/macos/AppRoutingSpike/DerivedData-test/Build"
touch "$TEST_ROOT/macos/AppRoutingSpike/allowed.txt"
touch \
  "$TEST_ROOT/macos/AppRoutingSpike/DerivedData/Build/probe" \
  "$TEST_ROOT/macos/AppRoutingSpike/DerivedData-test/Build/probe"

SPIKE_REPOSITORY_ROOT="$TEST_ROOT" "$SCRIPT_DIR/verify-isolation.sh" >/dev/null

generated_status=$(git -C "$TEST_ROOT" status --short --untracked-files=all -- \
  macos/AppRoutingSpike/DerivedData \
  macos/AppRoutingSpike/DerivedData-test)
if [ -n "$generated_status" ]; then
  echo "격리 자체 검사 실패: 정상 규칙에서도 생성물이 표시됩니다." >&2
  exit 1
fi

sed '/^\/DerivedData-test\/$/d' \
  "$TEST_ROOT/macos/AppRoutingSpike/.gitignore" \
  > "$TEST_ROOT/macos/AppRoutingSpike/.gitignore.without-test-output"
mv \
  "$TEST_ROOT/macos/AppRoutingSpike/.gitignore.without-test-output" \
  "$TEST_ROOT/macos/AppRoutingSpike/.gitignore"
if SPIKE_REPOSITORY_ROOT="$TEST_ROOT" "$SCRIPT_DIR/verify-isolation.sh" \
  > "$TEST_ROOT/missing-rule.out" 2>&1; then
  echo "격리 자체 검사 실패: DerivedData-test 규칙 누락을 놓쳤습니다." >&2
  exit 1
fi
if ! grep -q "생성물 Git 제외 규칙" "$TEST_ROOT/missing-rule.out"; then
  echo "격리 자체 검사 실패: 규칙 누락이 아닌 다른 이유로 실패했습니다." >&2
  exit 1
fi

cp "$SCRIPT_DIR/../.gitignore" "$TEST_ROOT/macos/AppRoutingSpike/.gitignore"
touch "$TEST_ROOT/windows/forbidden.txt"
if SPIKE_REPOSITORY_ROOT="$TEST_ROOT" "$SCRIPT_DIR/verify-isolation.sh" \
  > "$TEST_ROOT/protected-path.out" 2>&1; then
  echo "격리 자체 검사 실패: 미추적 보호 파일을 놓쳤습니다." >&2
  exit 1
fi
if ! grep -q "제품 또는 릴리스 보호 경로" "$TEST_ROOT/protected-path.out"; then
  echo "격리 자체 검사 실패: 보호 경로가 아닌 다른 이유로 실패했습니다." >&2
  exit 1
fi

echo "격리 자체 검사 통과: 정상·규칙 누락·보호 경로 세 사례를 확인했습니다."
