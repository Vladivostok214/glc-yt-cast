#!/usr/bin/env bash
set -euo pipefail

# ========================================================
# Script interno ejecutado dentro de un contenedor Ubuntu 22.04 (GLIBC 2.35)
# Recolecta Python 3.10 + GTK 3 + PyGObject + AyatanaAppIndicator3
# en /work/AppDir para crear una AppImage 100% autocontenida.
# ========================================================

APP_DIR="/work/AppDir"

echo "    -> [Contenedor Ubuntu 22.04] Instalando runtime Python + GTK3 + Ayatana..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    python3 \
    python3-minimal \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gtk-3.0 \
    gir1.2-gdkpixbuf-2.0 \
    gir1.2-ayatanaappindicator3-0.1 \
    libgtk-3-0 \
    libayatana-appindicator3-1 \
    librsvg2-2 \
    librsvg2-common \
    adwaita-icon-theme \
    hicolor-icon-theme \
    libglib2.0-bin

echo "    -> [Contenedor] Copiando Python 3.10 y PyGObject..."
mkdir -p "${APP_DIR}/usr/bin" \
         "${APP_DIR}/usr/lib/python3/dist-packages" \
         "${APP_DIR}/usr/lib/girepository-1.0" \
         "${APP_DIR}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders" \
         "${APP_DIR}/usr/share/glib-2.0/schemas" \
         "${APP_DIR}/usr/share/icons/Adwaita" \
         "${APP_DIR}/usr/share/icons/hicolor"

# Binario Python 3.10
cp -L /usr/bin/python3.10 "${APP_DIR}/usr/bin/python3.10"
ln -sf python3.10 "${APP_DIR}/usr/bin/python3"

# Biblioteca estándar de Python 3.10 (excluyendo tests/caches para reducir tamaño)
cp -a /usr/lib/python3.10 "${APP_DIR}/usr/lib/"
rm -rf "${APP_DIR}/usr/lib/python3.10/test" \
       "${APP_DIR}/usr/lib/python3.10/tkinter" \
       "${APP_DIR}/usr/lib/python3.10/idlelib" \
       "${APP_DIR}/usr/lib/python3.10/ensurepip" \
       "${APP_DIR}/usr/lib/python3.10/lib2to3" \
       "${APP_DIR}/usr/lib/python3.10/pydoc_data"
find "${APP_DIR}/usr/lib/python3.10" -name "__pycache__" -type d -exec rm -rf {} +

# Paquetes dist-packages (gi, cairo)
cp -a /usr/lib/python3/dist-packages/gi "${APP_DIR}/usr/lib/python3/dist-packages/"
cp -a /usr/lib/python3/dist-packages/cairo "${APP_DIR}/usr/lib/python3/dist-packages/"
cp -a /usr/lib/python3/dist-packages/pygobject* "${APP_DIR}/usr/lib/python3/dist-packages/" 2>/dev/null || true
find "${APP_DIR}/usr/lib/python3/dist-packages" -name "__pycache__" -type d -exec rm -rf {} +

