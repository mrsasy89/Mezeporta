#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use base64::engine::general_purpose;
use base64::Engine;
use meze_butter::MhfConfig;
use std::io::Read;
use std::process::exit;

fn main() {
    #[cfg(target_os = "windows")]
    unsafe {
        use windows::Win32::UI::HiDpi::{
            SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED,
        };

        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED);
    }

    let mut args = std::env::args().skip(1);
    let input = match args.next().as_deref() {
        Some("--stdin-b64") if args.next().is_none() => {
            let mut input = String::new();
            std::io::stdin().read_to_string(&mut input).unwrap_or_else(|e| {
                eprintln!("error reading stdin: {e}");
                exit(2);
            });
            input
        }
        Some("--config-b64-file") => {
            let path = args.next().unwrap_or_else(|| {
                eprintln!("missing path after --config-b64-file");
                exit(1);
            });
            if args.next().is_some() {
                eprintln!("unexpected argument after config file path");
                exit(1);
            }
            std::fs::read_to_string(&path).unwrap_or_else(|e| {
                eprintln!("error reading config file {path}: {e}");
                exit(2);
            })
        }
        _ => {
            eprintln!("usage: meze-deps.exe --stdin-b64 | --config-b64-file <path>");
            exit(1);
        }
    };

    let decoded = general_purpose::STANDARD
        .decode(input.trim())
        .unwrap_or_else(|e| {
            eprintln!("error decoding base64 stdin: {e}");
            exit(3);
        });

    let config_text = String::from_utf8(decoded).unwrap_or_else(|e| {
        eprintln!("error parsing config text: {e}");
        exit(4);
    });

    let config: MhfConfig = serde_json::from_str(&config_text).unwrap_or_else(|e| {
        eprintln!("error parsing config data: {e}");
        exit(5);
    });

    if let Err(e) = meze_butter::run(config) {
        eprintln!("error running meze-deps: {e}");
        exit(6);
    }
}
