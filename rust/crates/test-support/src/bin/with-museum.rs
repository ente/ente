use std::process::ExitStatus;
#[cfg(unix)]
use std::time::Duration;

use ente_test_support::{Museum, TestResult};
use tokio::process::{Child, Command};

fn main() -> TestResult {
    let mut args = std::env::args_os().skip(1);
    let command = args.next().ok_or("expected a command to run")?;

    Museum::run(|museum| {
        eprintln!("Test Museum ready at {}", museum.endpoint());
        tokio::runtime::Runtime::new()?.block_on(async {
            let mut command = Command::new(command);
            command
                .args(args)
                .env("NEXT_PUBLIC_ENTE_ENDPOINT", museum.endpoint())
                .env(
                    "ENTE_TEST_EMAIL_SUFFIX",
                    ente_test_support::HARDCODED_OTT_EMAIL_SUFFIX,
                )
                .env("ENTE_TEST_EMAIL_CODE", ente_test_support::HARDCODED_OTT)
                .kill_on_drop(true);
            #[cfg(unix)]
            command.process_group(0);
            let mut child = command.spawn()?;

            let status = tokio::select! {
                status = child.wait() => status?,
                signal = interrupted() => {
                    signal?;
                    stop(&mut child).await?;
                    return Err("test command interrupted".into());
                }
            };
            check_status(status)
        })
    })
}

fn check_status(status: ExitStatus) -> TestResult {
    if status.success() {
        Ok(())
    } else {
        Err(format!("test command failed: {status}").into())
    }
}

async fn interrupted() -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{SignalKind, signal};
        let mut terminate = signal(SignalKind::terminate())?;
        tokio::select! {
            result = tokio::signal::ctrl_c() => result,
            _ = terminate.recv() => Ok(()),
        }
    }
    #[cfg(not(unix))]
    tokio::signal::ctrl_c().await
}

async fn stop(child: &mut Child) -> TestResult {
    #[cfg(unix)]
    if let Some(pid) = child.id() {
        let _ = Command::new("kill")
            .args(["-INT", "--", &format!("-{pid}")])
            .status()
            .await;
        if tokio::time::timeout(Duration::from_secs(20), child.wait())
            .await
            .is_err()
        {
            let _ = Command::new("kill")
                .args(["-KILL", "--", &format!("-{pid}")])
                .status()
                .await;
        }
    }
    if child.try_wait()?.is_none() {
        child.kill().await?;
    }
    Ok(())
}
