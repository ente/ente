use std::cell::Cell;
use std::rc::Rc;
use std::sync::mpsc;
use std::thread::{self, ThreadId};

use super::Worker;
use crate::llm::Error;

struct State {
    value: Rc<Cell<usize>>,
    owner: ThreadId,
    dropped: mpsc::Sender<ThreadId>,
}

impl Drop for State {
    fn drop(&mut self) {
        let _ = self.dropped.send(thread::current().id());
    }
}

#[test]
fn creates_uses_and_drops_non_send_state_on_one_thread() {
    let (dropped, received) = mpsc::channel();
    let worker = Worker::spawn(move || {
        Ok(State {
            value: Rc::new(Cell::new(0)),
            owner: thread::current().id(),
            dropped,
        })
    })
    .unwrap();
    let owner = worker.call(|state| Ok(state.owner)).unwrap();
    assert_ne!(owner, thread::current().id());
    thread::scope(|scope| {
        for _ in 0..8 {
            scope.spawn(|| {
                for _ in 0..100 {
                    worker
                        .call(|state| {
                            assert_eq!(state.owner, thread::current().id());
                            state.value.set(state.value.get() + 1);
                            Ok(())
                        })
                        .unwrap();
                }
            });
        }
    });
    assert_eq!(worker.call(|state| Ok(state.value.get())).unwrap(), 800);
    drop(worker);
    assert_eq!(received.recv().unwrap(), owner);
}

#[test]
fn initialization_failures_and_panics_reach_the_caller() {
    let result = Worker::<()>::spawn(|| Err(Error::InvalidInput("fixture".to_owned())));
    assert!(matches!(result, Err(Error::InvalidInput(_))));
    let result = Worker::<()>::spawn(|| panic!("initialization failed"));
    assert!(matches!(result, Err(Error::Panicked)));
}

#[test]
fn operation_error_keeps_worker_available() {
    let worker = Worker::spawn(|| Ok(Rc::new(Cell::new(7)))).unwrap();
    let result = worker.call::<()>(|_| Err(Error::Cancelled));
    assert!(matches!(result, Err(Error::Cancelled)));
    assert_eq!(worker.call(|state| Ok(state.get())).unwrap(), 7);
}

#[test]
fn panic_closes_pending_requests_and_drops_state_on_worker() {
    let (dropped, received) = mpsc::channel();
    let worker = Worker::spawn(move || {
        Ok(State {
            value: Rc::new(Cell::new(0)),
            owner: thread::current().id(),
            dropped,
        })
    })
    .unwrap();
    let owner = worker.call(|state| Ok(state.owner)).unwrap();
    let (release, released) = mpsc::channel();
    let first = worker
        .submit::<()>(move |_| {
            released.recv().unwrap();
            panic!("operation failed");
        })
        .unwrap();
    let second = worker.submit(|_| Ok(1)).unwrap();
    release.send(()).unwrap();
    assert!(matches!(first.recv().unwrap(), Err(Error::Panicked)));
    assert!(second.recv().is_err());
    assert!(matches!(worker.call(|_| Ok(())), Err(Error::Panicked)));
    drop(worker);
    assert_eq!(received.recv().unwrap(), owner);
}
