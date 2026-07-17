use crate::Result;
use crate::api::AppClient;
use crate::api::methods::ApiMethods;
use crate::models::{
    account::Account,
    export_metadata::{AlbumMetadata, DiskFileMetadata},
    filter::ExportFilter,
    metadata::FileMetadata,
};
use crate::storage::Storage;
use crate::sync::SyncEngine;
use base64::Engine;
use ente_core::crypto;
use std::collections::HashMap;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::io::AsyncWriteExt;

/// Information about a file already on disk, loaded from metadata
#[derive(Debug, Clone)]
struct ExistingFile {
    /// Path to the actual file on disk
    file_path: PathBuf,
    /// Path to the metadata JSON file
    meta_path: PathBuf,
}

/// Load existing file metadata for a specific album
async fn load_album_metadata(
    export_path: &Path,
    album_name: &str,
) -> Result<HashMap<i64, ExistingFile>> {
    let mut existing_files = HashMap::new();

    let meta_dir = export_path.join(album_name).join(".meta");
    if !meta_dir.exists() {
        return Ok(existing_files);
    }

    let mut entries = match fs::read_dir(&meta_dir).await {
        Ok(entries) => entries,
        Err(e) => {
            log::warn!("Failed to read metadata directory {:?}: {}", meta_dir, e);
            return Ok(existing_files);
        }
    };

    while let Some(entry) = entries.next_entry().await? {
        let meta_path = entry.path();

        // Skip non-JSON files and album_meta.json
        if meta_path.extension().is_none_or(|ext| ext != "json") {
            continue;
        }

        if meta_path
            .file_name()
            .is_some_and(|name| name == "album_meta.json")
        {
            continue;
        }

        // Read and parse metadata file
        let json_content = match fs::read_to_string(&meta_path).await {
            Ok(content) => content,
            Err(e) => {
                log::warn!("Failed to read metadata file {:?}: {}", meta_path, e);
                continue;
            }
        };

        let disk_metadata: DiskFileMetadata = match serde_json::from_str(&json_content) {
            Ok(metadata) => metadata,
            Err(e) => {
                log::warn!("Failed to parse metadata file {:?}: {}", meta_path, e);
                continue;
            }
        };

        // Check if the actual file exists
        for filename in &disk_metadata.info.file_names {
            let file_path = export_path.join(album_name).join(filename);
            if file_path.exists() {
                existing_files.insert(
                    disk_metadata.info.id,
                    ExistingFile {
                        file_path,
                        meta_path: meta_path.clone(),
                    },
                );
                break; // Only need one existing file per ID
            }
        }
    }

    Ok(existing_files)
}

pub async fn run_export(account_email: Option<String>, filter: ExportFilter) -> Result<()> {
    // Initialize crypto
    // Open database
    let config_dir = crate::utils::get_cli_config_dir()?;
    let db_path = config_dir.join("ente.db");
    let storage = Storage::new(&db_path)?;

    // Get accounts to export
    let accounts = if let Some(email) = account_email {
        // Export specific account - try to find it with any app
        let all_accounts = storage.accounts().list()?;
        log::debug!("Found {} total accounts", all_accounts.len());
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
        // Export all accounts
        storage.accounts().list()?
    };

    if accounts.is_empty() {
        println!("No accounts configured. Use 'ente-rs account add' first.");
        return Ok(());
    }

    // Apply email filter at account level (matching Go CLI behavior)
    let accounts_to_export: Vec<Account> = if let Some(ref emails) = filter.emails {
        if emails.is_empty() {
            accounts
        } else {
            accounts
                .into_iter()
                .filter(|a| {
                    let should_export = emails
                        .iter()
                        .any(|e| e.eq_ignore_ascii_case(a.email.trim()));
                    if !should_export {
                        log::info!("Skip account {}: account is excluded by filter", a.email);
                    }
                    should_export
                })
                .collect()
        }
    } else {
        accounts
    };

    if accounts_to_export.is_empty() {
        println!("No accounts match the email filter.");
        return Ok(());
    }

    // Export each account
    let mut failures = 0;
    for account in accounts_to_export {
        println!("\n=== Exporting account: {} ===", account.email);

        // First sync the account (like Go implementation does)
        println!("Syncing account data...");
        if let Err(e) = sync_account_before_export(&storage, &account).await {
            log::error!("Failed to sync account {}: {}", account.email, e);
            println!("❌ Sync failed: {e}");
            failures += 1;
            continue;
        }
        println!("✅ Sync completed!");

        if let Err(e) = export_account(&storage, &account, &filter).await {
            log::error!("Failed to export account {}: {}", account.email, e);
            println!("❌ Export failed: {e}");
            failures += 1;
        } else {
            println!("✅ Export completed successfully!");
        }
    }

    if failures > 0 {
        return Err(crate::Error::Generic(format!(
            "export failed for {failures} account(s)"
        )));
    }
    Ok(())
}

