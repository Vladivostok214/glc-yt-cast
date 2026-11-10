#!/usr/bin/env python3
"""
GLC YouTube TV Cast — Lanzador rápido y minimalista de YouTube para Android TV
Diseñado con GTK 3 y AyatanaAppIndicator para Ubuntu / GNOME.

Características:
- Icono persistente en la barra superior de Ubuntu (System Tray).
- Ventana flotante estilo Spotlight que se auto-oculta al presionar Enter.
- Botón ON con feedback visual de conexión (verde) antes de desplegar la barra.
- Gtk.Stack con transición suave entre la vista de conexión y la barra de búsqueda.
- Búsqueda instantánea en YouTube TV mediante Deep Links de Android.
- Detección inteligente: Si es texto, busca; si es URL de YouTube, reproduce directamente.
- Al salir desde la bandeja superior, desconecta ADB limpiamente.
"""

import sys
import os
# Forzar backend X11 (vía Xwayland) para permitir posicionamiento exacto move(x, y) en la esquina superior derecha
os.environ["GDK_BACKEND"] = "x11"
import time
import queue
import json
import socket
import subprocess
import threading
import urllib.parse
import concurrent.futures
from pathlib import Path

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
gi.require_version('GdkPixbuf', '2.0')
gi.require_version('AyatanaAppIndicator3', '0.1')
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf, AyatanaAppIndicator3

BASE_DIR = Path(__file__).resolve().parent
ASSETS_DIR = BASE_DIR / "assets"
ICON_PATH = str(ASSETS_DIR / "yt_tv_icon.png")
CONFIG_DIR = Path.home() / ".config" / "glc_tv"
CONFIG_FILE = CONFIG_DIR / "remote_config.json"

CSS = """
window.search-window,
window.background.search-window,
.search-window,
.search-window decoration {
    background-color: transparent;
    background: transparent;
    border: none;
    box-shadow: none;
}

/* ========================================================
   POPOVER CARD ANCLADO EN LA ESQUINA SUPERIOR DERECHA
   ======================================================== */
.popover-card {
    background-color: #181822;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 20px;
    padding: 9px 14px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.55);
}

.app-title {
    color: #ffffff;
    font-size: 13px;
    font-weight: 600;
}

.status-label {
    color: #8b8ba7;
    font-size: 11px;
}

.status-online {
    color: #3fb950;
    font-weight: 600;
}

.status-connecting {
    color: #38bdf8;
    font-weight: 600;
}

.header-close-btn {
    border: none;
    background: transparent;
    color: #7b7b90;
    min-width: 24px;
    min-height: 24px;
    border-radius: 12px;
    padding: 0;
    transition: all 150ms ease;
}

.header-close-btn:hover {
    background-color: rgba(255, 255, 255, 0.1);
    color: #ffffff;
}

/* ========================================================
   1. TOGGLE UIVERSE (Inspirado en gharsh11032000)
   ======================================================== */
switch.uiverse-switch {
    font-size: 15px;
    border: 2px solid #414141;
    border-radius: 50px;
    background-color: #141418;
    min-width: 46px;
    min-height: 23px;
    transition: all 300ms ease;
}

switch.uiverse-switch:checked {
    box-shadow: 0 0 18px rgba(9, 117, 241, 0.85);
    border: 2px solid #0974f1;
    background-color: #0974f1;
}

switch.uiverse-switch slider {
    background-color: #ffffff;
    border-radius: 50px;
    min-width: 17px;
    min-height: 17px;
    margin: 1px;
    transition: all 300ms ease;
}

/* ========================================================
   2. BARRA DE BÚSQUEDA CÁPSULA (Inspirada en satyamchaudharydev)
   ======================================================== */
.search-form {
    background-color: #22222c;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 22px;
    padding: 2px 10px;
    box-shadow: none;
    transition: all 220ms ease;
}

.search-form:focus-within {
    border-color: #0974f1;
    box-shadow: 0 0 12px rgba(9, 117, 241, 0.35);
}

.search-form button {
    border: none;
    background: transparent;
    color: #8b8ba7;
    padding: 6px;
    transition: color 180ms ease;
}

.search-form button:hover {
    color: #0974f1;
}

.reset-btn {
    border: none;
    background: transparent;
    color: #8b8ba7;
    padding: 4px 6px;
    transition: color 180ms ease;
}

.reset-btn:hover {
    color: #ffffff;
}

.search-input {
    font-size: 14px;
    color: #ffffff;
    background: transparent;
    border: none;
    box-shadow: none;
    padding: 6px 6px;
}

.search-input:focus {
    box-shadow: none;
    border: none;
}

/* ========================================================
   3. BARRA HORIZONTAL DE NAVEGACIÓN D-PAD
   ======================================================== */
.nav-capsule {
    background-color: #22222c;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 18px;
    padding: 3px 6px;
    box-shadow: none;
}

.nav-btn {
    border: none;
    background: transparent;
    color: #a5a5b5;
    min-width: 34px;
    min-height: 30px;
    border-radius: 15px;
    padding: 0;
    transition: all 150ms ease;
}

.nav-btn:hover {
    background-color: rgba(255, 255, 255, 0.1);
    color: #ffffff;
}

.nav-btn:active {
    background-color: rgba(255, 255, 255, 0.2);
}

.nav-btn-play {
    color: #0974f1;
}

.nav-btn-play:hover {
    background-color: rgba(9, 117, 241, 0.2);
    color: #38bdf8;
}
"""

