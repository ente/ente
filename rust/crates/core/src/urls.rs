//! URL construction utilities.

/// Production API origin.
pub const PRODUCTION_API_ORIGIN: &str = "https://api.ente.com";

/// Append a trusted endpoint path to the configured API origin.
///
/// The configured value is expected to be an origin and endpoint paths are
/// trusted. Any path prefix is retained as a best-effort convenience for
/// self-hosted deployments.
pub(crate) fn api_url(origin: &str, path: &str) -> String {
    format!(
        "{}/{}",
        origin.trim_end_matches('/'),
        path.trim_start_matches('/')
    )
}

/// Generate the download URL for a file.
pub fn file_download_url(api_origin: &str, file_id: i64) -> String {
    if api_origin == PRODUCTION_API_ORIGIN {
        format!("https://files.ente.com/?fileID={}", file_id)
    } else {
        api_url(api_origin, &format!("files/download/{file_id}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_production_url() {
        let url = file_download_url(PRODUCTION_API_ORIGIN, 12345);
        assert_eq!(url, "https://files.ente.com/?fileID=12345");
    }

    #[test]
    fn test_custom_server() {
        let url = file_download_url("https://my-server.example.com", 99);
        assert_eq!(url, "https://my-server.example.com/files/download/99");
    }

    #[test]
    fn test_custom_server_path_prefix() {
        let url = file_download_url("https://my-server.example.com/ente/", 99);
        assert_eq!(url, "https://my-server.example.com/ente/files/download/99");
    }
}