async fn sync_account_before_export(storage: &Storage, account: &Account) -> Result<()> {
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

    // Get the database path to create a new Storage instance
    let db_path = storage
        .db_path()
        .ok_or_else(|| crate::Error::Generic("Database path not available".into()))?;

    // Create new Storage instance for sync engine (needed for ownership)
    let sync_storage = Storage::new(db_path)?;

    // Create sync engine
    let sync_engine = SyncEngine::new(api_client, sync_storage, account.clone());

    // Run sync for this account
    let stats = sync_engine.sync().await?;

    log::info!(
        "Sync completed: {} new collections, {} new files",
        stats.collections.new,
        stats.files.new
    );

    Ok(())
}

async fn export_account(storage: &Storage, account: &Account, filter: &ExportFilter) -> Result<()> {
    // Get export directory
    let export_dir = account
        .export_dir
        .as_ref()
        .ok_or_else(|| crate::Error::InvalidInput("No export directory configured".into()))?;
    let export_path = Path::new(export_dir);

    println!("Export directory: {export_dir}");

    // Create export directory if needed
    fs::create_dir_all(export_path).await?;

    // Track exported hashes for deduplication within this export session
    let mut exported_hashes: HashMap<String, PathBuf> = HashMap::new();

    // Track albums that have metadata written
    let mut albums_with_metadata: HashMap<String, bool> = HashMap::new();

    // Track file indices per album for unique metadata filenames
    let mut album_file_indices: HashMap<String, usize> = HashMap::new();

    // Track existing files per album (loaded on demand)
    let mut album_existing_files: HashMap<String, HashMap<i64, ExistingFile>> = HashMap::new();

    // Get stored secrets
    let secrets = storage
        .accounts()
        .get_secrets(account.user_id, account.app)?
        .ok_or_else(|| crate::Error::NotFound("Account secrets not found".into()))?;

    // Create API client with account's endpoint
    let api_client = AppClient::new(Some(account.endpoint.clone()), account.app)?;

    // Store token for this account
    // Token is stored as raw bytes from sealed_box_open
    // The Go CLI encodes it as base64 URL-encoded string WITH padding for the API
    let token = base64::engine::general_purpose::URL_SAFE.encode(&secrets.token);
    api_client.set_token(&token);

    let api = ApiMethods::new(&api_client);

    // Master key is already raw bytes, no need to decode
    let master_key = &secrets.master_key;

    // We'll also need the secret key and public key for decrypting shared collection keys
    let secret_key = &secrets.secret_key;
    let public_key = &secrets.public_key;

    // Step 1: Fetch all collections and create a map of collection IDs to collections
    println!("\nFetching collections...");
    let collections = api.get_collections(0).await?;
    println!("Found {} collections", collections.len());

    // Create collection ID to collection map and decrypt collection keys
    let mut collection_map: HashMap<i64, (crate::api::models::Collection, Vec<u8>)> =
        HashMap::new();

    for mut collection in collections {
        // Skip deleted collections
        if collection.is_deleted {
            continue;
        }

        // Log collection processing (with better handling of empty owner email)
        let owner_info = if collection.owner.email.is_empty() {
            format!("owner_id={}", collection.owner.id)
        } else {
            format!("owner={}", collection.owner.email)
        };

        log::debug!(
            "Processing collection {}: name={:?}, encrypted_name={:?}, {}",
            collection.id,
            collection.name,
            collection.encrypted_name,
            owner_info
        );

        // Decrypt collection key
        // Collections can be encrypted in two ways:
        // 1. Owned collections: Use secret_box with master key and nonce
        // 2. Shared collections: Use sealed_box with public key cryptography
        let collection_key = if let Some(ref key_nonce) = collection.key_decryption_nonce {
            // Owned collection - decrypt with master key
            match decrypt_collection_key(
                &collection.encrypted_key,
                key_nonce,
                master_key,
                secret_key,
            ) {
                Ok(key) => key,
                Err(e) => {
                    log::error!(
                        "Failed to decrypt owned collection key for {}: {e}",
                        collection.id
                    );
                    continue;
                }
            }
        } else {
            // Shared collection - check if it's shared with us (not by us)
            if collection.owner.id == account.user_id {
                log::warn!(
                    "Collection {} owned by current user but missing key_decryption_nonce, skipping",
                    collection.id
                );
                continue;
            }

            // This is a collection shared with us - decrypt with sealed_box
            log::info!(
                "Collection {} is shared from user {}, using sealed_box decryption",
                collection.id,
                collection.owner.id
            );

            match decrypt_shared_collection_key(&collection.encrypted_key, public_key, secret_key) {
                Ok(key) => key,
                Err(e) => {
                    log::error!(
                        "Failed to decrypt shared collection key for {}: {e}",
                        collection.id
                    );
                    continue;
                }
            }
        };

        // Decrypt collection name if it's encrypted
        if collection.name.as_ref().is_none_or(|n| n.is_empty())
            && let Some(ref encrypted_name) = collection.encrypted_name
            && let Some(ref nonce) = collection.name_decryption_nonce
        {
            match decrypt_collection_name(encrypted_name, nonce, &collection_key) {
                Ok(name) => {
                    log::debug!("Decrypted collection {} name: {}", collection.id, name);
                    collection.name = Some(name);
                }
                Err(e) => {
                    log::warn!("Failed to decrypt collection {} name: {}", collection.id, e);
                }
            }
        }

        collection_map.insert(collection.id, (collection, collection_key));
    }

    // Step 2: Fetch all files from all collections (like Go CLI does)
    println!("\nFetching all files...");
    let mut all_files = Vec::new();

    // Iterate through each collection and fetch its files
    for collection_id in collection_map.keys() {
        let mut has_more = true;
        let mut since_time = 0i64;

        while has_more {
            let (files, more) = api.get_collection_files(*collection_id, since_time).await?;
            has_more = more;

            if files.is_empty() {
                break;
            }

            // Update since_time for next batch
            for file in &files {
                if file.updation_time > since_time {
                    since_time = file.updation_time;
                }
            }

            all_files.extend(files);
        }
    }

    println!("Found {} total files", all_files.len());

    // Step 3: Process each file and export to the correct album folder
    let mut total_files = 0;
    let mut exported_files = 0;
    let mut skipped_files = 0;
    let mut deleted_files = 0;

    for file in all_files {
        // Skip deleted files
        if file.is_deleted {
            deleted_files += 1;
            continue;
        }

        // Count non-deleted files
        total_files += 1;

        // Find the collection this file belongs to
        // Files have a collection_id field that indicates which album they belong to
        let collection_info = match collection_map.get(&file.collection_id) {
            Some(info) => info,
            None => {
                log::debug!(
                    "File {} belongs to unknown/deleted collection {}",
                    file.id,
                    file.collection_id
                );
                continue;
            }
        };

        let (collection, collection_key) = collection_info;

        // Apply collection filters
        let collection_name = collection.name.as_deref().unwrap_or("Unnamed");

        // Determine if collection is shared
        let is_shared = collection.sharees.as_ref().is_some_and(|s| !s.is_empty())
            || collection.shared_magic_metadata.is_some()
            || collection.owner.id != account.user_id;

        // Determine if collection is hidden from metadata
        let is_hidden = check_collection_visibility(collection, collection_key);

        // Log collection visibility for debugging
        log::debug!(
            "Collection {}: name={:?}, is_hidden={}, is_shared={}",
            collection.id,
            collection.name,
            is_hidden,
            is_shared
        );

        if !filter.should_include_collection(collection_name, is_shared, is_hidden) {
            log::debug!("Skipping file in filtered collection: {}", collection_name);
            continue;
        }

        // Decrypt the file key using the collection key
        let file_key = match decrypt_file_key(
            &file.encrypted_key,
            &file.key_decryption_nonce,
            collection_key,
        ) {
            Ok(key) => key,
            Err(e) => {
                log::error!("Failed to decrypt key for file {}: {}", file.id, e);
                continue;
            }
        };

        // Decrypt metadata to get original filename and hash
        let metadata = match decrypt_file_metadata(&file, &file_key) {
            Ok(meta) => meta,
            Err(e) => {
                log::warn!("Failed to decrypt metadata for file {}: {}", file.id, e);
                None
            }
        };

        // Decrypt public magic metadata to check for edited name
        let pub_magic_metadata = if let Some(pub_magic_metadata) = file.pub_magic_metadata.as_ref()
        {
            match decrypt_magic_metadata(pub_magic_metadata, &file_key) {
                Ok(meta) => meta,
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
        };

        // Check for deduplication by hash
        let content_hash = if let Some(ref meta) = metadata {
            let hash = match meta.get_file_type() {
                crate::models::metadata::FileType::Image => {
                    meta.image_hash.as_ref().or(meta.hash.as_ref())
                }
                crate::models::metadata::FileType::Video => {
                    meta.video_hash.as_ref().or(meta.hash.as_ref())
                }
                _ => meta.hash.as_ref(),
            };
            if let Some(h) = hash {
                log::debug!("File {} has hash: {}", file.id, h);
            } else {
                log::debug!("File {} has no hash in metadata", file.id);
            }
            hash
        } else {
            log::debug!("File {} has no metadata", file.id);
            None
        };

        // Generate export path with original filename from metadata
        let file_path = generate_export_path(
            export_path,
            &file,
            Some(collection),
            metadata.as_ref(),
            pub_magic_metadata.as_ref(),
        )?;

        // Determine album folder
        let album_folder = if let Some(ref name) = collection.name
            && !name.is_empty()
        {
            sanitize_album_name(name)
        } else {
            "Uncategorized".to_string()
        };

        // Load existing files for this album if not already loaded
        if !album_existing_files.contains_key(&album_folder) {
            let existing = load_album_metadata(export_path, &album_folder).await?;
            log::debug!(
                "Loaded {} existing files for album {}",
                existing.len(),
                album_folder
            );
            album_existing_files.insert(album_folder.clone(), existing);
        }

        // Check if this file already exists in the album by ID (for rename detection)
        let existing_files = album_existing_files.get_mut(&album_folder).unwrap();
        if let Some(existing) = existing_files.remove(&file.id) {
            if existing.file_path == file_path {
                // File exists at the same path - no rename needed
                log::debug!(
                    "File {} already exists at correct path: {:?}",
                    file.id,
                    file_path
                );
                skipped_files += 1;

                // Add to hash map even for existing files to prevent duplicates
                if let Some(hash) = content_hash {
                    exported_hashes.insert(hash.clone(), file_path.clone());
                }
                continue;
            } else {
                // File exists at different path - it was renamed
                log::info!(
                    "File {} renamed from {:?} to {:?}",
                    file.id,
                    existing.file_path,
                    file_path
                );

                // Remove old file
                if existing.file_path.exists() {
                    log::debug!("Removing old file: {:?}", existing.file_path);
                    fs::remove_file(&existing.file_path).await.ok();
                }

                // For live photos, also remove the MOV component
                let is_live_photo = metadata
                    .as_ref()
                    .map(|m| m.is_live_photo())
                    .unwrap_or(false);

                if is_live_photo {
                    // Try to remove old MOV file
                    // The MOV file has the same base name but with .MOV extension
                    let old_mov_path = existing.file_path.with_extension("MOV");
                    if old_mov_path.exists() {
                        log::debug!("Removing old live photo MOV component: {:?}", old_mov_path);
                        fs::remove_file(&old_mov_path).await.ok();
                    }

                    // Also try lowercase .mov
                    let old_mov_path_lower = existing.file_path.with_extension("mov");
                    if old_mov_path_lower.exists() && old_mov_path_lower != old_mov_path {
                        log::debug!(
                            "Removing old live photo mov component: {:?}",
                            old_mov_path_lower
                        );
                        fs::remove_file(&old_mov_path_lower).await.ok();
                    }
                }

                // Remove old metadata
                if existing.meta_path.exists() {
                    log::debug!("Removing old metadata: {:?}", existing.meta_path);
                    fs::remove_file(&existing.meta_path).await.ok();
                }

                // Continue to re-export with new name
            }
        } else if file_path.exists() {
            // File exists but not tracked by ID (old export or hash collision)
            log::debug!("File already exists (not tracked by ID): {file_path:?}");
            skipped_files += 1;

            // Add to hash map even for existing files to prevent duplicates
            if let Some(hash) = content_hash {
                exported_hashes.insert(hash.clone(), file_path.clone());
            }
            continue;
        }

        // Check if we've already downloaded this file content (by hash) in another album
        // If so, we can copy it instead of downloading again
        let need_download = if let Some(hash) = content_hash
            && let Some(existing_path) = exported_hashes.get(hash)
            && existing_path != &file_path
        {
            log::info!(
                "File {} has same content as {}, copying instead of downloading",
                file.id,
                existing_path.display()
            );

            // Copy the existing file to the new location
            if let Some(parent) = file_path.parent() {
                fs::create_dir_all(parent).await?;
            }
            fs::copy(existing_path, &file_path).await?;

            // For live photos, also copy the MOV component
            let is_live_photo = metadata
                .as_ref()
                .map(|m| m.is_live_photo())
                .unwrap_or(false);

            if is_live_photo {
                // Try to copy MOV file
                let existing_mov = existing_path.with_extension("MOV");
                let new_mov = file_path.with_extension("MOV");
                if existing_mov.exists() {
                    log::debug!(
                        "Copying live photo MOV component from {:?} to {:?}",
                        existing_mov,
                        new_mov
                    );
                    fs::copy(&existing_mov, &new_mov).await.ok();
                } else {
                    // Try lowercase .mov
                    let existing_mov_lower = existing_path.with_extension("mov");
                    let new_mov_lower = file_path.with_extension("mov");
                    if existing_mov_lower.exists() {
                        log::debug!(
                            "Copying live photo mov component from {:?} to {:?}",
                            existing_mov_lower,
                            new_mov_lower
                        );
                        fs::copy(&existing_mov_lower, &new_mov_lower).await.ok();
                    }
                }
            }

            false
        } else {
            true
        };

        // Download and save file only if needed
        if need_download {
            log::debug!("Downloading file {} to {:?}", file.id, file_path);

            // Ensure directory exists
            if let Some(parent) = file_path.parent() {
                fs::create_dir_all(parent).await?;
            }

            // Download encrypted file
            let encrypted_data = api.download_file(file.id).await?;

            // The file nonce/header is stored separately in the API response
            let file_nonce = match base64::engine::general_purpose::STANDARD
                .decode(&file.file.decryption_header)
            {
                Ok(nonce) => nonce,
                Err(e) => {
                    log::error!("Failed to decode file nonce for file {}: {}", file.id, e);
                    continue;
                }
            };

            // Decrypt the file data using streaming XChaCha20-Poly1305
            // Use chunked decryption for large files
            let decrypt_result = crypto::Header::try_from_slice(&file_nonce).and_then(|header| {
                crypto::stream::decrypt_file_data(
                    &encrypted_data,
                    &header,
                    &crypto::Key::try_from_slice(&file_key)?,
                )
            });
            let decrypted = match decrypt_result {
                Ok(data) => data,
                Err(e) => {
                    log::error!("Failed to decrypt file {}: {}", file.id, e);
                    log::debug!(
                        "File size: {}, header length: {}",
                        encrypted_data.len(),
                        file_nonce.len()
                    );
                    continue;
                }
            };

            // Check if this is a live photo that needs extraction
            let is_live_photo = metadata
                .as_ref()
                .map(|m| m.is_live_photo())
                .unwrap_or(false);

            if is_live_photo {
                // Extract live photo components from ZIP
                if let Err(e) = extract_live_photo(&decrypted, &file_path).await {
                    log::error!("Failed to extract live photo {}: {}", file.id, e);
                    // Fall back to saving as ZIP
                    let mut file_handle = fs::File::create(&file_path).await?;
                    file_handle.write_all(&decrypted).await?;
                    file_handle.sync_all().await?;
                }
            } else {
                // Write regular file
                let mut file_handle = fs::File::create(&file_path).await?;
                file_handle.write_all(&decrypted).await?;
                file_handle.sync_all().await?;
            }
        }

        exported_files += 1;

        // Add hash to deduplication map
        if let Some(hash) = content_hash {
            exported_hashes.insert(hash.clone(), file_path.clone());
        }

        // Write album metadata if not already written for this album
        if !albums_with_metadata.contains_key(&album_folder) {
            write_album_metadata(export_path, &album_folder, collection, account.user_id).await?;
            albums_with_metadata.insert(album_folder.clone(), true);
        }

        // Get and increment file index for this album
        let file_index = album_file_indices.entry(album_folder.clone()).or_insert(0);

        // Write file metadata
        let filename = file_path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| crate::Error::Generic(format!("Invalid file path: {:?}", file_path)))?;
        write_file_metadata(
            export_path,
            &album_folder,
            &file,
            metadata.as_ref(),
            filename,
            *file_index,
        )
        .await?;

        // Note: We don't add newly exported files to album_existing_files
        // That map is only for tracking files that existed before this export
        // and need to be checked for deletion

        *file_index += 1;

        // Progress indicator - show every 10 files for better UX
        if exported_files % 10 == 0 || exported_files == 1 {
            println!("  [{}/{}] Exported files...", exported_files, total_files);
        }
    }

    // Clean up deleted files that are still on disk
    // Any files remaining in album_existing_files were not seen during export (deleted)
    let mut removed_files = 0;
    for (album_name, remaining_files) in album_existing_files {
        for (file_id, existing_file) in remaining_files {
            log::info!(
                "Removing deleted file {} from album {}: {:?}",
                file_id,
                album_name,
                existing_file.file_path
            );

            // Remove the actual file
            if existing_file.file_path.exists() {
                if let Err(e) = fs::remove_file(&existing_file.file_path).await {
                    log::warn!(
                        "Failed to remove deleted file {:?}: {}",
                        existing_file.file_path,
                        e
                    );
                } else {
                    removed_files += 1;
                }
            }

            // For live photos, also remove the MOV component
            let mov_path = existing_file.file_path.with_extension("MOV");
            if mov_path.exists() {
                log::debug!("Removing live photo MOV component: {:?}", mov_path);
                fs::remove_file(&mov_path).await.ok();
            }

            // Also try lowercase .mov
            let mov_path_lower = existing_file.file_path.with_extension("mov");
            if mov_path_lower.exists() && mov_path_lower != mov_path {
                log::debug!("Removing live photo mov component: {:?}", mov_path_lower);
                fs::remove_file(&mov_path_lower).await.ok();
            }

            // Remove the metadata file
            if existing_file.meta_path.exists() {
                log::debug!(
                    "Removing metadata for deleted file: {:?}",
                    existing_file.meta_path
                );
                if let Err(e) = fs::remove_file(&existing_file.meta_path).await {
                    log::warn!(
                        "Failed to remove metadata {:?}: {}",
                        existing_file.meta_path,
                        e
                    );
                }
            }
        }
    }

    if removed_files > 0 {
        log::info!("Removed {} deleted files from disk", removed_files);
    }

    println!("\n{}", "=".repeat(50));
    println!("Export Summary:");
    println!("{}", "=".repeat(50));
    println!("  📁 Total files (non-deleted): {total_files}");
    println!("  ✅ Successfully exported: {exported_files}");

    if skipped_files > 0 {
        println!("  ⏭️  Skipped (already exists): {skipped_files}");
    }

    if deleted_files > 0 {
        println!("  🗑️  Deleted files (skipped): {deleted_files}");
    }

    if removed_files > 0 {
        println!("  🧹 Removed from disk: {removed_files}");
    }

    let failed = total_files - exported_files - skipped_files;
    if failed > 0 {
        println!("  ❌ Failed to export: {failed}");
    }

    if exported_files == total_files {
        println!("\n🎉 All files exported successfully!");
    } else if exported_files > 0 {
        println!("\n✨ Export completed with {exported_files} new files!");
    } else if skipped_files == total_files {
        println!("\n✨ All files already exported!");
    }

    Ok(())
}

