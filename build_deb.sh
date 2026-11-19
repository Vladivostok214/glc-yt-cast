#!/usr/bin/env bash
# Redirección al script de empaquetado oficial
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/packaging/deb/build_deb.sh" "$@"
