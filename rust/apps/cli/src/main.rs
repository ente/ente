use clap::Parser;
use ente_rs::{
    Result,
    cli::{Cli, Commands},
    commands,
    storage::Storage,
};

#[tokio::main]
async fn main() {
    if let Err(e) = run().await {
        eprintln!("{}", ente_core::error::chain(&e));
        std::process::exit(1);
    }
}

async fn run() -> Result<()> {
    env_logger::init();

    let config_dir = ente_rs::utils::get_cli_config_dir()?;
    let db_path = config_dir.join("ente.db");
    let storage = Storage::new(&db_path)?;

    let cli = Cli::parse();

    match cli.command {
        Commands::Version => {
            println!("ente-rs version {}", ente_rs::cli::version::VERSION);
        }
        Commands::Account(account_cmd) => {
            commands::account::handle_account_command(account_cmd, &storage).await?;
        }
        Commands::Export(export_cmd) => {
            use ente_rs::models::filter::ExportFilter;

            let filter = ExportFilter {
                include_shared: export_cmd.shared,
                include_hidden: export_cmd.hidden,
                albums: export_cmd.albums,
                emails: export_cmd.emails,
            };

            commands::export::run_export(export_cmd.account, filter).await?;
        }
        Commands::Paste(paste_cmd) => {
            commands::paste::handle_paste_command(paste_cmd).await?;
        }
    }

    Ok(())
}