fn generate_export_path(
    export_dir: &Path,
    file: &crate::api::models::File,
    collection: Option<&crate::api::models::Collection>,
    metadata: Option<&FileMetadata>,
    pub_magic_metadata: Option<&serde_json::Value>,
) -> Result<PathBuf> {
    // Start with export directory
    let mut path = export_dir.to_path_buf();

    // Match Go CLI structure: export_dir/AlbumName/filename
    // Use collection/album name as folder, or "Uncategorized" if none
    let album_folder = if let Some(col) = collection
        && let Some(ref name) = col.name
        && !name.is_empty()
    {
        // Sanitize collection name for filesystem (matching Go's approach)
        sanitize_album_name(name)
    } else {
        // Files without a collection go to "Uncategorized" (matching Go CLI)
        "Uncategorized".to_string()
    };

    path.push(album_folder);

    // Use filename from public magic metadata (edited name) or regular metadata
    let filename = {
        // First check for edited name in public magic metadata
        if let Some(pub_meta) = pub_magic_metadata
            && let Some(edited_name) = pub_meta.get("editedName")
            && let Some(name_str) = edited_name.as_str()
            && !name_str.is_empty()
        {
            sanitize_filename(name_str)
        } else if let Some(meta) = metadata {
            // Fall back to original title from metadata
            if let Some(title) = meta.get_title() {
                sanitize_filename(title)
            } else {
                // Match Go CLI behavior: error if no title found
                return Err(crate::Error::Generic(format!(
                    "File {} has no title in metadata",
                    file.id
                )));
            }
        } else {
            // Match Go CLI behavior: error if no metadata
            return Err(crate::Error::Generic(format!(
                "File {} has no metadata",
                file.id
            )));
        }
    };
    path.push(filename);

    Ok(path)
}

