use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

const GLOBAL_HOOK: &str = "enteRustLog";

static LOGGER: WasmLogger = WasmLogger;

struct WasmLogger;

impl log::Log for WasmLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Info
    }

    fn log(&self, record: &log::Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let level = record.level().to_string();
        let target = record.target().to_string();
        let message = record.args().to_string();

        let handled = js_sys::Reflect::get(&js_sys::global(), &GLOBAL_HOOK.into())
            .ok()
            .and_then(|hook| hook.dyn_into::<js_sys::Function>().ok())
            .is_some_and(|hook| {
                hook.call3(
                    &JsValue::NULL,
                    &level.as_str().into(),
                    &target.as_str().into(),
                    &message.as_str().into(),
                )
                .is_ok()
            });

        if !handled {
            let line = JsValue::from(format!("[{target}] {message}"));
            match record.level() {
                log::Level::Error => web_sys::console::error_1(&line),
                log::Level::Warn => web_sys::console::warn_1(&line),
                log::Level::Info => web_sys::console::info_1(&line),
                log::Level::Debug | log::Level::Trace => {}
            }
        }
    }

    fn flush(&self) {}
}

#[wasm_bindgen(start)]
fn start() {
    #[expect(
        clippy::expect_used,
        reason = "Initialization requires exclusive ownership of the process logger"
    )]
    log::set_logger(&LOGGER).expect("Rust logger already initialized");
    log::set_max_level(log::LevelFilter::Info);
}
