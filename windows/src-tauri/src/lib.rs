mod adb;

use adb::YouTubeCaster;
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, LogicalSize, Manager, PhysicalPosition, State, WebviewWindow};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

struct AppState {
    caster: Arc<YouTubeCaster>,
}

fn position_bottom_right(window: &WebviewWindow) {
    let monitor = window
        .current_monitor()
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten());

    if let (Some(mon), Ok(win_size)) = (monitor, window.outer_size()) {
        let work = mon.work_area();
        let scale = mon.scale_factor();
        let margin = (14.0 * scale) as i32;

        let x = (work.position.x + work.size.width as i32 - win_size.width as i32 - margin).max(0);
        let y =
            (work.position.y + work.size.height as i32 - win_size.height as i32 - margin).max(0);

        let _ = window.set_position(PhysicalPosition::new(x, y));
    }
}

fn show_and_focus_popover(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        position_bottom_right(&win);
        let _ = win.show();
        let _ = win.set_focus();
        position_bottom_right(&win);
    }
}

fn toggle_popover(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        if win.is_visible().unwrap_or(false) {
            let _ = win.hide();
        } else {
            show_and_focus_popover(app);
        }
    }
}

#[tauri::command]
async fn connect_tv(
    force_ip: Option<String>,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let caster = Arc::clone(&state.caster);
    tauri::async_runtime::spawn_blocking(move || caster.connect(force_ip))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
fn disconnect_tv(state: State<'_, AppState>) {
    state.caster.disconnect();
}

#[tauri::command]
fn get_connection_state(state: State<'_, AppState>) -> (bool, Option<String>) {
    (state.caster.is_connected(), state.caster.get_ip())
}

#[tauri::command]
fn cast_query(query: String, state: State<'_, AppState>) {
    state.caster.cast_query(query);
}

#[tauri::command]
fn send_dpad_key(keycode: u32, state: State<'_, AppState>) {
    state.caster.send_key(keycode);
}

#[tauri::command]
fn set_popover_height(height: f64, window: WebviewWindow) {
    let clamped = height.clamp(76.0, 360.0);
    let _ = window.set_size(LogicalSize::new(404.0, clamped));
    position_bottom_right(&window);
}

#[tauri::command]
fn hide_popover(window: WebviewWindow) {
    let _ = window.hide();
}

#[tauri::command]
fn quit_app(app: AppHandle, state: State<'_, AppState>) {
    state.caster.disconnect();
    app.exit(0);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let caster = Arc::new(YouTubeCaster::new());

    tauri::Builder::default()
        .manage(AppState {
            caster: Arc::clone(&caster),
        })
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(move |app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        toggle_popover(app);
                    }
                })
                .build(),
        )
        .setup(move |app| {
            // 1. Registrar atajo global Ctrl + Alt + Y
            let shortcut = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyY);
            let _ = app.global_shortcut().register(shortcut);

            // 2. Construir menú de la bandeja del sistema (System Tray)
            let item_open = MenuItem::with_id(app, "open", "Buscar en YouTube TV (Ctrl+Alt+Y)", true, None::<&str>)?;
            let item_ip = MenuItem::with_id(app, "config_ip", "Configurar IP de la TV...", true, None::<&str>)?;
            let sep = PredefinedMenuItem::separator(app)?;
            let item_quit = MenuItem::with_id(app, "quit", "Desconectar y Salir", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&item_open, &item_ip, &sep, &item_quit])?;

            let mut tray_builder = TrayIconBuilder::with_id("main-tray")
                .tooltip("GLC YouTube TV Cast")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => show_and_focus_popover(app),
                    "config_ip" => {
                        show_and_focus_popover(app);
                        let _ = app.emit("open-ip-config", ());
                    }
                    "quit" => {
                        if let Some(st) = app.try_state::<AppState>() {
                            st.caster.disconnect();
                        }
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_popover(tray.app_handle());
                    }
                });

            if let Some(icon) = app.default_window_icon().cloned() {
                tray_builder = tray_builder.icon(icon);
            }
            let _tray = tray_builder.build(app)?;

            // 3. Posicionar ventana inicial sobre la bandeja (esquina inferior derecha)
            if let Some(win) = app.get_webview_window("main") {
                position_bottom_right(&win);
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            connect_tv,
            disconnect_tv,
            get_connection_state,
            cast_query,
            send_dpad_key,
            set_popover_height,
            hide_popover,
            quit_app,
        ])
        .run(tauri::generate_context!())
        .expect("error al iniciar GLC YouTube TV Cast");
}