/// Decrypt a collection key using the master key
fn decrypt_collection_key(
    encrypted_key: &str,
    nonce: &str,
    master_key: &[u8],
    _secret_key: &[u8],
) -> Result<Vec<u8>> {
    use base64::engine::general_purpose::STANDARD as BASE64;

    let encrypted_bytes = BASE64.decode(encrypted_key)?;
    let nonce_bytes = BASE64.decode(nonce)?;

    // Collection keys are encrypted with secret_box (XSalsa20-Poly1305) using master key
    Ok(crypto::secretbox::decrypt(
        &encrypted_bytes,
        &crypto::Nonce::try_from_slice(&nonce_bytes)?,
        &crypto::Key::try_from_slice(master_key)?,
    )?)
}

/// Decrypt a shared collection key using public key cryptography (sealed box)
fn decrypt_shared_collection_key(
    encrypted_key: &str,
    public_key: &[u8],
    secret_key: &[u8],
) -> Result<Vec<u8>> {
    use base64::engine::general_purpose::STANDARD as BASE64;

    let encrypted_bytes = BASE64.decode(encrypted_key)?;

    // Shared collection keys are encrypted with sealed_box (crypto_box_seal)
    // which uses the recipient's public key and an ephemeral keypair
    Ok(crypto::sealed::open(
        &encrypted_bytes,
        &crypto::PublicKey::try_from_slice(public_key)?,
        &crypto::SecretKey::try_from_slice(secret_key)?,
    )?)
}

