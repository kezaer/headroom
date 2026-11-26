#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
quit_pacemark() {
    osascript -l JavaScript <<'JXA'
ObjC.import('AppKit')
const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('com.kezaer.pacemark')
for (let i = 0; i < apps.count; i++) {
    const app = apps.objectAtIndex(i)
    app.terminate
    for (let attempt = 0; attempt < 100 && !app.terminated; attempt++) delay(0.1)
    if (!app.terminated) throw Error('Pacemark did not quit.')
}
JXA
}
case "${1:-}" in
  build) exec Scripts/build-app.sh ;;
  run)
    shift
    [[ -d Pacemark.app ]] || Scripts/build-app.sh
    exec open Pacemark.app --args "$@" ;;
  install)
    [[ -d Pacemark.app ]] || Scripts/build-app.sh
    target=/Applications/Pacemark.app
    stage=$(mktemp -d /Applications/.pacemark-install.XXXXXX)
    trap 'rm -rf "$stage"' EXIT
    ditto Pacemark.app "$stage/Pacemark.app"
    quit_pacemark
    backup=
    if [[ -e "$target" ]]; then
      root="$HOME/Library/Application Support/Pacemark/Backups"
      mkdir -p "$root"
      backup=$(mktemp -d "$root/$(date +%Y%m%d-%H%M%S).XXXXXX")
      mv "$target" "$backup/"
    fi
    if ! mv "$stage/Pacemark.app" "$target"; then
      if [[ -n "$backup" ]]; then mv "$backup/Pacemark.app" "$target"; fi
      exit 1
    fi
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target" ;;
  quit)
    quit_pacemark ;;
  *) echo 'Usage: pacemark.sh build | run [--demo scenario] | install | quit' >&2; exit 64 ;;
esac
