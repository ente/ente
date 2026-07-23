use crate::TestResult;

pub const LOCAL_HOST: &str = "127.0.0.1";

/// An unused local TCP port.
///
/// Racy: the port is free when returned, not reserved, so the caller should
/// bind it promptly.
pub fn free_port() -> TestResult<u16> {
    Ok(std::net::TcpListener::bind((LOCAL_HOST, 0))?
        .local_addr()?
        .port())
}
