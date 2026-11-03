use std::fmt::Write as _;
use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, bail};
use ente_assets::AssetStore;
use ente_ml::assets::ensure_clip_text;
use ente_ml::indexing::{RunClipTextRequest, run_clip_text};

const ASSET_CACHE: &str = "../../.cache/assets";
const OUTPUT: &str = "../photos/src/memories/text_embeddings.rs";
const DIMENSIONS: usize = 512;
const I8_LIMIT: f32 = 127.0;
const NOSTALGIA: &str = "Photo of a precious and nostalgic memory radiating warmth, vibrant energy, or quiet beauty — alive with color, light, or emotion";
const CLIP_MEMORY_TYPES: [(&str, &str); 48] = [
    (
        "Sunrise",
        "Photo of an absolutely stunning sunrise or sunset",
    ),
    ("Mountains", "Photo of a beautiful mountain range"),
    ("Greenery", "Photo of lush greenery"),
    ("Beach", "Photo of a beautiful beach"),
    ("City", "Beautiful photo showing a metropolitan city"),
    ("Moon", "Photo of a beautiful moon"),
    ("OnTheRoad", "Photo of a nostalgic road trip"),
    ("Food", "Photo of delicious looking food"),
    ("Pets", "Photo of cute pets"),
    (
        "Festivities",
        "Photo capturing a joyful celebration or festival",
    ),
    (
        "SnowAdventures",
        "Photo of a cozy winter adventure in the snow",
    ),
    (
        "Waterfalls",
        "Photo of a majestic waterfall cascading through nature",
    ),
    (
        "Wildlife",
        "Photo of a magnificent wild animal in its natural habitat",
    ),
    ("Flowers", "Photo of vibrant blooming flowers in a garden"),
    (
        "NightLights",
        "Photo of dazzling city lights glowing at night",
    ),
    (
        "Architecture",
        "Photo showcasing striking architectural design or landmark",
    ),
    (
        "AutumnColors",
        "Photo of trees glowing with vibrant autumn colors",
    ),
    (
        "DesertDreams",
        "Photo of sweeping desert dunes under golden light",
    ),
    (
        "Stargazing",
        "Photo of a brilliant night sky filled with stars or the Milky Way",
    ),
    (
        "Lakeside",
        "Photo of a serene lake reflecting the surrounding landscape",
    ),
    ("RainyDays", "Photo capturing the cozy mood of a rainy day"),
    (
        "SportsAction",
        "Photo of thrilling sports action frozen in motion",
    ),
    (
        "StreetArt",
        "Photo showcasing vibrant street art or graffiti murals",
    ),
    (
        "FamilyMoments",
        "Photo capturing heartwarming moments with family",
    ),
    (
        "Fireworks",
        "Photo of dazzling fireworks bursting in the sky",
    ),
    (
        "HistoricSites",
        "Photo of an awe-inspiring historical monument or landmark",
    ),
    (
        "TropicalParadise",
        "Photo of a dreamy tropical paradise with turquoise water and palm trees",
    ),
    (
        "ForestTrails",
        "Photo of a peaceful forest trail bathed in soft light",
    ),
    (
        "CitySunsets",
        "Photo of a vibrant sunset casting colors over a city skyline",
    ),
    (
        "ColorfulMarkets",
        "Photo of a bustling market overflowing with colorful stalls",
    ),
    ("CozyCafes", "Photo of a cozy cafe scene with warm ambience"),
    (
        "VintageVibes",
        "Photo with a charming vintage aesthetic or retro details",
    ),
    (
        "AerialViews",
        "Photo captured from above showing sweeping aerial views",
    ),
    (
        "ArtisticPortraits",
        "Photo of an expressive artistic portrait",
    ),
    (
        "StreetFood",
        "Photo of mouthwatering street food being prepared or served",
    ),
    (
        "RiverCruises",
        "Photo of a scenic river cruise or boat drifting along the water",
    ),
    (
        "PlayfulKids",
        "Photo capturing joyful kids playing and laughing",
    ),
    (
        "CoastalCliffs",
        "Photo of dramatic coastal cliffs meeting the sea",
    ),
    (
        "CandidLaughter",
        "Photo capturing candid laughter, joy, and shared smiles",
    ),
    (
        "GroupSelfies",
        "Photo of friends or family gathered for a fun group selfie",
    ),
    (
        "BirthdayJoy",
        "Photo of a birthday celebration with cake, candles, and happy faces",
    ),
    (
        "WeddingMoments",
        "Photo capturing a wedding moment full of love, celebration, and togetherness",
    ),
    (
        "GoldenHourPortraits",
        "Photo of a beautiful portrait taken in warm golden hour light",
    ),
    (
        "ConcertNights",
        "Photo of a live concert, music performance, or crowd under stage lights",
    ),
    (
        "PoolDays",
        "Photo of a fun summer day at the pool with splashes and sunshine",
    ),
    (
        "PicnicDays",
        "Photo of a relaxed picnic outdoors with food, blankets, and loved ones",
    ),
    (
        "CampingMoments",
        "Photo of a camping trip with tents, campfires, or cozy outdoor moments",
    ),
    (
        "BabySmiles",
        "Photo capturing a baby smiling, laughing, or sharing a tender family moment",
    ),
];

