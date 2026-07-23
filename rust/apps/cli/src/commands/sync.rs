use crate::Result;
use crate::api::AppClient;
use crate::api::methods::ApiMethods;
use crate::models::{account::Account, metadata::FileMetadata};
use crate::storage::Storage;
use crate::sync::{SyncEngine, SyncStats, download::DownloadManager};
use base64::Engine;
use ente_core::crypto;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub async fn run_sync(
    account_email: Option<String>,
    metadata_only: bool,
    full_sync: bool,
) -> Result<()> {
    // Initialize crypto
    // Open database
    let config_dir = crate::utils::get_cli_config_dir()?;
    let db_path = config_dir.join("ente.db");
    let storage = Storage::new(&db_path)?;

    // Get accounts to sync
    let accounts = if let Some(email) = account_email {
        // Sync specific account
        let all_accounts = storage.accounts().list()?;
        let matching: Vec<Account> = all_accounts
            .into_iter()
            .filter(|a| a.email == email)
            .collect();

        if matching.is_empty() {
            return Err(crate::Error::NotFound(format!(
                "Account not found: {email}"
            )));
        }
        matching
    } else {
        // Sync all accounts
        storage.accounts().list()?
    };

    if accounts.is_empty() {
        println!("No accounts configured. Use 'ente-rs account add' first.");
        return Ok(());
    }

    // Sync each account
    for account in accounts {
        println!("\n=== Syncing account: {} ===", account.email);

        if let Err(e) = sync_account(&storage, &account, metadata_only, full_sync).await {
            log::error!("Failed to sync account {}: {}", account.email, e);
            println!("❌ Sync failed: {e}");
        } else {
            println!("✅ Sync completed successfully!");
        }
    }

    Ok(())
}

async fn sync_account(
    storage: &Storage,
    account: &Account,
    metadata_only: bool,
    full_sync: bool,
) -> Result<()> {
    // Get stored secrets
    let secrets = storage
        .accounts()
        .get_secrets(account.user_id, account.app)?
        .ok_or_else(|| crate::Error::NotFound("Account secrets not found".into()))?;

    // Create API client with account's endpoint
    let api_client = AppClient::new(Some(account.endpoint.clone()), account.app)?;

    // Store token for this account
    let token = base64::engine::general_purpose::URL_SAFE.encode(&secrets.token);
    api_client.set_token(&token);

    // Clear sync state if full sync requested
    if full_sync {
        println!("Performing full sync (clearing existing sync state)...");
        storage.sync().clear_sync_state(account.user_id)?;
    }

    // Create sync engine (need to create new instances for ownership)
    let db_path = storage
        .db_path()
        .ok_or_else(|| crate::Error::Generic("Database path not available".into()))?;

    // Create API client for sync engine
    let sync_api_client = AppClient::new(Some(account.endpoint.clone()), account.app)?;
    sync_api_client.set_token(&token);

    let sync_storage = Storage::new(db_path)?;
    let sync_engine = SyncEngine::new(sync_api_client, sync_storage, account.clone());

    // Run sync
    println!("Fetching collections and files...");
    let stats = sync_engine.sync().await?;

    // Display sync statistics
    display_sync_stats(&stats);

    // Download files if not metadata-only
    if !metadata_only {
        // Get pending downloads
        let pending_files = storage.sync().get_pending_downloads(account.user_id)?;

        if !pending_files.is_empty() {
            println!("\n📥 Found {} files to download", pending_files.len());

            // Get collections to decrypt collection keys
            // Need to fetch from API to get the api::models::Collection type with encrypted_key
            let api = ApiMethods::new(&api_client);
            let api_collections = api.get_collections(0).await?;

            // Decrypt collection keys
            let collection_keys = decrypt_collection_keys(
                &api_collections,
                &secrets.master_key,
                &secrets.secret_key,
            )?;

            // Create download manager
            // Create a new API client for the download manager
            let download_api_client =
                AppClient::new(Some(account.endpoint.clone()), account.app)?;
            download_api_client.set_token(&token);

            let mut download_manager = DownloadManager::new(download_api_client)?;
            download_manager.set_collection_keys(collection_keys);

            // Determine export directory
            let export_dir = if let Some(ref dir) = account.export_dir {
                PathBuf::from(dir)
            } else {
                std::env::current_dir()?.join("ente-export")
            };

            // Prepare download tasks with proper paths
            let download_tasks = prepare_download_tasks(
                &pending_files,
                &export_dir,
                &api_collections,
                &download_manager,
            )
            .await?;

            // First, mark files that already exist as synced
            let mut already_synced = 0;
            let mut to_download = Vec::new();

            for (file, path) in download_tasks {
                if path.exists() {
                    // File already exists, mark it as synced in database
                    storage
                        .sync()
                        .mark_file_synced(file.id, Some(path.to_str().unwrap_or("")))?;
                    already_synced += 1;
                } else {
                    to_download.push((file, path));
                }
            }

            if already_synced > 0 {
                log::info!("Marked {already_synced} already existing files as synced");
            }

            if !to_download.is_empty() {
                println!("📥 Downloading {} new files", to_download.len());

                // Download files with progress bar
                let download_stats = download_manager.download_files(to_download).await?;

                // Update local paths in database for newly downloaded files
                for (file, path) in &download_stats.successful_downloads {
                    storage
                        .sync()
                        .mark_file_synced(file.id, Some(path.to_str().unwrap_or("")))?;
                }

                println!(
                    "\n✅ Downloaded {} files successfully",
                    download_stats.successful
                );
                if download_stats.failed > 0 {
                    println!("❌ Failed to download {} files", download_stats.failed);
                }
            } else {
                println!("\n✨ All files are already downloaded");
            }
        } else {
            println!("\n✨ All files are already downloaded");
        }
    } else {
        println!("\n📋 Metadata-only sync completed (skipping file downloads)");
    }

    Ok(())
}

