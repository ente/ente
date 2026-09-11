#![expect(
    clippy::expect_used,
    reason = "Benchmark failures should abort the run"
)]

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use ente_ml::vecdb::{
    AttrValue, Attribute, DistanceMetric, Match, SearchParams, StorageKind, VecDb,
};

const SEED: u64 = 0xE47E_0000_0000_0001;
const LATENT_DIMS: usize = 24;
const QUERY_COUNT: usize = 100;
const SINGLE_ADD_COUNT: usize = 2000;
const BULK_BATCH_SIZE: usize = 1000;
const SEARCH_K: usize = 10;
const STORED_SEARCH_COUNT: usize = 100;
const WARMUP_QUERIES: usize = 10;
const REMOVAL_PERCENT: usize = 15;
const DEFAULT_SCALES: &str = "10000,100000";
const DEFAULT_DIMS: usize = 512;

struct Config {
    scales: Vec<usize>,
    dims: usize,
    attrs: bool,
    storage: StorageKind,
}

struct BenchData {
    entries: Vec<(String, Vec<f32>)>,
    queries: Vec<Vec<f32>>,
    probe: Vec<f32>,
    allowed_indices: Vec<usize>,
}

struct VecdbReport {
    storage: StorageKind,
    single_count: usize,
    single_total: Duration,
    bulk_count: usize,
    bulk_total: Duration,
    snapshot_write: Duration,
    approx_total: Duration,
    exact_total: Duration,
    recall: f64,
    truth_recall: Option<f64>,
    threshold: f32,
    threshold_total: Duration,
    threshold_avg_hits: f64,
    filtered_total: Duration,
    stored_keys: usize,
    stored_total: Duration,
    stored_avg_hits: f64,
    open_with_snapshot: Duration,
    open_full_rebuild: Duration,
    removed: usize,
    remove_and_compact: Duration,
    compaction_fired: bool,
    log_bytes: u64,
    snapshot_bytes: u64,
    memory_bytes: usize,
}

fn main() {
    let config = parse_args();
    println!(
        "vecdb bench  dims={}  storage={}  queries={}  seed={:#018x}{}",
        config.dims,
        storage_name(config.storage),
        QUERY_COUNT,
        SEED,
        if config.attrs { "  attrs=on" } else { "" }
    );
    println!(
        "scales: {}",
        config
            .scales
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(", ")
    );
    let temp_root = tempfile::TempDir::new().expect("create bench temp dir");
    for &scale in &config.scales {
        run_scale(
            scale,
            config.dims,
            config.attrs,
            config.storage,
            temp_root.path(),
        );
    }
}

fn parse_args() -> Config {
    let mut scales = parse_scales(DEFAULT_SCALES);
    let mut dims = DEFAULT_DIMS;
    let mut attrs = false;
    let mut storage = StorageKind::I8;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--scales" => scales = parse_scales(&required_value(args.next())),
            "--dims" => {
                dims = required_value(args.next())
                    .parse()
                    .unwrap_or_else(|_| usage_exit())
            }
            "--attrs" => attrs = true,
            "--storage" => {
                storage = match required_value(args.next()).as_str() {
                    "f32" => StorageKind::F32,
                    "i8" => StorageKind::I8,
                    _ => usage_exit(),
                }
            }
            _ => usage_exit(),
        }
    }
    let lane_width = match storage {
        StorageKind::F32 => 8,
        StorageKind::I8 => 32,
    };
    if dims == 0 || !dims.is_multiple_of(lane_width) {
        eprintln!(
            "--dims must be a nonzero multiple of {lane_width} for {} storage",
            storage_name(storage)
        );
        std::process::exit(2);
    }
    Config {
        scales,
        dims,
        attrs,
        storage,
    }
}

fn required_value(value: Option<String>) -> String {
    value.unwrap_or_else(|| usage_exit())
}

fn parse_scales(list: &str) -> Vec<usize> {
    let scales: Vec<usize> = list
        .split(',')
        .map(|part| match part.trim().parse() {
            Ok(scale) if scale > 0 => scale,
            _ => usage_exit(),
        })
        .collect();
    if scales.is_empty() {
        usage_exit();
    }
    scales
}

fn usage_exit() -> ! {
    eprintln!(
        "usage: cargo run -p ente-ml --example vecdb_bench --release -- \
         [--scales 10000,100000] [--dims 512] [--attrs] [--storage f32|i8]"
    );
    std::process::exit(2);
}

