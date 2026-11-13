use crate::TestResult;

pub const LOCAL_HOST: &str = "127.0.0.1";

// The port is free when returned, not reserved; bind it immediately.
pub fn free_port() -> TestResult<u16> {
    Ok(std::net::TcpListener::bind((LOCAL_HOST, 0))?
        .local_addr()?
        .port())
}
