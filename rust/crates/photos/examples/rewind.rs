use std::env;
use std::error::Error;
use std::fs;
use std::path::PathBuf;

use ente_photos::ml_store::MlStore;
use ente_photos::rewind::{RewindRequest, compute_rewind};

fn main() -> Result<(), Box<dyn Error>> {
    let snapshot = PathBuf::from(
        env::args()
            .nth(1)
            .ok_or("usage: cargo run -p ente-photos --example rewind -- <snapshot directory>")?,
    );
    let request: RewindRequest = serde_json::from_slice(&fs::read(snapshot.join("request.json"))?)?;
    let ml_db = snapshot.join("ml.db");
    let store = ml_db.exists().then(|| MlStore::open(&ml_db)).transpose()?;
    let state = compute_rewind(&request, store.as_ref())?;
    println!("{}", serde_json::to_string_pretty(&state)?);
    Ok(())
}