fn storage_name(storage: StorageKind) -> &'static str {
    match storage {
        StorageKind::F32 => "f32",
        StorageKind::I8 => "i8",
    }
}

fn run_scale(scale: usize, dims: usize, attrs: bool, storage: StorageKind, temp_root: &Path) {
    let clusters = (scale / 150).max(1) as u64;
    println!();
    println!(
        "=== scale {scale}  dims {dims}  storage {}  clusters {clusters} ===",
        storage_name(storage)
    );
    let dir = temp_root.join(format!("scale-{scale}-{dims}"));
    std::fs::create_dir_all(&dir).expect("create bench dir");
    drop(
        VecDb::open(
            &dir.join("bench.vecdb"),
            dims,
            Some(storage),
            DistanceMetric::Cosine,
        )
        .expect("open vecdb"),
    );
    eprintln!("[scale {scale}] generating data");
    let data = generate_data(scale, dims, clusters);
    let vecdb = run_vecdb(&data, dims, attrs, storage, &dir, scale);
    print_vecdb_report(&vecdb);
    let _ = std::fs::remove_dir_all(&dir);
}

fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

fn normalized(mut values: Vec<f32>) -> Vec<f32> {
    let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
    for value in &mut values {
        *value /= norm;
    }
    values
}

fn seeded_unit_vector(seed: u64, dims: usize) -> Vec<f32> {
    let mut state = seed;
    normalized(
        (0..dims)
            .map(|_| {
                let unit = (splitmix64(&mut state) >> 40) as f32 / (1u64 << 24) as f32;
                unit * 2.0 - 1.0
            })
            .collect(),
    )
}

fn clustered_unit_vector(center_seed: u64, noise_seed: u64, dims: usize) -> Vec<f32> {
    let center = seeded_unit_vector(center_seed, dims);
    let noise = seeded_unit_vector(noise_seed, dims);
    let mut spread_state = noise_seed ^ 0xD1B5_4A32_D192_ED03;
    let spread = 0.6 + (splitmix64(&mut spread_state) >> 40) as f32 / (1u64 << 24) as f32;
    normalized(
        center
            .iter()
            .zip(&noise)
            .map(|(center, noise)| center + spread * noise)
            .collect(),
    )
}

fn projected_unit_vector(projection: &[Vec<f32>], latent: &[f32]) -> Vec<f32> {
    let dims = projection[0].len();
    let mut values = vec![0.0f32; dims];
    for (weight, basis) in latent.iter().zip(projection) {
        for (value, basis_value) in values.iter_mut().zip(basis) {
            *value += weight * basis_value;
        }
    }
    normalized(values)
}

fn generate_data(scale: usize, dims: usize, clusters: u64) -> BenchData {
    let projection: Vec<Vec<f32>> = (0..LATENT_DIMS as u64)
        .map(|axis| seeded_unit_vector(SEED + 0x0300_0000 + axis, dims))
        .collect();
    let member = |cluster: u64, noise_seed: u64| {
        projected_unit_vector(
            &projection,
            &clustered_unit_vector(SEED + cluster, noise_seed, LATENT_DIMS),
        )
    };
    let entries = (0..scale as u64)
        .map(|index| {
            (
                format!("vec-{index}"),
                member(index % clusters, SEED + 0x0100_0000 + index),
            )
        })
        .collect();
    let queries = (0..QUERY_COUNT as u64)
        .map(|index| member(index % clusters, SEED + 0x0200_0000 + index))
        .collect();
    let probe = member(0, SEED + 0x0400_0000);
    let mut filter_state = SEED + 0x0500_0000;
    let allowed_indices = (0..scale)
        .filter(|_| splitmix64(&mut filter_state).is_multiple_of(10))
        .collect();
    BenchData {
        entries,
        queries,
        probe,
        allowed_indices,
    }
}

struct IngestTimings {
    single_count: usize,
    single_total: Duration,
    bulk_count: usize,
    bulk_total: Duration,
    snapshot_write: Duration,
}

struct SearchTimings {
    approx_total: Duration,
    exact_total: Duration,
    recall: f64,
    truth_recall: Option<f64>,
    threshold: f32,
    threshold_total: Duration,
    threshold_avg_hits: f64,
    filtered_total: Duration,
    stored_keys: usize,
    stored_total: Duration,
    stored_avg_hits: f64,
}

struct ReopenTimings {
    open_with_snapshot: Duration,
    open_full_rebuild: Duration,
}

struct CompactionTimings {
    removed: usize,
    remove_and_compact: Duration,
    compaction_fired: bool,
}

