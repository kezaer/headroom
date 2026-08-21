#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source Scripts/macos-compatibility.sh
source Scripts/sparkle-release-notes.sh

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/headroom-sparkle-release-notes.XXXXXX")"
SOURCE_DIR="${TEST_ROOT}/source"
WRONG_BUILD_SOURCE_DIR="${TEST_ROOT}/wrong-build-source"
UPDATES_DIR="${TEST_ROOT}/updates"
mkdir -p "${SOURCE_DIR}" "${WRONG_BUILD_SOURCE_DIR}" "${UPDATES_DIR}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "expected command to fail: $*"
  fi
}

assert_file_contains() {
  local path="$1"
  local expected="$2"

  grep -Fq "${expected}" "${path}" || fail "${path} does not contain ${expected}"
}

VERSION="9.8.7"
BUILD="654"
NOTE_NAME="Headroom-${VERSION}-${BUILD}.html"
NOTE_URL="https://headroom.example/${NOTE_NAME}"
APPCAST_PATH="${UPDATES_DIR}/appcast.xml"
FAKE_GENERATOR="${TEST_ROOT}/generate_appcast"

assert_fails \
  headroom_stage_sparkle_release_notes \
  "${VERSION}" \
  "${BUILD}" \
  "${SOURCE_DIR}" \
  "${UPDATES_DIR}"

: > "${SOURCE_DIR}/${NOTE_NAME}"
assert_fails \
  headroom_stage_sparkle_release_notes \
  "${VERSION}" \
  "${BUILD}" \
  "${SOURCE_DIR}" \
  "${UPDATES_DIR}"

printf '   \n\t' > "${SOURCE_DIR}/${NOTE_NAME}"
assert_fails \
  headroom_stage_sparkle_release_notes \
  "${VERSION}" \
  "${BUILD}" \
  "${SOURCE_DIR}" \
  "${UPDATES_DIR}"

cat > "${WRONG_BUILD_SOURCE_DIR}/Headroom-${VERSION}-653.html" <<'HTML'
<p>Notes for another build.</p>
HTML
assert_fails \
  headroom_stage_sparkle_release_notes \
  "${VERSION}" \
  "${BUILD}" \
  "${WRONG_BUILD_SOURCE_DIR}" \
  "${UPDATES_DIR}"
[[ ! -e "${UPDATES_DIR}/${NOTE_NAME}" ]] || fail "staged a note for the wrong build"

cat > "${SOURCE_DIR}/${NOTE_NAME}" <<'HTML'
<h2>More headroom at a glance</h2>
<p>This release improves the update workflow.</p>
HTML
headroom_stage_sparkle_release_notes \
  "${VERSION}" \
  "${BUILD}" \
  "${SOURCE_DIR}" \
  "${UPDATES_DIR}"
cmp -s "${SOURCE_DIR}/${NOTE_NAME}" "${UPDATES_DIR}/${NOTE_NAME}" || \
  fail "staged release notes differ from the source"

cat > "${FAKE_GENERATOR}" <<'BASH'
#!/bin/bash
set -euo pipefail

[[ "$1" == "--download-url-prefix" ]]
[[ "$2" == "https://headroom.example/" ]]
[[ "$3" == "--release-notes-url-prefix" ]]
[[ "$4" == "https://headroom.example/" ]]
updates_dir="$5"

cat > "${updates_dir}/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>653</sparkle:version>
      <sparkle:releaseNotesLink>https://headroom.example/Headroom-${FAKE_VERSION}-653.html</sparkle:releaseNotesLink>
    </item>
    <item>
      <sparkle:version>${FAKE_BUILD}</sparkle:version>
      <sparkle:releaseNotesLink>${FAKE_NOTE_URL}</sparkle:releaseNotesLink>
    </item>
  </channel>
</rss>
EOF
BASH
chmod +x "${FAKE_GENERATOR}"

