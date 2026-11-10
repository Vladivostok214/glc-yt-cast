# GLC YouTube TV Cast

Lanzador rápido, minimalista y de alto rendimiento para búsqueda y control de YouTube en dispositivos Android TV, desarrollado en Python 3 con GTK 3 para Ubuntu / GNOME.

---

## 1. Características Principales

- **Popover Superior Derecho:** Ventana flotante anclada de forma nativa bajo el panel superior de GNOME mediante backend Xwayland.
- **Interruptor de Conexión:** Switch estilo Uiverse con feedback visual de iluminación activo (`#0974f1`).
- **Cápsula de Búsqueda:** Entrada de texto transparente con botón de limpieza y envío directo por eventos de activación.
- **Botonera y Navegación por Teclado:** Control con flechas de dirección (Izquierda, Arriba, Abajo, Derecha) y selección/reproducción mediante la tecla Enter.
- **Cierre Limpio del Sistema:** Al apagar el interruptor, la aplicación desconecta la sesión ADB y finaliza todos los subprocesos sin dejar procesos huérfanos ni iconos residuales en el área de notificación.
- **Empaquetado Nativo:** Distribuible como paquete Debian (`.deb`) de bajo peso (~33 KB) con resolución automática de dependencias.

---

## 2. Requisitos Previos

Para que la aplicación interactúe con el televisor:

1. **Dispositivo con Android:** Smart TV o TV Box con Android TV o Google TV.
2. **Red Local Común:** La computadora y el televisor deben compartir la misma subred local (Wi-Fi o cable Ethernet).
3. **Depuración ADB Habilitada:**
   - En el televisor, ingresar a *Ajustes* -> *Información* y pulsar 7 veces consecutivas sobre *Compilación del SO de Android TV* para desbloquear las *Opciones de desarrollador*.
   - Dentro de *Opciones de desarrollador*, habilitar **Depuración por USB / Depuración de red (ADB)**.
   - En la primera conexión, aceptar el cuadro de diálogo de autorización en pantalla ("Permitir siempre desde esta computadora").

---

## 3. Arquitectura y Funcionamiento Técnico

### 3.1. Detección y Conexión de Red (ADB)
- **Persistencia de IP:** Almacena la última dirección IP exitosa en `~/.config/glc_tv/remote_config.json`.
- **Estrategia de Conexión Directa:** En primer lugar intenta un apretón de manos directo sobre el puerto `5555` de la última IP registrada para lograr tiempos de respuesta inferiores a 300 ms.
- **Escaneo Multihilo de Subred:** Si la IP dinámica cambió (por asignación DHCP del router), se activa un escaneo paralelo utilizando un grupo de hilos (`concurrent.futures.ThreadPoolExecutor`) con sockets TCP no bloqueantes sobre el rango `/24` de la interfaz activa. Al detectar el puerto `5555` abierto, valida la firma del dispositivo (`getprop ro.product.model`) y actualiza el archivo de configuración.

### 3.2. Procesamiento de Texto e Inyección de Deep Links
Al confirmar una entrada en la barra de búsqueda, el script analiza el contenido para determinar la acción correspondiente:
- **Detección de URLs o IDs:** Si el texto coincide con una URL de YouTube (`youtube.com/watch?v=...`, `youtu.be/...`) o un identificador alfanumérico de 11 caracteres, extrae el identificador del video y lanza el reproductor directamente:
  ```bash
  am start -a android.intent.action.VIEW -d "vnd.youtube://watch/{video_id}"
  ```
- **Búsqueda por Texto:** Si es una consulta en texto plano, la codifica en formato URI y despacha el Intent de búsqueda hacia el cliente oficial de YouTube TV (motor Cobalt):
  ```bash
  am start -a android.intent.action.VIEW -d "vnd.youtube://search/{query_escaped}"
  ```

### 3.3. Cola de Comandos y Driver de Hardware Linux (sendevent)
Para garantizar una latencia inferior a 1 ms en la navegación y evitar saturar la memoria RAM del televisor:
- **Tubería Interactiva Persistente:** Mantiene abierto un proceso `adb shell` persistente mediante un hilo en segundo plano (`ADBCommandQueue`), evitando instanciar la máquina virtual Java de Android (`app_process`) en cada pulsación.
- **Inyección por Kernel Directo:** Las teclas de navegación se transmiten directamente al controlador de hardware del dispositivo de entrada (`/dev/input/event3`) mediante llamadas `sendevent`:
  - `KEY_UP` (Linux 103) -> `DPAD_UP` (Android 19)
  - `KEY_DOWN` (Linux 108) -> `DPAD_DOWN` (Android 20)
  - `KEY_LEFT` (Linux 105) -> `DPAD_LEFT` (Android 21)
  - `KEY_RIGHT` (Linux 106) -> `DPAD_RIGHT` (Android 22)
  - `KEY_ENTER` (Linux 28) + `DPAD_CENTER` (Android 23) -> Selección y reproducción.
- **Protección Anti-Lag (Cooldown):** Aplica una ventana de enfriamiento de 650 ms tras disparar la búsqueda. Esto evita colisiones entre el Enter de envío de formulario y el Enter de reproducción mientras YouTube TV consulta los resultados y renderiza las miniaturas en pantalla.

---

## 4. Estructura del Proyecto

```
glc-yt-cast/
├── glc_yt_cast.py            # Código fuente principal de la aplicación
├── com.glc.ytcast.desktop    # Archivo descriptor de lanzador de escritorio
├── build_deb.sh              # Script automatizado para compilar el paquete .deb
├── assets/                   # Recursos gráficos (iconos SVG y PNG en 512, 256, 48 px)
├── LICENSE                   # Licencia de código abierto MIT
├── .gitignore                # Reglas de exclusión para control de versiones Git
└── README.md                 # Documentación técnica del proyecto
```

---

## 5. Instalación y Uso

### 5.1. Construcción del paquete .deb
Para generar el paquete instalador desde el código fuente:
```bash
./build_deb.sh
```

### 5.2. Instalación mediante paquete .deb
```bash
sudo apt install ./glc-yt-cast_1.0.0_all.deb
```

### 5.3. Atajo de Teclado Recomendado
- **Atajo:** Super + Y
- **Comando:** `glc-yt-cast`

### 5.4. Desinstalación
```bash
sudo apt remove glc-yt-cast
```
