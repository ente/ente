use std::{
    io::{BufRead, BufReader, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::Duration,
};

pub(super) struct MailInbox {
    pub(super) port: u16,
    messages: mpsc::Receiver<String>,
    stop: Arc<AtomicBool>,
    worker: Option<thread::JoinHandle<()>>,
}

impl MailInbox {
    pub(super) fn new() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        listener.set_nonblocking(true).unwrap();
        let (send, messages) = mpsc::channel();
        let stop = Arc::new(AtomicBool::new(false));
        let done = stop.clone();
        let worker = thread::spawn(move || {
            while !done.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => receive_mail(stream, &send),
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10))
                    }
                    Err(error) => panic!("SMTP listener: {error}"),
                }
            }
        });
        Self {
            port,
            messages,
            stop,
            worker: Some(worker),
        }
    }

    pub(super) fn receive(&self, subject: &str) -> String {
        loop {
            let message = self.messages.recv_timeout(Duration::from_secs(5)).unwrap();
            if message.contains(subject) {
                return message;
            }
        }
    }
}

impl Drop for MailInbox {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        let _ = self.worker.take().unwrap().join();
    }
}

fn receive_mail(mut stream: TcpStream, messages: &mpsc::Sender<String>) {
    stream.set_nonblocking(false).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    stream.write_all(b"220 localhost\r\n").unwrap();
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut message = String::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).unwrap() == 0 {
            break;
        }
        message.push_str(&line);
        if line == "DATA\r\n" {
            stream.write_all(b"354 Send data\r\n").unwrap();
            loop {
                line.clear();
                assert_ne!(reader.read_line(&mut line).unwrap(), 0);
                if line == ".\r\n" {
                    break;
                }
                message.push_str(&line);
            }
            messages.send(std::mem::take(&mut message)).unwrap();
        } else if line == "QUIT\r\n" {
            stream.write_all(b"221 Bye\r\n").unwrap();
            break;
        }
        stream.write_all(b"250 OK\r\n").unwrap();
    }
}
