mod api;
mod args;
mod login;
mod output;
mod vault;

use std::{
    io::{Read, Write},
    path::Path,
};

use anyhow::{Context, Result, bail};
use clap::Parser;
use ente_core::{b64, crypto::Key};
use ente_photos::collections;
use serde::de::DeserializeOwned;
use serde_json::json;
use zeroize::Zeroizing;

use args::{
    AccountCommand, AlbumCommand, Cli, Command, KeyCommand, PhotosCommand, Product, SessionCommand,
    VaultCommand,
};
use output::{AccountView, AlbumView};
use vault::{State, Vault};

#[tokio::main(flavor = "current_thread")]
async fn main() {
    if let Err(error) = run(Cli::parse()).await {
        eprintln!("Error: {error:#}");
        std::process::exit(1);
    }
}

async fn run(cli: Cli) -> Result<()> {
    let Cli { json, command } = cli;
    match command {
        Command::Photos {
            selector,
            command: PhotosCommand::Session(command),
        } => session(Product::Photos, command, selector.account.as_deref(), json).await,
        Command::Locker { selector, command } => {
            session(Product::Locker, command, selector.account.as_deref(), json).await
        }
        Command::Auth { selector, command } => {
            session(Product::Auth, command, selector.account.as_deref(), json).await
        }
        Command::Photos {
            selector,
            command:
                PhotosCommand::Album {
                    command: AlbumCommand::List,
                },
        } => album_list(selector.account.as_deref(), json).await,
        Command::Accounts { command } => account_command(command, json).await,
        Command::Vault {
            command:
                VaultCommand::Key {
                    command: KeyCommand::Generate,
                },
        } => vault_key(json),
    }
}

fn vault_key(json_output: bool) -> Result<()> {
    let key = Zeroizing::new(b64::encode(Key::generate().as_bytes()));
    if json_output {
        output::json(&json!({ "key": key.as_str() }))
    } else {
        writeln!(std::io::stdout(), "{}", key.as_str()).map_err(Into::into)
    }
}

async fn album_list(selected: Option<&str>, json_output: bool) -> Result<()> {
    let state = State::load()?;
    let account = &state.accounts[state.resolve(selected)?];
    let session = api::session(account, Product::Photos)?;
    let albums = collections::list(&session)
        .await?
        .into_iter()
        .map(AlbumView::try_from)
        .collect::<Result<Vec<_>>>()?;
    if json_output {
        output::json(&albums)
    } else {
        output::albums(&albums)
    }
}

async fn session(
    product: Product,
    command: SessionCommand,
    selected: Option<&str>,
    json_output: bool,
) -> Result<()> {
    match command {
        SessionCommand::Api(args) => {
            let state = State::load()?;
            let index = state.resolve(selected)?;
            api::raw(&state.accounts[index], product, args).await
        }
        SessionCommand::Login(args) => {
            let (state, index) = login::login(product, args, selected).await?;
            let account = AccountView::new(&state.accounts[index], state.selected);
            if json_output {
                output::json(&json!({ "account": account, "product": product }))
            } else {
                output::account(&account)
            }
        }
        SessionCommand::Logout => {
            let mut vault = Vault::open()?;
            let index = vault.state.resolve(selected)?;
            let name = vault.state.accounts[index].name.clone();
            api::logout(&vault.state.accounts[index], product).await?;
            vault.state.accounts[index].sessions.remove(&product);
            if vault.state.accounts[index].sessions.is_empty() {
                remove_account(&mut vault.state, index);
            }
            vault.save()?;
            drop(vault);
            output::action(
                json_output,
                &json!({ "account": name, "product": product, "loggedOut": true }),
                &format!("Logged out of {} for {:?}.", product.display_name(), name),
            )
        }
    }
}

