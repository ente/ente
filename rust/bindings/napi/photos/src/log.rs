use napi::bindgen_prelude::{FnArgs, Function};
use napi::threadsafe_function::{ThreadsafeFunction, ThreadsafeFunctionCallMode};
use napi::{Error, Status};
use napi_derive::napi;

struct LogEntry {
    level: String,
    target: String,
    message: String,
}

type LogSink =
    ThreadsafeFunction<LogEntry, (), FnArgs<(String, String, String)>, Status, false, true>;

struct NapiLogger {
    sink: LogSink,
}

impl log::Log for NapiLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Info
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            self.sink.call(
                LogEntry {
                    level: record.level().to_string(),
                    target: record.target().to_string(),
                    message: record.args().to_string(),
                },
                ThreadsafeFunctionCallMode::NonBlocking,
            );
        }
    }

    fn flush(&self) {}
}

#[napi]
pub fn init_logging(sink: Function<'_, FnArgs<(String, String, String)>, ()>) -> napi::Result<()> {
    let sink = sink
        .build_threadsafe_function::<LogEntry>()
        .callee_handled::<false>()
        .weak::<true>()
        .build_callback(|ctx| {
            let entry = ctx.value;
            Ok(FnArgs::from((entry.level, entry.target, entry.message)))
        })?;
    log::set_boxed_logger(Box::new(NapiLogger { sink }))
        .map_err(|_| Error::from_reason("Rust logger already initialized"))?;
    log::set_max_level(log::LevelFilter::Info);
    Ok(())
}