FAKE_VERSION="${VERSION}" \
FAKE_BUILD="${BUILD}" \
FAKE_NOTE_URL="${NOTE_URL}" \
  headroom_generate_appcast_with_timeout \
  "${FAKE_GENERATOR}" \
  "https://headroom.example/" \
  "https://headroom.example/" \
  "${UPDATES_DIR}" \
  "4"
headroom_verify_appcast_release_notes \
  "${APPCAST_PATH}" \
  "${UPDATES_DIR}" \
  "${BUILD}" \
  "${NOTE_NAME}" \
  "${NOTE_URL}"

cat > "${TEST_ROOT}/failing_generate_appcast" <<'BASH'
#!/bin/bash
exit 42
BASH
chmod +x "${TEST_ROOT}/failing_generate_appcast"
generate_appcast_status=0
headroom_generate_appcast_with_timeout \
  "${TEST_ROOT}/failing_generate_appcast" \
  "https://headroom.example/" \
  "https://headroom.example/" \
  "${UPDATES_DIR}" \
  "4" || generate_appcast_status="$?"
[[ "${generate_appcast_status}" == "42" ]] || \
  fail "generate_appcast failure status was not preserved"

cat > "${TEST_ROOT}/slow_generate_appcast" <<'BASH'
#!/bin/bash
exec /bin/sleep 10
BASH
chmod +x "${TEST_ROOT}/slow_generate_appcast"
generate_appcast_status=0
headroom_generate_appcast_with_timeout \
  "${TEST_ROOT}/slow_generate_appcast" \
  "https://headroom.example/" \
  "https://headroom.example/" \
  "${UPDATES_DIR}" \
  "0" || generate_appcast_status="$?"
[[ "${generate_appcast_status}" == "124" ]] || \
  fail "generate_appcast timeout status was not preserved"

headroom_validate_sparkle_url_prefix "https://headroom.example/"
assert_fails headroom_validate_sparkle_url_prefix "http://headroom.example/"
assert_fails headroom_validate_sparkle_url_prefix "https://headroom.example"

headroom_write_minimal_sparkle_appcast \
  "${APPCAST_PATH}" \
  "https://headroom.example/appcast.xml" \
  "${VERSION}" \
  "${BUILD}" \
  "Fri, 21 Aug 2026 12:00:00 -0700" \
  "15.0.0" \
  "https://headroom.example/Headroom-${VERSION}-${BUILD}.dmg" \
  "test-signature" \
  "12345" \
  "${NOTE_URL}"
assert_file_contains "${APPCAST_PATH}" "<sparkle:releaseNotesLink>${NOTE_URL}</sparkle:releaseNotesLink>"
headroom_verify_appcast_release_notes \
  "${APPCAST_PATH}" \
  "${UPDATES_DIR}" \
  "${BUILD}" \
  "${NOTE_NAME}" \
  "${NOTE_URL}"

sed '/sparkle:releaseNotesLink/d' "${APPCAST_PATH}" > "${TEST_ROOT}/missing-link.xml"
assert_fails \
  headroom_verify_appcast_release_notes \
  "${TEST_ROOT}/missing-link.xml" \
  "${UPDATES_DIR}" \
  "${BUILD}" \
  "${NOTE_NAME}" \
  "${NOTE_URL}"

sed "s@${NOTE_URL}@https://headroom.example/Headroom-${VERSION}-653.html@" \
  "${APPCAST_PATH}" > "${TEST_ROOT}/wrong-link.xml"
assert_fails \
  headroom_verify_appcast_release_notes \
  "${TEST_ROOT}/wrong-link.xml" \
  "${UPDATES_DIR}" \
  "${BUILD}" \
  "${NOTE_NAME}" \
  "${NOTE_URL}"

MISSING_UPDATES_DIR="${TEST_ROOT}/missing-updates"
mkdir -p "${MISSING_UPDATES_DIR}"
assert_fails \
  headroom_verify_appcast_release_notes \
  "${APPCAST_PATH}" \
  "${MISSING_UPDATES_DIR}" \
  "${BUILD}" \
  "${NOTE_NAME}" \
  "${NOTE_URL}"

echo "PASS: Sparkle release notes contract"
