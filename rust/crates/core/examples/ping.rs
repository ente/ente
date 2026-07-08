//! Example: ping the Ente API.
//!
//! ```sh
//! cargo run --example ping -- https://api.ente.com
//! ```

use ente_core::http::HttpClient;

#[tokio::main]
async fn main() {
    let base_url = std::env::args().nth(1).expect("Usage: ping <base_url>");

    let client = HttpClient::new(&base_url).expect("failed to build HTTP client");

    match client.ping().await {
        Ok(response) => println!("message: {}, id: {}", response.message, response.id),
        Err(e) => eprintln!("Error: {}", e),
    }
}
