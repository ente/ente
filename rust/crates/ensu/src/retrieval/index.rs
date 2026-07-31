use std::cmp::{Ordering, Reverse};
use std::collections::{BTreeMap, BinaryHeap};
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;

use memmap2::{Mmap, MmapOptions};
use serde::Deserialize;
use url::Url;

use crate::config::{
    KNOWLEDGE_MANIFEST_FILE, KNOWLEDGE_META_FILE, KNOWLEDGE_OFFSETS_FILE, KNOWLEDGE_VECTORS_FILE,
    KnowledgeDatasetConfig, is_path_safe_component, knowledge_index_contract,
};

use super::{BEGIN_CONTEXT_SENTINEL, END_CONTEXT_SENTINEL, RetrievalError, normalize_single_line};

const MAX_MANIFEST_BYTES: u64 = 1_048_576;
const MAX_METADATA_FRAME_BYTES: u64 = 1_048_576;
#[derive(Debug, Clone, PartialEq)]
pub struct RetrievalHit {
    pub score: f32,
    pub text: String,
    pub title: String,
    pub section: Option<String>,
    pub source_url: String,
}

#[derive(Debug, Deserialize)]
struct Manifest {
    dataset: String,
    max_chars: u32,
    model: String,
    source_dim: u32,
    matryoshka: bool,
    doc_prompt: String,
    query_prompt: String,
    dim: u32,
    count: u64,
    quant: String,
    scale: u32,
    meta_codec: String,
    meta_rows_per_block: u64,
    url_template: String,
}

#[derive(Debug, Deserialize)]
struct MetadataRow {
    title: String,
    text: String,
    #[serde(default)]
    section: Option<String>,
}

pub struct RetrievalIndex {
    dataset_identity: String,
    count: usize,
    dim: usize,
    scale: f32,
    rows_per_block: usize,
    max_chars: usize,
    url_template: String,
    vectors: Mmap,
    metadata: Mmap,
    offsets: Vec<u64>,
}

impl RetrievalIndex {
    pub fn open(
        directory: impl AsRef<Path>,
        expected_pack: &KnowledgeDatasetConfig,
    ) -> Result<Self, RetrievalError> {
        let directory = directory.as_ref();
        let directory_metadata = fs::symlink_metadata(directory)?;
        if !directory_metadata.file_type().is_dir() {
            return Err(RetrievalError::InvalidPack(
                "revision path must be a directory, not a symlink".to_string(),
            ));
        }
        let directory_identity = directory
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| {
                RetrievalError::InvalidPack(
                    "revision directory must have a UTF-8 identity".to_string(),
                )
            })?;
        if !is_path_safe_component(directory_identity) {
            return Err(RetrievalError::InvalidPack(
                "revision directory identity is not path-safe".to_string(),
            ));
        }

        let manifest_path = directory.join(KNOWLEDGE_MANIFEST_FILE);
        let manifest_metadata = regular_file_metadata(&manifest_path)?;
        if manifest_metadata.len() == 0 || manifest_metadata.len() > MAX_MANIFEST_BYTES {
            return Err(RetrievalError::InvalidPack(
                "manifest size is outside the supported range".to_string(),
            ));
        }
        let manifest: Manifest = serde_json::from_slice(&fs::read(&manifest_path)?)?;
        validate_manifest(&manifest, directory_identity, expected_pack)?;

