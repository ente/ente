#![cfg(feature = "museum")]

#[expect(
    dead_code,
    reason = "Sync tests use only part of the shared CLI helpers"
)]
mod support;

use ente_test_support::HARDCODED_OTT;
use support::{Museum, TestResult};

#[test]
fn sync() -> TestResult {
    Museum::run(|museum| {
        let export_dir = museum.temp_dir().join("export");
        std::fs::create_dir_all(&export_dir)?;

        for command in ["create", "add"] {
            let cli = support::cli_session(museum, command)?;
            cli.run_ok(&[
                "account",
                command,
                "--email",
                "sync-test@example.org",
                "--password",
                "sync-test-password",
                "--endpoint",
                museum.endpoint(),
                "--export-dir",
                export_dir.to_str().unwrap(),
                "--otp",
                HARDCODED_OTT,
            ])?;

            let output = cli.run_ok(&["export"])?;
            assert!(
                output.contains("Sync completed"),
                "export did not sync: {output}"
            );
        }

        Ok(())
    })
}