fn display_sync_stats(stats: &SyncStats) {
    println!("\n📊 Sync Statistics:");
    println!("┌─────────────────────────────────────┐");
    println!("│ Collections:                        │");
    println!(
        "│   Total: {:5}                      │",
        stats.collections.total
    );
    println!(
        "│   New:   {:5}                      │",
        stats.collections.new
    );
    println!(
        "│   Updated: {:5}                    │",
        stats.collections.updated
    );
    println!("├─────────────────────────────────────┤");
    println!("│ Files:                              │");
    println!("│   Total: {:5}                      │", stats.files.total);
    println!("│   New:   {:5}                      │", stats.files.new);
    println!(
        "│   Updated: {:5}                    │",
        stats.files.updated
    );
    println!("└─────────────────────────────────────┘");
}

/// Decrypt collection keys for file decryption
fn decrypt_collection_keys(
    collections: &[crate::api::models::Collection],
    master_key: &[u8],
    _secret_key: &[u8],
) -> Result<HashMap<i64, Vec<u8>>> {
    use base64::engine::general_purpose::STANDARD as BASE64;

    let mut keys = HashMap::new();

    for collection in collections {
        if collection.is_deleted {
            continue;
        }

        // Decrypt collection key
        let encrypted_bytes = BASE64.decode(&collection.encrypted_key)?;
        let nonce_bytes = BASE64.decode(&collection.key_decryption_nonce)?;

        let decrypted = crypto::Nonce::try_from_slice(&nonce_bytes).and_then(|nonce| {
            crypto::secretbox::decrypt(
                &encrypted_bytes,
                &nonce,
                &crypto::Key::try_from_slice(master_key)?,
            )
        });
        match decrypted {
            Ok(key) => {
                keys.insert(collection.id, key);
            }
            Err(e) => {
                log::warn!(
                    "Failed to decrypt key for collection {}: {}",
                    collection.id,
                    e
                );
            }
        }
    }

    Ok(keys)
}

/// Sanitize a filename for the filesystem
fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            '\0' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect::<String>()
        .trim()
        .to_string()
}