        let count = usize::try_from(manifest.count).map_err(|_| {
            RetrievalError::InvalidPack("manifest count does not fit this platform".to_string())
        })?;
        let dim = usize::try_from(manifest.dim).map_err(|_| {
            RetrievalError::InvalidPack("manifest dim does not fit this platform".to_string())
        })?;
        let rows_per_block = usize::try_from(manifest.meta_rows_per_block).map_err(|_| {
            RetrievalError::InvalidPack(
                "metadata rows per block does not fit this platform".to_string(),
            )
        })?;
        let expected_vector_bytes = count.checked_mul(dim).ok_or_else(|| {
            RetrievalError::InvalidPack("vector byte length overflow".to_string())
        })?;
        let vector_path = directory.join(KNOWLEDGE_VECTORS_FILE);
        let vector_file = open_regular_file(&vector_path)?;
        let vector_length = usize::try_from(vector_file.metadata()?.len()).map_err(|_| {
            RetrievalError::InvalidPack("vector file is too large for this platform".to_string())
        })?;
        if vector_length != expected_vector_bytes {
            return Err(RetrievalError::InvalidPack(format!(
                "vector file has {vector_length} bytes; expected {expected_vector_bytes}"
            )));
        }

        let metadata_path = directory.join(KNOWLEDGE_META_FILE);
        let metadata_file = open_regular_file(&metadata_path)?;
        let metadata_len = metadata_file.metadata()?.len();
        if metadata_len == 0 {
            return Err(RetrievalError::InvalidPack(
                "metadata file must not be empty".to_string(),
            ));
        }

        let block_count = count.div_ceil(rows_per_block);
        let offset_count = block_count.checked_add(1).ok_or_else(|| {
            RetrievalError::InvalidPack("metadata offset count overflow".to_string())
        })?;
        let expected_offset_bytes = offset_count.checked_mul(8).ok_or_else(|| {
            RetrievalError::InvalidPack("metadata offset byte length overflow".to_string())
        })?;
        let offsets_path = directory.join(KNOWLEDGE_OFFSETS_FILE);
        let offset_metadata = regular_file_metadata(&offsets_path)?;
        let offset_bytes = usize::try_from(offset_metadata.len()).map_err(|_| {
            RetrievalError::InvalidPack("metadata offsets are too large".to_string())
        })?;
        if offset_bytes != expected_offset_bytes {
            return Err(RetrievalError::InvalidPack(format!(
                "metadata offsets have {offset_bytes} bytes; expected {expected_offset_bytes}"
            )));
        }
        let offsets_raw = fs::read(&offsets_path)?;
        let offsets = offsets_raw
            .chunks_exact(8)
            .map(|chunk| u64::from_le_bytes(chunk.try_into().expect("eight-byte chunk")))
            .collect::<Vec<_>>();
        validate_offsets(&offsets, metadata_len)?;

        // Knowledge-pack revisions are immutable while an index is open. Native callers
        // synchronize swaps/deletion around this object, satisfying mmap's safety contract.
        let vectors = unsafe { MmapOptions::new().map(&vector_file)? };
        let metadata = unsafe { MmapOptions::new().map(&metadata_file)? };

