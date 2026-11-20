# GLC YouTube TV Cast

Lanzador rápido, minimalista y de alto rendimiento para búsqueda y control de YouTube en dispositivos Android TV y decos certificados. Disponible para **Ubuntu / Debian (`.deb`)**, **Steam Deck / Linux Universal (`.AppImage`)** y **Windows 10 / 11 (Rust + Tauri v2, portable `.zip` e instalador `.exe`)**.

---

## 1. Características Principales

- **Popover Superior Derecho:** Ventana flotante anclada con márgenes adaptables mediante backend X11/Xwayland.
- **Interruptor de Conexión:** Switch estilo Uiverse con feedback visual de estado activo (`#0974f1`).
- **Descubrimiento Automático de Red + Configuración Manual (⚙️):** Detecta dinámicamente la subred local activa (sin IPs fijas) e incluye un botón de ajustes (⚙️) en la cabecera y en el menú de bandeja para ingresar o cambiar la IP del televisor/deco manualmente.
- **Cápsula de Búsqueda:** Entrada de texto transparente con botón de limpieza y envío directo por eventos de activación.
- **Botonera y Navegación D-Pad Universal:** Control con flechas de dirección (teclado o D-Pad físico en Steam Deck) y selección/reproducción con Enter.
- **Cierre Limpio del Sistema:** Al apagar el interruptor o salir desde la bandeja, desconecta la sesión ADB y finaliza los subprocesos sin dejar procesos huérfanos.
- **Multiplataforma Ligera:**
  - **Ubuntu / Debian (`.deb`):** Paquete ligero (~34 KB) en Python 3 + GTK 3 con instalación automática de dependencias vía `apt`.
  - **Steam Deck / Otros Linux (`.AppImage`):** Ejecutable único 100% autocontenido (~45 MB, base GLIBC 2.35) con Python 3.10, GTK 3, PyGObject, AyatanaAppIndicator3 y `adb` oficial embebidos.
  - **Windows 10 / 11 (`.zip` portable / `.exe` instalador):** Mini-app tipo Popover de bandeja escrita en **Rust + Tauri v2** (~4,4–5,7 MB incluyendo `adb.exe`), con atajo global **`Ctrl + Alt + Y`** y cero ventanas de consola.

---

## 2. Requisitos Previos

Para que la aplicación interactúe con el televisor o deco:

1. **Dispositivo con Android:** Smart TV, TV Box o deco certificado con Android TV / Google TV. Consulta la lista de dispositivos probados y aprobados en [COMPATIBILITY.md](COMPATIBILITY.md).
2. **Red Local Común:** La computadora / Steam Deck y el dispositivo Android TV deben compartir la misma red local (Wi-Fi o Ethernet).
3. **Depuración ADB Habilitada:**
   - En el televisor/deco, ingresar a *Ajustes* → *Preferencias del dispositivo* → *Información* (o *Acerca de*) y pulsar **7 veces** consecutivas sobre *Compilación* para desbloquear las *Opciones de desarrollador*.
   - Dentro de *Opciones de desarrollador*, habilitar **Depuración por USB** (y **Depuración de red / ADB** si aparece). En algunos decos como el SEI500W puede ser necesario reiniciar el deco una vez tras activar la opción.
   - En la primera conexión, aceptar el cuadro de diálogo de autorización en pantalla (*"Permitir siempre desde esta computadora"*).

---

## 3. Arquitectura y Funcionamiento Técnico

### 3.1. Detección y Conexión de Red (ADB)
- **Persistencia de IP:** Almacena la última dirección IP exitosa en `~/.config/glc_tv/remote_config.json`.
- **Resolución Inteligente de `adb`:** Prioriza automáticamente el binario `adb` embebido dentro de la AppImage (`$APPDIR/usr/bin/adb`) o el `adb` instalado en el sistema (`/usr/bin/adb`).
- **Estrategia de Conexión Directa y Escaneo Dinámico:** Intenta primero conectar sobre el puerto `5555` de la última IP guardada. Si no responde o no existe configuración previa, detecta automáticamente el prefijo de la subred local activa (`get_local_subnet_prefix()`) y escanea el rango `/24` en paralelo mediante `concurrent.futures.ThreadPoolExecutor`.
- **Configuración Manual (⚙️):** Permite establecer o corregir la IP en cualquier momento desde la interfaz gráfica.

### 3.2. Procesamiento de Texto e Inyección de Deep Links
Al confirmar una entrada en la barra de búsqueda, el script analiza el contenido para determinar la acción correspondiente:
- **Enlaces Directos de YouTube:** Si el texto es una URL de video (`youtube.com/watch`, `youtu.be/`, `youtube.com/shorts/`), abre el video directamente en la app de YouTube TV:
  ```bash
  am start -a android.intent.action.VIEW -d "<target_url>"
  ```
- **Búsqueda por Texto:** Si es texto plano, codifica la consulta en formato URI y lanza la búsqueda en YouTube TV.

### 3.3. Cola de Comandos y D-Pad Universal
- **Tubería Interactiva Persistente:** Mantiene abierto un proceso `adb shell` persistente en segundo plano (`ADBCommandQueue`).
- **Auto-detección de Hardware (`sendevent` + Fallback `input keyevent`):** Al iniciar la sesión, explora automáticamente `/dev/input/event*` buscando un nodo escribible que soporte `KEY_UP` (`0x0067`):
  - Si el dispositivo lo permite, inyecta eventos directamente al kernel mediante `sendevent` (latencia mínima).
  - En decos o Android TV certificados sin permisos de escritura en `/dev/input/event*` (como el SEI500W sin root), cambia automáticamente a `input keyevent` estándar dentro de la misma sesión persistente.
