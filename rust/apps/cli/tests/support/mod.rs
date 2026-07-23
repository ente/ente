mod cli;

pub use cli::Cli;
pub use ente_test_support::{Museum, TestResult};

pub fn cli_session(museum: &Museum, scenario: &str) -> TestResult<Cli> {
    let config_dir = museum.temp_dir().join("cli").join(scenario);
    std::fs::create_dir_all(&config_dir)?;
    Ok(Cli::new(config_dir))
}
