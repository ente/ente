pub use log::warn;

#[macro_export]
macro_rules! setup {
    () => {
        #[derive(uniffi::Enum)]
        pub enum RustLogLevel {
            Error,
            Warn,
            Info,
        }

        #[uniffi::export(foreign)]
        pub trait RustLogSink: Send + Sync {
            fn log(&self, level: RustLogLevel, target: String, message: String);
        }

        #[uniffi::export]
        pub fn init_rust_logging(sink: std::sync::Arc<dyn RustLogSink>) {
            $crate::__log::set_boxed_logger(Box::new(UniffiLogger { sink }))
                .expect("Rust logger already initialized");
            $crate::__log::set_max_level($crate::__log::LevelFilter::Info);
        }

        struct UniffiLogger {
            sink: std::sync::Arc<dyn RustLogSink>,
        }

        impl $crate::__log::Log for UniffiLogger {
            fn enabled(&self, metadata: &$crate::__log::Metadata) -> bool {
                metadata.level() <= $crate::__log::Level::Info
            }

            fn log(&self, record: &$crate::__log::Record) {
                if !self.enabled(record.metadata()) {
                    return;
                }
                let level = match record.level() {
                    $crate::__log::Level::Error => RustLogLevel::Error,
                    $crate::__log::Level::Warn => RustLogLevel::Warn,
                    $crate::__log::Level::Info => RustLogLevel::Info,
                    $crate::__log::Level::Debug | $crate::__log::Level::Trace => return,
                };
                self.sink.log(
                    level,
                    record.target().to_string(),
                    record.args().to_string(),
                );
            }

            fn flush(&self) {}
        }
    };
}

#[doc(hidden)]
pub use log as __log;