- **Protección Anti-Lag (Cooldown):** Ventana de enfriamiento de 650 ms tras enviar una búsqueda para evitar colisiones con el Enter de reproducción.

---

## 4. Estructura del Proyecto

```text
glc-yt-cast/
├── glc_yt_cast.py                  # Código fuente principal (único para Ubuntu y Steam Deck)
├── com.glc.ytcast.desktop          # Archivo descriptor de lanzador de escritorio
├── build_deb.sh                    # Acceso directo al constructor del paquete .deb
├── assets/                         # Recursos gráficos (iconos SVG y PNG en 512, 256, 48 px)
├── packaging/
│   ├── README.md                   # Guía técnica de empaquetado y pruebas Linux
│   ├── deb/
│   │   └── build_deb.sh            # Constructor de paquete Debian (.deb)
│   ├── appimage/
│   │   ├── build_appimage.sh       # Constructor de AppImage autocontenida (GLIBC 2.35)
│   │   └── container_build.sh      # Recolector de runtime dentro de Ubuntu 22.04
│   └── tests-distrobox/            # Scripts de prueba aislada en Arch Linux y Fedora
├── windows/                        # Aplicación nativa de Windows (Rust + Tauri v2)
│   ├── ui/                         # Frontend HTML/CSS/JS puro (estilo Uiverse)
│   └── src-tauri/                  # Backend Rust (ADB persistente, Tray, Ctrl+Alt+Y)
├── .github/workflows/
│   └── build-windows.yml           # Compilación automática de Windows en GitHub Actions
├── LICENSE                         # Licencia de código abierto MIT
├── .gitignore                      # Reglas de exclusión Git
├── COMPATIBILITY.md                # Matriz de dispositivos probados y aprobados
└── README.md                       # Documentación técnica del proyecto
```

---

## 5. Instalación y Uso

### 5.1. Ubuntu / Debian / Linux Mint (Paquete `.deb`)

**Compilar desde el código fuente:**
```bash
./build_deb.sh
```

**Instalar (descarga e instala automáticamente Python GI, GTK 3, Ayatana y ADB si faltan):**
```bash
sudo apt install ./glc-yt-cast_1.1.0_all.deb
```

**Atajo de Teclado Recomendado (GNOME):**
- **Atajo:** `Super + Y`
- **Comando:** `glc-yt-cast`

**Desinstalar:**
```bash
sudo apt remove glc-yt-cast
```

---

### 5.2. Steam Deck (SteamOS) y Otras Distribuciones Linux (`.AppImage`)

La AppImage no modifica el sistema raíz de SteamOS ni requiere permisos de administrador.

**Compilar desde el código fuente (requiere `podman` o `docker`):**
```bash
./packaging/appimage/build_appimage.sh
```
Generará el archivo **`glc-yt-steamdesk.AppImage`** (~45 MB).

**Instalar en Steam Deck (Modo Escritorio):**
1. Pasar la Steam Deck a **Modo Escritorio**.
2. **Opción recomendada (con icono integrado en el menú):** Instalar **Gear Lever** desde la tienda **Discover**, arrastrar `glc-yt-steamdesk.AppImage` dentro y pulsar **"Move to the app menu"**.
3. **Opción directa (sin instalar nada):** Clic derecho sobre `glc-yt-steamdesk.AppImage` → *Propiedades* → *Permisos* → marcar **"Es ejecutable"** → doble clic para ejecutar.

---

### 5.3. Windows 10 / 11 (Rust + Tauri v2)

Descarga la versión que prefieras desde la sección **Releases** de GitHub:
- **Portable (`glc-yt-cast-windows-portable.zip`, ~5,7 MB):** Descomprimir y ejecutar `GLC-YouTube-TV-Cast.exe` (incluye `adb.exe` y DLLs).
- **Instalador (`GLC YouTube TV Cast_1.1.0_x64-setup.exe`, ~4,4 MB):** Instalación estándar con icono en el Menú Inicio y desinstalador de Windows.

**Uso rápido en Windows:**
- **Atajo global:** `Ctrl + Alt + Y` para mostrar u ocultar el popover desde cualquier ventana.
- **Toggle OFF:** Desconecta ADB y mantiene el icono en la bandeja del reloj para reapertura instantánea.
- **Salir por completo:** Clic derecho en el icono junto al reloj → *"Desconectar y Salir"*.

*(Nota: al ser un proyecto independiente sin firma digital comercial, la primera ejecución puede mostrar el aviso de Windows SmartScreen → "Más información" → "Ejecutar de todas formas").*

---

## 6. Aviso Legal y Marcas Registradas

Este proyecto es una herramienta independiente y de código abierto desarrollada con propósitos de interoperabilidad y uso personal.

- No está respaldado, patrocinado, afiliado ni asociado de ninguna forma con Google LLC, Alphabet Inc., YouTube ni Valve Corporation.
- Las marcas registradas "YouTube", "Android", "Android TV" y sus logotipos correspondientes son propiedad exclusiva de Google LLC. "Steam" y "Steam Deck" son marcas registradas de Valve Corporation.
- Todo el código original de esta aplicación se distribuye bajo los términos de la Licencia MIT.