fn run_vecdb(
    data: &BenchData,
    dims: usize,
    attrs: bool,
    storage: StorageKind,
    dir: &Path,
    scale: usize,
) -> VecdbReport {
    let path = dir.join("bench.vecdb");
    let mut db =
        VecDb::open(&path, dims, Some(storage), DistanceMetric::Cosine).expect("open vecdb");
    let ingest = ingest_phase(&mut db, data, attrs, scale);
    let searches = search_phase(&db, data, storage, scale);
    let stats = db.stats().expect("vecdb stats");
    let snapshot_file = PathBuf::from(format!("{}.graph", path.display()));
    let snapshot_bytes = std::fs::metadata(&snapshot_file)
        .map(|meta| meta.len())
        .unwrap_or(0);
    drop(db);
    let (reopens, mut db) = reopen_phase(&path, dims, storage, &snapshot_file, scale);
    let compaction = compaction_phase(&mut db, data, scale);
    db.delete().expect("vecdb delete");
    VecdbReport {
        storage,
        single_count: ingest.single_count,
        single_total: ingest.single_total,
        bulk_count: ingest.bulk_count,
        bulk_total: ingest.bulk_total,
        snapshot_write: ingest.snapshot_write,
        approx_total: searches.approx_total,
        exact_total: searches.exact_total,
        recall: searches.recall,
        truth_recall: searches.truth_recall,
        threshold: searches.threshold,
        threshold_total: searches.threshold_total,
        threshold_avg_hits: searches.threshold_avg_hits,
        filtered_total: searches.filtered_total,
        stored_keys: searches.stored_keys,
        stored_total: searches.stored_total,
        stored_avg_hits: searches.stored_avg_hits,
        open_with_snapshot: reopens.open_with_snapshot,
        open_full_rebuild: reopens.open_full_rebuild,
        removed: compaction.removed,
        remove_and_compact: compaction.remove_and_compact,
        compaction_fired: compaction.compaction_fired,
        log_bytes: stats.log_bytes,
        snapshot_bytes,
        memory_bytes: stats.approximate_memory_bytes,
    }
}

fn bench_attrs(index: usize) -> Vec<Attribute> {
    vec![
        Attribute {
            name: "model".to_string(),
            value: AttrValue::Str("mobileclip-s2-v2".to_string()),
        },
        Attribute {
            name: "version".to_string(),
            value: AttrValue::I64(index as i64),
        },
        Attribute {
            name: "indexed".to_string(),
            value: AttrValue::Bool(index.is_multiple_of(2)),
        },
    ]
}

fn ingest_phase(db: &mut VecDb, data: &BenchData, attrs: bool, scale: usize) -> IngestTimings {
    let single_count = SINGLE_ADD_COUNT.min(data.entries.len());
    eprintln!("[scale {scale}] vecdb single adds");
    let single_attrs: Option<Vec<Vec<Attribute>>> =
        attrs.then(|| (0..single_count).map(bench_attrs).collect());
    let started = Instant::now();
    match &single_attrs {
        Some(all) => {
            for ((key, vector), entry_attrs) in data.entries[..single_count].iter().zip(all) {
                db.add_with_attrs(key, vector, entry_attrs)
                    .expect("vecdb add");
            }
        }
        None => {
            for (key, vector) in &data.entries[..single_count] {
                db.add(key, vector).expect("vecdb add");
            }
        }
    }
    let single_total = started.elapsed();
    let rest = &data.entries[single_count..];
    eprintln!("[scale {scale}] vecdb bulk adds");
    let batches: Vec<(Vec<String>, Vec<Vec<f32>>)> = rest
        .chunks(BULK_BATCH_SIZE)
        .map(|batch| batch.iter().cloned().unzip())
        .collect();
    let bulk_attrs: Option<Vec<Vec<Option<Vec<Attribute>>>>> = attrs.then(|| {
        batches
            .iter()
            .scan(single_count, |next_index, (keys, _)| {
                let start = *next_index;
                *next_index += keys.len();
                Some(
                    (start..start + keys.len())
                        .map(bench_attrs)
                        .map(Some)
                        .collect(),
                )
            })
            .collect()
    });
    let started = Instant::now();
    match &bulk_attrs {
        Some(all) => {
            for ((keys, vectors), batch_attrs) in batches.iter().zip(all) {
                db.bulk_add_with_attrs(keys, vectors, batch_attrs)
                    .expect("vecdb bulk add");
            }
        }
        None => {
            for (keys, vectors) in &batches {
                db.bulk_add(keys, vectors).expect("vecdb bulk add");
            }
        }
    }
    let bulk_total = started.elapsed();
    db.add("bench-probe", &data.probe).expect("vecdb probe add");
    let started = Instant::now();
    db.flush().expect("vecdb flush");
    IngestTimings {
        single_count,
        single_total,
        bulk_count: rest.len(),
        bulk_total,
        snapshot_write: started.elapsed(),
    }
}

