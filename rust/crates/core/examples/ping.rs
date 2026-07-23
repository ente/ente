//! Example: ping the Ente API.
//!
//! ```sh
//! cargo run --example ping -- https://api.ente.com
//! ```

use ente_core::http::{Api, ApiConfig, Http};

#[tokio::main]
async fn main() {
    let origin = std::env::args().nth(1).expect("Usage: ping <origin>");

    let api = Api::new(
        Http::new().expect("failed to build HTTP client"),
        ApiConfig::new(origin),
    );

    match api.ping().await {
        Ok(response) => println!("message: {}, id: {}", response.message, response.id),
        Err(e) => eprintln!("Error: {e}"),
    }
}
