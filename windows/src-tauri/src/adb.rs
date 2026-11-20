use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::net::{IpAddr, SocketAddr, TcpStream, UdpSocket};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Debug, Serialize, Deserialize)]
struct SavedConfig {
    last_ip: String,
}

fn config_file_path() -> Option<PathBuf> {
    if let Ok(appdata) = std::env::var("APPDATA") {
        return Some(PathBuf::from(appdata).join("glc_tv").join("remote_config.json"));
    }
    if let Ok(home) = std::env::var("USERPROFILE").or_else(|_| std::env::var("HOME")) {
        return Some(
            PathBuf::from(home)
                .join(".config")
                .join("glc_tv")
                .join("remote_config.json"),
        );
    }
    None
}

pub fn load_saved_ip() -> Option<String> {
    let path = config_file_path()?;
    let raw = fs::read_to_string(path).ok()?;
    let parsed: SavedConfig = serde_json::from_str(&raw).ok()?;
    let trimmed = parsed.last_ip.trim().to_string();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

pub fn save_ip(ip: &str) {
    let trimmed = ip.trim();
    if trimmed.is_empty() {
        return;
    }
    if let Some(path) = config_file_path() {
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let cfg = SavedConfig {
            last_ip: trimmed.to_string(),
        };
        if let Ok(json) = serde_json::to_string(&cfg) {
            let _ = fs::write(path, json);
        }
    }
}

pub fn get_adb_binary() -> PathBuf {
    let bin_name = if cfg!(windows) { "adb.exe" } else { "adb" };

    if let Ok(exe) = std::env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            let candidates = [
                exe_dir.join(bin_name),
                exe_dir.join("bin").join(bin_name),
                exe_dir.join("resources").join("bin").join(bin_name),
            ];
            for candidate in candidates {
                if candidate.is_file() {
                    return candidate;
                }
            }
        }
    }

    PathBuf::from(bin_name)
}

