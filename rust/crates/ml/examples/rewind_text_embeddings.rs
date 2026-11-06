use std::fmt::Write as _;
use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, bail};
use ente_assets::AssetStore;
use ente_ml::assets::ensure_clip_text;
use ente_ml::indexing::{RunClipTextRequest, run_clip_text, set_kleidiai_enabled};

const ASSET_CACHE: &str = "../../.cache/assets";
const OUTPUT: &str = "../photos/src/rewind/queries.rs";
const DIMENSIONS: usize = 512;
const I8_LIMIT: f32 = 127.0;
const COLOURS: [(&str, &str); 10] = [
    (
        "CherryBomb",
        "Photo in which deep red is the dominant color",
    ),
    (
        "TangerinePop",
        "Photo in which bright orange is the dominant color",
    ),
    (
        "LemonDrop",
        "Photo in which sunny yellow is the dominant color",
    ),
    ("Pistachio", "Photo in which green is the dominant color"),
    ("BerryBlue", "Photo in which blue is the dominant color"),
    (
        "LavenderFizz",
        "Photo in which purple is the dominant color",
    ),
    ("Bubblegum", "Photo in which pink is the dominant color"),
    ("HotCocoa", "Photo in which brown is the dominant color"),
    ("Marshmallow", "Photo in which white is the dominant color"),
    ("MidnightCola", "Photo in which black is the dominant color"),
];
const SUBJECTS: [(&str, &str); 13] = [
    (
        "GoldenHour",
        "Photo taken at golden hour, bathed in warm low sunlight",
    ),
    ("Pets", "Photo of cute pets"),
    ("Food", "Photo of delicious looking food"),
    ("Plants", "Photo of houseplants, potted plants or a garden"),
    (
        "Architecture",
        "Photo showcasing striking architectural design or landmark",
    ),
    ("Indoors", "Photo taken indoors, inside a room"),
    ("Outdoors", "Photo taken outdoors, in the open air"),
    (
        "SportsAction",
        "Photo of thrilling sports action frozen in motion",
    ),
    (
        "Concerts",
        "Photo of a live concert, music performance, or crowd under stage lights",
    ),
    ("Parties", "Photo of people celebrating together"),
    (
        "Festivities",
        "Photo capturing a joyful celebration or festival",
    ),
    ("Outfits", "Mirror selfie showing off an outfit"),
    (
        "Artwork",
        "Photo of paintings, sculptures or artwork in a museum or gallery",
    ),
];

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    std::env::var_os("ORT_DYLIB_PATH").context("set ORT_DYLIB_PATH to an ONNX Runtime library")?;
    set_kleidiai_enabled(false);
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let cache = manifest_dir.join(ASSET_CACHE);
    let paths = ensure_clip_text(&AssetStore::new(cache.clone()), &cache).await?;
    let embed_all = |queries: &[(&'static str, &str)]| -> Result<Vec<(&'static str, Vec<i8>)>> {
        queries
            .iter()
            .map(|(name, query)| {
                let result = run_clip_text(RunClipTextRequest {
                    text: (*query).to_owned(),
                    model_path: paths.model.to_string_lossy().into_owned(),
                    vocab_path: paths.vocab.to_string_lossy().into_owned(),
                })
                .with_context(|| format!("embed {query:?}"))?;
                let embedding =
                    quantize(&result.embedding).with_context(|| format!("quantize {query:?}"))?;
                Ok((*name, embedding))
            })
            .collect()
    };
    let colours = embed_all(&COLOURS)?;
    let subjects = embed_all(&SUBJECTS)?;
    write_source(&manifest_dir.join(OUTPUT), render(&colours, &subjects)?)
}

fn write_source(path: &Path, source: String) -> Result<()> {
    std::fs::write(path, source).with_context(|| format!("write {}", path.display()))?;
    let rustfmt = Command::new("rustfmt")
        .args(["--edition", "2024"])
        .arg(path)
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

fn render(colours: &[(&str, Vec<i8>)], subjects: &[(&str, Vec<i8>)]) -> Result<String> {
    let mut source = String::from(
        "use super::clip::Subject;\n\
         use super::report::RewindColour;\n\
         use crate::ml_db::CLIP_EMBEDDING_DIMENSIONS;\n\n\
         pub(super) type TextEmbedding = [i8; CLIP_EMBEDDING_DIMENSIONS];\n\n",
    );
    render_embedding_lookup(&mut source, "RewindColour", colours)?;
    source.push('\n');
    render_embedding_lookup(&mut source, "Subject", subjects)?;
    for (name, embedding) in colours.iter().chain(subjects) {
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