/// Decrypt a collection name using the collection key
fn decrypt_collection_name(
    encrypted_name: &str,
    nonce: &str,
    collection_key: &[u8],
) -> Result<String> {
    use base64::engine::general_purpose::STANDARD as BASE64;

    let encrypted_bytes = BASE64.decode(encrypted_name)?;
    let nonce_bytes = BASE64.decode(nonce)?;

    // Collection names are encrypted with secret_box using the collection key
    let decrypted = crypto::secretbox::decrypt(
        &encrypted_bytes,
        &crypto::Nonce::try_from_slice(&nonce_bytes)?,
        &crypto::Key::try_from_slice(collection_key)?,
    )?;

    // Convert to string
    String::from_utf8(decrypted)
        .map_err(|e| crate::Error::Generic(format!("Invalid UTF-8 in collection name: {}", e)))
}

/// Decrypt a file key using the collection key
fn decrypt_file_key(encrypted_key: &str, nonce: &str, collection_key: &[u8]) -> Result<Vec<u8>> {
    use base64::engine::general_purpose::STANDARD as BASE64;

    let encrypted_bytes = BASE64.decode(encrypted_key)?;
    let nonce_bytes = BASE64.decode(nonce)?;

    // File keys are encrypted with secret_box (XSalsa20-Poly1305) using collection key
    Ok(crypto::secretbox::decrypt(
        &encrypted_bytes,
        &crypto::Nonce::try_from_slice(&nonce_bytes)?,
        &crypto::Key::try_from_slice(collection_key)?,
    )?)
}

