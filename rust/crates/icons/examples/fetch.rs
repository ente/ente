#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let url = args
        .next()
        .filter(|_| args.next().is_none())
        .ok_or("usage: cargo run -p ente-icons --example fetch -- https://example.com")?;
    match ente_icons::Fetcher::new()?.fetch(&url).await? {
        Some(icon) => println!("{} ({} bytes, image/png)", icon.url, icon.data.len()),
        None => println!("No icon found"),
    }
    Ok(())
}
