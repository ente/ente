use std::{
    collections::{BTreeSet, HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use ente_model_download::download;
use ente_photos::ml::{
    error::MlError,
    indexing::{
        AnalyzeImageRequest, AnalyzeImageResult, analyze_image, init_ml_runtime, release_ml_runtime,
    },
    runtime::ModelPaths,
    types::FaceResult as RustFaceResult,
};
use flate2::read::GzDecoder;
use serde::Deserialize;
use url::Url;

const ASSET_LOCK_PATH: &str = "infra/ml/test/ml_indexing/assets.json";
const CLIP_EMBEDDING_DIM: usize = 512;
const FACE_EMBEDDING_DIM: usize = 192;
const FLOAT_TOLERANCE: f64 = 1e-8;
const PRINT_STATS_ENV: &str = "ENTE_ML_INDEXING_PRINT_STATS";

pub(crate) fn run_with_large_stack(name: &str, test: fn() -> Result<()>) {
    let result = std::thread::Builder::new()
        .name(name.to_string())
        .stack_size(64 * 1024 * 1024)
        .spawn(test)
        .expect("spawn ML indexing test thread")
        .join();

    match result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => panic!("{error:#}"),
        Err(panic) => std::panic::resume_unwind(panic),
    }
}

pub(crate) fn fail_if_any(mut failures: Vec<String>, stats: &ComparisonStats) -> Result<()> {
    if failures.is_empty() {
        return Ok(());
    }

    failures.sort();
    let mut message = format!(
        "Rust ML indexing test failed with {} finding(s):\n{}",
        failures.len(),
        failures.join("\n")
    );
    if stats.has_observations() {
        message.push_str("\n\n");
        message.push_str(&stats.format_report());
    }

    bail!("{message}");
}

#[derive(Default)]
pub(crate) struct ComparisonStats {
    files_compared: usize,
    faces_compared: usize,
    clip_cosine_distance: MetricStats,
    face_box_iou_error: MetricStats,
    face_embedding_cosine_distance: MetricStats,
    landmark_error: MetricStats,
    score_delta: MetricStats,
}

impl ComparisonStats {
    pub(crate) fn print_if_requested(&self) {
        if should_print_stats() {
            println!("{}", self.format_report());
        }
    }

    fn record_file(&mut self) {
        self.files_compared += 1;
    }

    fn record_face(&mut self) {
        self.faces_compared += 1;
    }

    fn has_observations(&self) -> bool {
        self.files_compared > 0
    }

    fn format_report(&self) -> String {
        [
            "ML indexing Python comparison summary:".to_string(),
            format!(
                "files_compared={} faces_compared={}",
                self.files_compared, self.faces_compared
            ),
            self.clip_cosine_distance
                .format_line("clip_cosine_distance"),
            self.face_box_iou_error.format_line("face_box_iou_error"),
            self.face_embedding_cosine_distance
                .format_line("face_embedding_cosine_distance"),
            self.landmark_error.format_line("landmark_error"),
            self.score_delta.format_line("score_delta"),
        ]
        .join("\n")
    }
}

#[derive(Default)]
struct MetricStats {
    count: usize,
    max: Option<MetricObservation>,
    threshold: Option<f64>,
}

impl MetricStats {
    fn record(&mut self, file_id: &str, value: f64, threshold: f64) {
        self.count += 1;
        self.threshold = Some(threshold);
        let should_replace = match &self.max {
            Some(observation) => value > observation.value,
            None => true,
        };
        if should_replace {
            self.max = Some(MetricObservation {
                file_id: file_id.to_owned(),
                value,
            });
        }
    }

    fn format_line(&self, name: &str) -> String {
        let threshold = self
            .threshold
            .map(|value| format!("{value:.15}"))
            .unwrap_or_else(|| "n/a".to_string());
        match &self.max {
            Some(max) => format!(
                "{name}: count={} max={:.15} file={} threshold={}",
                self.count, max.value, max.file_id, threshold
            ),
            None => format!("{name}: count=0 max=n/a file=n/a threshold={threshold}"),
        }
    }
}

struct MetricObservation {
    file_id: String,
    value: f64,
}

fn should_print_stats() -> bool {
    let Ok(value) = std::env::var(PRINT_STATS_ENV) else {
        return false;
    };
    let value = value.trim();
    !(value.is_empty()
        || value == "0"
        || value.eq_ignore_ascii_case("false")
        || value.eq_ignore_ascii_case("no"))
}

pub(crate) struct MlIndexingTestContext {
    asset_lock: AssetLock,
    cache_dir: PathBuf,
    golden_results: HashMap<String, ComparableResult>,
    manifest: FixtureManifest,
    model_paths: ModelPaths,
}

struct AssetFetcher {
    runtime: tokio::runtime::Runtime,
    downloader: download::Downloader,
}

impl AssetFetcher {
    fn new() -> Result<Self> {
        Ok(Self {
            runtime: tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .context("build download runtime")?,
            downloader: download::Downloader::new().context("build downloader")?,
        })
    }

    fn fetch(&self, targets: Vec<download::Target>) -> Result<()> {
        self.runtime.block_on(self.downloader.download(
            targets,
            |_| {},
            download::CancellationToken::default(),
        ))?;
        Ok(())
    }
}

impl MlIndexingTestContext {
    pub(crate) fn load() -> Result<Self> {
        let repo_root = repo_root()?;
        let asset_lock = load_asset_lock(&repo_root)?;
        let cache_dir = cache_dir(&repo_root);
        let fetcher = AssetFetcher::new()?;

        let manifest_path =
            resolve_document_asset(&fetcher, &cache_dir, "manifest", &asset_lock.manifest)?;
        let golden_path = resolve_document_asset(
            &fetcher,
            &cache_dir,
            "python-golden",
            &asset_lock.python_golden,
        )?;
        let manifest = load_manifest(&manifest_path)?;
        let golden_results = load_golden_results(&golden_path)?;
        fetch_fixtures(
            &fetcher,
            &cache_dir,
            &asset_lock.fixture_base_url,
            &manifest,
        )?;

        let onnx_runtime_library =
            resolve_onnx_runtime_library(&fetcher, &cache_dir, &asset_lock.onnx_runtime)?;
        let _ = ort::init_from(&onnx_runtime_library)
            .context("load ONNX Runtime dynamic library")?
            .commit();

        let model_paths = resolve_model_paths(&fetcher, &cache_dir, &asset_lock.models)?;

        Ok(Self {
            asset_lock,
            cache_dir,
            golden_results,
            manifest,
            model_paths,
        })
    }

    pub(crate) fn prepare_runtime(&self) -> PreparedMlRuntime {
        init_ml_runtime(self.model_paths.clone());
        PreparedMlRuntime {
            model_paths: self.model_paths.clone(),
        }
    }

    pub(crate) fn validate_manifest_expectations(&self) -> Result<Vec<String>> {
        let mut failures = Vec::new();
        let manifest_ids = self.manifest_file_ids()?;
        for file_id in self.unsupported_decode_file_ids() {
            if !manifest_ids.contains(&file_id) {
                failures.push(format!(
                    "{file_id}: expected unsupported decode entry is not present in manifest"
                ));
            }
        }
        Ok(failures)
    }

    pub(crate) fn run_rust_indexing(
        &self,
        runtime: &PreparedMlRuntime,
        failures: &mut Vec<String>,
    ) -> Result<HashMap<String, ComparableResult>> {
        let expected_unsupported = self.unsupported_decode_file_ids();
        let mut rust_results = HashMap::new();

        for (index, fixture) in self.manifest.files.iter().enumerate() {
            let file_id = file_id_for_manifest_path(&fixture.path)?;
            let image_path = match self.resolve_fixture(fixture) {
                Ok(path) => path,
                Err(error) => {
                    failures.push(format!("{file_id}: failed to resolve fixture: {error:#}"));
                    continue;
                }
            };
            let req = AnalyzeImageRequest {
                file_id: (index + 1) as i64,
                image_path: image_path.to_string_lossy().into_owned(),
                run_faces: true,
                run_clip: true,
                run_pets: false,
                model_paths: runtime.model_paths().clone(),
            };

            if expected_unsupported.contains(&file_id) {
                expect_decode_error(&file_id, req, failures);
                continue;
            }

            match analyze_image(req) {
                Ok(result) => match comparable_from_rust(&file_id, &result) {
                    Ok(comparable) => {
                        if rust_results.insert(file_id.clone(), comparable).is_some() {
                            failures.push(format!("{file_id}: duplicate Rust result"));
                        }
                    }
                    Err(error) => {
                        failures.push(format!("{file_id}: invalid Rust result: {error:#}"))
                    }
                },
                Err(error) => failures.push(format!("{file_id}: Rust ML indexing failed: {error}")),
            }
        }

        Ok(rust_results)
    }

    pub(crate) fn compare_with_python_goldens(
        &self,
        rust_results: &HashMap<String, ComparableResult>,
        failures: &mut Vec<String>,
        stats: &mut ComparisonStats,
    ) -> Result<()> {
        let expected_unsupported = self.unsupported_decode_file_ids();
        let supported_manifest_ids = self
            .manifest_file_ids()?
            .into_iter()
            .filter(|file_id| !expected_unsupported.contains(file_id))
            .collect::<BTreeSet<_>>();

        for file_id in &supported_manifest_ids {
            if !self.golden_results.contains_key(file_id) {
                failures.push(format!("{file_id}: missing from Python golden"));
            }
            if !rust_results.contains_key(file_id) {
                failures.push(format!("{file_id}: missing from Rust results"));
            }
        }

        for file_id in self.golden_results.keys() {
            if !supported_manifest_ids.contains(file_id) && !expected_unsupported.contains(file_id)
            {
                failures.push(format!(
                    "{file_id}: Python golden is not present in manifest"
                ));
            }
        }

        for file_id in &supported_manifest_ids {
            let Some(golden) = self.golden_results.get(file_id) else {
                continue;
            };
            let Some(rust) = rust_results.get(file_id) else {
                continue;
            };
            compare_results(
                file_id,
                golden,
                rust,
                &self.asset_lock.thresholds,
                failures,
                stats,
            );
        }

        Ok(())
    }

    fn manifest_file_ids(&self) -> Result<BTreeSet<String>> {
        let mut ids = BTreeSet::new();
        for file in &self.manifest.files {
            let file_id = file_id_for_manifest_path(&file.path)?;
            if !ids.insert(file_id.clone()) {
                bail!("manifest has duplicate file id: {file_id}");
            }
        }
        Ok(ids)
    }

    fn resolve_fixture(&self, fixture: &FixtureFile) -> Result<PathBuf> {
        cache_path_for(&self.cache_dir, "fixtures", &fixture.path, &fixture.sha256)
    }

    fn unsupported_decode_file_ids(&self) -> HashSet<String> {
        self.asset_lock
            .expected_unsupported_decode_file_ids
            .iter()
            .cloned()
            .collect()
    }
}

/// A downloaded production model together with its content hash as pinned in
/// the asset lock, for embedding into generated golden entries.
#[allow(dead_code)]
pub(crate) struct GoldenModelAsset {
    pub(crate) path: PathBuf,
    pub(crate) sha256: String,
}

/// Downloaded production model assets for the golden self-test tooling, with
/// ONNX Runtime already initialized. Used by the ml_goldens developer tool only.
#[allow(dead_code)]
pub(crate) struct GoldenTestAssets {
    pub(crate) face_detection: GoldenModelAsset,
    pub(crate) face_embedding: GoldenModelAsset,
    pub(crate) clip_image: GoldenModelAsset,
    pub(crate) clip_text: GoldenModelAsset,
    pub(crate) clip_text_vocab: PathBuf,
}

#[allow(dead_code)]
impl GoldenTestAssets {
    pub(crate) fn load() -> Result<Self> {
        let repo_root = repo_root()?;
        let asset_lock = load_asset_lock(&repo_root)?;
        let cache_dir = cache_dir(&repo_root);
        let fetcher = AssetFetcher::new()?;

        let onnx_runtime_library =
            resolve_onnx_runtime_library(&fetcher, &cache_dir, &asset_lock.onnx_runtime)?;
        let _ = ort::init_from(&onnx_runtime_library)
            .context("load ONNX Runtime dynamic library")?
            .commit();

        let golden_model = |label: &str, model: &ModelAsset| -> Result<GoldenModelAsset> {
            Ok(GoldenModelAsset {
                path: resolve_model_asset(&fetcher, &cache_dir, label, model)?,
                sha256: model.sha256.clone(),
            })
        };

        let models = &asset_lock.models;
        Ok(Self {
            face_detection: golden_model("face-detection", &models.face_detection)?,
            face_embedding: golden_model("face-embedding", &models.face_embedding)?,
            clip_image: golden_model("clip-image", &models.clip_image)?,
            clip_text: golden_model("clip-text", &models.clip_text)?,
            clip_text_vocab: resolve_model_asset(
                &fetcher,
                &cache_dir,
                "clip-text-vocab",
                &models.clip_text_vocab,
            )?,
        })
    }

    pub(crate) fn golden_data_path() -> Result<PathBuf> {
        Ok(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src/ml/golden_data.rs"))
    }
}

pub(crate) struct PreparedMlRuntime {
    model_paths: ModelPaths,
}

impl PreparedMlRuntime {
    fn model_paths(&self) -> &ModelPaths {
        &self.model_paths
    }
}

impl Drop for PreparedMlRuntime {
    fn drop(&mut self) {
        release_ml_runtime();
    }
}

#[derive(Debug, Deserialize)]
struct AssetLock {
    fixture_base_url: String,
    manifest: DocumentAsset,
    python_golden: DocumentAsset,
    onnx_runtime: OnnxRuntimeAssets,
    models: ModelAssets,
    expected_unsupported_decode_file_ids: Vec<String>,
    thresholds: Thresholds,
}

#[derive(Debug, Deserialize)]
struct DocumentAsset {
    path: String,
    url: String,
    sha256: String,
}

#[derive(Debug, Deserialize)]
struct OnnxRuntimeAssets {
    archives: HashMap<String, OnnxRuntimeArchive>,
}

#[derive(Debug, Deserialize)]
struct OnnxRuntimeArchive {
    url: String,
    sha256: String,
    library_path: String,
    library_sha256: String,
}

#[derive(Debug, Deserialize)]
struct ModelAssets {
    face_detection: ModelAsset,
    face_embedding: ModelAsset,
    clip_image: ModelAsset,
    // Used by the ml_goldens developer tool only.
    #[allow(dead_code)]
    clip_text: ModelAsset,
    #[allow(dead_code)]
    clip_text_vocab: ModelAsset,
}

#[derive(Debug, Deserialize)]
struct ModelAsset {
    file_name: String,
    url: String,
    sha256: String,
}

#[derive(Clone, Copy, Debug, Deserialize)]
struct Thresholds {
    clip_cosine_distance: f64,
    face_embedding_cosine_distance: f64,
    box_iou: f64,
    face_duplicate_iou: f64,
    face_match_iou_floor: f64,
    landmark_error: f64,
    score_delta: f64,
    min_face_score_for_comparison: f64,
    embedding_norm_tolerance: f64,
}

#[derive(Debug, Deserialize)]
struct FixtureManifest {
    files: Vec<FixtureFile>,
}

#[derive(Debug, Deserialize)]
struct FixtureFile {
    path: String,
    sha256: String,
}

#[derive(Clone, Debug, Deserialize)]
pub(crate) struct ComparableResult {
    file_id: String,
    clip: ComparableClip,
    faces: Vec<ComparableFace>,
}

#[derive(Clone, Debug, Deserialize)]
struct ComparableClip {
    embedding: Vec<f64>,
}

#[derive(Clone, Debug, Deserialize)]
struct ComparableFace {
    #[serde(rename = "box")]
    box_xywh: [f64; 4],
    landmarks: Vec<[f64; 2]>,
    score: f64,
    embedding: Vec<f64>,
}

fn repo_root() -> Result<PathBuf> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .context("resolve repository root from CARGO_MANIFEST_DIR")
}

fn cache_dir(repo_root: &Path) -> PathBuf {
    repo_root.join("rust/.cache")
}

fn load_asset_lock(repo_root: &Path) -> Result<AssetLock> {
    let path = repo_root.join(ASSET_LOCK_PATH);
    let payload =
        fs::read_to_string(&path).with_context(|| format!("read asset lock {}", path.display()))?;
    serde_json::from_str(&payload).with_context(|| format!("parse asset lock {}", path.display()))
}

fn load_manifest(path: &Path) -> Result<FixtureManifest> {
    let payload =
        fs::read_to_string(path).with_context(|| format!("read manifest {}", path.display()))?;
    let manifest: FixtureManifest = serde_json::from_str(&payload)
        .with_context(|| format!("parse manifest {}", path.display()))?;
    if manifest.files.is_empty() {
        bail!("manifest has no files: {}", path.display());
    }
    Ok(manifest)
}

fn load_golden_results(path: &Path) -> Result<HashMap<String, ComparableResult>> {
    let payload =
        fs::read_to_string(path).with_context(|| format!("read golden {}", path.display()))?;
    let document: ResultsDocument = serde_json::from_str(&payload)
        .with_context(|| format!("parse golden {}", path.display()))?;
    if document.results.is_empty() {
        bail!("golden has no results: {}", path.display());
    }

    let mut results = HashMap::new();
    for result in document.results {
        if results.insert(result.file_id.clone(), result).is_some() {
            bail!("Python golden has duplicate file_id");
        }
    }
    Ok(results)
}

#[derive(Clone, Debug, Deserialize)]
struct ResultsDocument {
    results: Vec<ComparableResult>,
}

fn file_id_for_manifest_path(path: &str) -> Result<String> {
    Path::new(path)
        .file_name()
        .and_then(|file_name| file_name.to_str())
        .map(ToOwned::to_owned)
        .with_context(|| format!("derive file_id from manifest path '{path}'"))
}

fn resolve_document_asset(
    fetcher: &AssetFetcher,
    cache_dir: &Path,
    label: &str,
    asset: &DocumentAsset,
) -> Result<PathBuf> {
    let target = cache_path_for(cache_dir, "documents", &asset.path, &asset.sha256)?;
    ensure_remote_asset(fetcher, &asset.url, &asset.sha256, &target, label)
}

fn fixture_url(fixture_base_url: &str, path: &str) -> Result<String> {
    Ok(Url::parse(fixture_base_url)
        .with_context(|| format!("parse fixture base URL '{fixture_base_url}'"))?
        .join(path)
        .with_context(|| format!("join fixture URL for {path}"))?
        .to_string())
}

fn fetch_fixtures(
    fetcher: &AssetFetcher,
    cache_dir: &Path,
    fixture_base_url: &str,
    manifest: &FixtureManifest,
) -> Result<()> {
    let targets = manifest
        .files
        .iter()
        .map(|fixture| {
            Ok(download::Target {
                label: file_id_for_manifest_path(&fixture.path)?,
                url: fixture_url(fixture_base_url, &fixture.path)?,
                sha256: normalize_sha256(&fixture.sha256),
                destination: cache_path_for(cache_dir, "fixtures", &fixture.path, &fixture.sha256)?,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    fetcher.fetch(targets).context("fetch fixtures")
}

fn resolve_onnx_runtime_library(
    fetcher: &AssetFetcher,
    cache_dir: &Path,
    assets: &OnnxRuntimeAssets,
) -> Result<PathBuf> {
    let target_key = onnx_runtime_target_key()?;
    let archive = assets.archives.get(&target_key).with_context(|| {
        let supported = assets
            .archives
            .keys()
            .map(String::as_str)
            .collect::<Vec<_>>()
            .join(", ");
        format!(
            "no ONNX Runtime asset for target '{target_key}' in {ASSET_LOCK_PATH}; supported: {supported}"
        )
    })?;

    let archive_name = url_file_name(&archive.url)?;
    let archive_path = cache_path_for(
        cache_dir,
        "onnx-runtime-archives",
        &archive_name,
        &archive.sha256,
    )?;
    let archive_path = ensure_remote_asset(
        fetcher,
        &archive.url,
        &archive.sha256,
        &archive_path,
        "onnx-runtime-archive",
    )?;

    let library_name = file_id_for_manifest_path(&archive.library_path)?;
    let library_cache_path = format!("{target_key}/{library_name}");
    let library_target = cache_path_for(
        cache_dir,
        "onnx-runtime-libraries",
        &library_cache_path,
        &archive.library_sha256,
    )?;
    if library_target.is_file() {
        verify_file_sha256(
            &library_target,
            &archive.library_sha256,
            "onnx-runtime-library",
        )?;
        return Ok(library_target);
    }

    extract_tgz_member(&archive_path, &archive.library_path, &library_target)
        .with_context(|| format!("extract ONNX Runtime library for {target_key}"))?;
    verify_file_sha256(
        &library_target,
        &archive.library_sha256,
        "onnx-runtime-library",
    )?;
    Ok(library_target)
}

fn onnx_runtime_target_key() -> Result<String> {
    onnx_runtime_target_key_for(std::env::consts::OS, std::env::consts::ARCH)
}

fn onnx_runtime_target_key_for(os: &str, arch: &str) -> Result<String> {
    match (os, arch) {
        ("linux", "x86_64") => Ok("x86_64-unknown-linux-gnu".to_string()),
        ("linux", "aarch64") => Ok("aarch64-unknown-linux-gnu".to_string()),
        ("macos", "aarch64") => Ok("aarch64-apple-darwin".to_string()),
        (os, arch) => bail!("unsupported ONNX Runtime target for ML indexing test: {arch}-{os}"),
    }
}

fn url_file_name(url: &str) -> Result<String> {
    Url::parse(url)
        .with_context(|| format!("parse asset URL '{url}'"))?
        .path_segments()
        .and_then(Iterator::last)
        .filter(|segment| !segment.is_empty())
        .map(ToOwned::to_owned)
        .with_context(|| format!("derive file name from URL '{url}'"))
}

fn extract_tgz_member(archive_path: &Path, member_path: &str, target: &Path) -> Result<()> {
    let expected_member = Path::new(member_path);
    if expected_member.is_absolute() {
        bail!("archive member path must be relative: {member_path}");
    }

    let parent = target
        .parent()
        .with_context(|| format!("resolve parent for {}", target.display()))?;
    fs::create_dir_all(parent)
        .with_context(|| format!("create cache directory {}", parent.display()))?;

    let archive_file = fs::File::open(archive_path)
        .with_context(|| format!("open archive {}", archive_path.display()))?;
    let decoder = GzDecoder::new(archive_file);
    let mut archive = tar::Archive::new(decoder);
    for entry in archive.entries().context("read tgz entries")? {
        let mut entry = entry.context("read tgz entry")?;
        let entry_path = entry.path().context("read tgz entry path")?;
        if entry_path.as_ref() != expected_member {
            continue;
        }
        entry
            .unpack(target)
            .with_context(|| format!("unpack {member_path} to {}", target.display()))?;
        return Ok(());
    }

    bail!(
        "archive {} did not contain expected member {member_path}",
        archive_path.display()
    );
}

fn resolve_model_paths(
    fetcher: &AssetFetcher,
    cache_dir: &Path,
    models: &ModelAssets,
) -> Result<ModelPaths> {
    let face_detection =
        resolve_model_asset(fetcher, cache_dir, "face-detection", &models.face_detection)?;
    let face_embedding =
        resolve_model_asset(fetcher, cache_dir, "face-embedding", &models.face_embedding)?;
    let clip_image = resolve_model_asset(fetcher, cache_dir, "clip-image", &models.clip_image)?;

    Ok(ModelPaths {
        face_detection: face_detection.to_string_lossy().into_owned(),
        face_embedding: face_embedding.to_string_lossy().into_owned(),
        clip_image: clip_image.to_string_lossy().into_owned(),
        clip_text: String::new(),
        pet_face_detection: String::new(),
        pet_face_embedding_dog: String::new(),
        pet_face_embedding_cat: String::new(),
        pet_body_detection: String::new(),
        pet_body_embedding_dog: String::new(),
        pet_body_embedding_cat: String::new(),
    })
}

fn resolve_model_asset(
    fetcher: &AssetFetcher,
    cache_dir: &Path,
    label: &str,
    asset: &ModelAsset,
) -> Result<PathBuf> {
    let target = cache_path_for(cache_dir, "models", &asset.file_name, &asset.sha256)?;
    ensure_remote_asset(fetcher, &asset.url, &asset.sha256, &target, label)
}

fn ensure_remote_asset(
    fetcher: &AssetFetcher,
    url: &str,
    expected_sha256: &str,
    target: &Path,
    label: &str,
) -> Result<PathBuf> {
    fetcher
        .fetch(vec![download::Target {
            label: label.to_string(),
            url: url.to_string(),
            sha256: normalize_sha256(expected_sha256),
            destination: target.to_path_buf(),
        }])
        .with_context(|| format!("download {label} from {url}"))?;
    Ok(target.to_path_buf())
}

fn cache_path_for(
    cache_dir: &Path,
    namespace: &str,
    relative_path: &str,
    expected_sha256: &str,
) -> Result<PathBuf> {
    let relative = Path::new(relative_path);
    if relative.is_absolute() {
        bail!("asset path must be relative: {relative_path}");
    }
    let sha = normalize_sha256(expected_sha256);
    let prefix = sha
        .get(..16)
        .with_context(|| format!("SHA-256 is too short for {relative_path}"))?;
    Ok(cache_dir.join(namespace).join(prefix).join(relative))
}

fn verify_file_sha256(path: &Path, expected_sha256: &str, label: &str) -> Result<()> {
    let actual_sha256 =
        download::sha256_file(path).with_context(|| format!("hash {}", path.display()))?;
    let expected_sha256 = normalize_sha256(expected_sha256);
    if actual_sha256 != expected_sha256 {
        bail!(
            "{label} SHA-256 mismatch at {}: expected {}, got {}",
            path.display(),
            expected_sha256,
            actual_sha256
        );
    }
    Ok(())
}

fn normalize_sha256(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn expect_decode_error(file_id: &str, req: AnalyzeImageRequest, failures: &mut Vec<String>) {
    match analyze_image(req) {
        Err(MlError::Decode(_)) => {}
        Err(error) => failures.push(format!(
            "{file_id}: expected decode error, got different ML error: {error}"
        )),
        Ok(_) => failures.push(format!(
            "{file_id}: expected decode error, but Rust ML indexing succeeded"
        )),
    }
}

fn comparable_from_rust(file_id: &str, result: &AnalyzeImageResult) -> Result<ComparableResult> {
    let clip = result
        .clip
        .as_ref()
        .context("missing CLIP result")?
        .embedding
        .iter()
        .map(|value| *value as f64)
        .collect();
    let faces = result
        .faces
        .as_ref()
        .context("missing face results")?
        .iter()
        .map(comparable_face_from_rust)
        .collect();

    Ok(ComparableResult {
        file_id: file_id.to_owned(),
        clip: ComparableClip { embedding: clip },
        faces,
    })
}

fn comparable_face_from_rust(face: &RustFaceResult) -> ComparableFace {
    let [x_min, y_min, x_max, y_max] = face.detection.box_xyxy;
    ComparableFace {
        box_xywh: [
            x_min as f64,
            y_min as f64,
            (x_max - x_min).max(0.0) as f64,
            (y_max - y_min).max(0.0) as f64,
        ],
        landmarks: face
            .detection
            .keypoints
            .iter()
            .map(|point| [point[0] as f64, point[1] as f64])
            .collect(),
        score: face.detection.score as f64,
        embedding: face.embedding.iter().map(|value| *value as f64).collect(),
    }
}

fn compare_results(
    file_id: &str,
    reference: &ComparableResult,
    candidate: &ComparableResult,
    thresholds: &Thresholds,
    failures: &mut Vec<String>,
    stats: &mut ComparisonStats,
) {
    stats.record_file();
    validate_result(file_id, "python golden", reference, thresholds, failures);
    validate_result(file_id, "rust", candidate, thresholds, failures);

    match cosine_distance(&reference.clip.embedding, &candidate.clip.embedding) {
        Ok(distance) => {
            stats
                .clip_cosine_distance
                .record(file_id, distance, thresholds.clip_cosine_distance);
            if distance > thresholds.clip_cosine_distance {
                failures.push(format!(
                    "{file_id}: CLIP cosine distance {distance:.6} exceeded threshold {:.6}",
                    thresholds.clip_cosine_distance
                ));
            }
        }
        Err(error) => failures.push(format!("{file_id}: CLIP cosine distance failed: {error:#}")),
    }

    let reference_faces = dedupe_faces(&reference.faces, thresholds.face_duplicate_iou);
    let candidate_faces = dedupe_faces(&candidate.faces, thresholds.face_duplicate_iou);
    let all_matches = match_faces(
        &reference_faces,
        &candidate_faces,
        thresholds.face_match_iou_floor,
    );

    let matched_reference_indices: BTreeSet<usize> = all_matches
        .iter()
        .map(|face_match| face_match.reference_index)
        .collect();
    let matched_candidate_indices: BTreeSet<usize> = all_matches
        .iter()
        .map(|face_match| face_match.candidate_index)
        .collect();
    let relevant_matches: Vec<FaceMatch> = all_matches
        .iter()
        .copied()
        .filter(|face_match| {
            reference_faces[face_match.reference_index].score
                >= thresholds.min_face_score_for_comparison
                || candidate_faces[face_match.candidate_index].score
                    >= thresholds.min_face_score_for_comparison
        })
        .collect();

    let unmatched_reference_indices: Vec<usize> = reference_faces
        .iter()
        .enumerate()
        .filter_map(|(index, face)| {
            (face.score >= thresholds.min_face_score_for_comparison
                && !matched_reference_indices.contains(&index))
            .then_some(index)
        })
        .collect();
    let unmatched_candidate_indices: Vec<usize> = candidate_faces
        .iter()
        .enumerate()
        .filter_map(|(index, face)| {
            (face.score >= thresholds.min_face_score_for_comparison
                && !matched_candidate_indices.contains(&index))
            .then_some(index)
        })
        .collect();

    let comparable_reference_indices: BTreeSet<usize> = relevant_matches
        .iter()
        .map(|face_match| face_match.reference_index)
        .chain(unmatched_reference_indices.iter().copied())
        .collect();
    let comparable_candidate_indices: BTreeSet<usize> = relevant_matches
        .iter()
        .map(|face_match| face_match.candidate_index)
        .chain(unmatched_candidate_indices.iter().copied())
        .collect();

    if comparable_reference_indices.len() != comparable_candidate_indices.len() {
        failures.push(format!(
            "{file_id}: comparable face count mismatch: python={} rust={}",
            comparable_reference_indices.len(),
            comparable_candidate_indices.len()
        ));
    }

    let expected_match_count = comparable_reference_indices
        .len()
        .min(comparable_candidate_indices.len());
    if relevant_matches.len() != expected_match_count {
        failures.push(format!(
            "{file_id}: matched comparable face count mismatch: matched={} expected={}",
            relevant_matches.len(),
            expected_match_count
        ));
    }

    for index in unmatched_reference_indices {
        failures.push(format!(
            "{file_id}: unmatched high-score python face {}",
            describe_face(&reference_faces[index])
        ));
    }
    for index in unmatched_candidate_indices {
        failures.push(format!(
            "{file_id}: unmatched high-score Rust face {}",
            describe_face(&candidate_faces[index])
        ));
    }

    for face_match in relevant_matches {
        stats.record_face();
        let reference_face = &reference_faces[face_match.reference_index];
        let candidate_face = &candidate_faces[face_match.candidate_index];
        let face_box_iou_error = (thresholds.box_iou - face_match.iou).max(0.0);
        stats
            .face_box_iou_error
            .record(file_id, face_box_iou_error, 0.0);

        if face_match.iou < thresholds.box_iou {
            failures.push(format!(
                "{file_id}: face box IoU {iou:.6} below threshold {threshold:.6}; python={python} rust={rust}",
                iou = face_match.iou,
                threshold = thresholds.box_iou,
                python = describe_face(reference_face),
                rust = describe_face(candidate_face)
            ));
        }

        match landmark_error(&reference_face.landmarks, &candidate_face.landmarks) {
            Ok(error) => {
                stats
                    .landmark_error
                    .record(file_id, error, thresholds.landmark_error);
                if error > thresholds.landmark_error {
                    failures.push(format!(
                        "{file_id}: landmark error {error:.6} exceeded threshold {:.6}",
                        thresholds.landmark_error
                    ));
                }
            }
            Err(error) => {
                failures.push(format!("{file_id}: landmark comparison failed: {error:#}"))
            }
        }

        let score_delta = (reference_face.score - candidate_face.score).abs();
        stats
            .score_delta
            .record(file_id, score_delta, thresholds.score_delta);
        if score_delta > thresholds.score_delta {
            failures.push(format!(
                "{file_id}: face score delta {score_delta:.6} exceeded threshold {:.6}",
                thresholds.score_delta
            ));
        }

        match cosine_distance(&reference_face.embedding, &candidate_face.embedding) {
            Ok(distance) => {
                stats.face_embedding_cosine_distance.record(
                    file_id,
                    distance,
                    thresholds.face_embedding_cosine_distance,
                );
                if distance > thresholds.face_embedding_cosine_distance {
                    failures.push(format!(
                        "{file_id}: face embedding cosine distance {distance:.6} exceeded threshold {:.6}",
                        thresholds.face_embedding_cosine_distance
                    ));
                }
            }
            Err(error) => failures.push(format!(
                "{file_id}: face embedding cosine distance failed: {error:#}"
            )),
        }
    }
}

fn validate_result(
    file_id: &str,
    label: &str,
    result: &ComparableResult,
    thresholds: &Thresholds,
    failures: &mut Vec<String>,
) {
    validate_embedding(
        file_id,
        label,
        "clip.embedding",
        &result.clip.embedding,
        CLIP_EMBEDDING_DIM,
        thresholds.embedding_norm_tolerance,
        failures,
    );

    for (index, face) in result.faces.iter().enumerate() {
        validate_box(file_id, label, index, &face.box_xywh, failures);
        if !face.score.is_finite() {
            failures.push(format!(
                "{file_id}: {label} faces[{index}].score is not finite"
            ));
        }
        if face.landmarks.len() != 5 {
            failures.push(format!(
                "{file_id}: {label} faces[{index}].landmarks has len {}, expected 5",
                face.landmarks.len()
            ));
        }
        for (landmark_index, landmark) in face.landmarks.iter().enumerate() {
            for (axis, value) in landmark.iter().enumerate() {
                if !value.is_finite() || *value < 0.0 || *value > 1.0 {
                    failures.push(format!(
                        "{file_id}: {label} faces[{index}].landmarks[{landmark_index}][{axis}] is outside [0, 1]: {value}"
                    ));
                }
            }
        }
        validate_embedding(
            file_id,
            label,
            &format!("faces[{index}].embedding"),
            &face.embedding,
            FACE_EMBEDDING_DIM,
            thresholds.embedding_norm_tolerance,
            failures,
        );
    }
}

fn validate_box(
    file_id: &str,
    label: &str,
    index: usize,
    box_xywh: &[f64; 4],
    failures: &mut Vec<String>,
) {
    let [x, y, width, height] = *box_xywh;
    if !box_xywh.iter().all(|value| value.is_finite()) {
        failures.push(format!(
            "{file_id}: {label} faces[{index}].box has non-finite values: {box_xywh:?}"
        ));
        return;
    }
    if width < 0.0 || height < 0.0 {
        failures.push(format!(
            "{file_id}: {label} faces[{index}].box has negative size: {box_xywh:?}"
        ));
    }
    if x < 0.0 || y < 0.0 || x + width > 1.0 + FLOAT_TOLERANCE || y + height > 1.0 + FLOAT_TOLERANCE
    {
        failures.push(format!(
            "{file_id}: {label} faces[{index}].box is outside [0, 1]: {box_xywh:?}"
        ));
    }
}

fn validate_embedding(
    file_id: &str,
    label: &str,
    field: &str,
    values: &[f64],
    expected_len: usize,
    norm_tolerance: f64,
    failures: &mut Vec<String>,
) {
    if values.len() != expected_len {
        failures.push(format!(
            "{file_id}: {label} {field} has len {}, expected {expected_len}",
            values.len()
        ));
        return;
    }
    if let Some((index, value)) = values
        .iter()
        .enumerate()
        .find(|(_, value)| !value.is_finite())
    {
        failures.push(format!(
            "{file_id}: {label} {field}[{index}] is not finite: {value}"
        ));
        return;
    }

    let norm = l2_norm(values);
    if norm <= FLOAT_TOLERANCE {
        failures.push(format!("{file_id}: {label} {field} is a zero vector"));
    } else if (norm - 1.0).abs() > norm_tolerance {
        failures.push(format!(
            "{file_id}: {label} {field} is not L2-normalized: norm={norm:.6}"
        ));
    }
}

#[derive(Clone, Copy, Debug)]
struct FaceMatch {
    reference_index: usize,
    candidate_index: usize,
    iou: f64,
}

fn dedupe_faces(faces: &[ComparableFace], min_iou_for_duplicate: f64) -> Vec<ComparableFace> {
    let mut sorted_faces: Vec<(usize, &ComparableFace)> = faces.iter().enumerate().collect();
    sorted_faces.sort_by(|left, right| {
        right
            .1
            .score
            .total_cmp(&left.1.score)
            .then_with(|| left.0.cmp(&right.0))
    });

    let mut kept: Vec<(usize, &ComparableFace)> = Vec::new();
    for (index, face) in sorted_faces {
        if kept.iter().any(|(_, kept_face)| {
            box_iou(&face.box_xywh, &kept_face.box_xywh) >= min_iou_for_duplicate
        }) {
            continue;
        }
        kept.push((index, face));
    }

    kept.sort_by_key(|(index, _)| *index);
    kept.into_iter().map(|(_, face)| face.clone()).collect()
}

fn match_faces(
    reference_faces: &[ComparableFace],
    candidate_faces: &[ComparableFace],
    min_iou_for_match: f64,
) -> Vec<FaceMatch> {
    let mut pairs = Vec::new();
    for (reference_index, reference_face) in reference_faces.iter().enumerate() {
        for (candidate_index, candidate_face) in candidate_faces.iter().enumerate() {
            pairs.push((
                box_iou(&reference_face.box_xywh, &candidate_face.box_xywh),
                reference_index,
                candidate_index,
            ));
        }
    }
    pairs.sort_by(|left, right| {
        right
            .0
            .total_cmp(&left.0)
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(&right.2))
    });

    let mut used_reference = HashSet::new();
    let mut used_candidate = HashSet::new();
    let mut matches = Vec::new();
    for (iou, reference_index, candidate_index) in pairs {
        if iou < min_iou_for_match {
            break;
        }
        if used_reference.contains(&reference_index) || used_candidate.contains(&candidate_index) {
            continue;
        }
        used_reference.insert(reference_index);
        used_candidate.insert(candidate_index);
        matches.push(FaceMatch {
            reference_index,
            candidate_index,
            iou,
        });
    }

    matches.sort_by(|left, right| {
        left.reference_index
            .cmp(&right.reference_index)
            .then_with(|| left.candidate_index.cmp(&right.candidate_index))
    });
    matches
}

fn box_iou(left: &[f64; 4], right: &[f64; 4]) -> f64 {
    let [left_x, left_y, left_width, left_height] = *left;
    let [right_x, right_y, right_width, right_height] = *right;

    let left_x2 = left_x + left_width;
    let left_y2 = left_y + left_height;
    let right_x2 = right_x + right_width;
    let right_y2 = right_y + right_height;

    let inter_x1 = left_x.max(right_x);
    let inter_y1 = left_y.max(right_y);
    let inter_x2 = left_x2.min(right_x2);
    let inter_y2 = left_y2.min(right_y2);

    let inter_width = (inter_x2 - inter_x1).max(0.0);
    let inter_height = (inter_y2 - inter_y1).max(0.0);
    let inter_area = inter_width * inter_height;
    let left_area = (left_width * left_height).max(0.0);
    let right_area = (right_width * right_height).max(0.0);
    let denominator = left_area + right_area - inter_area;
    if denominator <= 0.0 {
        return 0.0;
    }
    inter_area / denominator
}

fn landmark_error(left: &[[f64; 2]], right: &[[f64; 2]]) -> Result<f64> {
    if left.len() != right.len() {
        bail!(
            "landmark count mismatch: python={} rust={}",
            left.len(),
            right.len()
        );
    }
    if left.is_empty() {
        return Ok(0.0);
    }

    let total = left
        .iter()
        .zip(right.iter())
        .map(|(left_point, right_point)| {
            let dx = left_point[0] - right_point[0];
            let dy = left_point[1] - right_point[1];
            (dx * dx + dy * dy).sqrt()
        })
        .sum::<f64>();
    Ok(total / left.len() as f64)
}

fn cosine_distance(left: &[f64], right: &[f64]) -> Result<f64> {
    if left.len() != right.len() {
        bail!(
            "cosine distance vector dimension mismatch: left={} right={}",
            left.len(),
            right.len()
        );
    }

    let dot = left
        .iter()
        .zip(right.iter())
        .map(|(left_value, right_value)| left_value * right_value)
        .sum::<f64>();
    let denominator = l2_norm(left) * l2_norm(right);
    if denominator <= FLOAT_TOLERANCE {
        bail!("cosine distance cannot be computed for zero vectors");
    }
    let similarity = (dot / denominator).clamp(-1.0, 1.0);
    Ok(1.0 - similarity)
}

fn l2_norm(values: &[f64]) -> f64 {
    values.iter().map(|value| value * value).sum::<f64>().sqrt()
}

fn describe_face(face: &ComparableFace) -> String {
    format!(
        "score={:.4} box=[{:.4}, {:.4}, {:.4}, {:.4}]",
        face.score, face.box_xywh[0], face.box_xywh[1], face.box_xywh[2], face.box_xywh[3]
    )
}
