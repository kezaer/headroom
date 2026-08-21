#!/bin/bash

headroom_sparkle_release_notes_filename() {
  local version="$1"
  local build="$2"

  if [[ ! "${version}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Invalid release-note version: ${version}" >&2
    return 65
  fi
  if [[ ! "${build}" =~ ^[0-9]+$ ]]; then
    echo "Invalid release-note build: ${build}" >&2
    return 65
  fi

  printf 'Headroom-%s-%s.html\n' "${version}" "${build}"
}

headroom_validate_sparkle_url_prefix() {
  local url_prefix="$1"

  if [[ ! "${url_prefix}" =~ ^https://[^[:space:]]+/$ ]]; then
    echo "Sparkle download URL prefix must be an https URL ending in '/': ${url_prefix}" >&2
    return 64
  fi
}

headroom_file_has_nonwhitespace_content() {
  local path="$1"

  [[ -f "${path}" ]] && LC_ALL=C grep -q '[^[:space:]]' "${path}"
}

headroom_stage_sparkle_release_notes() {
  local version="$1"
  local build="$2"
  local source_dir="$3"
  local updates_dir="$4"
  local filename
  local source_path
  local staged_path

  filename="$(headroom_sparkle_release_notes_filename "${version}" "${build}")" || return
  source_path="${source_dir}/${filename}"
  staged_path="${updates_dir}/${filename}"

  if ! headroom_file_has_nonwhitespace_content "${source_path}"; then
    echo "Missing non-empty Sparkle release notes: ${source_path}" >&2
    return 65
  fi

  mkdir -p "${updates_dir}"
  cp "${source_path}" "${staged_path}"
  echo "→ staged Sparkle release notes: ${filename}"
}

headroom_generate_appcast_with_timeout() {
  local generate_appcast="$1"
  local download_url_prefix="$2"
  local release_notes_url_prefix="$3"
  local updates_dir="$4"
  local timeout_seconds="$5"
  local pid
  local elapsed=0

  "${generate_appcast}" \
    --download-url-prefix "${download_url_prefix}" \
    --release-notes-url-prefix "${release_notes_url_prefix}" \
    "${updates_dir}" &
  pid="$!"

  while kill -0 "${pid}" 2>/dev/null; do
    if (( elapsed >= timeout_seconds )); then
      kill -TERM "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  wait "${pid}"
}

headroom_write_minimal_sparkle_appcast() {
  local appcast_path="$1"
  local feed_url="$2"
  local version="$3"
  local build="$4"
  local pub_date="$5"
  local minimum_system_version="$6"
  local download_url="$7"
  local ed_signature="$8"
  local archive_length="$9"
  local release_notes_url="${10}"

  cat > "${appcast_path}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Headroom Updates</title>
    <link>${feed_url}</link>
    <description>Headroom release feed</description>
    <item>
      <title>Headroom ${version}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${build}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${minimum_system_version}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>${release_notes_url}</sparkle:releaseNotesLink>
      <enclosure url="${download_url}" sparkle:edSignature="${ed_signature}" length="${archive_length}" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
}

headroom_verify_appcast_release_notes() {
  local appcast="$1"
  local updates_dir="$2"
  local build="$3"
  local expected_filename="$4"
  local expected_url="$5"
  local item
  local actual_url
  local staged_path="${updates_dir}/${expected_filename}"

  [[ -f "${appcast}" ]] || {
    echo "Missing Sparkle appcast: ${appcast}" >&2
    return 65
  }

  item="$(headroom_appcast_item_for_build "${appcast}" "${build}")"
  [[ -n "${item}" ]] || {
    echo "Sparkle appcast has no item for build ${build}: ${appcast}" >&2
    return 65
  }

  actual_url="$(printf '%s\n' "${item}" | sed -n 's@.*<sparkle:releaseNotesLink>\([^<]*\)</sparkle:releaseNotesLink>.*@\1@p' | head -n 1)"
  if [[ "${actual_url}" != "${expected_url}" ]]; then
    echo "Sparkle item ${build} has unexpected release notes: ${actual_url:-missing}" >&2
    return 65
  fi
  if ! headroom_file_has_nonwhitespace_content "${staged_path}"; then
    echo "Missing staged Sparkle release notes: ${staged_path}" >&2
    return 65
  fi

  echo "→ verified Sparkle build ${build} release notes: ${expected_filename}"
}
