#!/usr/bin/env bash
set -e

# ========================================================
# Script de construcción de paquete Debian para glc-yt-cast
# ========================================================

VERSION="1.0.0"
PKG_NAME="glc-yt-cast"
ARCH="all"
BUILD_DIR="/tmp/${PKG_NAME}-build"
OUTPUT_DEB="${PKG_NAME}_${VERSION}_${ARCH}.deb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Iniciando construcción de ${OUTPUT_DEB}..."

# 1. Limpiar directorio previo de construcción
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/DEBIAN"
mkdir -p "${BUILD_DIR}/usr/bin"
mkdir -p "${BUILD_DIR}/usr/share/${PKG_NAME}/assets"
mkdir -p "${BUILD_DIR}/usr/share/applications"
mkdir -p "${BUILD_DIR}/usr/share/icons/hicolor/512x512/apps"
mkdir -p "${BUILD_DIR}/usr/share/icons/hicolor/scalable/apps"

# 2. Archivo de control de Debian
cat <<EOF > "${BUILD_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: GLC TV <vladivostok@localhost>
Depends: python3, python3-gi, gir1.2-gtk-3.0, gir1.2-ayatanaappindicator3-0.1, adb
Description: YouTube TV Cast para Android TV
 Lanzador rápido y minimalista con Popover superior y Toggle Uiverse
 para enviar búsquedas y controlar YouTube TV en Android TV por ADB.
EOF

# 3. Scripts postinst y postrm
cat <<'EOF' > "${BUILD_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    chmod 755 /usr/bin/glc-yt-cast
    chmod 755 /usr/share/glc-yt-cast/glc_yt_cast.py
    if which update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
    if which gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q /usr/share/icons/hicolor || true
    fi
fi
exit 0
EOF
chmod 755 "${BUILD_DIR}/DEBIAN/postinst"

cat <<'EOF' > "${BUILD_DIR}/DEBIAN/postrm"
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if which update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
    if which gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q /usr/share/icons/hicolor || true
    fi
fi
exit 0
EOF
chmod 755 "${BUILD_DIR}/DEBIAN/postrm"

# 4. Binario ejecutable en /usr/bin
cat <<'EOF' > "${BUILD_DIR}/usr/bin/glc-yt-cast"
#!/bin/sh
exec /usr/bin/python3 /usr/share/glc-yt-cast/glc_yt_cast.py "$@"
EOF
chmod 755 "${BUILD_DIR}/usr/bin/glc-yt-cast"

# 5. Copiar código fuente y assets
cp "${SCRIPT_DIR}/glc_yt_cast.py" "${BUILD_DIR}/usr/share/${PKG_NAME}/"
chmod 755 "${BUILD_DIR}/usr/share/${PKG_NAME}/glc_yt_cast.py"
cp -r "${SCRIPT_DIR}/assets/"* "${BUILD_DIR}/usr/share/${PKG_NAME}/assets/"

# 6. Copiar lanzador .desktop e iconos
cp "${SCRIPT_DIR}/com.glc.ytcast.desktop" "${BUILD_DIR}/usr/share/applications/"
cp "${SCRIPT_DIR}/assets/yt_tv_icon_512.png" "${BUILD_DIR}/usr/share/icons/hicolor/512x512/apps/com.glc.ytcast.png"
cp "${SCRIPT_DIR}/assets/yt_tv_icon.svg" "${BUILD_DIR}/usr/share/icons/hicolor/scalable/apps/com.glc.ytcast.svg"

# 7. Compilar paquete con dpkg-deb
dpkg-deb --root-owner-group --build "${BUILD_DIR}" "${SCRIPT_DIR}/${OUTPUT_DEB}"

# 8. Limpiar temporales
rm -rf "${BUILD_DIR}"

echo "==> ¡Paquete creado exitosamente en ${SCRIPT_DIR}/${OUTPUT_DEB}!"