def load_saved_ip():
    try:
        if CONFIG_FILE.exists():
            data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            return data.get("last_ip", "192.168.1.167")
    except Exception:
        pass
    return "192.168.1.167"

def save_ip(ip):
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.write_text(json.dumps({"last_ip": ip}), encoding="utf-8")
    except Exception:
        pass


LINUX_KEY_MAP = {
    19: 103,  # KEY_UP -> Linux 103
    20: 108,  # KEY_DOWN -> Linux 108
    21: 105,  # KEY_LEFT -> Linux 105
    22: 106,  # KEY_RIGHT -> Linux 106
    23: 28,   # KEY_DPAD_CENTER / SELECT -> Linux 28 (KEY_ENTER)
    66: 28,   # KEY_ENTER -> Linux 28 (KEY_ENTER)
}


class ADBCommandQueue:
    """Cola interactiva con proceso shell ADB persistente y eventos directos de kernel."""
    def __init__(self, get_ip_func):
        self.get_ip = get_ip_func
        self.cmd_queue = queue.Queue()
        self.shell_proc = None
        self.current_ip = None
        self.last_send_time = 0.0
        self.min_interval = 0.035
        self.running = True
        self.worker_thread = threading.Thread(target=self._worker_loop, daemon=True)
        self.worker_thread.start()

    def put_key(self, keycode):
        while self.cmd_queue.qsize() > 2:
            try:
                self.cmd_queue.get_nowait()
            except queue.Empty:
                break
        self.cmd_queue.put(('key', keycode))

    def reset_shell(self):
        if self.shell_proc is not None:
            try:
                self.shell_proc.terminate()
                self.shell_proc.wait(timeout=0.2)
            except Exception:
                pass
            self.shell_proc = None
        self.current_ip = None

    def _get_shell(self, ip):
        if self.shell_proc is not None and self.current_ip == ip:
            if self.shell_proc.poll() is None:
                return self.shell_proc
        self.reset_shell()
        try:
            self.shell_proc = subprocess.Popen(
                ["adb", "-s", f"{ip}:5555", "shell"],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1
            )
            self.current_ip = ip
            return self.shell_proc
        except Exception:
            return None

    def _worker_loop(self):
        while self.running:
            item = self.cmd_queue.get()
            if item is None:
                break
            ip = self.get_ip()
            if not ip:
                self.cmd_queue.task_done()
                continue

            now = time.time()
            elapsed = now - self.last_send_time
            if elapsed < self.min_interval:
                time.sleep(self.min_interval - elapsed)

            try:
                shell = self._get_shell(ip)
                if item[0] == 'key':
                    keycode = item[1]
                    linux_code = LINUX_KEY_MAP.get(keycode)
                    if shell and linux_code:
                        cmd = (
                            f"sendevent /dev/input/event3 1 {linux_code} 1\n"
                            f"sendevent /dev/input/event3 0 0 0\n"
                            f"sendevent /dev/input/event3 1 {linux_code} 0\n"
                            f"sendevent /dev/input/event3 0 0 0\n"
                        )
                        if keycode in (23, 66):
                            cmd += "input keyevent 23\n"
                        shell.stdin.write(cmd)
                        shell.stdin.flush()
                    elif shell:
                        shell.stdin.write(f"input keyevent {keycode}\n")
                        shell.stdin.flush()
                        shell.stdin.flush()
            except Exception:
                self.reset_shell()
            finally:
                self.last_send_time = time.time()
                self.cmd_queue.task_done()