        Ok(Self {
            dataset_identity: manifest.dataset,
            count,
            dim,
            scale: manifest.scale as f32,
            rows_per_block,
            max_chars: expected_pack.max_chars as usize,
            url_template: manifest.url_template,
            vectors,
            metadata,
            offsets,
        })
    }

    pub fn dataset_identity(&self) -> &str {
        &self.dataset_identity
    }

    pub fn search(
        &self,
        query: &[f32],
        max_hits: u32,
        threshold: f32,
    ) -> Result<Vec<RetrievalHit>, RetrievalError> {
        if query.len() != self.dim {
            return Err(RetrievalError::InvalidInput(format!(
                "query has {} dimensions; expected {}",
                query.len(),
                self.dim
            )));
        }
        if query.iter().any(|component| !component.is_finite()) {
            return Err(RetrievalError::InvalidInput(
                "query contains a non-finite component".to_string(),
            ));
        }
        if !threshold.is_finite() || !(0.0..=1.0).contains(&threshold) {
            return Err(RetrievalError::InvalidInput(
                "threshold must be finite and between 0 and 1".to_string(),
            ));
        }
        let max_hits = usize::try_from(max_hits).map_err(|_| {
            RetrievalError::InvalidInput("max_hits does not fit this platform".to_string())
        })?;
        if max_hits == 0 {
            return Ok(Vec::new());
        }
        let max_hits = max_hits.min(self.count);

        let mut heap = BinaryHeap::<Reverse<RankedRow>>::with_capacity(max_hits);
        for row in 0..self.count {
            let start = row * self.dim;
            let vector = &self.vectors[start..start + self.dim];
            let dot = query
                .iter()
                .zip(vector)
                .map(|(query_component, document_component)| {
                    *query_component * f32::from(*document_component as i8)
                })
                .sum::<f32>();
            let score = dot / self.scale;
            if !score.is_finite() || score < threshold {
                continue;
            }
            let candidate = RankedRow { score, row };
            if heap.len() < max_hits {
                heap.push(Reverse(candidate));
            } else if heap.peek().is_some_and(|worst| candidate > worst.0) {
                heap.pop();
                heap.push(Reverse(candidate));
            }
        }

        let mut ranked = heap
            .into_iter()
            .map(|Reverse(candidate)| candidate)
            .collect::<Vec<_>>();
        ranked.sort_unstable_by(|left, right| right.cmp(left));
        self.load_hits(&ranked)
    }

    fn load_hits(&self, ranked: &[RankedRow]) -> Result<Vec<RetrievalHit>, RetrievalError> {
        let mut by_block = BTreeMap::<usize, Vec<(usize, RankedRow)>>::new();
        for (rank, selected) in ranked.iter().copied().enumerate() {
            by_block
                .entry(selected.row / self.rows_per_block)
                .or_default()
                .push((rank, selected));
        }

        let mut hits = vec![None; ranked.len()];
        for (block, selected_rows) in by_block {
            let lines = self.decompress_block(block)?;
            for (rank, selected) in selected_rows {
                let row_in_block = selected.row % self.rows_per_block;
                let line = lines.get(row_in_block).ok_or_else(|| {
                    RetrievalError::InvalidPack(format!(
                        "metadata block {block} is missing row {row_in_block}"
                    ))
                })?;
                let row: MetadataRow = serde_json::from_str(line)?;
                if row.title.trim().is_empty() {
                    return Err(RetrievalError::InvalidPack(
                        "metadata title must not be empty".to_string(),
                    ));
                }
                if row.text.chars().count() > self.max_chars {
                    return Err(RetrievalError::InvalidPack(format!(
                        "metadata passage exceeds max_chars {}",
                        self.max_chars
                    )));
                }

                let raw_section = row.section.filter(|section| !section.trim().is_empty());
                let source_url =
                    canonical_source_url(&self.url_template, &row.title, raw_section.as_deref())?;
                let title = normalize_single_line(&row.title);
                if title.is_empty() {
                    return Err(RetrievalError::InvalidPack(
                        "metadata title is empty after sanitation".to_string(),
                    ));
                }
                let section = raw_section
                    .as_deref()
                    .map(normalize_single_line)
                    .filter(|section| !section.is_empty());
                let text = sanitize_prompt_text(&row.text);
                if text.trim().is_empty() {
                    return Err(RetrievalError::InvalidPack(
                        "metadata passage must not be empty".to_string(),
                    ));
                }
                hits[rank] = Some(RetrievalHit {
                    score: selected.score,
                    text,
                    title,
                    section,
                    source_url,
                });
            }
        }

        hits.into_iter()
            .map(|hit| {
                hit.ok_or_else(|| {
                    RetrievalError::InvalidPack("selected metadata row was not loaded".to_string())
                })
            })
            .collect()
    }

    fn decompress_block(&self, block: usize) -> Result<Vec<String>, RetrievalError> {
        let start = usize::try_from(self.offsets[block]).map_err(|_| {
            RetrievalError::InvalidPack("metadata frame start is too large".to_string())
        })?;
        let end = usize::try_from(self.offsets[block + 1]).map_err(|_| {
            RetrievalError::InvalidPack("metadata frame end is too large".to_string())
        })?;
        let frame = &self.metadata[start..end];
        let decoder = zstd::stream::read::Decoder::new(frame)
            .map_err(|error| RetrievalError::Zstd(error.to_string()))?;
        let mut capped = decoder.take(MAX_METADATA_FRAME_BYTES + 1);
        let mut decoded = Vec::new();
        capped
            .read_to_end(&mut decoded)
            .map_err(|error| RetrievalError::Zstd(error.to_string()))?;
        if decoded.len() as u64 > MAX_METADATA_FRAME_BYTES {
            return Err(RetrievalError::InvalidPack(
                "decompressed metadata frame exceeds 1 MiB".to_string(),
            ));
        }
        let decoded = String::from_utf8(decoded).map_err(|error| {
            RetrievalError::InvalidPack(format!("metadata frame is not UTF-8: {error}"))
        })?;
        let lines = decoded.lines().map(str::to_owned).collect::<Vec<_>>();
        if lines.iter().any(|line| line.trim().is_empty()) {
            return Err(RetrievalError::InvalidPack(format!(
                "metadata block {block} contains an empty row"
            )));
        }
        let block_start = block.checked_mul(self.rows_per_block).ok_or_else(|| {
            RetrievalError::InvalidPack("metadata block row overflow".to_string())
        })?;
        let expected_rows = self.rows_per_block.min(self.count - block_start);
        if lines.len() != expected_rows {
            return Err(RetrievalError::InvalidPack(format!(
                "metadata block {block} has {} rows; expected {expected_rows}",
                lines.len()
            )));
        }
        Ok(lines)
    }
}

