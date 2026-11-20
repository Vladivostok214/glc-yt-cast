#!/usr/bin/env bash
set -euo pipefail

# ========================================================
# Script de construcción de AppImage 100% AUTOCONTENIDA para GLC YouTube TV Cast
# Usa un contenedor Ubuntu 22.04 (GLIBC 2.35) vía Podman/Docker para empaquetar
# Python 3.10 + GTK 3 + PyGObject + AyatanaAppIndicator3 + ADB oficial.
# Compatible con SteamOS (Steam Deck), Arch Linux, Fedora, Ubuntu 22.04+, etc.
# ========================================================

VERSION="1.0.0"
APP_NAME="glc-yt-cast"
OUTPUT_NAME="${1:-glc-yt-steamdesk}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="/tmp/${APP_NAME}-appimage-build"
APP_DIR="${BUILD_DIR}/AppDir"
OUTPUT_APPIMAGE="${PROJECT_DIR}/${OUTPUT_NAME}.AppImage"
CACHE_DIR="${SCRIPT_DIR}/.cache"

mkdir -p "${CACHE_DIR}"

# Detectar motor de contenedores (podman o docker)
if command -v podman >/dev/null 2>&1; then
    CONTAINER_CMD="podman"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_CMD="docker"
else
    echo "Error: se requiere 'podman' o 'docker' para compilar la AppImage autocontenida." >&2
    echo "Ejecuta primero: ./packaging/tests-distrobox/setup_distrobox.sh" >&2
    exit 1
fi

echo "==> [1/6] Preparando herramientas y dependencias (motor: ${CONTAINER_CMD})..."

# 1. Obtener appimagetool si no existe en cache
APPIMAGETOOL="${CACHE_DIR}/appimagetool"
if [ ! -f "${APPIMAGETOOL}" ]; then
    echo "    -> Descargando appimagetool..."
    curl -L -s "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -o "${APPIMAGETOOL}"
    chmod +x "${APPIMAGETOOL}"
fi

# 2. Obtener ADB estático oficial de Google Platform Tools
ADB_BIN="${CACHE_DIR}/adb"
if [ ! -f "${ADB_BIN}" ]; then
    echo "    -> Descargando binario ADB oficial de Google (platform-tools)..."
    TMP_ZIP="/tmp/platform-tools-linux.zip"
    curl -L -s "https://dl.google.com/android/repository/platform-tools-latest-linux.zip" -o "${TMP_ZIP}"
    unzip -q -o "${TMP_ZIP}" platform-tools/adb -d "/tmp"
    mv "/tmp/platform-tools/adb" "${ADB_BIN}"
    chmod +x "${ADB_BIN}"
    rm -rf "${TMP_ZIP}" "/tmp/platform-tools"
fi

echo "==> [2/6] Preparando AppDir en ${APP_DIR}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_DIR}/usr/bin"
mkdir -p "${APP_DIR}/usr/share/${APP_NAME}/assets"
mkdir -p "${APP_DIR}/usr/share/applications"
mkdir -p "${APP_DIR}/usr/share/icons/hicolor/512x512/apps"
mkdir -p "${APP_DIR}/usr/share/icons/hicolor/scalable/apps"

echo "==> [3/6] Empaquetando runtime Python + GTK3 + Ayatana desde Ubuntu 22.04 (GLIBC 2.35)..."
"${CONTAINER_CMD}" run --rm \
    -v "${BUILD_DIR}:/work:Z" \
    -v "${SCRIPT_DIR}/container_build.sh:/container_build.sh:ro,Z" \
    docker.io/library/ubuntu:22.04 \
    bash /container_build.sh

echo "==> [4/6] Copiando aplicación, assets y binario ADB..."
cp "${ADB_BIN}" "${APP_DIR}/usr/bin/adb"
chmod +x "${APP_DIR}/usr/bin/adb"