fn search_phase(db: &VecDb, data: &BenchData, storage: StorageKind, scale: usize) -> SearchTimings {
    eprintln!("[scale {scale}] vecdb searches");
    let approx_params = limit_params(SEARCH_K, false);
    let exact_params = limit_params(SEARCH_K, true);
    warm(db, &data.queries, &approx_params);
    let (approx_total, approx_results) = timed_searches(db, &data.queries, &approx_params);
    warm(db, &data.queries, &exact_params);
    let (exact_total, exact_results) = timed_searches(db, &data.queries, &exact_params);
    let recall = recall_at_k(&exact_results, &approx_results, SEARCH_K);
    let truth_recall = match storage {
        StorageKind::F32 => None,
        StorageKind::I8 => {
            eprintln!("[scale {scale}] f32 ground truth (brute force)");
            let truth = f32_ground_truth(data, SEARCH_K);
            Some(recall_at_k(&truth, &exact_results, SEARCH_K))
        }
    };
    let threshold = one_percent_threshold(db, data);
    let threshold_params = SearchParams {
        limit: None,
        max_distance: Some(threshold),
        exact: false,
        allowed_keys: None,
    };
    warm(db, &data.queries, &threshold_params);
    let (threshold_total, threshold_results) = timed_searches(db, &data.queries, &threshold_params);
    let threshold_avg_hits = threshold_results.iter().map(Vec::len).sum::<usize>() as f64
        / threshold_results.len().max(1) as f64;
    let filtered_params = SearchParams {
        limit: Some(SEARCH_K),
        max_distance: None,
        exact: false,
        allowed_keys: Some(
            data.allowed_indices
                .iter()
                .map(|index| format!("vec-{index}"))
                .collect(),
        ),
    };
    warm(db, &data.queries, &filtered_params);
    let (filtered_total, _) = timed_searches(db, &data.queries, &filtered_params);
    eprintln!("[scale {scale}] vecdb stored-key search");
    let stored_keys: Vec<String> = data.entries.iter().map(|(key, _)| key.clone()).collect();
    let warm_span = WARMUP_QUERIES.min(stored_keys.len());
    db.bulk_search_stored(
        &stored_keys[..warm_span],
        STORED_SEARCH_COUNT,
        Some(threshold),
        false,
        true,
    )
    .expect("vecdb stored warmup");
    let started = Instant::now();
    let stored_results = db
        .bulk_search_stored(
            &stored_keys,
            STORED_SEARCH_COUNT,
            Some(threshold),
            false,
            true,
        )
        .expect("vecdb stored search");
    let stored_total = started.elapsed();
    let stored_avg_hits = stored_results
        .iter()
        .map(|entry| entry.matches.len())
        .sum::<usize>() as f64
        / stored_results.len().max(1) as f64;
    SearchTimings {
        approx_total,
        exact_total,
        recall,
        truth_recall,
        threshold,
        threshold_total,
        threshold_avg_hits,
        filtered_total,
        stored_keys: stored_results.len(),
        stored_total,
        stored_avg_hits,
    }
}

fn reopen_phase(
    path: &Path,
    dims: usize,
    storage: StorageKind,
    snapshot_file: &Path,
    scale: usize,
) -> (ReopenTimings, VecDb) {
    eprintln!("[scale {scale}] vecdb cold open with snapshot");
    let started = Instant::now();
    let reopened = VecDb::open(path, dims, Some(storage), DistanceMetric::Cosine)
        .expect("vecdb reopen with snapshot");
    let open_with_snapshot = started.elapsed();
    drop(reopened);
    std::fs::remove_file(snapshot_file).expect("remove snapshot");
    eprintln!("[scale {scale}] vecdb cold open without snapshot (full rebuild)");
    let started = Instant::now();
    let db = VecDb::open(path, dims, Some(storage), DistanceMetric::Cosine)
        .expect("vecdb reopen without snapshot");
    let open_full_rebuild = started.elapsed();
    (
        ReopenTimings {
            open_with_snapshot,
            open_full_rebuild,
        },
        db,
    )
}

