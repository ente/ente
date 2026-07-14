mod support;

use ente_test_support::HARDCODED_OTT;
use support::{Museum, TestResult};

#[test]
fn sync() -> TestResult {
    Museum::run(|museum| {
        let cli = support::cli_session(museum, "sync")?;
        let export_dir = museum.temp_dir().join("export");
        std::fs::create_dir_all(&export_dir)?;

        cli.run_ok(&[
            "account",
            "create",
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

        Ok(())
    })
}