/// Prepare download tasks with proper file paths
async fn prepare_download_tasks(
    files: &[crate::models::file::RemoteFile],
    export_dir: &Path,
    collections: &[crate::api::models::Collection],
    download_manager: &DownloadManager,
) -> Result<Vec<(crate::models::file::RemoteFile, PathBuf)>> {
    use base64::engine::general_purpose::STANDARD as BASE64;
    use chrono::{TimeZone, Utc};

    let mut tasks = Vec::new();
    let mut seen_hashes: HashMap<String, PathBuf> = HashMap::new();

    // Create collection lookup map
    let collection_map: HashMap<i64, &crate::api::models::Collection> =
        collections.iter().map(|c| (c.id, c)).collect();

    for file in files {
        // Get collection for this file
        let collection = collection_map.get(&file.collection_id);

        // Try to decrypt metadata to get original filename
        let (metadata, pub_magic_metadata) = if let Some(col_key) =
            download_manager.collection_keys.get(&file.collection_id)
        {
            // Decrypt file key first
            let file_key = {
                let key_bytes = BASE64.decode(&file.encrypted_key)?;
                let nonce = BASE64.decode(&file.key_decryption_nonce)?;
                crypto::secretbox::decrypt(
                    &key_bytes,
                    &crypto::Nonce::try_from_slice(&nonce)?,
                    &crypto::Key::try_from_slice(col_key)?,
                )?
            };

            // Decrypt regular metadata
            let regular_meta = if !file.metadata.encrypted_data.is_empty() {
                if !file.metadata.decryption_header.is_empty() {
                    let encrypted_bytes = BASE64.decode(&file.metadata.encrypted_data)?;
                    let header_bytes = BASE64.decode(&file.metadata.decryption_header)?;

                    let decrypted =
                        crypto::Header::try_from_slice(&header_bytes).and_then(|header| {
                            crypto::blob::decrypt(
                                &encrypted_bytes,
                                &header,
                                &crypto::Key::try_from_slice(&file_key)?,
                            )
                        });
                    match decrypted {
                        Ok(decrypted) => serde_json::from_slice::<FileMetadata>(&decrypted).ok(),
                        Err(e) => {
                            log::warn!("Failed to decrypt metadata for file {}: {}", file.id, e);
                            None
                        }
                    }
                } else {
                    None
                }
            } else {
                None
            };

            // Decrypt public magic metadata if available
            let pub_meta = if let Some(ref magic) = file.pub_magic_metadata {
                if !magic.data.is_empty() && !magic.header.is_empty() {
                    let encrypted_bytes = BASE64.decode(&magic.data)?;
                    let header_bytes = BASE64.decode(&magic.header)?;

                    let decrypted =
                        crypto::Header::try_from_slice(&header_bytes).and_then(|header| {
                            crypto::blob::decrypt(
                                &encrypted_bytes,
                                &header,
                                &crypto::Key::try_from_slice(&file_key)?,
                            )
                        });
                    match decrypted {
                        Ok(decrypted) => {
                            serde_json::from_slice::<serde_json::Value>(&decrypted).ok()
                        }
                        Err(e) => {
                            log::debug!(
                                "Failed to decrypt public magic metadata for file {}: {}",
                                file.id,
                                e
                            );
                            None
                        }
                    }
                } else {
                    None
                }
            } else {
                None
            };

            (regular_meta, pub_meta)
        } else {
            (None, None)
        };

        // Generate export path
        let mut path = export_dir.to_path_buf();

        // Add date-based directory structure
        let datetime = Utc
            .timestamp_micros(file.updated_at)
            .single()
            .ok_or_else(|| crate::Error::Generic("Invalid timestamp".into()))?;

        let year = datetime.format("%Y").to_string();
        let month = datetime.format("%m-%B").to_string();

        path.push(year);
        path.push(month);

        // Add collection name if available
        if let Some(col) = collection
            && let Some(ref name) = col.name
            && !name.is_empty()
            && name != "Uncategorized"
        {
            let safe_name: String = name
                .chars()
                .map(|c| match c {
                    '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
                    c if c.is_control() => '_',
                    c => c,
                })
                .collect();
            path.push(safe_name.trim());
        }

        // Use filename from public magic metadata (edited name) or regular metadata
        let filename = {
            // First check for edited name in public magic metadata
            let base_name = if let Some(ref pub_meta) = pub_magic_metadata
                && let Some(edited_name) = pub_meta.get("editedName")
                && let Some(name_str) = edited_name.as_str()
                && !name_str.is_empty()
            {
                sanitize_filename(name_str)
            } else if let Some(ref meta) = metadata {
                // Fall back to original title from metadata
                if let Some(title) = meta.get_title() {
                    sanitize_filename(title)
                } else {
                    // Match Go CLI behavior: error if no title found
                    log::error!("File {} has no title in metadata", file.id);
                    continue; // Skip this file
                }
            } else {
                // Match Go CLI behavior: error if no metadata
                log::error!("File {} has no metadata", file.id);
                continue; // Skip this file
            };

            // For live photos, ensure .zip extension if not already present
            if let Some(ref meta) = metadata {
                if meta.is_live_photo() && !base_name.to_lowercase().ends_with(".zip") {
                    // Remove any existing extension and add .zip
                    if let Some(pos) = base_name.rfind('.') {
                        format!("{}.zip", &base_name[..pos])
                    } else {
                        format!("{}.zip", base_name)
                    }
                } else {
                    base_name
                }
            } else {
                base_name
            }
        };

        path.push(filename);

        // Check for deduplication by hash
        let content_hash = if let Some(ref meta) = metadata {
            match meta.get_file_type() {
                crate::models::metadata::FileType::Image => {
                    meta.image_hash.as_ref().or(meta.hash.as_ref())
                }
                crate::models::metadata::FileType::Video => {
                    meta.video_hash.as_ref().or(meta.hash.as_ref())
                }
                _ => meta.hash.as_ref(),
            }
        } else {
            None
        };

        // Skip if we've already seen this hash (duplicate)
        if let Some(hash) = content_hash {
            if let Some(existing_path) = seen_hashes.get(hash) {
                log::info!(
                    "Skipping duplicate file {} (same hash as {})",
                    file.id,
                    existing_path.display()
                );
                continue;
            }
            seen_hashes.insert(hash.clone(), path.clone());
        }

        tasks.push((file.clone(), path));
    }

    Ok(tasks)
}