class YouTubeCaster:
    """Manejo de conexión ADB y envío de órdenes de YouTube por Deep Link."""
    def __init__(self):
        self.ip = load_saved_ip()
        self.connected = False
        self.cmd_queue = ADBCommandQueue(lambda: self.ip)

    def connect(self, callback_success, callback_failure):
        def _task():
            # 1. Probar primero la última IP guardada
            if self._try_connect(self.ip):
                save_ip(self.ip)
                self.connected = True
                GLib.idle_add(callback_success, self.ip)
                return

            # 2. Si no responde, escanear la red local en paralelo con as_completed
            found_ip = self._scan_network()
            if found_ip and self._try_connect(found_ip):
                self.ip = found_ip
                save_ip(found_ip)
                self.connected = True
                GLib.idle_add(callback_success, found_ip)
            else:
                self.connected = False
                GLib.idle_add(callback_failure)

        threading.Thread(target=_task, daemon=True).start()

    def _try_connect(self, ip):
        if not ip:
            return False
        try:
            res = subprocess.run(
                ["adb", "connect", f"{ip}:5555"],
                capture_output=True, text=True, timeout=2.5
            )
            out = res.stdout.lower()
            return "connected" in out or "already" in out
        except Exception:
            pass
        return False

    def _scan_network(self):
        def check(ip):
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(0.7)
                r = s.connect_ex((ip, 5555))
                s.close()
                if r == 0:
                    return ip
            except Exception:
                pass
            return None

        ips = [f"192.168.1.{i}" for i in range(100, 220)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=40) as executor:
            futures = [executor.submit(check, ip) for ip in ips]
            for f in concurrent.futures.as_completed(futures):
                res = f.result()
                if res:
                    return res
        return None

    def cast_query(self, query):
        if not self.ip or not query:
            return
        
        q = query.strip()
        # Si el usuario pegó un enlace directo de video de YouTube
        if "youtu.be/" in q or "youtube.com/watch" in q or "youtube.com/shorts/" in q:
            target_url = q
        else:
            escaped = urllib.parse.quote_plus(q)
            target_url = f"https://www.youtube.com/results?search_query={escaped}"

        def _send():
            subprocess.run(
                ["adb", "-s", f"{self.ip}:5555", "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", target_url],
                capture_output=True, timeout=3
            )

        threading.Thread(target=_send, daemon=True).start()

    def send_key(self, keycode):
        if self.connected:
            self.cmd_queue.put_key(keycode)

    def disconnect(self):
        self.connected = False
        self.cmd_queue.reset_shell()
        try:
            subprocess.run(["adb", "disconnect"], capture_output=True, timeout=2)
        except Exception:
            pass


