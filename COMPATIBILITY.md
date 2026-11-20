# Matriz de Compatibilidad — GLC YouTube TV Cast

Registro de dispositivos cliente (donde se ejecuta la aplicación) y dispositivos destino (Android TV / decos) en los que **GLC YouTube TV Cast** ha sido probado y aprobado.

---

## 1. Dispositivos Cliente (donde corre la aplicación)

| Sistema / Dispositivo | Entorno Gráfico | Formato | Estado | Notas |
| :--- | :--- | :--- | :---: | :--- |
| **Ubuntu 26.04 LTS** | GNOME (Xwayland) | `.deb` (`v1.1.0`) | ✅ Aprobado | Instalación nativa vía `sudo apt install` con resolución automática de dependencias. |
| **Steam Deck (SteamOS 3)** | KDE Plasma (Modo Escritorio) | `.AppImage` (`glc-yt-steamdesk.AppImage`) | ✅ Aprobado | 100% autocontenida (sin instalar dependencias ni modificar el sistema raíz). Se recomienda **Gear Lever** (Discover) para integrar el icono al menú. |
| **Arch Linux (limpio)** | X11 / Xwayland | `.AppImage` | ✅ Aprobado | Verificado en contenedor limpio sin Python, GTK, PyGObject ni ADB preinstalados (Distrobox). |
| **Windows 11 (x64)** | WebView2 / Tray Nativo | Portable `.zip` (5,7 MB) e Instalador NSIS `.exe` (4,4 MB) | ✅ Aprobado | Compilado en Rust + Tauri v2 con `adb.exe` embebido, atajo global `Ctrl + Alt + Y`, icono en bandeja y cierre limpio. |

---

## 2. Dispositivos Destino (Televisores y Decos Android TV)

| Dispositivo / Modelo | Plataforma / SoC | Firmware / Fabricante | Versión Android | Puerto ADB | Método D-Pad | Estado | Notas |
| :--- | :--- | :--- | :---: | :---: | :--- | :---: | :--- |
| **SMART TV (`SMART_TV`)** | HiSilicon `Hi3751V352E_DMO` / `Hi3751V350` | CVTE (Guangzhou Shiyuan Electronic Technology Co.) | Android 14 | `5555` | `sendevent` directo (`/dev/input/event3`) | ✅ Aprobado | Latencia mínima en D-Pad y conexión automática por Wi-Fi (DHCP). |
| **SEI Robotics SEI500W** *(WOM TV)* | Amlogic `S905X2` | SEI Robotics (Android TV certificado) | Android TV 9 / 10 | `5555` | Auto-detección + fallback `input keyevent` | ✅ Aprobado | Requiere activar *Depuración USB* y reiniciar el deco la primera vez para abrir el puerto `5555`. Búsqueda, reproducción y D-Pad operativos. |

---

## 3. ¿Probaste otro dispositivo?

Si probaste **GLC YouTube TV Cast** en otro televisor, TV Box, deco o distribución Linux, puedes abrir un **Issue** o un **Pull Request** indicando:
1. Dispositivo cliente y distribución Linux (y si usaste `.deb` o `.AppImage`).
2. Marca/modelo del televisor o deco y su versión de Android TV.
3. Si funcionó la conexión automática, la búsqueda y el control D-Pad.
