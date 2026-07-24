use crate::Result;
use crate::api::client::AppClient;
use crate::api::methods::ApiMethods;
use crate::live_photo::extract_live_photo;
use crate::models::file::RemoteFile;
use ente_core::b64;
use ente_core::crypto;
use indicatif::{MultiProgress, ProgressBar, ProgressStyle};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::fs;
use tokio::io::AsyncWriteExt;

/// Manages file downloads with parallel processing and error recovery
pub struct DownloadManager {
    api_client: AppClient,
    temp_dir: PathBuf,
    pub collection_keys: HashMap<i64, Vec<u8>>,
    concurrent_downloads: usize,
    show_progress: bool,
}

impl DownloadManager {
    /// Create a new download manager
    pub fn new(api_client: AppClient) -> Result<Self> {
        let temp_dir = std::env::temp_dir().join("ente-downloads");
        std::fs::create_dir_all(&temp_dir)?;

        Ok(Self {
            api_client,
            temp_dir,
            collection_keys: HashMap::new(),
            concurrent_downloads: 4, // Default concurrent downloads
            show_progress: true,
        })
    }

    /// Set collection keys for file decryption
    pub fn set_collection_keys(&mut self, keys: HashMap<i64, Vec<u8>>) {
        self.collection_keys = keys;
    }

    /// Set number of concurrent downloads
    pub fn set_concurrent_downloads(&mut self, count: usize) {
        self.concurrent_downloads = count.clamp(1, 10); // Limit between 1-10
    }

    /// Set whether to show progress indicators
    pub fn set_show_progress(&mut self, show: bool) {
        self.show_progress = show;
    }

    /// Download a single file
    pub async fn download_file(&self, file: &RemoteFile, destination: &Path) -> Result<()> {
        self.download_file_with_progress(file, destination, None)
            .await
    }

