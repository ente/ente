use std::{
    fs,
    io::{Read, Write},
    net::TcpStream,
    path::Path,
    process::Command,
    time::{Duration, Instant},
};

use crate::{
    HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, TestResult, net::LOCAL_HOST, postgres::Postgres,
    process::ChildProcess,
};

pub fn start(
    server_dir: &Path,
    log_dir: &Path,
    config_file: &Path,
    museum_port: u16,
    museum_bin: &Path,
    db: &Postgres,
) -> TestResult<ChildProcess> {
    require_go()?;
    build_museum(server_dir, museum_bin)?;

    let mut command = Command::new(museum_bin);
    command
        .current_dir(server_dir)
        .env("ENTE_CREDENTIALS_FILE", config_file)
        .env("ENTE_DB_HOST", db.host())
        .env("ENTE_DB_PORT", db.port().to_string())
        .env("ENTE_DB_NAME", db.database())
        .env("ENTE_DB_USER", db.username())
        .env("ENTE_DB_PASSWORD", db.password())
        .env("ENTE_DB_SSLMODE", "disable")
        .env("ENTE_HTTP_PORT", museum_port.to_string())
        .env(
            "ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_SUFFIX",
            HARDCODED_OTT_EMAIL_SUFFIX,
        )
        .env(
            "ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_VALUE",
            HARDCODED_OTT,
        )
        .env("ENTE_JOBS_CRON_SKIP", "true");

    let mut museum = ChildProcess::spawn("museum", &mut command, log_dir)?;
    wait_for_museum(&mut museum, museum_port)?;
    Ok(museum)
}

/// A local `museum.yaml` can clobber anything written here; keys that must
/// survive that are set via env in [`start`] instead.
pub fn write_config(path: &Path, object_store_endpoint: &str) -> TestResult {
    fs::write(
        path,
        format!(
            r#"s3:
    are_local_buckets: true
    b2-eu-cen:
        key: changeme
        secret: changeme1234
        endpoint: {object_store_endpoint}
        region: eu-central-2
        bucket: b2-eu-cen
space:
    assets:
        primaryBucket: b2-eu-cen
"#
        ),
    )?;
    Ok(())
}

fn require_go() -> TestResult {
    match Command::new("go").arg("version").output() {
        Ok(output) if output.status.success() => Ok(()),
        _ => Err("Museum live tests require `go` on PATH".into()),
    }
}

fn build_museum(server_dir: &Path, out: &Path) -> TestResult {
    let status = Command::new("go")
        .arg("build")
        .arg("-o")
        .arg(out)
        .arg("./cmd/museum")
        .current_dir(server_dir)
        .status()?;
    if !status.success() {
        return Err("go build ./cmd/museum failed".into());
    }
    Ok(())
}

fn wait_for_museum(process: &mut ChildProcess, port: u16) -> TestResult {
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        process.ensure_running()?;
        if ping(port)? {
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(format!(
                "Museum did not become ready at http://{LOCAL_HOST}:{port}/ping\n{}",
                process.log_summary()
            )
            .into());
        }
        std::thread::sleep(Duration::from_millis(500));
    }
}

fn ping(port: u16) -> TestResult<bool> {
    let mut stream = match TcpStream::connect((LOCAL_HOST, port)) {
        Ok(stream) => stream,
        Err(_) => return Ok(false),
    };
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.write_all(b"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")?;

    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    Ok(response.starts_with("HTTP/1.1 200") || response.starts_with("HTTP/1.0 200"))
}