// Removed generate_fallback_filename - Go CLI panics if no title, we return error instead

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

/// Sanitize an album/collection name for filesystem (matching Go CLI's logic)
fn sanitize_album_name(name: &str) -> String {
    // Go CLI replaces : and / with _ in album names
    name.chars()
        .map(|c| match c {
            ':' | '/' => '_',
            c => c,
        })
        .collect::<String>()
        .trim()
        .to_string()
}

/// Decrypt file metadata
fn decrypt_file_metadata(
    file: &crate::api::models::File,
    file_key: &[u8],
) -> Result<Option<FileMetadata>> {
    use base64::engine::general_purpose::STANDARD as BASE64;

    // Check if metadata exists
    if file.metadata.encrypted_data.is_none() || file.metadata.decryption_header.is_empty() {
        return Ok(None);
    }

    let encrypted_data = file.metadata.encrypted_data.as_ref().unwrap();
    let encrypted_bytes = BASE64.decode(encrypted_data)?;
    let header_bytes = BASE64.decode(&file.metadata.decryption_header)?;

    // Decrypt the metadata using streaming XChaCha20-Poly1305
    let decrypted = crypto::blob::decrypt(
        &encrypted_bytes,
        &crypto::Header::try_from_slice(&header_bytes)?,
        &crypto::Key::try_from_slice(file_key)?,
    )?;

    // Parse JSON metadata
    let metadata: FileMetadata = serde_json::from_slice(&decrypted)?;
    Ok(Some(metadata))
}

