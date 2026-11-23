use std::{
    fs,
    io::{Read, Write},
    net::TcpStream,
    path::Path,
    process::Command,
    time::{Duration, Instant},
};

use uuid::Uuid;

use crate::{
    HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, TestResult,
    net::{LOCAL_HOST, PORT_ATTEMPTS},
    postgres::Postgres,
    process::ChildProcess,
};

enum Startup {
    Ready,
    PortTaken,
}

pub fn start(
    server_dir: &Path,
    env: &[(&str, &str)],
    config_file: &Path,
    museum_bin: &Path,
    db: &Postgres,
    object_store_endpoint: &str,
    mut next_port: impl FnMut() -> TestResult<u16>,
) -> TestResult<(ChildProcess, u16)> {
    require_go()?;
    build_museum(server_dir, museum_bin)?;

    let mut command = Command::new(museum_bin);
    command
        .current_dir(server_dir)
        .env("ENTE_CREDENTIALS_FILE", config_file)
        .env("ENTE_S3_ARE_LOCAL_BUCKETS", "true")
        .env("ENTE_S3_B2_EU_CEN_KEY", "changeme")
        .env("ENTE_S3_B2_EU_CEN_SECRET", "changeme1234")
        .env("ENTE_S3_B2_EU_CEN_ENDPOINT", object_store_endpoint)
        .env("ENTE_S3_B2_EU_CEN_REGION", "eu-central-2")
        .env("ENTE_S3_B2_EU_CEN_BUCKET", "b2-eu-cen")
        .env("ENTE_SPACE_ASSETS_PRIMARYBUCKET", "b2-eu-cen")
        .env("ENTE_DB_HOST", db.host())
        .env("ENTE_DB_PORT", db.port().to_string())
        .env("ENTE_DB_NAME", db.database())
        .env("ENTE_DB_USER", db.username())
        .env("ENTE_DB_PASSWORD", db.password())
        .env("ENTE_DB_SSLMODE", "disable")
        .env(
            "ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_SUFFIX",
            HARDCODED_OTT_EMAIL_SUFFIX,
        )
        .env(
            "ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_VALUE",
            HARDCODED_OTT,
        )
        .env("ENTE_JOBS_CRON_SKIP", "true")
        .envs(env.iter().copied());

    let log_dir = config_file.with_file_name("logs");
    let mut attempts = 0;
    loop {
        attempts += 1;
        let port = next_port()?;
        let instance = Uuid::new_v4().to_string();
        command
            .env("ENTE_HTTP_PORT", port.to_string())
            .env("GIT_COMMIT", &instance);
        let mut museum = ChildProcess::spawn("museum", &mut command, &log_dir)?;
        match wait_for_museum(&mut museum, port, &instance)? {
            Startup::Ready => return Ok((museum, port)),
            Startup::PortTaken if attempts < PORT_ATTEMPTS => {
                eprintln!("Museum port {port} is taken, retrying on another port");
            }
            Startup::PortTaken => {
                return Err(format!(
                    "Museum port {port} is taken after {attempts} attempts\n{}",
                    museum.log_summary()
                )
                .into());
            }
        }
    }
}

pub fn write_config(path: &Path) -> TestResult {
    // Do not add config here: a local museum.yaml would clobber it. Use env
    // in `start` instead. This empty file masks any local credentials.yaml.
    fs::write(path, "")?;
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

fn wait_for_museum(process: &mut ChildProcess, port: u16, instance: &str) -> TestResult<Startup> {
    let listening = format!("starting server on port {port}");
    let bind_failed = format!(":{port}: bind: address already in use");
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        process.ensure_running()?;
        let log = process.log();
        match ping(port) {
            Some(response) if response.contains(instance) => return Ok(Startup::Ready),
            Some(_) if !log.contains(&listening) => return Ok(Startup::PortTaken),
            _ if log.contains(&bind_failed) => return Ok(Startup::PortTaken),
            _ => {}
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

fn ping(port: u16) -> Option<String> {
    let mut stream = TcpStream::connect((LOCAL_HOST, port)).ok()?;
    let mut response = Vec::new();
    let _ = stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .and_then(|()| {
            stream.write_all(b"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        })
        .and_then(|()| stream.read_to_end(&mut response));
    Some(String::from_utf8_lossy(&response).into_owned())
}