    /// Download a single file with optional progress bar
    async fn download_file_with_progress(
        &self,
        file: &RemoteFile,
        destination: &Path,
        progress: Option<Arc<ProgressBar>>,
    ) -> Result<()> {
        log::debug!("Downloading file {} to {:?}", file.id, destination);

        // Ensure destination directory exists
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent).await?;
        }

        // Check if file already exists
        if destination.exists() {
            log::debug!(
                "File already exists at {destination:?}, skipping download but marking as successful"
            );
            // Even though we skip downloading, we should still update the database
            // This is handled by returning Ok(()) which will mark it as successful
            return Ok(());
        }

        // Download to temp file first
        let temp_path = self.temp_dir.join(format!("{}.tmp", file.id));

        // Get file data
        let api = ApiMethods::new(&self.api_client);
        let encrypted_data = api.download_file(file.id).await?;

        // Decrypt file
        let decrypted_data = self.decrypt_file_data(file, &encrypted_data)?;

        // Check if this is a live photo (based on .zip extension in destination)
        let is_live_photo = destination
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.to_lowercase() == "zip")
            .unwrap_or(false);

        if is_live_photo {
            // Extract live photo components
            if let Err(e) = extract_live_photo(&decrypted_data, destination).await {
                log::warn!(
                    "Failed to extract live photo components for file {}, saving as ZIP: {}",
                    file.id,
                    e
                );
                // Fall back to saving as ZIP
                let mut temp_file = fs::File::create(&temp_path).await?;
                temp_file.write_all(&decrypted_data).await?;
                temp_file.sync_all().await?;
                drop(temp_file);
                fs::copy(&temp_path, destination).await?;
                fs::remove_file(&temp_path).await?;
            }
        } else {
            // Write regular file
            let mut temp_file = fs::File::create(&temp_path).await?;
            temp_file.write_all(&decrypted_data).await?;
            temp_file.sync_all().await?;
            drop(temp_file);

            // Move to final destination (use copy + delete to work across filesystems)
            fs::copy(&temp_path, destination).await?;
            fs::remove_file(&temp_path).await?;
        }

        // TODO: Update storage with local path
        // self.storage.sync().update_file_local_path(file.id, destination.to_str().unwrap())?;

        // Update progress if available
        if let Some(pb) = progress {
            pb.inc(1);
        }

        log::info!("Downloaded file {} to {:?}", file.id, destination);
        Ok(())
    }

    /// Download multiple files with concurrency control
    pub async fn download_files(&self, files: Vec<(RemoteFile, PathBuf)>) -> Result<DownloadStats> {
        use futures::stream::{self, StreamExt};

        let total = files.len();
        log::info!("Starting download of {total} files");

        let mut stats = DownloadStats {
            total,
            ..Default::default()
        };

        // Create progress bars if enabled
        let (_multi_progress, progress_bar) = if self.show_progress && total > 0 {
            let mp = MultiProgress::new();
            let pb = mp.add(ProgressBar::new(total as u64));
            pb.set_style(
                ProgressStyle::default_bar()
                    .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} ({percent}%) {msg}")
                    .unwrap()
                    .progress_chars("#>-"),
            );
            pb.set_message("Downloading files...");
            (Some(Arc::new(mp)), Some(Arc::new(pb)))
        } else {
            (None, None)
        };

        // Process files in parallel with concurrency limit
        let pb_clone = progress_bar.clone();
        let results: Vec<_> = stream::iter(files)
            .map(|(file, path)| {
                let file_clone = file.clone();
                let path_clone = path.clone();
                let pb = pb_clone.clone();
                async move {
                    let result = self.download_file_with_progress(&file, &path, pb).await;
                    (file_clone, path_clone, result)
                }
            })
            .buffer_unordered(self.concurrent_downloads)
            .collect()
            .await;

        // Count results
        for (file, path, result) in results {
            match result {
                Ok(_) => {
                    stats.successful += 1;
                    stats.successful_downloads.push((file, path));
                }
                Err(e) => {
                    log::error!("Download failed for file {}: {}", file.id, e);
                    stats.failed += 1;
                }
            }
        }

        // Finish progress bar
        if let Some(pb) = progress_bar {
            pb.finish_with_message(format!("Downloaded {} files", stats.successful));
        }

        log::info!(
            "Download completed: {} successful, {} failed",
            stats.successful,
            stats.failed
        );
        Ok(stats)
    }

    /// Download thumbnail for a file
    pub async fn download_thumbnail(&self, file: &RemoteFile, destination: &Path) -> Result<()> {
        log::debug!(
            "Downloading thumbnail for file {} to {:?}",
            file.id,
            destination
        );

        // Ensure destination directory exists
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent).await?;
        }

        // Get thumbnail data
        let api = ApiMethods::new(&self.api_client);
        let encrypted_data = api.download_thumbnail(file.id).await?;

        // Decrypt thumbnail
        let decrypted_data = self.decrypt_file_data(file, &encrypted_data)?;

        // Write to file
        let mut file_handle = fs::File::create(destination).await?;
        file_handle.write_all(&decrypted_data).await?;
        file_handle.sync_all().await?;

        log::debug!("Thumbnail downloaded for file {}", file.id);
        Ok(())
    }

    /// Decrypt file data using file key and collection key
    fn decrypt_file_data(&self, file: &RemoteFile, encrypted_data: &[u8]) -> Result<Vec<u8>> {
        // Get collection key
        let collection_key = self
            .collection_keys
            .get(&file.collection_id)
            .ok_or_else(|| {
                crate::Error::Crypto("Missing collection key for file decryption".into())
            })?;

        // Decrypt file key using collection key (XSalsa20-Poly1305)
        let file_key = {
            let key_bytes = b64::decode(&file.encrypted_key)?;
            let nonce = b64::decode(&file.key_decryption_nonce)?;
            crypto::secretbox::decrypt(
                &key_bytes,
                &crypto::Nonce::try_from_slice(&nonce)?,
                &crypto::Key::try_from_slice(collection_key)?,
            )?
        };

        // Decrypt file data using file key (Streaming XChaCha20-Poly1305)
        let file_nonce = b64::decode(&file.file.decryption_header)?;
        let decrypted = crypto::stream::decrypt_file_data(
            encrypted_data,
            &crypto::Header::try_from_slice(&file_nonce)?,
            &crypto::Key::try_from_slice(&file_key)?,
        )?;

        Ok(decrypted)
    }

    /// Resume a partial download (for future implementation)
    pub async fn resume_download(
        &self,
        _file: &RemoteFile,
        _destination: &Path,
        _offset: u64,
    ) -> Result<()> {
        // TODO: Implement resume functionality using Range headers
        todo!("Resume download not yet implemented")
    }

    /// Clean up temporary files
    pub async fn cleanup(&self) -> Result<()> {
        log::debug!("Cleaning up temporary download files");

        let mut entries = fs::read_dir(&self.temp_dir).await?;
        let mut count = 0;

        while let Some(entry) = entries.next_entry().await? {
            if entry.path().extension().and_then(|s| s.to_str()) == Some("tmp") {
                if let Err(e) = fs::remove_file(entry.path()).await {
                    log::warn!("Failed to remove temp file {:?}: {}", entry.path(), e);
                } else {
                    count += 1;
                }
            }
        }

        log::debug!("Cleaned up {count} temporary files");
        Ok(())
    }
}

/// Statistics from download operations
#[derive(Debug, Default)]
pub struct DownloadStats {
    pub total: usize,
    pub successful: usize,
    pub failed: usize,
    pub skipped: usize,
    pub successful_downloads: Vec<(RemoteFile, PathBuf)>,
}

impl DownloadStats {
    /// Check if all downloads were successful
    pub fn all_successful(&self) -> bool {
        self.failed == 0 && self.successful == self.total
    }

    /// Get success rate as percentage
    pub fn success_rate(&self) -> f64 {
        if self.total == 0 {
            100.0
        } else {
            (self.successful as f64 / self.total as f64) * 100.0
        }
    }
}