#[derive(Debug, Clone, Copy)]
struct RankedRow {
    score: f32,
    row: usize,
}

impl PartialEq for RankedRow {
    fn eq(&self, other: &Self) -> bool {
        self.score.total_cmp(&other.score) == Ordering::Equal && self.row == other.row
    }
}

impl Eq for RankedRow {}

impl PartialOrd for RankedRow {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for RankedRow {
    fn cmp(&self, other: &Self) -> Ordering {
        self.score
            .total_cmp(&other.score)
            .then_with(|| other.row.cmp(&self.row))
    }
}

fn validate_manifest(
    manifest: &Manifest,
    directory_identity: &str,
    expected_pack: &KnowledgeDatasetConfig,
) -> Result<(), RetrievalError> {
    if !is_path_safe_component(&manifest.dataset) || manifest.dataset != directory_identity {
        return Err(RetrievalError::InvalidPack(
            "manifest dataset must equal its path-safe revision directory".to_string(),
        ));
    }
    if manifest.count == 0 || manifest.dim == 0 || manifest.meta_rows_per_block == 0 {
        return Err(RetrievalError::InvalidPack(
            "manifest count, dim, and metadata rows per block must be positive".to_string(),
        ));
    }

    let contract = knowledge_index_contract();
    let matches = manifest.max_chars == expected_pack.max_chars
        && manifest.model == contract.model
        && manifest.source_dim == contract.source_dim
        && manifest.matryoshka == contract.matryoshka
        && manifest.doc_prompt == contract.doc_prompt
        && manifest.query_prompt == contract.query_prompt
        && manifest.dim == contract.dim
        && manifest.quant == contract.quant
        && manifest.scale == contract.scale
        && manifest.meta_codec == contract.meta_codec
        && manifest.meta_rows_per_block == u64::from(contract.meta_rows_per_block)
        && manifest.url_template == expected_pack.source_url_template;
    if !matches {
        return Err(RetrievalError::InvalidPack(
            "manifest does not match the selected dataset and v1 index contract".to_string(),
        ));
    }
    Ok(())
}

fn validate_offsets(offsets: &[u64], metadata_len: u64) -> Result<(), RetrievalError> {
    if offsets.first() != Some(&0) {
        return Err(RetrievalError::InvalidPack(
            "first metadata offset must be zero".to_string(),
        ));
    }
    if offsets
        .windows(2)
        .any(|window| window[0] >= window[1] || window[1] > metadata_len)
    {
        return Err(RetrievalError::InvalidPack(
            "metadata offsets must be strictly increasing and in bounds".to_string(),
        ));
    }
    if offsets.last() != Some(&metadata_len) {
        return Err(RetrievalError::InvalidPack(
            "final metadata offset must equal metadata size".to_string(),
        ));
    }
    Ok(())
}

fn regular_file_metadata(path: &Path) -> Result<fs::Metadata, RetrievalError> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_file() {
        return Err(RetrievalError::InvalidPack(format!(
            "{} must be a regular file",
            path.display()
        )));
    }
    Ok(metadata)
}