class FloatingSearchWindow(Gtk.Window):
    def __init__(self, caster, on_quit_request):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.caster = caster
        self.on_quit_request = on_quit_request

        self.set_title("YouTube TV Search")
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)

        # Transparencia real RGBA para esquinas redondeadas limpias (sin esquinas negras)
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)

        try:
            self.set_icon_from_file(str(ASSETS_DIR / "yt_tv_icon_512.png"))
        except Exception:
            pass
        self.get_style_context().add_class("search-window")

        # Cooldown de seguridad para evitar que el Enter de búsqueda colisione con YouTube
        self.last_search_time = 0.0
        self.search_cooldown = 0.65  # 650 ms de protección
        self.is_internal_toggle = False

        self.setup_ui()
        self.connect("key-press-event", self.on_key_press)
        self.connect("delete-event", lambda w, e: self.hide_window())

    def position_window(self):
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor() or display.get_monitor(0)
        geom = monitor.get_geometry()
        win_w = 380
        # Posición anclada a la esquina superior derecha, justo bajo el panel de Ubuntu
        x = geom.x + geom.width - win_w - 18
        y = geom.y + 36
        self.move(x, y)

    def setup_ui(self):
        self.card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.card.get_style_context().add_class("popover-card")
        self.card.set_size_request(380, -1)
        self.add(self.card)

        # ----------------------------------------------------
        # CABECERA POP-OVER: Icono + Título / Estado + Toggle Uiverse + Cerrar
        # ----------------------------------------------------
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)

        # Icono YouTube TV escalado nítido a 24x24
        icon_path = str(ASSETS_DIR / "yt_tv_icon_512.png")
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, 24, 24, True)
            icon = Gtk.Image.new_from_pixbuf(pixbuf)
        except Exception:
            icon = Gtk.Image.new_from_icon_name("video-x-generic-symbolic", Gtk.IconSize.BUTTON)
        header.pack_start(icon, False, False, 0)

        # Título y etiqueta de estado de conexión
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        lbl_title = Gtk.Label(label="YouTube TV")
        lbl_title.get_style_context().add_class("app-title")
        lbl_title.set_xalign(0)
        title_box.pack_start(lbl_title, False, False, 0)

        self.lbl_status = Gtk.Label(label="Desconectado")
        self.lbl_status.get_style_context().add_class("status-label")
        self.lbl_status.set_xalign(0)
        title_box.pack_start(self.lbl_status, False, False, 0)
        header.pack_start(title_box, False, False, 0)

        # Espaciador flexible para empujar el toggle a la derecha
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        header.pack_start(spacer, True, True, 0)

        # Toggle Switch estilo Uiverse (gharsh11032000)
        self.switch = Gtk.Switch()
        self.switch.get_style_context().add_class("uiverse-switch")
        self.switch.set_valign(Gtk.Align.CENTER)
        self.switch.set_can_focus(False)
        self.switch.set_tooltip_text("Conectar / Desconectar YouTube TV")
        self.switch.connect("notify::active", self.on_switch_toggled)
        header.pack_start(self.switch, False, False, 0)

        # Botón sutil de cerrar / ocultar ventana
        btn_close = Gtk.Button()
        btn_close.set_image(Gtk.Image.new_from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON))
        btn_close.get_style_context().add_class("header-close-btn")
        btn_close.set_tooltip_text("Ocultar controles (Escape)")
        btn_close.set_can_focus(False)
        btn_close.connect("clicked", lambda _: self.hide_window())
        header.pack_start(btn_close, False, False, 0)

        self.card.pack_start(header, False, False, 0)

        # ----------------------------------------------------
        # CUERPO DESPLEGABLE: Barra de búsqueda + Controles D-Pad
        # ----------------------------------------------------
        self.body_revealer = Gtk.Revealer()
        self.body_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.body_revealer.set_transition_duration(250)

        body_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)

        # 1. Barra de búsqueda principal estilo Satyam
        self.capsule = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.capsule.get_style_context().add_class("search-form")
        self.capsule.set_hexpand(True)

        self.search_btn = Gtk.Button()
        search_icon = Gtk.Image.new_from_icon_name("system-search-symbolic", Gtk.IconSize.BUTTON)
        self.search_btn.set_image(search_icon)
        self.search_btn.set_tooltip_text("Enviar búsqueda a la TV (Enter)")
        self.search_btn.set_can_focus(False)
        self.search_btn.connect("clicked", self.on_search_submitted)
        self.capsule.pack_start(self.search_btn, False, False, 0)

        self.entry = Gtk.Entry()
        self.entry.set_placeholder_text("Buscar video o música...")
        self.entry.get_style_context().add_class("search-input")
        self.entry.set_hexpand(True)
        self.entry.connect("activate", self.on_search_submitted)
        self.entry.connect("changed", self.on_entry_changed)
        self.capsule.pack_start(self.entry, True, True, 0)

        self.reset_btn = Gtk.Button()
        clear_icon = Gtk.Image.new_from_icon_name("edit-clear-symbolic", Gtk.IconSize.BUTTON)
        self.reset_btn.set_image(clear_icon)
        self.reset_btn.get_style_context().add_class("reset-btn")
        self.reset_btn.set_tooltip_text("Borrar texto")
        self.reset_btn.set_no_show_all(True)
        self.reset_btn.set_can_focus(False)
        self.reset_btn.connect("clicked", self.on_reset_clicked)
        self.capsule.pack_start(self.reset_btn, False, False, 0)

        body_box.pack_start(self.capsule, False, False, 0)

        # 2. Barra horizontal de navegación D-Pad (Revealer animado)
        self.nav_revealer = Gtk.Revealer()
        self.nav_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.nav_revealer.set_transition_duration(200)

        self.nav_capsule = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.nav_capsule.get_style_context().add_class("nav-capsule")
        self.nav_capsule.set_halign(Gtk.Align.CENTER)

        # Botón Izquierda (←)
        self.btn_left = Gtk.Button()
        self.btn_left.set_image(Gtk.Image.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON))
        self.btn_left.get_style_context().add_class("nav-btn")
        self.btn_left.set_tooltip_text("Izquierda (Flecha ←)")
        self.btn_left.connect("clicked", lambda _: self.send_dpad_key(21))
        self.nav_capsule.pack_start(self.btn_left, False, False, 0)

        # Botón Arriba (↑)
        self.btn_up = Gtk.Button()
        self.btn_up.set_image(Gtk.Image.new_from_icon_name("go-up-symbolic", Gtk.IconSize.BUTTON))
        self.btn_up.get_style_context().add_class("nav-btn")
        self.btn_up.set_tooltip_text("Arriba (Flecha ↑)")
        self.btn_up.connect("clicked", lambda _: self.send_dpad_key(19))
        self.nav_capsule.pack_start(self.btn_up, False, False, 0)

        # Botón Play / OK (▶)
        self.btn_play = Gtk.Button()
        self.btn_play.set_image(Gtk.Image.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON))
        self.btn_play.get_style_context().add_class("nav-btn")
        self.btn_play.get_style_context().add_class("nav-btn-play")
        self.btn_play.set_tooltip_text("Reproducir / Seleccionar (Enter)")
        self.btn_play.connect("clicked", lambda _: self.send_dpad_key(23))
        self.nav_capsule.pack_start(self.btn_play, False, False, 0)

        # Botón Abajo (↓)
        self.btn_down = Gtk.Button()
        self.btn_down.set_image(Gtk.Image.new_from_icon_name("go-down-symbolic", Gtk.IconSize.BUTTON))
        self.btn_down.get_style_context().add_class("nav-btn")
        self.btn_down.set_tooltip_text("Abajo (Flecha ↓)")
        self.btn_down.connect("clicked", lambda _: self.send_dpad_key(20))
        self.nav_capsule.pack_start(self.btn_down, False, False, 0)

        # Botón Derecha (→)
        self.btn_right = Gtk.Button()
        self.btn_right.set_image(Gtk.Image.new_from_icon_name("go-next-symbolic", Gtk.IconSize.BUTTON))
        self.btn_right.get_style_context().add_class("nav-btn")
        self.btn_right.set_tooltip_text("Derecha (Flecha →)")
        self.btn_right.connect("clicked", lambda _: self.send_dpad_key(22))
        self.nav_capsule.pack_start(self.btn_right, False, False, 0)

        for btn in (self.btn_left, self.btn_up, self.btn_play, self.btn_down, self.btn_right):
            btn.set_can_focus(False)

        self.nav_revealer.add(self.nav_capsule)
        body_box.pack_start(self.nav_revealer, False, False, 0)

        self.body_revealer.add(body_box)
        self.body_revealer.connect("notify::child-revealed", self._on_body_revealed_changed)
        self.card.pack_start(self.body_revealer, False, False, 0)

    def _on_body_revealed_changed(self, revealer, gparam):
        if not revealer.get_child_revealed():
            self.resize(380, 1)

    def _on_toggle_off_finish(self):
        self.resize(380, 1)
        self.hide()
        self.on_quit_request()
        return False

    def on_switch_toggled(self, switch, gparam):
        if self.is_internal_toggle:
            return
        active = switch.get_active()
        if active:
            if not self.caster.connected:
                self.lbl_status.set_text("Conectando...")
                self.lbl_status.get_style_context().remove_class("status-online")
                self.lbl_status.get_style_context().add_class("status-connecting")
                self.caster.connect(self.on_connected_success, self.on_connected_failed)
            else:
                self.on_connected_success(self.caster.target_ip)
        else:
            self.caster.disconnect()
            self.lbl_status.set_text("Desconectado")
            self.lbl_status.get_style_context().remove_class("status-online")
            self.lbl_status.get_style_context().remove_class("status-connecting")
            self.body_revealer.set_reveal_child(False)
            self.nav_revealer.set_reveal_child(False)
            # Tras contraerse suavemente, auto-cerrar a la bandeja
            GLib.timeout_add(280, self._on_toggle_off_finish)

    def on_connected_success(self, ip):
        self.is_internal_toggle = True
        self.switch.set_active(True)
        self.is_internal_toggle = False

        self.lbl_status.set_text("En línea")
        self.lbl_status.get_style_context().remove_class("status-connecting")
        self.lbl_status.get_style_context().add_class("status-online")

        self.body_revealer.set_reveal_child(True)
        self.entry.grab_focus()

    def on_connected_failed(self):
        self.is_internal_toggle = True
        self.switch.set_active(False)
        self.is_internal_toggle = False

        self.lbl_status.set_text("Error de conexión")
        self.lbl_status.get_style_context().remove_class("status-connecting")
        self.lbl_status.get_style_context().remove_class("status-online")
        self.body_revealer.set_reveal_child(False)

    def on_entry_changed(self, entry):
        text = entry.get_text()
        self.reset_btn.set_visible(bool(text))

    def on_reset_clicked(self, widget):
        self.entry.set_text("")
        self.entry.grab_focus()

    def send_dpad_key(self, keycode):
        if keycode in (23, 66):
            if time.time() - self.last_search_time < self.search_cooldown:
                return
        self.caster.send_key(keycode)

    def on_search_submitted(self, widget):
        text = self.entry.get_text().strip()
        if not text:
            return
        self.last_search_time = time.time()
        self.caster.cast_query(text)
        self.nav_revealer.set_reveal_child(True)
        self.set_focus(None)

    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.hide_window()
            return True

        if self.body_revealer.get_reveal_child():
            is_entry_focused = self.entry.is_focus()

            if not is_entry_focused:
                if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                    self.send_dpad_key(23)
                    return True
                elif event.keyval == Gdk.KEY_Left:
                    self.send_dpad_key(21)
                    return True
                elif event.keyval == Gdk.KEY_Right:
                    self.send_dpad_key(22)
                    return True
                elif event.keyval == Gdk.KEY_Up:
                    self.send_dpad_key(19)
                    return True
                elif event.keyval == Gdk.KEY_Down:
                    self.send_dpad_key(20)
                    return True

            elif event.keyval in (Gdk.KEY_Up, Gdk.KEY_Down):
                self.set_focus(None)
                if event.keyval == Gdk.KEY_Up:
                    self.send_dpad_key(19)
                else:
                    self.send_dpad_key(20)
                return True

        return False

    def show_window(self):
        self.position_window()
        self.show_all()
        self.present()
        self.position_window()
        if self.caster.connected:
            self.is_internal_toggle = True
            self.switch.set_active(True)
            self.is_internal_toggle = False
            self.lbl_status.set_text("En línea")
            self.lbl_status.get_style_context().add_class("status-online")
            self.body_revealer.set_reveal_child(True)
            self.entry.grab_focus()
        else:
            self.is_internal_toggle = True
            self.switch.set_active(False)
            self.is_internal_toggle = False
            self.lbl_status.set_text("Desconectado")
            self.lbl_status.get_style_context().remove_class("status-online")
            self.body_revealer.set_reveal_child(False)
            self.resize(380, 1)

    def hide_window(self):
        self.hide()
        return True


