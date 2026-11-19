#!/usr/bin/env bash
set -e

# ========================================================
# Instalación de Podman y Distrobox en Ubuntu / Debian
# ========================================================

echo "==> Verificando herramientas de virtualización ligera..."

if ! command -v distrobox >/dev/null 2>&1; then
    echo "==> Instalando podman y distrobox mediante apt..."
    sudo apt update
    sudo apt install -y podman distrobox
    echo "==> ¡Instalación completa!"
else
    echo "==> Distrobox ya está instalado en el sistema."
fi

echo "==> Para probar la AppImage:"
echo "    - En Arch Linux (clon de SteamOS): ./packaging/tests-distrobox/test_arch.sh"
echo "    - En Fedora (base de Bazzite):      ./packaging/tests-distrobox/test_fedora.sh"
