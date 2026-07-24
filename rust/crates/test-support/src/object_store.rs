use std::{
    collections::HashMap,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
};

use crate::{TestResult, net::LOCAL_HOST};

pub struct ObjectStore {
    port: u16,
    stop: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl ObjectStore {
    pub fn start() -> TestResult<Self> {
        let listener = TcpListener::bind((LOCAL_HOST, 0))?;
        let port = listener.local_addr()?.port();
        let stop = Arc::new(AtomicBool::new(false));
        let worker_stop = Arc::clone(&stop);
        let worker = thread::spawn(move || {
            let mut objects = HashMap::new();
            while let Ok((stream, _)) = listener.accept() {
                if worker_stop.load(Ordering::Relaxed) {
                    break;
                }
                handle(stream, &mut objects);
            }
        });
        Ok(Self {
            port,
            stop,
            worker: Some(worker),
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
    }
}

fn handle(mut stream: TcpStream, objects: &mut HashMap<String, usize>) {
    let mut request = Vec::new();
    let mut buffer = [0; 4096];
    let header_end = loop {
        let Ok(read) = stream.read(&mut buffer) else {
            return;
        };
        if read == 0 {
            return;
        }
        request.extend_from_slice(&buffer[..read]);
        if let Some(end) = request.windows(4).position(|bytes| bytes == b"\r\n\r\n") {
            break end + 4;
        }
    };
    let Ok(headers) = std::str::from_utf8(&request[..header_end]) else {
        return;
    };
    let mut lines = headers.lines();
    let Some((method, target)) = lines.next().and_then(|line| {
        let mut parts = line.split_whitespace();
        Some((parts.next()?.to_owned(), parts.next()?.to_owned()))
    }) else {
        return;
    };
    let content_length = lines
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            if name.eq_ignore_ascii_case("content-length") {
                value.trim().parse().ok()
            } else {
                None
            }
        })
        .unwrap_or(0);
    while request.len() < header_end + content_length {
        let Ok(read) = stream.read(&mut buffer) else {
            return;
        };
        if read == 0 {
            return;
        }
        request.extend_from_slice(&buffer[..read]);
    }
    let path = target.split('?').next().unwrap_or(&target).to_owned();
    match method.as_str() {
        "PUT" => {
            objects.insert(path, content_length);
            respond(&mut stream, "200 OK", 0);
        }
        "HEAD" => match objects.get(&path) {
            Some(content_length) => respond(&mut stream, "200 OK", *content_length),
            None => respond(&mut stream, "404 Not Found", 0),
        },
        _ => respond(&mut stream, "405 Method Not Allowed", 0),
    }
}

fn respond(stream: &mut TcpStream, status: &str, content_length: usize) {
    let _ = write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Length: {content_length}\r\nConnection: close\r\n\r\n"
    );
}