fn open_regular_file(path: &Path) -> Result<File, RetrievalError> {
    regular_file_metadata(path)?;
    Ok(File::open(path)?)
}

fn canonical_source_url(
    template: &str,
    title: &str,
    section: Option<&str>,
) -> Result<String, RetrievalError> {
    let encoded_title = python_quote(&title.replace(' ', "_"));
    let mut source_url = template.replacen("{title}", &encoded_title, 1);
    if let Some(section) = section.filter(|section| !section.trim().is_empty()) {
        source_url.push('#');
        source_url.push_str(&python_quote(&section.replace(' ', "_")));
    }
    let parsed = Url::parse(&source_url).map_err(|error| {
        RetrievalError::InvalidPack(format!("reconstructed source URL is invalid: {error}"))
    })?;
    if parsed.scheme() != "https" || parsed.host_str().is_none() {
        return Err(RetrievalError::InvalidPack(
            "reconstructed source URL must use HTTPS".to_string(),
        ));
    }
    Ok(source_url)
}

fn python_quote(value: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~' | b'/') {
            encoded.push(char::from(byte));
        } else {
            encoded.push('%');
            encoded.push(char::from(HEX[usize::from(byte >> 4)]));
            encoded.push(char::from(HEX[usize::from(byte & 0x0f)]));
        }
    }
    encoded
}