echo "    -> [Contenedor] Copiando typelibs GI, GDK-Pixbuf loaders, schemas e iconos..."
cp -a /usr/lib/x86_64-linux-gnu/girepository-1.0/*.typelib "${APP_DIR}/usr/lib/girepository-1.0/"

# GDK-Pixbuf loaders + plantilla relocalizable de loaders.cache
cp -a /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders/*.so "${APP_DIR}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/"
sed 's|/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders/|@APPDIR@/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/|g' \
    /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache \
    > "${APP_DIR}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache.in"

# Schemas GLib/GTK
cp -a /usr/share/glib-2.0/schemas/* "${APP_DIR}/usr/share/glib-2.0/schemas/"
glib-compile-schemas "${APP_DIR}/usr/share/glib-2.0/schemas/"

# Base de datos MIME (requerida por gdk-pixbuf/GIO en contenedores mínimos sin shared-mime-info)
mkdir -p "${APP_DIR}/usr/share/mime"
cp -a /usr/share/mime/* "${APP_DIR}/usr/share/mime/"

# Configuración Fontconfig de respaldo (para sistemas mínimos sin /etc/fonts/fonts.conf)
mkdir -p "${APP_DIR}/etc/fonts"
cp -a /etc/fonts/* "${APP_DIR}/etc/fonts/"

# Iconos simbólicos de Adwaita (ligeros y necesarios para los botones de la UI)
cp -a /usr/share/icons/Adwaita/index.theme "${APP_DIR}/usr/share/icons/Adwaita/"
for icon_subdir in scalable symbolic 16x16 24x24; do
    if [ -d "/usr/share/icons/Adwaita/${icon_subdir}" ]; then
        cp -a "/usr/share/icons/Adwaita/${icon_subdir}" "${APP_DIR}/usr/share/icons/Adwaita/"
    fi
done
cp -a /usr/share/icons/hicolor/index.theme "${APP_DIR}/usr/share/icons/hicolor/"
gtk-update-icon-cache -q -t -f "${APP_DIR}/usr/share/icons/Adwaita" || true

echo "    -> [Contenedor] Resolviendo y empaquetando librerías compartidas (.so)..."
# Lista de librerías de bajo nivel que DEBEN venir del sistema anfitrión (AppImage excludelist)
EXCLUDE_REGEX='^(ld-linux|libc\.so|libm\.so|libdl\.so|librt\.so|libpthread\.so|libresolv\.so|libutil\.so|libnsl\.so|libnss_|libstdc\+\+\.so|libgcc_s\.so|libGL\.so|libGLX\.so|libGLdispatch\.so|libEGL\.so|libdrm\.so|libgbm\.so|libX11\.so|libX11-xcb\.so|libxcb\.so)'

# Librerías raíz que cargamos por GI/dlopen además de los binarios directos
ROOT_LIBS=(
    /usr/lib/x86_64-linux-gnu/libgtk-3.so.0
    /usr/lib/x86_64-linux-gnu/libgdk-3.so.0
    /usr/lib/x86_64-linux-gnu/libgdk_pixbuf-2.0.so.0
    /usr/lib/x86_64-linux-gnu/libayatana-appindicator3.so.1
    /usr/lib/x86_64-linux-gnu/libgirepository-1.0.so.1
    /usr/lib/x86_64-linux-gnu/librsvg-2.so.2
    /usr/lib/x86_64-linux-gnu/libdbusmenu-gtk3.so.4
    /usr/lib/x86_64-linux-gnu/libdbusmenu-glib.so.4
    /usr/lib/x86_64-linux-gnu/libatk-1.0.so.0
    /usr/lib/x86_64-linux-gnu/libpango-1.0.so.0
    /usr/lib/x86_64-linux-gnu/libpangocairo-1.0.so.0
    /usr/lib/x86_64-linux-gnu/libcairo.so.2
    /usr/lib/x86_64-linux-gnu/libcairo-gobject.so.2
)

for lib in "${ROOT_LIBS[@]}"; do
    if [ -f "$lib" ]; then
        cp -L "$lib" "${APP_DIR}/usr/lib/$(basename "$lib")"
    fi
done

# Recolección recursiva de dependencias con ldd
collect_deps() {
    local target="$1"
    ldd "$target" 2>/dev/null | awk '/=> \// {print $3}' || true
}

SEEN_FILE="/tmp/seen_libs.txt"
: > "${SEEN_FILE}"

# Semillas iniciales: python, extensiones .so, loaders pixbuf y librerías raíz
mapfile -t TARGETS < <(
    echo "${APP_DIR}/usr/bin/python3.10"
    find "${APP_DIR}/usr/lib/python3.10/lib-dynload" -name "*.so"
    find "${APP_DIR}/usr/lib/python3/dist-packages" -name "*.so"
    find "${APP_DIR}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders" -name "*.so"
    find "${APP_DIR}/usr/lib" -maxdepth 1 -name "*.so*"
)

# Dos pasadas para capturar dependencias transitivas
for _pass in 1 2; do
    NEW_TARGETS=()
    for t in "${TARGETS[@]}"; do
        while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            base=$(basename "$dep")
            if echo "$base" | grep -Eq "${EXCLUDE_REGEX}"; then
                continue
            fi
            if ! grep -Fxq "$base" "${SEEN_FILE}"; then
                echo "$base" >> "${SEEN_FILE}"
                if [ ! -f "${APP_DIR}/usr/lib/${base}" ]; then
                    cp -L "$dep" "${APP_DIR}/usr/lib/${base}"
                    NEW_TARGETS+=("${APP_DIR}/usr/lib/${base}")
                fi
            fi
        done < <(collect_deps "$t")
    done
    if [ "${#NEW_TARGETS[@]}" -eq 0 ]; then
        break
    fi
    TARGETS=("${NEW_TARGETS[@]}")
done

# Asegurar permisos de lectura/ejecución limpios para el usuario anfitrión
chmod -R a+rX "${APP_DIR}/usr"
echo "    -> [Contenedor] Empaquetado de dependencias completado ($(du -sh "${APP_DIR}/usr" | awk '{print $1}'))."
