use std::collections::{HashMap, HashSet};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, PoisonError};

use ente_assets::{AssetStore, download};
use ente_ensu::config::{AttributionConfig, KnowledgeDatasetConfig};
use ente_ensu::{llm, retrieval};
use serde::{Deserialize, Serialize};
use tauri::async_runtime;
use tauri::{AppHandle, Emitter, Manager, State as TauriState, WebviewWindow};

use crate::commands::common::ApiError;
use crate::commands::llm::ModelDownloadState;
use crate::logging;

struct OpenIndex {
    directory: String,
    index: retrieval::RetrievalIndex,
}

#[derive(Default)]
pub struct State {
    indexes: Arc<Mutex<HashMap<String, OpenIndex>>>,
    active_downloads: Mutex<HashMap<String, download::CancellationToken>>,
    pack_lifecycles: Mutex<HashMap<String, Arc<async_runtime::Mutex<()>>>>,
}

impl State {
    fn pack_lifecycle(&self, stable_id: &str) -> Arc<async_runtime::Mutex<()>> {
        Arc::clone(
            self.pack_lifecycles
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .entry(stable_id.to_owned())
                .or_default(),
        )
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AttributionDto {
    credit: String,
    license_label: String,
    license_url: String,
    public_pack_url: String,
    modification_notice: String,
}

impl From<AttributionConfig> for AttributionDto {
    fn from(value: AttributionConfig) -> Self {
        Self {
            credit: value.credit,
            license_label: value.license_label,
            license_url: value.license_url,
            public_pack_url: value.public_pack_url,
            modification_notice: value.modification_notice,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum KnowledgePackStatusDto {
    Download,
    Ready,
    UpdateAvailable,
}

impl From<retrieval::KnowledgeReconciliationStatus> for KnowledgePackStatusDto {
    fn from(value: retrieval::KnowledgeReconciliationStatus) -> Self {
        match value {
            retrieval::KnowledgeReconciliationStatus::Download => Self::Download,
            retrieval::KnowledgeReconciliationStatus::Ready => Self::Ready,
            retrieval::KnowledgeReconciliationStatus::UpdateAvailable => Self::UpdateAvailable,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KnowledgePackDto {
    stable_id: String,
    label: String,
    download_size_bytes: i64,
    status: Option<KnowledgePackStatusDto>,
    attribution: AttributionDto,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceCitationDto {
    pub dataset_id: String,
    pub dataset_label: String,
    pub credit: String,
    pub title: String,
    pub source_url: String,
    pub license_label: String,
    pub license_url: String,
}

impl From<retrieval::SourceCitation> for SourceCitationDto {
    fn from(value: retrieval::SourceCitation) -> Self {
        Self {
            dataset_id: value.dataset_id,
            dataset_label: value.dataset_label,
            credit: value.credit,
            title: value.title,
            source_url: value.source_url,
            license_label: value.license_label,
            license_url: value.license_url,
        }
    }
}

impl From<SourceCitationDto> for retrieval::SourceCitation {
    fn from(value: SourceCitationDto) -> Self {
        Self {
            dataset_id: value.dataset_id,
            dataset_label: value.dataset_label,
            credit: value.credit,
            title: value.title,
            source_url: value.source_url,
            license_label: value.license_label,
            license_url: value.license_url,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KnowledgePromptContextDto {
    text: String,
    citations: Vec<SourceCitationDto>,
}

impl From<retrieval::KnowledgePromptContext> for KnowledgePromptContextDto {
    fn from(value: retrieval::KnowledgePromptContext) -> Self {
        Self {
            text: value.text,
            citations: value.citations.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct KnowledgeDownloadProgressDto {
    stable_id: String,
    percent: i32,
}

fn knowledge_dataset(stable_id: &str) -> Result<KnowledgeDatasetConfig, ApiError> {
    ente_ensu::config::knowledge_dataset(stable_id).ok_or_else(|| {
        ApiError::new(
            "invalid_target",
            format!("Unknown knowledge pack: {stable_id}"),
        )
    })
}

pub(crate) fn retrieval_error(error: retrieval::RetrievalError) -> ApiError {
    let code = match &error {
        retrieval::RetrievalError::InvalidInput(_) => "invalid_input",
        retrieval::RetrievalError::InvalidPack(_) => "invalid_pack",
        retrieval::RetrievalError::Io(_) => "io",
        retrieval::RetrievalError::Json(_) => "json",
        retrieval::RetrievalError::Zstd(_) => "zstd",
    };
    ApiError::new(code, error.to_string())
}

fn reconcile_and_open(
    store: &AssetStore,
    indexes: &Mutex<HashMap<String, OpenIndex>>,
    dataset: &KnowledgeDatasetConfig,
) -> Result<retrieval::KnowledgeReconciliation, ApiError> {
    let pack_root = retrieval::knowledge_pack_root(store, dataset)
        .map_err(|error| ApiError::new("invalid_target", error.to_string()))?;
    let result =
        retrieval::reconcile_knowledge_pack(&pack_root, dataset).map_err(retrieval_error)?;

    let mut indexes = indexes.lock().unwrap_or_else(PoisonError::into_inner);
    match result.active_directory.as_deref() {
        None => {
            indexes.remove(&dataset.stable_id);
        }
        Some(directory) => {
            let needs_replacement = indexes
                .get(&dataset.stable_id)
                .is_none_or(|open| open.directory != directory);
            if needs_replacement {
                let index =
                    retrieval::RetrievalIndex::open(directory, dataset).map_err(retrieval_error)?;
                indexes.insert(
                    dataset.stable_id.clone(),
                    OpenIndex {
                        directory: directory.to_string(),
                        index,
                    },
                );
            }
        }
    }
    drop(indexes);

    if let Some(active_identity) = result.active_identity.as_deref()
        && let Err(error) = retrieval::cleanup_obsolete_knowledge_pack_revisions(
            &pack_root,
            dataset,
            active_identity,
        )
    {
        logging::log(
            "Knowledge",
            format!(
                "obsolete revision cleanup skipped pack={} error={error}",
                dataset.stable_id
            ),
        );
    }

    Ok(result)
}

fn pack_dto(
    dataset: KnowledgeDatasetConfig,
    reconciliation: Option<retrieval::KnowledgeReconciliation>,
) -> KnowledgePackDto {
    KnowledgePackDto {
        stable_id: dataset.stable_id,
        label: dataset.label,
        download_size_bytes: dataset.download_size_bytes,
        status: reconciliation.map(|result| result.status.into()),
        attribution: dataset.attribution.into(),
    }
}

#[tauri::command]
pub async fn knowledge_catalog(
    model_state: TauriState<'_, ModelDownloadState>,
    knowledge_state: TauriState<'_, State>,
    reconcile_stable_ids: Option<Vec<String>>,
) -> Result<Vec<KnowledgePackDto>, ApiError> {
    let store = model_state.store();
    let selected = reconcile_stable_ids.map(|ids| ids.into_iter().collect::<HashSet<_>>());
    let mut packs = Vec::new();
    for dataset in ente_ensu::config::defaults().knowledge_datasets {
        if selected
            .as_ref()
            .is_some_and(|ids| !ids.contains(&dataset.stable_id))
        {
            packs.push(pack_dto(dataset, None));
            continue;
        }
        let lifecycle = knowledge_state.pack_lifecycle(&dataset.stable_id);
        let _lifecycle = lifecycle.lock().await;
        let indexes = Arc::clone(&knowledge_state.indexes);
        let reconcile_store = Arc::clone(&store);
        let reconcile_dataset = dataset.clone();
        let reconciliation = async_runtime::spawn_blocking(move || {
            reconcile_and_open(&reconcile_store, &indexes, &reconcile_dataset)
        })
        .await;
        let reconciliation = match reconciliation {
            Ok(Ok(result)) => result,
            result => {
                let error = match result {
                    Ok(Err(error)) => error.message,
                    Err(error) => error.to_string(),
                    Ok(Ok(_)) => unreachable!(),
                };
                logging::log(
                    "Knowledge",
                    format!(
                        "pack reconciliation failed pack={} error={error}",
                        dataset.stable_id
                    ),
                );
                retrieval::KnowledgeReconciliation {
                    status: retrieval::KnowledgeReconciliationStatus::Download,
                    active_identity: None,
                    active_directory: None,
                }
            }
        };
        packs.push(pack_dto(dataset, Some(reconciliation)));
    }
    Ok(packs)
}

#[tauri::command]
pub async fn knowledge_download_pack(
    window: WebviewWindow,
    model_state: TauriState<'_, ModelDownloadState>,
    knowledge_state: TauriState<'_, State>,
    stable_id: String,
) -> Result<KnowledgePackDto, ApiError> {
    let dataset = knowledge_dataset(&stable_id)?;
    let asset = retrieval::knowledge_asset(&dataset)
        .map_err(|error| ApiError::new("invalid_target", error.to_string()))?;
    let store = model_state.store();
    let token = {
        let mut active = knowledge_state
            .active_downloads
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        if active.contains_key(&stable_id) {
            return Err(ApiError::new(
                "download_active",
                "This knowledge pack is already downloading",
            ));
        }
        let token = download::CancellationToken::new();
        active.insert(stable_id.clone(), token.clone());
        token
    };
    let lifecycle = knowledge_state.pack_lifecycle(&stable_id);
    let _lifecycle = lifecycle.lock().await;

    let progress_id = stable_id.clone();
    let download_result = store
        .download(
            std::slice::from_ref(&asset),
            move |progress| {
                let _ = window.emit(
                    "knowledge-download-progress",
                    KnowledgeDownloadProgressDto {
                        stable_id: progress_id.clone(),
                        percent: (progress.batch_percentage as i32).clamp(0, 99),
                    },
                );
            },
            token.clone(),
        )
        .await;

    let indexes = Arc::clone(&knowledge_state.indexes);
    let reconcile_store = Arc::clone(&store);
    let reconcile_dataset = dataset.clone();
    let reconciliation_result = async_runtime::spawn_blocking(move || {
        reconcile_and_open(&reconcile_store, &indexes, &reconcile_dataset)
    })
    .await;

    let was_cancelled = {
        let mut active = knowledge_state
            .active_downloads
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let was_cancelled = token.is_cancelled();
        active.remove(&stable_id);
        was_cancelled
    };

    if let Err(error) = download_result {
        match &reconciliation_result {
            Ok(Err(reconcile_error)) => logging::log(
                "Knowledge",
                format!(
                    "post-download reconciliation failed pack={} error={}",
                    dataset.stable_id, reconcile_error.message
                ),
            ),
            Err(error) => logging::log(
                "Knowledge",
                format!(
                    "post-download reconciliation task failed pack={} error={error}",
                    dataset.stable_id
                ),
            ),
            Ok(Ok(_)) => {}
        }
        return Err(ApiError::new(
            crate::commands::llm::download_code(&error),
            error.to_string(),
        ));
    }
    if was_cancelled {
        return Err(ApiError::new(
            "cancelled",
            "Knowledge pack download cancelled",
        ));
    }
    let reconciliation = reconciliation_result
        .map_err(|_| ApiError::new("io_thread", "Knowledge reconciliation task failed"))??;

    if reconciliation.active_identity.as_deref() != Some(dataset.current_download_identity.as_str())
    {
        return Err(ApiError::new(
            "validation",
            "Downloaded knowledge pack failed current revision validation",
        ));
    }

    Ok(pack_dto(dataset, Some(reconciliation)))
}

#[tauri::command]
pub fn knowledge_cancel_pack_download(knowledge_state: TauriState<'_, State>, stable_id: String) {
    if let Some(token) = knowledge_state
        .active_downloads
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .get(&stable_id)
    {
        token.cancel();
    }
}

#[tauri::command]
pub async fn knowledge_retrieve(
    model_state: TauriState<'_, ModelDownloadState>,
    llm_state: TauriState<'_, crate::commands::llm::State>,
    knowledge_state: TauriState<'_, State>,
    query: String,
    enabled_stable_ids: Vec<String>,
    max_context_utf8_bytes: u32,
    retrieval_epoch: u64,
) -> Result<Option<KnowledgePromptContextDto>, ApiError> {
    if query.trim().is_empty() || enabled_stable_ids.is_empty() || max_context_utf8_bytes == 0 {
        return Ok(None);
    }

    let defaults = ente_ensu::config::defaults();
    let enabled = enabled_stable_ids.into_iter().collect::<HashSet<_>>();
    let datasets = defaults
        .knowledge_datasets
        .into_iter()
        .filter(|dataset| enabled.contains(&dataset.stable_id))
        .collect::<Vec<_>>();

    let embedding = defaults.knowledge_embedding;
    let store = model_state.store();
    let embedding_asset = ente_ensu::model::knowledge_embedding_model_asset();
    if !store.is_downloaded(&embedding_asset) {
        return Err(ApiError::new(
            "embedding_missing",
            "The knowledge embedding model is not downloaded",
        ));
    }
    let embedding_path = ente_ensu::model::llm_model_path(&store, &embedding_asset)
        .ok_or_else(|| ApiError::new("embedding_missing", "Embedding model path is missing"))?;
    let indexes = Arc::clone(&knowledge_state.indexes);
    let cancellation_epoch = llm_state.retrieval_epoch();
    if cancellation_epoch.load(Ordering::Relaxed) != retrieval_epoch {
        return Err(ApiError::new("cancelled", "Knowledge retrieval cancelled"));
    }
    let _lifecycle = llm_state.lifecycle().lock().await;
    if cancellation_epoch.load(Ordering::Relaxed) != retrieval_epoch {
        return Err(ApiError::new("cancelled", "Knowledge retrieval cancelled"));
    }
    crate::commands::llm::replace_state(&llm_state, None, None)?;

    async_runtime::spawn_blocking(move || {
        let check_cancelled = || {
            if cancellation_epoch.load(Ordering::Relaxed) == retrieval_epoch {
                Ok(())
            } else {
                Err(ApiError::new("cancelled", "Knowledge retrieval cancelled"))
            }
        };
        check_cancelled()?;
        let model = llm::Model::load(llm::ModelLoadParams {
            model_path: embedding_path.display().to_string(),
            n_gpu_layers: Some(0),
            use_mmap: Some(true),
            use_mlock: Some(false),
        })
        .map_err(crate::commands::llm::llm_api_error)?;
        check_cancelled()?;
        let threads = std::thread::available_parallelism()
            .map(|count| count.get().saturating_sub(1).max(1))
            .unwrap_or(1);
        let threads = i32::try_from(threads).unwrap_or(1);
        let context = llm::Context::new_knowledge_embedding(&model, Some(threads))
            .map_err(crate::commands::llm::llm_api_error)?;
        check_cancelled()?;
        let query_embedding = context
            .embed(query.trim())
            .map_err(crate::commands::llm::llm_api_error)?;
        check_cancelled()?;

        let indexes = indexes.lock().unwrap_or_else(PoisonError::into_inner);
        let mut hits = Vec::<retrieval::KnowledgePromptHit>::new();
        for dataset in &datasets {
            check_cancelled()?;
            let Some(open) = indexes.get(&dataset.stable_id) else {
                continue;
            };
            match open.index.search(
                &query_embedding,
                embedding.max_hits,
                dataset.relevance_threshold,
            ) {
                Ok(dataset_hits) => {
                    hits.extend(dataset_hits.into_iter().map(|hit| {
                        retrieval::KnowledgePromptHit {
                            dataset_id: dataset.stable_id.clone(),
                            hit,
                        }
                    }));
                }
                Err(error) => logging::log(
                    "Knowledge",
                    format!(
                        "pack search skipped pack={} error={error}",
                        dataset.stable_id
                    ),
                ),
            }
        }
        drop(indexes);
        check_cancelled()?;

        hits.sort_by(|left, right| right.hit.score.total_cmp(&left.hit.score));
        hits.truncate(embedding.max_hits as usize);
        let budget = max_context_utf8_bytes.min(embedding.max_context_utf8_bytes) as usize;
        retrieval::build_knowledge_prompt_context(&hits, budget)
            .map(|context| context.map(Into::into))
            .map_err(retrieval_error)
    })
    .await
    .map_err(|_| ApiError::new("llm_thread", "Knowledge retrieval task failed"))?
}

pub(crate) fn clear_for_exit(app: &AppHandle) {
    let Some(state) = app.try_state::<State>() else {
        return;
    };
    for token in state
        .active_downloads
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .values()
    {
        token.cancel();
    }
    state
        .indexes
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
}