/// Decrypt magic metadata (public or private)
fn decrypt_magic_metadata(
    magic_metadata: &crate::api::models::MagicMetadata,
    file_key: &[u8],
) -> Result<Option<serde_json::Value>> {
    use base64::engine::general_purpose::STANDARD as BASE64;

    // Check if data exists
    if magic_metadata.data.is_empty() || magic_metadata.header.is_empty() {
        return Ok(None);
    }

    let encrypted_bytes = BASE64.decode(&magic_metadata.data)?;
    let header_bytes = BASE64.decode(&magic_metadata.header)?;

    // Decrypt the metadata using streaming XChaCha20-Poly1305
    let decrypted = crypto::blob::decrypt(
        &encrypted_bytes,
        &crypto::Header::try_from_slice(&header_bytes)?,
        &crypto::Key::try_from_slice(file_key)?,
    )?;

    // Parse as generic JSON since magic metadata structure can vary
    let metadata: serde_json::Value = serde_json::from_slice(&decrypted)?;
    Ok(Some(metadata))
}

/// Extract live photo components from a ZIP file
async fn extract_live_photo(zip_data: &[u8], output_path: &Path) -> Result<()> {
    use zip::ZipArchive;

    // Parse the ZIP archive
    let cursor = Cursor::new(zip_data);
    let mut archive = ZipArchive::new(cursor)?;

    // Get the parent directory and base name
    let parent_dir = output_path
        .parent()
        .ok_or_else(|| crate::Error::Generic("Invalid output path".into()))?;

    let base_name = output_path
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or_else(|| crate::Error::Generic("Invalid filename".into()))?;

    // Extract each file from the ZIP
    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let file_name = file.name().to_string();

        // Determine the output filename preserving original extension
        // Following Go CLI's approach: use the actual extension from the file in the ZIP
        let output_file_path = if file_name.to_lowercase().contains("image") {
            // Image component - preserve its original extension
            let ext = std::path::Path::new(&file_name)
                .extension()
                .and_then(|e| e.to_str())
                .ok_or_else(|| {
                    crate::Error::Generic(format!(
                        "Live photo image component has no extension: {}",
                        file_name
                    ))
                })?;
            parent_dir.join(format!("{}.{}", base_name, ext))
        } else if file_name.to_lowercase().contains("video") {
            // Video component - preserve its original extension
            let ext = std::path::Path::new(&file_name)
                .extension()
                .and_then(|e| e.to_str())
                .ok_or_else(|| {
                    crate::Error::Generic(format!(
                        "Live photo video component has no extension: {}",
                        file_name
                    ))
                })?;
            parent_dir.join(format!("{}.{}", base_name, ext))
        } else {
            // Go CLI returns error for unexpected files in live photo ZIP
            return Err(crate::Error::Generic(format!(
                "Unexpected file in live photo ZIP: {}",
                file_name
            )));
        };

        // Read the file contents
        let mut contents = Vec::new();
        use std::io::Read;
        file.read_to_end(&mut contents)?;

        // Write to disk
        let mut output_file = fs::File::create(&output_file_path).await?;
        output_file.write_all(&contents).await?;
        output_file.sync_all().await?;

        log::debug!("Extracted live photo component: {:?}", output_file_path);
    }

    Ok(())
}

