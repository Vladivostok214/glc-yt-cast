#!/usr/bin/env bash
set -e

# ========================================================
# Prueba de GLC YouTube TV Cast en Fedora (Bazzite base)
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTAINER_NAME="glc-test-fedora"
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

echo "==> Creando/iniciando contenedor de prueba Fedora..."
distrobox create --image fedora:latest --name "${CONTAINER_NAME}" --yes || true

echo "==> Asegurando dependencias de entorno de escritorio en Fedora..."
distrobox enter "${CONTAINER_NAME}" -- bash -c "
    sudo dnf install -y gtk3 python3-gobject libayatana-appindicator-gtk3
"

echo "==> [OK] Lanzando AppImage dentro de Fedora..."
distrobox enter "${CONTAINER_NAME}" -- "${APPIMAGE}"
