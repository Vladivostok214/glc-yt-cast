#!/usr/bin/env bash
set -e

# ========================================================
# Script de construcción de AppImage para GLC YouTube TV Cast
# Compatible con SteamOS (Steam Deck), Arch Linux, Fedora, Ubuntu, etc.
# ========================================================

VERSION="1.0.0"
APP_NAME="glc-yt-cast"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="/tmp/${APP_NAME}-appimage-build"
APP_DIR="${BUILD_DIR}/AppDir"
OUTPUT_APPIMAGE="${PROJECT_DIR}/GLC-YouTube-TV-Cast-${VERSION}-x86_64.AppImage"
CACHE_DIR="${SCRIPT_DIR}/.cache"

mkdir -p "${CACHE_DIR}"

echo "==> [1/5] Preparando herramientas y dependencias..."

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

echo "==> [2/5] Creando estructura de AppDir en ${APP_DIR}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_DIR}/usr/bin"
mkdir -p "${APP_DIR}/usr/share/${APP_NAME}/assets"
mkdir -p "${APP_DIR}/usr/share/applications"
mkdir -p "${APP_DIR}/usr/share/icons/hicolor/512x512/apps"
mkdir -p "${APP_DIR}/usr/share/icons/hicolor/scalable/apps"

# Copiar ADB al bundle interno
cp "${ADB_BIN}" "${APP_DIR}/usr/bin/adb"
chmod +x "${APP_DIR}/usr/bin/adb"

# Copiar código y assets
cp "${PROJECT_DIR}/glc_yt_cast.py" "${APP_DIR}/usr/share/${APP_NAME}/"
chmod +x "${APP_DIR}/usr/share/${APP_NAME}/glc_yt_cast.py"
cp -r "${PROJECT_DIR}/assets/"* "${APP_DIR}/usr/share/${APP_NAME}/assets/"

# Copiar lanzador .desktop e iconos
cp "${PROJECT_DIR}/com.glc.ytcast.desktop" "${APP_DIR}/"
cp "${PROJECT_DIR}/com.glc.ytcast.desktop" "${APP_DIR}/usr/share/applications/"
cp "${PROJECT_DIR}/assets/yt_tv_icon_512.png" "${APP_DIR}/com.glc.ytcast.png"
cp "${PROJECT_DIR}/assets/yt_tv_icon_512.png" "${APP_DIR}/usr/share/icons/hicolor/512x512/apps/com.glc.ytcast.png"
cp "${PROJECT_DIR}/assets/yt_tv_icon.svg" "${APP_DIR}/usr/share/icons/hicolor/scalable/apps/com.glc.ytcast.svg"

# Icono en la raíz del AppDir requerido por appimagetool
ln -sf "com.glc.ytcast.png" "${APP_DIR}/.DirIcon"

echo "==> [3/5] Generando script AppRun de inicio..."
cat <<'EOF' > "${APP_DIR}/AppRun"
#!/usr/bin/env bash
SELF=$(readlink -f "$0")
APPDIR=$(dirname "$SELF")

# Priorizar binarios embebidos (ADB interno) antes que el sistema
export PATH="${APPDIR}/usr/bin:${PATH}"
export APPDIR="${APPDIR}"
export XDG_DATA_DIRS="${APPDIR}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Si el sistema tiene python3 instalado, lo ejecutamos directamente
if command -v python3 >/dev/null 2>&1; then
    exec python3 "${APPDIR}/usr/share/glc-yt-cast/glc_yt_cast.py" "$@"
else
    echo "Error: Python 3 no está disponible en este sistema." >&2
    exit 1
fi
EOF
chmod +x "${APP_DIR}/AppRun"

echo "==> [4/5] Empaquetando AppImage con appimagetool..."
ARCH=x86_64 "${APPIMAGETOOL}" --appimage-extract-and-run "${APP_DIR}" "${OUTPUT_APPIMAGE}"

echo "==> [5/5] Limpiando temporales..."
rm -rf "${BUILD_DIR}"

chmod +x "${OUTPUT_APPIMAGE}"
echo "==> ¡AppImage generada exitosamente en:"
echo "    ${OUTPUT_APPIMAGE}"
