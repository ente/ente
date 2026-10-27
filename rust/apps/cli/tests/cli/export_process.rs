use std::{
    io,
    ops::{Deref, DerefMut},
    process::{Child, Command, Output},
    time::{Duration, Instant},
};

pub(crate) struct ExportChild(Option<Child>);

impl ExportChild {
    pub fn spawn(command: &mut Command) -> io::Result<Self> {
        Ok(Self(Some(command.spawn()?)))
    }

    pub fn wait_with_output(mut self) -> io::Result<Output> {
        let deadline = Instant::now() + Duration::from_secs(60);
        while self.try_wait()?.is_none() {
            if Instant::now() >= deadline {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "export child did not exit",
                ));
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        self.0.take().unwrap().wait_with_output()
    }
}

impl Deref for ExportChild {
    type Target = Child;

    fn deref(&self) -> &Child {
        self.0.as_ref().unwrap()
    }
}

impl DerefMut for ExportChild {
    fn deref_mut(&mut self) -> &mut Child {
        self.0.as_mut().unwrap()
    }
}

impl Drop for ExportChild {
    fn drop(&mut self) {
        if let Some(child) = &mut self.0 {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}
