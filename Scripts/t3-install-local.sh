#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
case "${1:---build-only}" in
  --build-only) exec Scripts/pacemark.sh build ;;
  --install) Scripts/pacemark.sh build && exec Scripts/pacemark.sh install ;;
  *) echo 'Usage: t3-install-local.sh [--build-only | --install]' >&2; exit 64 ;;
esac
