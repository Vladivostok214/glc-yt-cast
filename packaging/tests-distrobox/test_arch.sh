#!/usr/bin/env bash
set -e

# ========================================================
# Prueba de GLC YouTube TV Cast en Arch Linux (SteamOS base)
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTAINER_NAME="glc-test-arch"
APPIMAGE="${PROJECT_DIR}/glc-yt-steamdesk.AppImage"

if [ ! -f "${APPIMAGE}" ]; then
    echo "==> AppImage no encontrada. Compilando primero..."
    "${PROJECT_DIR}/packaging/appimage/build_appimage.sh"
fi

if ! command -v distrobox >/dev/null 2>&1; then
    echo "Error: distrobox no está instalado. Ejecuta primero:" >&2
    echo "       ${SCRIPT_DIR}/setup_distrobox.sh" >&2
    exit 1
fi

echo "==> Creando/iniciando contenedor limpio de Arch Linux (sin instalar dependencias)..."
distrobox create --image docker.io/library/archlinux:latest --name "${CONTAINER_NAME}" --yes || true

echo "==> [OK] Lanzando AppImage autocontenida dentro de Arch Linux limpio..."
distrobox enter "${CONTAINER_NAME}" -- env APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGE}"
