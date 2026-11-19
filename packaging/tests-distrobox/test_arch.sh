#!/usr/bin/env bash
set -e

# ========================================================
# Prueba de GLC YouTube TV Cast en Arch Linux (SteamOS base)
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTAINER_NAME="glc-test-arch"
APPIMAGE="${PROJECT_DIR}/GLC-YouTube-TV-Cast-1.0.0-x86_64.AppImage"

if [ ! -f "${APPIMAGE}" ]; then
    echo "==> AppImage no encontrada. Compilando primero..."
    "${PROJECT_DIR}/packaging/appimage/build_appimage.sh"
fi

if ! command -v distrobox >/dev/null 2>&1; then
    echo "Error: distrobox no está instalado. Ejecuta primero:" >&2
    echo "       ${SCRIPT_DIR}/setup_distrobox.sh" >&2
    exit 1
fi

echo "==> Creando/iniciando contenedor de prueba Arch Linux..."
distrobox create --image archlinux:latest --name "${CONTAINER_NAME}" --yes || true

echo "==> Asegurando dependencias de entorno de escritorio en Arch..."
distrobox enter "${CONTAINER_NAME}" -- bash -c "
    sudo pacman -Syu --noconfirm --needed gtk3 python-gobject libayatana-appindicator
"

echo "==> [OK] Lanzando AppImage dentro de Arch Linux..."
distrobox enter "${CONTAINER_NAME}" -- "${APPIMAGE}"