fn compaction_phase(db: &mut VecDb, data: &BenchData, scale: usize) -> CompactionTimings {
    eprintln!("[scale {scale}] vecdb remove {REMOVAL_PERCENT}% + compact");
    let removed = data.entries.len() * REMOVAL_PERCENT / 100;
    let removals: Vec<String> = (0..removed).map(|index| format!("vec-{index}")).collect();
    let log_before = db.stats().expect("vecdb stats").log_bytes;
    let started = Instant::now();
    db.bulk_remove(&removals).expect("vecdb bulk remove");
    let remove_and_compact = started.elapsed();
    let stats_after = db.stats().expect("vecdb stats");
    CompactionTimings {
        removed,
        remove_and_compact,
        compaction_fired: stats_after.log_bytes < log_before && stats_after.dead_count == 0,
    }
}

fn limit_params(limit: usize, exact: bool) -> SearchParams {
    SearchParams {
        limit: Some(limit),
        max_distance: None,
        exact,
        allowed_keys: None,
    }
}

fn warm(db: &VecDb, queries: &[Vec<f32>], params: &SearchParams) {
    for query in queries.iter().take(WARMUP_QUERIES) {
        db.search(query, params).expect("warmup search");
    }
}

fn timed_searches(
    db: &VecDb,
    queries: &[Vec<f32>],
    params: &SearchParams,
) -> (Duration, Vec<Vec<Match>>) {
    let started = Instant::now();
    let results = queries
        .iter()
        .map(|query| db.search(query, params).expect("search"))
        .collect();
    (started.elapsed(), results)
}

fn dot(a: &[f32], b: &[f32]) -> f32 {
    let mut partials = [0.0f32; 8];
    for (x, y) in a.as_chunks::<8>().0.iter().zip(b.as_chunks::<8>().0) {
        for (partial, (left, right)) in partials.iter_mut().zip(x.iter().zip(y)) {
            *partial += left * right;
        }
    }
    partials.iter().sum()
}

fn f32_ground_truth(data: &BenchData, k: usize) -> Vec<Vec<Match>> {
    let corpus: Vec<(&str, &[f32])> = data
        .entries
        .iter()
        .map(|(key, vector)| (key.as_str(), vector.as_slice()))
        .chain(std::iter::once(("bench-probe", data.probe.as_slice())))
        .collect();
    data.queries
        .iter()
        .map(|query| {
            let mut scored: Vec<(f32, &str)> = corpus
                .iter()
                .map(|(key, vector)| (1.0 - dot(query, vector), *key))
                .collect();
            let keep = k.min(scored.len());
            if keep < scored.len() {
                scored.select_nth_unstable_by(keep, |a, b| {
                    a.0.total_cmp(&b.0).then_with(|| a.1.cmp(b.1))
                });
            }
            scored.truncate(keep);
            scored.sort_unstable_by(|a, b| a.0.total_cmp(&b.0).then_with(|| a.1.cmp(b.1)));
            scored
                .into_iter()
                .map(|(distance, key)| Match {
                    key: key.to_string(),
                    distance,
                })
                .collect()
        })
        .collect()
}

fn recall_at_k(truth: &[Vec<Match>], found: &[Vec<Match>], k: usize) -> f64 {
    let mut hits = 0usize;
    let mut total = 0usize;
    for (expected, actual) in truth.iter().zip(found) {
        let wanted: HashSet<&str> = expected
            .iter()
            .take(k)
            .map(|entry| entry.key.as_str())
            .collect();
        total += wanted.len();
        hits += actual
            .iter()
            .take(k)
            .filter(|entry| wanted.contains(entry.key.as_str()))
            .count();
    }
    if total == 0 {
        return 1.0;
    }
    hits as f64 / total as f64
}

fn one_percent_threshold(db: &VecDb, data: &BenchData) -> f32 {
    let tail_rank = (data.entries.len() / 100).max(1);
    let params = limit_params(tail_rank, true);
    let mut sum = 0.0f64;
    let mut counted = 0usize;
    for query in &data.queries {
        let found = db.search(query, &params).expect("threshold probe search");
        if let Some(last) = found.last() {
            sum += f64::from(last.distance);
            counted += 1;
        }
    }
    (sum / counted.max(1) as f64) as f32
}