fn adb_command() -> Command {
    let mut cmd = Command::new(get_adb_binary());
    #[cfg(windows)]
    {
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    cmd
}

fn get_local_subnet_prefix() -> String {
    if let Ok(sock) = UdpSocket::bind("0.0.0.0:0") {
        if sock.connect("8.8.8.8:80").is_ok() {
            if let Ok(local_addr) = sock.local_addr() {
                if let IpAddr::V4(v4) = local_addr.ip() {
                    let o = v4.octets();
                    if o[0] != 127 {
                        return format!("{}.{}.{}", o[0], o[1], o[2]);
                    }
                }
            }
        }
    }
    "192.168.1".to_string()
}

fn linux_keycode(android_keycode: u32) -> Option<u32> {
    match android_keycode {
        19 => Some(103), // KEY_UP
        20 => Some(108), // KEY_DOWN
        21 => Some(105), // KEY_LEFT
        22 => Some(106), // KEY_RIGHT
        23 | 66 => Some(28), // KEY_ENTER
        _ => None,
    }
}

struct PersistentShell {
    child: Child,
    stdin: ChildStdin,
    ip: String,
    input_event_dev: Option<String>,
}

enum WorkerMsg {
    Key(u32),
    Reset,
}

fn detect_input_event_device(ip: &str) -> Option<String> {
    let probe_cmd = r#"for d in /dev/input/event*; do if [ -w "$d" ] && getevent -p "$d" 2>/dev/null | grep -q "0067"; then echo "$d"; break; fi; done"#;
    let out = adb_command()
        .args(["-s", &format!("{}:5555", ip), "shell", probe_cmd])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let first_line = stdout.lines().next()?.trim();
    if first_line.starts_with("/dev/input/event") {
        Some(first_line.to_string())
    } else {
        None
    }
}

fn open_shell(ip: &str) -> Option<PersistentShell> {
    let input_event_dev = detect_input_event_device(ip);
    let mut child = adb_command()
        .args(["-s", &format!("{}:5555", ip), "shell"])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let stdin = child.stdin.take()?;
    Some(PersistentShell {
        child,
        stdin,
        ip: ip.to_string(),
        input_event_dev,
    })
}

pub struct YouTubeCaster {
    ip: Arc<Mutex<Option<String>>>,
    connected: Arc<AtomicBool>,
    tx: Mutex<mpsc::Sender<WorkerMsg>>,
}

impl YouTubeCaster {
    pub fn new() -> Self {
        let ip = Arc::new(Mutex::new(load_saved_ip()));
        let connected = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel::<WorkerMsg>();

        let worker_ip = Arc::clone(&ip);
        thread::spawn(move || {
            let mut shell: Option<PersistentShell> = None;
            let mut last_send = Instant::now() - Duration::from_secs(1);
            let min_interval = Duration::from_millis(35);

            for msg in rx {
                match msg {
                    WorkerMsg::Reset => {
                        if let Some(mut s) = shell.take() {
                            let _ = s.child.kill();
                            let _ = s.child.wait();
                        }
                    }
                    WorkerMsg::Key(keycode) => {
                        let current_ip = match worker_ip.lock().ok().and_then(|g| g.clone()) {
                            Some(v) => v,
                            None => continue,
                        };

                        let elapsed = last_send.elapsed();
                        if elapsed < min_interval {
                            thread::sleep(min_interval - elapsed);
                        }

                        // Verificar si el shell actual sigue vivo y corresponde a la misma IP
                        let need_reopen = match &mut shell {
                            Some(s) if s.ip == current_ip => {
                                matches!(s.child.try_wait(), Ok(Some(_)) | Err(_))
                            }
                            _ => true,
                        };

                        if need_reopen {
                            if let Some(mut old) = shell.take() {
                                let _ = old.child.kill();
                                let _ = old.child.wait();
                            }
                            shell = open_shell(&current_ip);
                        }

                        if let Some(s) = &mut shell {
                            let cmd = if let (Some(dev), Some(lcode)) =
                                (&s.input_event_dev, linux_keycode(keycode))
                            {
                                let mut c = format!(
                                    "sendevent {dev} 1 {lcode} 1\nsendevent {dev} 0 0 0\nsendevent {dev} 1 {lcode} 0\nsendevent {dev} 0 0 0\n"
                                );
                                if keycode == 23 || keycode == 66 {
                                    c.push_str("input keyevent 23\n");
                                }
                                c
                            } else {
                                format!("input keyevent {keycode}\n")
                            };

                            if s.stdin.write_all(cmd.as_bytes()).is_err()
                                || s.stdin.flush().is_err()
                            {
                                if let Some(mut broken) = shell.take() {
                                    let _ = broken.child.kill();
                                    let _ = broken.child.wait();
                                }
                            }
                        }

                        last_send = Instant::now();
                    }
                }
            }
        });

        Self {
            ip,
            connected,
            tx: Mutex::new(tx),
        }
    }

    pub fn get_ip(&self) -> Option<String> {
        self.ip.lock().ok().and_then(|g| g.clone())
    }

    pub fn is_connected(&self) -> bool {
        self.connected.load(Ordering::SeqCst)
    }

    fn try_connect(ip: &str) -> bool {
        let trimmed = ip.trim();
        if trimmed.is_empty() {
            return false;
        }
        let target = format!("{}:5555", trimmed);
        match adb_command()
            .args(["connect", &target])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
        {
            Ok(output) => {
                let out = String::from_utf8_lossy(&output.stdout).to_lowercase();
                out.contains("connected") || out.contains("already")
            }
            Err(_) => false,
        }
    }

    fn scan_network() -> Option<String> {
        let prefix = get_local_subnet_prefix();
        let mut ips = Vec::with_capacity(253);
        for i in 100..=220 {
            ips.push(format!("{}.{}", prefix, i));
        }
        for i in 2..100 {
            ips.push(format!("{}.{}", prefix, i));
        }
        for i in 221..=254 {
            ips.push(format!("{}.{}", prefix, i));
        }

        let found = Arc::new(AtomicBool::new(false));
        let result: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
        let queue = Arc::new(Mutex::new(ips.into_iter()));

        let mut handles = Vec::new();
        for _ in 0..48 {
            let found_c = Arc::clone(&found);
            let result_c = Arc::clone(&result);
            let queue_c = Arc::clone(&queue);
            handles.push(thread::spawn(move || loop {
                if found_c.load(Ordering::Relaxed) {
                    break;
                }
                let next_ip = {
                    let mut q = match queue_c.lock() {
                        Ok(g) => g,
                        Err(_) => break,
                    };
                    q.next()
                };
                let ip = match next_ip {
                    Some(v) => v,
                    None => break,
                };
                if let Ok(addr) = format!("{}:5555", ip).parse::<SocketAddr>() {
                    if TcpStream::connect_timeout(&addr, Duration::from_millis(450)).is_ok() {
                        found_c.store(true, Ordering::SeqCst);
                        if let Ok(mut res) = result_c.lock() {
                            if res.is_none() {
                                *res = Some(ip);
                            }
                        }
                        break;
                    }
                }
            }));
        }

        for h in handles {
            let _ = h.join();
        }

        result.lock().ok().and_then(|g| g.clone())
    }

    pub fn connect(&self, force_ip: Option<String>) -> Result<String, String> {
        if let Some(ref fip) = force_ip {
            let cleaned = fip.trim().to_string();
            if !cleaned.is_empty() {
                if let Ok(mut g) = self.ip.lock() {
                    *g = Some(cleaned);
                }
            }
        }

        // 1. Probar IP guardada o especificada
        if let Some(candidate) = self.get_ip() {
            if Self::try_connect(&candidate) {
                save_ip(&candidate);
                self.connected.store(true, Ordering::SeqCst);
                return Ok(candidate);
            }
        }

        // 2. Si no se forzó una IP específica (o falló), escanear subred local
        if let Some(found_ip) = Self::scan_network() {
            if Self::try_connect(&found_ip) {
                if let Ok(mut g) = self.ip.lock() {
                    *g = Some(found_ip.clone());
                }
                save_ip(&found_ip);
                self.connected.store(true, Ordering::SeqCst);
                return Ok(found_ip);
            }
        }

        self.connected.store(false, Ordering::SeqCst);
        Err("No se encontró ninguna Android TV con ADB en la red local".to_string())
    }

    pub fn cast_query(&self, query: String) {
        let q = query.trim().to_string();
        if q.is_empty() {
            return;
        }
        let ip = match self.get_ip() {
            Some(v) => v,
            None => return,
        };

        let target_url = if q.contains("youtu.be/")
            || q.contains("youtube.com/watch")
            || q.contains("youtube.com/shorts/")
        {
            q
        } else {
            let escaped = urlencoding::encode(&q);
            format!("https://www.youtube.com/results?search_query={}", escaped)
        };

        thread::spawn(move || {
            let _ = adb_command()
                .args([
                    "-s",
                    &format!("{}:5555", ip),
                    "shell",
                    "am",
                    "start",
                    "-a",
                    "android.intent.action.VIEW",
                    "-d",
                    &target_url,
                ])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        });
    }

    pub fn send_key(&self, keycode: u32) {
        if self.is_connected() {
            if let Ok(tx) = self.tx.lock() {
                let _ = tx.send(WorkerMsg::Key(keycode));
            }
        }
    }

    pub fn disconnect(&self) {
        self.connected.store(false, Ordering::SeqCst);
        if let Ok(tx) = self.tx.lock() {
            let _ = tx.send(WorkerMsg::Reset);
        }
        let _ = adb_command()
            .args(["disconnect"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}
