# Guía de Empaquetado y Compatibilidad Multiplataforma

Este directorio centraliza las herramientas para compilar y probar **GLC YouTube TV Cast** en diferentes distribuciones de Linux (incluyendo Steam Deck / SteamOS).

---

## 📦 Formatos Disponibles

### 1. AppImage (Recomendado para Steam Deck y otras distros)
* **Directorio:** `packaging/appimage/`
* **Script:** `./packaging/appimage/build_appimage.sh`
* **Características:**
  * Incluye el binario oficial de `adb` (Google platform-tools) embebido dentro del paquete.
  * No requiere permisos de administrador ni modifica el sistema raíz (ideal para el sistema de solo lectura de SteamOS).
  * Genera el archivo: `GLC-YouTube-TV-Cast-1.0.0-x86_64.AppImage`.
* **Cómo usar en Steam Deck:**
  1. Copiar el archivo `.AppImage` a la Steam Deck (en Modo Escritorio).
  2. Clic derecho -> *Propiedades* -> *Permisos* -> Marcar *Es ejecutable* (o `chmod +x`).
  3. Doble clic para ejecutar.

### 2. Debian (.deb para Ubuntu / Debian / Linux Mint)
* **Directorio:** `packaging/deb/`
* **Script:** `./packaging/deb/build_deb.sh` (o el alias `./build_deb.sh` en la raíz).
* **Características:**
  * Paquete nativo de Debian con dependencias del sistema (`dpkg`).
  * Genera el archivo: `glc-yt-cast_1.0.0_all.deb`.

---

## 🧪 Pruebas Rápidas con Distrobox

Si deseas verificar el funcionamiento de la AppImage en otras distribuciones (como Arch Linux o Fedora) sin crear máquinas virtuales pesadas:

1. **Instalar Distrobox y Podman:**
   ```bash
   ./packaging/tests-distrobox/setup_distrobox.sh
   ```

2. **Probar en Arch Linux (Entorno base de SteamOS):**
   ```bash
   ./packaging/tests-distrobox/test_arch.sh
   ```

3. **Probar en Fedora (Entorno base de Bazzite):**
   ```bash
   ./packaging/tests-distrobox/test_fedora.sh
   ```