async fn account_command(command: AccountCommand, json_output: bool) -> Result<()> {
    match command {
        AccountCommand::List => {
            let state = State::load()?;
            let accounts: Vec<_> = state
                .accounts
                .iter()
                .map(|a| AccountView::new(a, state.selected))
                .collect();
            if json_output {
                output::json(&accounts)
            } else {
                output::accounts(&accounts)
            }
        }
        AccountCommand::View { name } => {
            let state = State::load()?;
            let account = AccountView::new(&state.accounts[state.named(&name)?], state.selected);
            if json_output {
                output::json(&account)
            } else {
                output::account(&account)
            }
        }
        AccountCommand::Switch { name } => {
            let mut vault = Vault::open()?;
            let state = &mut vault.state;
            let index = state.named(&name)?;
            let selected = Some(state.accounts[index].storage_id);
            if state.selected != selected {
                state.selected = selected;
                vault.save()?;
            }
            output_account(vault.into_state(), index, json_output)
        }
        AccountCommand::Rename { name, new_name } => {
            let mut vault = Vault::open()?;
            let state = &mut vault.state;
            let index = state.named(&name)?;
            if name != new_name {
                state.check_name(&new_name)?;
                state.accounts[index].name = new_name;
                vault.save()?;
            }
            output_account(vault.into_state(), index, json_output)
        }
        AccountCommand::Logout { name, local } => {
            let mut vault = Vault::open()?;
            let index = vault.state.named(&name)?;
            let products = vault.state.accounts[index]
                .sessions
                .keys()
                .copied()
                .collect::<Vec<_>>();
            if !local {
                for product in &products {
                    if let Err(error) = api::logout(&vault.state.accounts[index], *product).await {
                        if vault.state.accounts[index].sessions.len() < products.len() {
                            vault.save()?;
                        }
                        let remaining = vault.state.accounts[index]
                            .sessions
                            .keys()
                            .copied()
                            .collect::<Vec<_>>();
                        bail!(
                            "cannot log out of {} for {name:?}: {error:#}. Still logged in: {}. Retry when the server is reachable, or use --local to forget the account on this device.",
                            product.display_name(),
                            product_names(&remaining),
                        );
                    }
                    vault.state.accounts[index].sessions.remove(product);
                }
            }
            remove_account(&mut vault.state, index);
            vault.save()?;
            drop(vault);
            let message = if local && !products.is_empty() {
                format!(
                    "Logged out of {name:?} on this device only. Still logged in on the server: {}.",
                    product_names(&products)
                )
            } else if products.is_empty() {
                format!("Removed account {name:?} from this device.")
            } else {
                format!("Logged out of {} for {name:?}.", product_names(&products))
            };
            output::action(
                json_output,
                &json!({
                    "account": name,
                    "products": products,
                    "sessions": if local { "active" } else { "revoked" },
                }),
                &message,
            )
        }
    }
}

fn remove_account(state: &mut State, index: usize) {
    let storage_id = state.accounts.remove(index).storage_id;
    if state.selected == Some(storage_id) {
        state.selected = None;
    }
}

fn product_names(products: &[Product]) -> String {
    let names = products
        .iter()
        .map(|product| product.display_name())
        .collect::<Vec<_>>();
    match names.as_slice() {
        [] => String::new(),
        [name] => (*name).to_owned(),
        [first, second] => format!("{first} and {second}"),
        [first, middle @ .., last] => {
            format!("{first}, {}, and {last}", middle.join(", "))
        }
    }
}

fn output_account(state: State, index: usize, json_output: bool) -> Result<()> {
    let account = AccountView::new(&state.accounts[index], state.selected);
    if json_output {
        output::json(&account)
    } else {
        output::account(&account)
    }
}

fn read_input(path: &Path) -> Result<Zeroizing<Vec<u8>>> {
    let mut bytes = Zeroizing::new(Vec::new());
    if path == Path::new("-") {
        std::io::stdin().read_to_end(&mut bytes)?;
    } else {
        std::fs::File::open(path)
            .with_context(|| format!("cannot open {}", path.display()))?
            .read_to_end(&mut bytes)?;
    }
    Ok(bytes)
}

fn parse_json<T: DeserializeOwned>(bytes: &[u8]) -> Result<T> {
    serde_json::from_slice(bytes).map_err(|error| {
        anyhow::anyhow!(
            "invalid JSON at line {}, column {}",
            error.line(),
            error.column()
        )
    })
}