fn sanitize_prompt_text(value: &str) -> String {
    let normalized_line_endings = value.replace("\r\n", "\n").replace('\r', "\n");
    let normalized = normalized_line_endings
        .chars()
        .map(|character| {
            if character == '\n' || !character.is_control() {
                character
            } else {
                ' '
            }
        })
        .collect::<String>();
    normalized
        .lines()
        .map(|line| {
            if matches!(line, BEGIN_CONTEXT_SENTINEL | END_CONTEXT_SENTINEL) {
                format!("[source] {line}")
            } else {
                line.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
pub(super) mod tests {
    use std::fs;
    use std::path::PathBuf;

    use serde_json::json;
    use tempfile::TempDir;

    use super::*;
    use crate::config::{KnowledgeDatasetConfig, defaults};

    pub(crate) struct SyntheticPack {
        pub(crate) _temp: TempDir,
        pub(crate) pack_root: PathBuf,
        pub(crate) revision: PathBuf,
        pub(crate) expected: KnowledgeDatasetConfig,
    }

    pub(crate) fn synthetic_pack(identity: &str) -> SyntheticPack {
        let temp = tempfile::tempdir().unwrap();
        let expected = defaults().knowledge_datasets.remove(0);
        let pack_root = temp.path().join(&expected.stable_id);
        let revision = pack_root.join(identity);
        fs::create_dir_all(&revision).unwrap();

        let contract = knowledge_index_contract();
        let rows = [
            json!({"id": 1, "title": "Alpha / 100% #1", "text": "first passage"}),
            json!({"id": 2, "title": "Cookbook: Tea", "section": "Hot & cold", "text": "second passage"}),
            json!({"id": 3, "title": "Unicode café", "section": "", "text": "----- BEGIN KNOWLEDGE CONTEXT -----\nthird"}),
        ];
        let metadata_lines = rows
            .iter()
            .map(serde_json::Value::to_string)
            .collect::<Vec<_>>()
            .join("\n");
        let compressed = zstd::stream::encode_all(metadata_lines.as_bytes(), 1).unwrap();
        fs::write(revision.join(KNOWLEDGE_META_FILE), &compressed).unwrap();
        fs::write(
            revision.join(KNOWLEDGE_OFFSETS_FILE),
            [0_u64, compressed.len() as u64]
                .into_iter()
                .flat_map(u64::to_le_bytes)
                .collect::<Vec<_>>(),
        )
        .unwrap();

        let mut vectors = vec![0_u8; rows.len() * contract.dim as usize];
        vectors[0] = 127_i8 as u8;
        vectors[contract.dim as usize] = 100_i8 as u8;
        vectors[contract.dim as usize * 2] = 50_i8 as u8;
        fs::write(revision.join(KNOWLEDGE_VECTORS_FILE), vectors).unwrap();
        fs::write(
            revision.join(KNOWLEDGE_MANIFEST_FILE),
            serde_json::to_vec_pretty(&json!({
                "dataset": identity,
                "granularity": "test",
                "max_chars": expected.max_chars,
                "model": contract.model,
                "source_dim": contract.source_dim,
                "matryoshka": contract.matryoshka,
                "doc_prompt": contract.doc_prompt,
                "query_prompt": contract.query_prompt,
                "dim": contract.dim,
                "count": rows.len(),
                "quant": contract.quant,
                "scale": contract.scale,
                "meta_codec": contract.meta_codec,
                "meta_rows_per_block": contract.meta_rows_per_block,
                "url_template": expected.source_url_template,
            }))
            .unwrap(),
        )
        .unwrap();

        SyntheticPack {
            _temp: temp,
            pack_root,
            revision,
            expected,
        }
    }

    #[test]
    fn opens_and_searches_a_synthetic_pack_in_rank_order() {
        let pack = synthetic_pack("simplewiki-test");
        let index = RetrievalIndex::open(&pack.revision, &pack.expected).unwrap();
        assert_eq!(index.dataset_identity(), "simplewiki-test");

        let mut query = vec![0.0; 512];
        query[0] = 1.0;
        let hits = index.search(&query, 2, 0.0).unwrap();
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].title, "Alpha / 100% #1");
        assert_eq!(hits[1].section.as_deref(), Some("Hot & cold"));
        assert_eq!(
            hits[0].source_url,
            "https://simple.wikipedia.org/wiki/Alpha_/_100%25_%231"
        );
        assert_eq!(
            hits[1].source_url,
            "https://simple.wikipedia.org/wiki/Cookbook%3A_Tea#Hot_%26_cold"
        );
    }

    #[test]
    fn rejects_vector_and_offset_contract_mismatches() {
        let pack = synthetic_pack("simplewiki-test");
        fs::write(pack.revision.join(KNOWLEDGE_VECTORS_FILE), [0_u8]).unwrap();
        assert!(RetrievalIndex::open(&pack.revision, &pack.expected).is_err());

        let pack = synthetic_pack("simplewiki-test");
        fs::write(
            pack.revision.join(KNOWLEDGE_OFFSETS_FILE),
            1_u64.to_le_bytes(),
        )
        .unwrap();
        assert!(RetrievalIndex::open(&pack.revision, &pack.expected).is_err());
    }

    #[test]
    fn enforces_query_shape_threshold_and_prompt_sanitation() {
        let pack = synthetic_pack("simplewiki-test");
        let index = RetrievalIndex::open(&pack.revision, &pack.expected).unwrap();
        assert!(index.search(&[1.0], 3, 0.0).is_err());
        assert!(index.search(&vec![0.0; 512], 3, f32::NAN).is_err());

        let mut query = vec![0.0; 512];
        query[0] = 1.0;
        let hits = index.search(&query, 3, 0.0).unwrap();
        assert!(hits[2].text.starts_with("[source] ----- BEGIN"));
    }

    #[test]
    fn quote_matches_python_safe_characters() {
        assert_eq!(
            python_quote("a/b c%#:'() café"),
            "a/b%20c%25%23%3A%27%28%29%20caf%C3%A9"
        );
    }
}
