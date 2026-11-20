# Guía de Empaquetado y Compatibilidad Multiplataforma

Este directorio centraliza las herramientas para compilar y probar **GLC YouTube TV Cast (v1.1.0)** en distintas distribuciones de Linux, manteniendo un único código fuente (`glc_yt_cast.py`).

---

## 📦 Formatos Disponibles

### 1. Debian / Ubuntu (`.deb` nativo)
* **Directorio:** `packaging/deb/`
* **Compilación:** `./build_deb.sh` (o `./packaging/deb/build_deb.sh`)
* **Archivo generado:** `glc-yt-cast_1.1.0_all.deb` (~34 KB)
* **Instalación (resuelve e instala dependencias automáticamente):**
  ```bash
  sudo apt install ./glc-yt-cast_1.1.0_all.deb
  ```

### 2. Steam Deck / Linux Universal (`.AppImage` 100% autocontenida)
* **Directorio:** `packaging/appimage/`
* **Compilación:** `./packaging/appimage/build_appimage.sh` (requiere `podman` o `docker`)
* **Archivo generado:** `glc-yt-steamdesk.AppImage` (~45 MB)
* **Características:**
  * Compilada en un contenedor limpio de **Ubuntu 22.04 (GLIBC 2.35)** para máxima compatibilidad con SteamOS, Arch Linux, Fedora, Debian 12+ y Ubuntu 22.04+.
  * Incluye todo embebido: **Python 3.10, GTK 3, PyGObject, AyatanaAppIndicator3, loaders PNG/SVG, iconos Adwaita, base MIME y `adb` oficial de Google**.
  * No requiere permisos de administrador ni modificar el sistema raíz inmutable de SteamOS.
* **Instalación recomendada en Steam Deck (Modo Escritorio):**
  * **Opción recomendada (con icono en el menú):** Instalar **Gear Lever** desde la tienda Discover, arrastrar `glc-yt-steamdesk.AppImage` y pulsar *"Move to the app menu"*.
  * **Opción directa:** Clic derecho → *Propiedades* → *Permisos* → marcar *"Es ejecutable"* y abrir con doble clic.

---

## 🧪 Pruebas Aisladas con Distrobox

Para verificar que la AppImage funciona sin dependencias externas en contenedores completamente limpios de Arch Linux o Fedora:

1. **Instalar Podman y Distrobox (solo la primera vez):**
   ```bash
   ./packaging/tests-distrobox/setup_distrobox.sh
   ```

2. **Probar en Arch Linux limpio (entorno base de SteamOS):**
   ```bash
   ./packaging/tests-distrobox/test_arch.sh
   ```

3. **Probar en Fedora limpio:**
   ```bash
   ./packaging/tests-distrobox/test_fedora.sh
   ```
