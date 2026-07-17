#![allow(dead_code)]

pub mod auth;
pub mod contacts;
pub mod legacy;
pub mod legacy_kit;
pub mod space;

use ente_test_support::HARDCODED_OTT_EMAIL_SUFFIX;
use std::collections::HashSet;
use uuid::Uuid;

pub fn endpoint() -> String {
    std::env::var("ENTE_E2E_ENDPOINT").unwrap_or_else(|_| "http://localhost:8080".to_string())
}

pub async fn assert_server_or_skip(endpoint: &str, test_name: &str) -> bool {
    let ping_url = format!("{endpoint}/ping");
    match reqwest::get(&ping_url).await {
        Ok(response) if response.status().is_success() => true,
        Ok(response) => {
            eprintln!(
                "skipping {test_name}: {ping_url} returned {}",
                response.status()
            );
            false
        }
        Err(error) => {
            eprintln!("skipping {test_name}: could not reach {ping_url}: {error}");
            false
        }
    }
}

pub fn stage_enabled(stage_name: &str) -> bool {
    let normalized_stage = stage_name.trim().to_ascii_lowercase();
    if let Some(only) = env_list("ENTE_E2E_ONLY")
        && !only.contains(&normalized_stage)
    {
        eprintln!(
            "skipping {stage_name}: not selected by ENTE_E2E_ONLY={}",
            std::env::var("ENTE_E2E_ONLY").unwrap_or_default()
        );
        return false;
    }
    if let Some(skip) = env_list("ENTE_E2E_SKIP")
        && skip.contains(&normalized_stage)
    {
        eprintln!(
            "skipping {stage_name}: selected by ENTE_E2E_SKIP={}",
            std::env::var("ENTE_E2E_SKIP").unwrap_or_default()
        );
        return false;
    }
    true
}

fn env_list(name: &str) -> Option<HashSet<String>> {
    let raw = std::env::var(name).ok()?;
    let values = raw
        .split(',')
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| !value.is_empty())
        .collect::<HashSet<_>>();
    if values.is_empty() {
        None
    } else {
        Some(values)
    }
}

pub fn unique_test_email(prefix: &str) -> String {
    format!("{prefix}-{}{HARDCODED_OTT_EMAIL_SUFFIX}", Uuid::new_v4())
}

pub fn unique_password(prefix: &str) -> String {
    format!("{prefix}-{}!", Uuid::new_v4().simple())
}
