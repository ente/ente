#[macro_export]
macro_rules! setup {
    ($stream_sink:path) => {
        use std::sync::atomic::{AtomicU64, Ordering};
        use std::sync::{Mutex, Once};

        use $crate::__flutter_rust_bridge::frb;

        use $stream_sink;

        #[derive(Clone, Copy)]
        pub enum LogLevel {
            Error,
            Warn,
            Info,
        }

        pub struct LogEntry {
            pub level: LogLevel,
            pub target: String,
            pub message: String,
        }

        static NEXT_SINK_ID: AtomicU64 = AtomicU64::new(0);
        static SINKS: Mutex<Vec<(u64, StreamSink<LogEntry>)>> = Mutex::new(Vec::new());
        static LOGGER: StreamLogger = StreamLogger;
        static LOGGER_INIT: Once = Once::new();

        struct StreamLogger;

        #[frb(opaque)]
        pub struct LogSinkGuard {
            id: u64,
        }

        impl LogSinkGuard {
            #[frb(sync)]
            pub fn new() -> Self {
                Self {
                    id: NEXT_SINK_ID.fetch_add(1, Ordering::Relaxed),
                }
            }

            pub fn attach_log_stream(&self, sink: StreamSink<LogEntry>) {
                SINKS.lock().unwrap().push((self.id, sink));
                $crate::__log::set_max_level($crate::__log::LevelFilter::Info);
            }
        }

        impl Drop for LogSinkGuard {
            fn drop(&mut self) {
                let _sink = {
                    let mut sinks = SINKS.lock().unwrap();
                    sinks
                        .iter()
                        .position(|(id, _)| *id == self.id)
                        .map(|index| sinks.remove(index).1)
                };
            }
        }

        impl $crate::__log::Log for StreamLogger {
            fn enabled(&self, metadata: &$crate::__log::Metadata) -> bool {
                metadata.level() <= $crate::__log::Level::Info
            }

            fn log(&self, record: &$crate::__log::Record) {
                if !self.enabled(record.metadata()) {
                    return;
                }
                let level = match record.level() {
                    $crate::__log::Level::Error => LogLevel::Error,
                    $crate::__log::Level::Warn => LogLevel::Warn,
                    $crate::__log::Level::Info => LogLevel::Info,
                    $crate::__log::Level::Debug | $crate::__log::Level::Trace => return,
                };
                let mut sinks = SINKS.lock().unwrap();
                while let Some((_, sink)) = sinks.first() {
                    if sink
                        .add(LogEntry {
                            level,
                            target: record.target().to_string(),
                            message: record.args().to_string(),
                        })
                        .is_ok()
                    {
                        break;
                    }
                    sinks.remove(0);
                }
            }

            fn flush(&self) {}
        }

        pub(crate) fn install() {
            LOGGER_INIT.call_once(|| {
                $crate::__log::set_logger(&LOGGER).expect("Rust logger already initialized");
                $crate::__log::set_max_level($crate::__log::LevelFilter::Info);
            });
        }
    };
}

#[doc(hidden)]
pub use flutter_rust_bridge as __flutter_rust_bridge;
#[doc(hidden)]
pub use log as __log;
