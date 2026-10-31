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
    net::{LOCAL_HOST, free_port, retry_taken_port},
    postgres::Postgres,
    process::ChildProcess,
};

pub fn start(
    server_dir: &Path,
    env: &[(&str, &str)],
    config_file: &Path,
    museum_bin: &Path,
    db: &Postgres,
    object_store_endpoint: &str,
) -> TestResult<(ChildProcess, String)> {
    require_go()?;
    build_museum(server_dir, museum_bin)?;

    let instance_id = Uuid::new_v4().to_string();
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
        .env("GIT_COMMIT", &instance_id)
        .envs(env.iter().copied());

    retry_taken_port(|| {
        let port = free_port()?;
        command.env("ENTE_HTTP_PORT", port.to_string());
        let mut museum =
            ChildProcess::spawn("museum", &mut command, &config_file.with_file_name("logs"))?;
        let bound = wait_for_museum(&mut museum, port, &instance_id)?;
        Ok(bound.then(|| (museum, format!("http://{LOCAL_HOST}:{port}"))))
    })
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

fn wait_for_museum(process: &mut ChildProcess, port: u16, instance_id: &str) -> TestResult<bool> {
    let bind_failure = format!("listen tcp :{port}: bind: address already in use");
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        if process.log_contains(&bind_failure) {
            return Ok(false);
        }
        process.ensure_running()?;
        if ping(port, instance_id).unwrap_or(false) {
            return Ok(true);
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

fn ping(port: u16, instance_id: &str) -> TestResult<bool> {
    let Ok(mut stream) = TcpStream::connect((LOCAL_HOST, port)) else {
        return Ok(false);
    };
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.write_all(b"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")?;

    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    Ok(
        (response.starts_with("HTTP/1.1 200") || response.starts_with("HTTP/1.0 200"))
            && response.contains(instance_id),
    )
}
