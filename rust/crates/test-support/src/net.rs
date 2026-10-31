use crate::TestResult;

pub const LOCAL_HOST: &str = "127.0.0.1";

const PORT_ATTEMPTS: usize = 5;

// The port is free when returned, not reserved; bind it immediately.
pub fn free_port() -> TestResult<u16> {
    Ok(std::net::TcpListener::bind((LOCAL_HOST, 0))?
        .local_addr()?
        .port())
}

pub fn retry_taken_port<T>(mut start: impl FnMut() -> TestResult<Option<T>>) -> TestResult<T> {
    for _ in 0..PORT_ATTEMPTS {
        if let Some(started) = start()? {
            return Ok(started);
        }
    }
    Err(format!("port still taken after {PORT_ATTEMPTS} attempts").into())
}
