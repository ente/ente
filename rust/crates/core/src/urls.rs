//! URL construction utilities.

/// Production API origin.
pub const PRODUCTION_API_ORIGIN: &str = "https://api.ente.com";

/// Generate the download URL for a file.
pub fn file_download_url(api_origin: &str, file_id: i64) -> String {
    if api_origin == PRODUCTION_API_ORIGIN {
        format!("https://files.ente.com/?fileID={}", file_id)
    } else {
        format!("{}/files/download/{}", api_origin, file_id)
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
}