class TrayApp:
    def __init__(self):
        self.caster = YouTubeCaster()
        self.apply_css()

        self.window = FloatingSearchWindow(self.caster, self.quit_app)

        # Indicador en la barra superior de Ubuntu
        self.indicator = AyatanaAppIndicator3.Indicator.new(
            "glc-yt-cast",
            ICON_PATH,
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)

        self.setup_menu()
        self.window.show_window()

    def apply_css(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        screen = Gdk.Screen.get_default()
        Gtk.StyleContext.add_provider_for_screen(screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)

    def setup_menu(self):
        menu = Gtk.Menu()

        item_search = Gtk.MenuItem(label="🔍 Buscar en YouTube TV")
        item_search.connect("activate", lambda _: self.window.show_window())
        menu.append(item_search)

        menu.append(Gtk.SeparatorMenuItem())

        item_quit = Gtk.MenuItem(label="✕ Desconectar y Salir")
        item_quit.connect("activate", lambda _: self.quit_app())
        menu.append(item_quit)

        menu.show_all()
        self.indicator.set_menu(menu)

    def quit_app(self):
        try:
            self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.PASSIVE)
        except Exception:
            pass
        self.caster.disconnect()
        Gtk.main_quit()

    def run(self):
        Gtk.main()


if __name__ == "__main__":
    app = TrayApp()
    app.run()