const PEOPLE_ACTIVITIES: [(&str, &str); 10] = [
    (
        "Admiring",
        "Photo of two people admiring or looking at each other in a loving but non-intimate and non-physical way",
    ),
    (
        "Embracing",
        "Photo of people hugging or embracing each other lovingly, without inappropriately kissing or other intimate actions",
    ),
    ("Party", "Photo of people celebrating together"),
    (
        "Hiking",
        "Photo of people hiking or walking together in nature",
    ),
    ("Feast", "Photo of people having a big feast together"),
    (
        "Selfies",
        "Happy and nostalgic selfie with people, clearly taken from the front camera of a phone",
    ),
    (
        "Posing",
        "Photo of people posing together in a funny manner for the camera",
    ),
    (
        "Background",
        "Photo of people with an absolutely stunning or interesting background",
    ),
    ("Sports", "Photo of people joyfully playing sports together"),
    ("Roadtrip", "Photo of people on a road trip together"),
];

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    std::env::var_os("ORT_DYLIB_PATH").context("set ORT_DYLIB_PATH to an ONNX Runtime library")?;
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let cache = manifest_dir.join(ASSET_CACHE);
    let paths = ensure_clip_text(&AssetStore::new(cache.clone()), &cache).await?;
    let embed = |text: &str| -> Result<Vec<i8>> {
        let result = run_clip_text(RunClipTextRequest {
            text: text.to_owned(),
            model_path: paths.model.to_string_lossy().into_owned(),
            vocab_path: paths.vocab.to_string_lossy().into_owned(),
        })
        .with_context(|| format!("embed {text:?}"))?;
        quantize(&result.embedding).with_context(|| format!("quantize {text:?}"))
    };
    let nostalgia = embed(NOSTALGIA)?;
    let embed_all = |queries: &[(&'static str, &str)]| -> Result<Vec<(&'static str, Vec<i8>)>> {
        queries
            .iter()
            .map(|(name, query)| Ok((*name, embed(query)?)))
            .collect()
    };
    let clip_memory_types = embed_all(&CLIP_MEMORY_TYPES)?;
    let people_activities = embed_all(&PEOPLE_ACTIVITIES)?;

    let path = manifest_dir.join(OUTPUT);
    let source = render(&nostalgia, &clip_memory_types, &people_activities)?;
    std::fs::write(&path, source).with_context(|| format!("write {}", path.display()))?;
    let rustfmt = Command::new("rustfmt")
        .args(["--edition", "2024"])
        .arg(&path)
        .status()
        .with_context(|| format!("run rustfmt on {}", path.display()))?;
    if !rustfmt.success() {
        bail!("rustfmt failed on {}", path.display());
    }
    println!("wrote {}", path.display());
    Ok(())
}

fn quantize(embedding: &[f32]) -> Result<Vec<i8>> {
    if embedding.len() != DIMENSIONS {
        bail!("expected {DIMENSIONS} dimensions, got {}", embedding.len());
    }
    let max_abs = embedding
        .iter()
        .fold(0.0f32, |max_abs, value| max_abs.max(value.abs()));
    if !max_abs.is_normal() {
        bail!("embedding has no usable magnitude");
    }
    let scale = max_abs / I8_LIMIT;
    Ok(embedding
        .iter()
        .map(|value| (value / scale).round().clamp(-I8_LIMIT, I8_LIMIT) as i8)
        .collect())
}

fn render(
    nostalgia: &[i8],
    clip_memory_types: &[(&str, Vec<i8>)],
    people_activities: &[(&str, Vec<i8>)],
) -> Result<String> {
    let mut source = String::from(
        "use super::output::{ClipMemoryType, PeopleActivity};\n\
         use crate::ml_db::CLIP_EMBEDDING_DIMENSIONS;\n\n\
         pub(super) type TextEmbedding = [i8; CLIP_EMBEDDING_DIMENSIONS];\n\n",
    );
    writeln!(
        source,
        "pub(super) static NOSTALGIA: TextEmbedding = {};\n",
        array(nostalgia)
    )?;
    render_embedding_lookup(&mut source, "ClipMemoryType", clip_memory_types)?;
    source.push('\n');
    render_embedding_lookup(&mut source, "PeopleActivity", people_activities)?;
    for (name, embedding) in clip_memory_types.iter().chain(people_activities) {
        writeln!(
            source,
            "\nstatic {}: TextEmbedding = {};",
            static_name(name),
            array(embedding)
        )?;
    }
    Ok(source)
}

fn render_embedding_lookup(
    source: &mut String,
    type_name: &str,
    embeddings: &[(&str, Vec<i8>)],
) -> Result<()> {
    writeln!(
        source,
        "impl {type_name} {{\n    pub(super) fn embedding(self) -> &'static TextEmbedding {{\n        match self {{"
    )?;
    for (name, _) in embeddings {
        writeln!(source, "Self::{name} => &{},", static_name(name))?;
    }
    source.push_str("}\n}\n}\n");
    Ok(())
}

fn array(values: &[i8]) -> String {
    let values: Vec<String> = values.iter().map(i8::to_string).collect();
    format!("[{}]", values.join(", "))
}

fn static_name(name: &str) -> String {
    let mut static_name = String::new();
    for (index, character) in name.chars().enumerate() {
        if index > 0 && character.is_ascii_uppercase() {
            static_name.push('_');
        }
        static_name.push(character.to_ascii_uppercase());
    }
    static_name
}