/// Check if a collection is hidden based on its metadata
fn check_collection_visibility(
    collection: &crate::api::models::Collection,
    collection_key: &[u8],
) -> bool {
    // Try encrypted magic metadata (private metadata) - this is where visibility is stored per Go CLI
    if let Some(ref magic_metadata) = collection.magic_metadata {
        // Try to decrypt and parse the magic metadata
        if let Ok(Some(decrypted_json)) = decrypt_magic_metadata(magic_metadata, collection_key) {
            // Check for visibility field - value of 2 means hidden (matching Go CLI logic)
            if let Some(visibility) = decrypted_json.get("visibility").and_then(|v| v.as_i64()) {
                log::debug!(
                    "Collection {} has visibility: {} (hidden={})",
                    collection.id,
                    visibility,
                    visibility == 2
                );
                return visibility == 2;
            }
        }
    }

    // Default to not hidden if we can't determine visibility
    false
}

/// Write album metadata to .meta/album_meta.json
async fn write_album_metadata(
    export_path: &Path,
    album_folder: &str,
    collection: &crate::api::models::Collection,
    account_id: i64,
) -> Result<()> {
    let meta_dir = export_path.join(album_folder).join(".meta");
    fs::create_dir_all(&meta_dir).await?;

    let album_meta = AlbumMetadata::new(
        collection.id,
        collection.owner.id,
        collection
            .name
            .clone()
            .unwrap_or_else(|| "Unnamed".to_string()),
        account_id,
    );

    let meta_path = meta_dir.join("album_meta.json");
    let json = serde_json::to_string_pretty(&album_meta)?;
    fs::write(meta_path, json).await?;

    Ok(())
}

/// Write file metadata to .meta folder
async fn write_file_metadata(
    export_path: &Path,
    album_folder: &str,
    file: &crate::api::models::File,
    metadata: Option<&FileMetadata>,
    filename: &str,
    file_index: usize,
) -> Result<PathBuf> {
    let meta_dir = export_path.join(album_folder).join(".meta");
    fs::create_dir_all(&meta_dir).await?;

    // Generate unique metadata filename
    // At this point, filename should always be valid since we error out earlier if not
    let base_name = Path::new(filename)
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or_else(|| crate::Error::Generic("Invalid filename for metadata".to_string()))?;
    let extension = Path::new(filename)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or(""); // Extension might be legitimately missing for some files

    // Create metadata filename like "IMG_1234.jpg_0.json"
    let meta_filename = format!("{}_{}.{}.json", base_name, file_index, extension);

    let mut disk_metadata = DiskFileMetadata::from_file(file, metadata, filename.to_string());
    disk_metadata.meta_file_name = meta_filename.clone();

    let meta_path = meta_dir.join(meta_filename);
    let json = serde_json::to_string_pretty(&disk_metadata)?;
    fs::write(&meta_path, json).await?;

    Ok(meta_path)
}