fn print_vecdb_report(report: &VecdbReport) {
    println!("  vecdb");
    row(
        "add single (append+fsync per op)",
        format!("{} ops", report.single_count),
        report.single_total,
        per_op_text(report.single_total, report.single_count, "op"),
    );
    row(
        "bulk add (1000/batch, fsync+auto snapshots)",
        format!("{} vecs", report.bulk_count),
        report.bulk_total,
        per_op_text(report.bulk_total, report.bulk_count, "vec"),
    );
    row(
        "snapshot write (flush at full scale)",
        "-".to_string(),
        report.snapshot_write,
        String::new(),
    );
    row(
        "search approx k=10",
        format!("{QUERY_COUNT} queries"),
        report.approx_total,
        per_op_text(report.approx_total, QUERY_COUNT, "query"),
    );
    row(
        "search exact k=10",
        format!("{QUERY_COUNT} queries"),
        report.exact_total,
        per_op_text(report.exact_total, QUERY_COUNT, "query"),
    );
    println!(
        "    {:<44} {:.4}",
        match report.storage {
            StorageKind::F32 => "recall@10 (approx vs exact)",
            StorageKind::I8 => "recall@10 (approx vs i8-exact)",
        },
        report.recall
    );
    if let Some(truth_recall) = report.truth_recall {
        println!(
            "    {:<44} {:.4}",
            "recall@10 (i8-exact vs f32 truth)", truth_recall
        );
    }
    row(
        &format!("search approx threshold d<={:.4} (~1%)", report.threshold),
        format!("{QUERY_COUNT} queries"),
        report.threshold_total,
        per_op_text(report.threshold_total, QUERY_COUNT, "query"),
    );
    println!(
        "    {:<44} {:.1}",
        "avg hits per threshold query", report.threshold_avg_hits
    );
    row(
        "search approx k=10 filtered (10% allowed)",
        format!("{QUERY_COUNT} queries"),
        report.filtered_total,
        per_op_text(report.filtered_total, QUERY_COUNT, "query"),
    );
    row(
        &format!(
            "stored-key search k={STORED_SEARCH_COUNT} d<={:.4} restricted",
            report.threshold
        ),
        format!("{} keys", report.stored_keys),
        report.stored_total,
        per_op_text(report.stored_total, report.stored_keys, "key"),
    );
    println!(
        "    {:<44} {:.1}",
        "avg hits per stored key", report.stored_avg_hits
    );
    row(
        "open cold (valid snapshot)",
        "-".to_string(),
        report.open_with_snapshot,
        String::new(),
    );
    row(
        "open cold (no snapshot: replay+rebuild+snap)",
        "-".to_string(),
        report.open_full_rebuild,
        String::new(),
    );
    row(
        &format!("remove {REMOVAL_PERCENT}% + auto compact"),
        format!("{} keys", report.removed),
        report.remove_and_compact,
        String::new(),
    );
    println!(
        "    {:<44} {}",
        "compaction fired",
        if report.compaction_fired { "yes" } else { "NO" }
    );
    println!(
        "    {:<44} log {}  snapshot {}  approx mem {}",
        "sizes at full scale",
        fmt_bytes(report.log_bytes),
        fmt_bytes(report.snapshot_bytes),
        fmt_bytes(report.memory_bytes as u64)
    );
}

fn row(label: &str, quantity: String, total: Duration, per: String) {
    println!(
        "    {label:<44} {quantity:>14}  total {:>10}  {per}",
        fmt_duration(total)
    );
}

fn per_op(total: Duration, count: usize) -> Duration {
    if count == 0 {
        return Duration::ZERO;
    }
    Duration::from_nanos((total.as_nanos() / count as u128) as u64)
}

fn per_op_text(total: Duration, count: usize, unit: &str) -> String {
    if count == 0 {
        return "-".to_string();
    }
    format!("{}/{unit}", fmt_duration(per_op(total, count)))
}

fn fmt_duration(duration: Duration) -> String {
    let nanos = duration.as_nanos() as f64;
    if nanos < 1_000.0 {
        format!("{nanos:.0} ns")
    } else if nanos < 1_000_000.0 {
        format!("{:.1} us", nanos / 1_000.0)
    } else if nanos < 1_000_000_000.0 {
        format!("{:.2} ms", nanos / 1_000_000.0)
    } else {
        format!("{:.2} s", nanos / 1_000_000_000.0)
    }
}

fn fmt_bytes(bytes: u64) -> String {
    let value = bytes as f64;
    if value < 1024.0 {
        format!("{bytes} B")
    } else if value < 1024.0 * 1024.0 {
        format!("{:.1} KB", value / 1024.0)
    } else {
        format!("{:.2} MB", value / (1024.0 * 1024.0))
    }
}
