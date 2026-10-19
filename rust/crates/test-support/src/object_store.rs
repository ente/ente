use std::{
    fs::{self, File},
    io::{self, BufRead, BufReader, Read, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    sync::{
        Arc, Condvar, Mutex, PoisonError,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    thread::{self, JoinHandle},
    time::Duration,
};

use ente_core::crypto::hash;
use uuid::Uuid;

use crate::{TestResult, net::LOCAL_HOST};

#[derive(Default)]
pub struct ObjectStoreControl {
    reads: AtomicUsize,
    interrupted: AtomicUsize,
    held: Mutex<Option<Arc<ReadGate>>>,
}

struct ReadGate {
    minimum_size: u64,
    state: Mutex<(usize, bool)>,
    changed: Condvar,
}

pub struct HeldReads(Arc<ReadGate>);

impl HeldReads {
    pub fn wait_for(&self, count: usize) {
        let (state, _) = self
            .0
            .changed
            .wait_timeout_while(
                self.0.state.lock().unwrap_or_else(PoisonError::into_inner),
                Duration::from_secs(60),
                |(started, _)| *started < count,
            )
            .unwrap_or_else(PoisonError::into_inner);
        let started = state.0;
        drop(state);
        assert!(
            started >= count,
            "expected {count} held downloads, got {started}"
        );
    }
}

impl Drop for HeldReads {
    fn drop(&mut self) {
        self.0
            .state
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .1 = true;
        self.0.changed.notify_all();
    }
}

impl ObjectStoreControl {
    pub fn hold_reads(&self, minimum_size: u64) -> HeldReads {
        let gate = Arc::new(ReadGate {
            minimum_size,
            state: Mutex::new((0, false)),
            changed: Condvar::new(),
        });
        *self.held.lock().unwrap_or_else(PoisonError::into_inner) = Some(gate.clone());
        HeldReads(gate)
    }

    pub fn reads(&self) -> usize {
        self.reads.load(Ordering::SeqCst)
    }
    pub fn interrupt_reads(&self, count: usize) {
        self.interrupted.store(count, Ordering::SeqCst);
    }
}

pub struct ObjectStore {
    port: u16,
    stop: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
    directory: PathBuf,
    pub control: Arc<ObjectStoreControl>,
}

impl ObjectStore {
    pub fn start() -> TestResult<Self> {
        let listener = TcpListener::bind((LOCAL_HOST, 0))?;
        let port = listener.local_addr()?.port();
        let directory = std::env::temp_dir().join(format!("ente-objects-{}", Uuid::new_v4()));
        fs::create_dir(&directory)?;
        let stop = Arc::new(AtomicBool::new(false));
        let worker_stop = stop.clone();
        let root = directory.clone();
        let control = Arc::new(ObjectStoreControl::default());
        let worker_control = control.clone();
        let worker = thread::spawn(move || {
            let mut requests: Vec<JoinHandle<()>> = Vec::new();
            while let Ok((stream, _)) = listener.accept() {
                if worker_stop.load(Ordering::Relaxed) {
                    break;
                }
                let root = root.clone();
                let control = worker_control.clone();
                requests.retain(|request| !request.is_finished());
                requests.push(thread::spawn(move || {
                    let _ = handle(stream, &root, &control);
                }));
            }
            for request in requests {
                let _ = request.join();
            }
        });
        Ok(Self {
            port,
            stop,
            worker: Some(worker),
            directory,
            control,
        })
    }

    pub fn endpoint(&self) -> String {
        format!("http://{LOCAL_HOST}:{}", self.port)
    }
}

impl Drop for ObjectStore {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        let _ = TcpStream::connect((LOCAL_HOST, self.port));
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        let _ = fs::remove_dir_all(&self.directory);
    }
}

fn handle(stream: TcpStream, root: &Path, control: &ObjectStoreControl) -> TestResult {
    stream.set_read_timeout(Some(Duration::from_secs(30)))?;
    stream.set_write_timeout(Some(Duration::from_secs(30)))?;
    let mut input = BufReader::new(stream);
    let mut line = String::new();
    input.read_line(&mut line)?;
    let mut words = line.split_whitespace();
    let method = words.next().ok_or("missing method")?.to_owned();
    let target = words
        .next()
        .ok_or("missing target")?
        .split('?')
        .next()
        .ok_or("missing path")?;
    let name: String = hash::hash(target.as_bytes(), Some(32), None)?
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    let path = root.join(&name);
    let mut length = 0u64;
    loop {
        line.clear();
        if input.read_line(&mut line)? == 0 {
            return Err("incomplete headers".into());
        }
        if line == "\r\n" {
            break;
        }
        if let Some((name, value)) = line.split_once(':')
            && name.eq_ignore_ascii_case("content-length")
        {
            length = value.trim().parse()?;
        }
    }
    match method.as_str() {
        "OPTIONS" => respond(input.get_mut(), "204 No Content", 0)?,
        "PUT" => {
            let temporary = root.join(format!("{name}.{}.part", Uuid::new_v4()));
            let mut file = File::create(&temporary)?;
            let received = io::copy(&mut (&mut input).take(length), &mut file)?;
            if received != length {
                fs::remove_file(temporary)?;
                return Err("incomplete upload".into());
            }
            file.sync_all()?;
            drop(file);
            fs::rename(temporary, path)?;
            respond(input.get_mut(), "200 OK", 0)?;
        }
        "HEAD" => match fs::metadata(path) {
            Ok(meta) => respond(input.get_mut(), "200 OK", meta.len())?,
            Err(_) => respond(input.get_mut(), "404 Not Found", 0)?,
        },
        "GET" => {
            control.reads.fetch_add(1, Ordering::SeqCst);
            let Ok(mut file) = File::open(path) else {
                respond(input.get_mut(), "404 Not Found", 0)?;
                return Ok(());
            };
            if control
                .interrupted
                .try_update(Ordering::SeqCst, Ordering::SeqCst, |left| {
                    left.checked_sub(1)
                })
                .is_ok()
            {
                return Ok(());
            }
            respond(input.get_mut(), "200 OK", file.metadata()?.len())?;
            let gate = control
                .held
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .clone();
            if let Some(gate) = gate
                && file.metadata()?.len() >= gate.minimum_size
            {
                let mut state = gate.state.lock().unwrap_or_else(PoisonError::into_inner);
                state.0 += 1;
                gate.changed.notify_all();
                while !state.1 {
                    state = gate
                        .changed
                        .wait(state)
                        .unwrap_or_else(PoisonError::into_inner);
                }
            }
            let mut buffer = vec![0; 64 * 1024];
            loop {
                let read = file.read(&mut buffer)?;
                if read == 0 {
                    break;
                }
                input.get_mut().write_all(&buffer[..read])?;
            }
        }
        _ => respond(input.get_mut(), "405 Method Not Allowed", 0)?,
    }
    Ok(())
}

fn respond(stream: &mut TcpStream, status: &str, length: u64) -> io::Result<()> {
    write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Length: {length}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, HEAD, PUT\r\nAccess-Control-Allow-Headers: Content-Type, Content-MD5, X-Client-Package, X-Client-Version\r\nConnection: close\r\n\r\n"
    )
}