cp "${PROJECT_DIR}/glc_yt_cast.py" "${APP_DIR}/usr/share/${APP_NAME}/"
chmod +x "${APP_DIR}/usr/share/${APP_NAME}/glc_yt_cast.py"
cp -r "${PROJECT_DIR}/assets/"* "${APP_DIR}/usr/share/${APP_NAME}/assets/"

cp "${PROJECT_DIR}/com.glc.ytcast.desktop" "${APP_DIR}/"
cp "${PROJECT_DIR}/com.glc.ytcast.desktop" "${APP_DIR}/usr/share/applications/"
cp "${PROJECT_DIR}/assets/yt_tv_icon_512.png" "${APP_DIR}/com.glc.ytcast.png"
cp "${PROJECT_DIR}/assets/yt_tv_icon_512.png" "${APP_DIR}/usr/share/icons/hicolor/512x512/apps/com.glc.ytcast.png"
cp "${PROJECT_DIR}/assets/yt_tv_icon.svg" "${APP_DIR}/usr/share/icons/hicolor/scalable/apps/com.glc.ytcast.svg"
ln -sf "com.glc.ytcast.png" "${APP_DIR}/.DirIcon"

echo "==> [5/6] Generando script AppRun autocontenido..."
cat <<'EOF' > "${APP_DIR}/AppRun"
#!/usr/bin/env bash
set -euo pipefail

SELF=$(readlink -f "$0")
APPDIR=$(dirname "$SELF")

export APPDIR="${APPDIR}"
export PATH="${APPDIR}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${LD_LIBRARY_PATH:-}"
export PYTHONHOME="${APPDIR}/usr"
export PYTHONPATH="${APPDIR}/usr/lib/python3/dist-packages:${APPDIR}/usr/lib/python3.10:${APPDIR}/usr/lib/python3.10/lib-dynload"
export PYTHONDONTWRITEBYTECODE=1
export GI_TYPELIB_PATH="${APPDIR}/usr/lib/girepository-1.0"
export GSETTINGS_SCHEMA_DIR="${APPDIR}/usr/share/glib-2.0/schemas"
export XDG_DATA_DIRS="${APPDIR}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GTK_EXE_PREFIX="${APPDIR}/usr"
export GTK_DATA_PREFIX="${APPDIR}/usr"

# Fallback de Fontconfig si el sistema destino no tiene /etc/fonts/fonts.conf
if [ ! -f /etc/fonts/fonts.conf ]; then
    export FONTCONFIG_PATH="${APPDIR}/etc/fonts"
    export FONTCONFIG_FILE="${APPDIR}/etc/fonts/fonts.conf"
fi

# Generar loaders.cache temporal apuntando al directorio de montaje actual de la AppImage
PIXBUF_CACHE="$(mktemp /tmp/glc-yt-cast-pixbuf.XXXXXX)"
sed "s|@APPDIR@|${APPDIR}|g" "${APPDIR}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache.in" > "${PIXBUF_CACHE}"
export GDK_PIXBUF_MODULE_FILE="${PIXBUF_CACHE}"
trap 'rm -f "${PIXBUF_CACHE}"' EXIT

"${APPDIR}/usr/bin/python3" "${APPDIR}/usr/share/glc-yt-cast/glc_yt_cast.py" "$@"
EOF
chmod +x "${APP_DIR}/AppRun"

echo "==> [6/6] Empaquetando AppImage con appimagetool..."
ARCH=x86_64 "${APPIMAGETOOL}" --appimage-extract-and-run "${APP_DIR}" "${OUTPUT_APPIMAGE}"

rm -rf "${BUILD_DIR}"
chmod +x "${OUTPUT_APPIMAGE}"

echo "==> ¡AppImage 100% autocontenida generada exitosamente!"
echo "    Archivo: ${OUTPUT_APPIMAGE}"
echo "    Tamaño:  $(du -h "${OUTPUT_APPIMAGE}" | awk '{print $1}')"
