use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread::{self, JoinHandle};

use super::Error;

type Task<T> = Box<dyn FnOnce(&T) -> bool + Send>;

pub(super) struct Worker<T> {
    sender: Option<Sender<Task<T>>>,
    thread: Option<JoinHandle<()>>,
}

impl<T: 'static> Worker<T> {
    pub(super) fn spawn(
        initialize: impl FnOnce() -> Result<T, Error> + Send + 'static,
    ) -> Result<Self, Error> {
        let (sender, receiver) = mpsc::channel::<Task<T>>();
        let (ready, initialized) = mpsc::sync_channel(1);
        let thread = thread::Builder::new()
            .name("ensu-llm".to_owned())
            .spawn(move || {
                let state = match initialize() {
                    Ok(state) => state,
                    Err(error) => {
                        let _ = ready.send(Err(error));
                        return;
                    }
                };
                if ready.send(Ok(())).is_err() {
                    return;
                }
                for task in receiver {
                    if !task(&state) {
                        break;
                    }
                }
            })
            .map_err(|error| Error::Llama {
                op: "Failed to start LLM worker",
                message: error.to_string(),
            })?;
        let worker = Self {
            sender: Some(sender),
            thread: Some(thread),
        };
        initialized.recv().map_err(|_| Error::Panicked)??;
        Ok(worker)
    }

    pub(super) fn submit<R: Send + 'static>(
        &self,
        task: impl FnOnce(&T) -> Result<R, Error> + Send + 'static,
    ) -> Result<Receiver<Result<R, Error>>, Error> {
        let (sender, receiver) = mpsc::sync_channel(1);
        self.sender
            .as_ref()
            .ok_or(Error::Panicked)?
            .send(Box::new(move |state| {
                let result = catch_unwind(AssertUnwindSafe(|| task(state)));
                let keep_running = result.is_ok();
                let _ = sender.send(result.unwrap_or(Err(Error::Panicked)));
                keep_running
            }))
            .map_err(|_| Error::Panicked)?;
        Ok(receiver)
    }

    pub(super) fn call<R: Send + 'static>(
        &self,
        task: impl FnOnce(&T) -> Result<R, Error> + Send + 'static,
    ) -> Result<R, Error> {
        self.submit(task)?.recv().map_err(|_| Error::Panicked)?
    }
}

impl<T> Drop for Worker<T> {
    fn drop(&mut self) {
        self.sender.take();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
            #[cfg(target_os = "android")]
            crate::platform::release_unused_memory();
        }
    }
}

#[cfg(test)]
#[path = "worker_tests.rs"]
mod tests;
