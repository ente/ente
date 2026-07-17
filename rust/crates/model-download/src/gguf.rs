use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::download::{self, Target};

const MIN_MODEL_BYTES: u64 = 1024 * 1024;

pub(crate) fn expected_targets(
    models_dir: &Path,
    id: &str,
    url: &str,
    mmproj_url: Option<&str>,
) -> Vec<Target> {
    let mut targets = vec![Target {
        label: "Model".to_string(),
        url: url.to_string(),
        destination_path: model_path(models_dir, id, url, mmproj_url)
            .display()
            .to_string(),
    }];
    if let Some(mmproj) = mmproj_path(models_dir, id, url, mmproj_url) {
        targets.push(Target {
            label: "Mmproj".to_string(),
            url: trimmed(mmproj_url).unwrap().to_string(),
            destination_path: mmproj.display().to_string(),
        });
    }
    targets
}

pub(crate) fn model_dir(
    models_dir: &Path,
    id: &str,
    url: &str,
    mmproj_url: Option<&str>,
) -> PathBuf {
    let key = if id.starts_with("custom") {
        let pair = format!("{url}\n{}", trimmed(mmproj_url).unwrap_or(""));
        format!("custom-{}", &sha256_hex(&pair)[..16])
    } else {
        id.to_string()
    };
    models_dir.join(key)
}

pub(crate) fn model_path(
    models_dir: &Path,
    id: &str,
    url: &str,
    mmproj_url: Option<&str>,
) -> PathBuf {
    model_dir(models_dir, id, url, mmproj_url).join("model.gguf")
}

pub(crate) fn mmproj_path(
    models_dir: &Path,
    id: &str,
    url: &str,
    mmproj_url: Option<&str>,
) -> Option<PathBuf> {
    trimmed(mmproj_url)?;
    Some(model_dir(models_dir, id, url, mmproj_url).join("mmproj.gguf"))
}

pub(crate) fn looks_like_gguf(path: &Path) -> bool {
    let mut file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let mut header = [0u8; 4];
    file.read_exact(&mut header).is_ok() && &header == b"GGUF"
}

pub(crate) fn validate_gguf(path: &Path) -> Result<(), download::Error> {
    if file_size(path).is_none_or(|size| size < MIN_MODEL_BYTES) {
        return Err(download::Error::Validation(format!(
            "{} is too small to be a model file",
            path.display()
        )));
    }
    if !looks_like_gguf(path) {
        return Err(download::Error::Validation(format!(
            "{} is not a valid GGUF file",
            path.display()
        )));
    }
    Ok(())
}

pub(crate) fn trimmed(url: Option<&str>) -> Option<&str> {
    url.map(str::trim).filter(|url| !url.is_empty())
}

pub(crate) fn filename_for_url(url: &str, fallback: &str) -> String {
    let without_query = url.split(['?', '#']).next().unwrap_or(url);
    let name = without_query.rsplit('/').next().unwrap_or("");
    if name.trim().is_empty() {
        fallback.to_string()
    } else {
        name.to_string()
    }
}

pub(crate) fn sha256_hex(value: &str) -> String {
    Sha256::digest(value.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn file_size(path: &Path) -> Option<u64> {
    std::fs::metadata(path).ok().map(|metadata| metadata.len())
}
