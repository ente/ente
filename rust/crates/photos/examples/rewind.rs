use std::env;
use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use ente_photos::location::LocationIndex;
use ente_photos::ml_store::MlStore;
use ente_photos::rewind::{RewindRequest, compute_rewind};

const ASSET_CACHE: &str = "../../.cache/assets";

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let mut arguments = env::args().skip(1);
    let snapshot = PathBuf::from(arguments.next().ok_or(
        "usage: cargo run -p ente-photos --example rewind -- <snapshot directory> [asset directory]",
    )?);
    let assets = arguments.next().map_or_else(
        || Path::new(env!("CARGO_MANIFEST_DIR")).join(ASSET_CACHE),
        PathBuf::from,
    );
    let request: RewindRequest = serde_json::from_slice(&fs::read(snapshot.join("request.json"))?)?;
    let ml_db = snapshot.join("ml.db");
    let store = ml_db.exists().then(|| MlStore::open(&ml_db)).transpose()?;
    let cities = LocationIndex::open(&assets).await?;
    let started = Instant::now();
    let state = compute_rewind(&request, store.as_ref(), Some(&cities), None)?;
    eprintln!(
        "computed rewind for {} files in {} ms",
        request.files.len(),
        started.elapsed().as_millis()
    );
    println!("{}", serde_json::to_string_pretty(&state)?);
    Ok(())
}
