use std::collections::{HashMap, HashSet};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, PoisonError};

use ente_assets::{AssetStore, download};
use ente_ensu::config::{AttributionConfig, KnowledgeDatasetConfig};
use ente_ensu::retrieval;
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

pub(crate) struct SourceSelection {
    pack_ids: HashSet<String>,
    note_collection_ids: HashSet<String>,
}

impl SourceSelection {
    pub(super) fn new(pack_ids: Vec<String>, note_collection_ids: Vec<String>) -> Self {
        Self {
            pack_ids: pack_ids.into_iter().collect(),
            note_collection_ids: note_collection_ids.into_iter().collect(),
        }
    }

    pub(super) fn allows(&self, locator: &retrieval::PassageLocator) -> bool {
        match locator {
            retrieval::PassageLocator::EnsuPack { dataset_id, .. } => {
                self.pack_ids.contains(dataset_id)
            }
            retrieval::PassageLocator::LocalNote(locator) => {
                self.note_collection_ids.contains(&locator.collection_id)
            }
        }
    }
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
    status: KnowledgePackStatusDto,
    attribution: AttributionDto,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceCitationDto {
    dataset_id: String,
    dataset_label: String,
    credit: String,
    title: String,
    source_url: String,
    license_label: String,
    license_url: String,
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

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteSourceReferenceDto {
    collection_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    collection_label: Option<String>,
    document_id: String,
    indexed_revision: String,
    title: String,
    section: Option<String>,
}

impl From<ente_ensu::notes::NoteSourceReference> for NoteSourceReferenceDto {
    fn from(value: ente_ensu::notes::NoteSourceReference) -> Self {
        Self {
            collection_id: value.collection_id,
            collection_label: value.collection_label,
            document_id: value.document_id,
            indexed_revision: value.indexed_revision,
            title: value.title,
            section: value.section,
        }
    }
}

impl From<NoteSourceReferenceDto> for ente_ensu::notes::NoteSourceReference {
    fn from(value: NoteSourceReferenceDto) -> Self {
        Self {
            collection_id: value.collection_id,
            collection_label: value.collection_label,
            document_id: value.document_id,
            indexed_revision: value.indexed_revision,
            title: value.title,
            section: value.section,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum GroundedSourceDto {
    EnsuPack { citation: SourceCitationDto },
    LocalNote { reference: NoteSourceReferenceDto },
}

impl From<retrieval::GroundedSource> for GroundedSourceDto {
    fn from(value: retrieval::GroundedSource) -> Self {
        match value {
            retrieval::GroundedSource::EnsuPack { citation } => Self::EnsuPack {
                citation: citation.into(),
            },
            retrieval::GroundedSource::LocalNote { reference } => Self::LocalNote {
                reference: reference.into(),
            },
        }
    }
}

impl From<GroundedSourceDto> for retrieval::GroundedSource {
    fn from(value: GroundedSourceDto) -> Self {
        match value {
            GroundedSourceDto::EnsuPack { citation } => Self::EnsuPack {
                citation: citation.into(),
            },
            GroundedSourceDto::LocalNote { reference } => Self::LocalNote {
                reference: reference.into(),
            },
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GroundedPromptContextDto {
    text: String,
    sources: Vec<GroundedSourceDto>,
    #[serde(skip_serializing_if = "Option::is_none")]
    candidates: Option<ente_ensu::conversation::GroundingCandidates>,
}

impl From<retrieval::GroundedPromptContext> for GroundedPromptContextDto {
    fn from(value: retrieval::GroundedPromptContext) -> Self {
        Self {
            text: value.text,
            sources: value.sources.into_iter().map(Into::into).collect(),
            candidates: None,
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

fn select_verified_mixed_grounding(
    pack_hits: &[retrieval::KnowledgePromptHit],
    note_hits: &[ente_ensu::notes::NotesSearchHit],
    mut verify: impl FnMut(&ente_ensu::notes::NoteSourceReference) -> Result<bool, ApiError>,
) -> Result<Vec<retrieval::GroundedExcerpt>, ApiError> {
    let selected = retrieval::select_mixed_grounding_candidates(pack_hits, note_hits, usize::MAX)
        .map_err(retrieval_error)?;
    let mut verified = Vec::with_capacity(selected.len());
    let mut verified_note_count = 0_usize;
    for excerpt in selected {
        if let retrieval::GroundedSource::LocalNote { reference } = &excerpt.source {
            if verified_note_count == retrieval::MAX_NOTES_GROUNDING_HITS {
                continue;
            }
            if !verify(reference)? {
                continue;
            }
            verified_note_count += 1;
        }
        verified.push(excerpt);
    }
    Ok(verified)
}

fn select_grounding(
    app: &AppHandle,
    pack_hits: &[retrieval::KnowledgePromptHit],
    note_hits: &[ente_ensu::notes::NotesSearchHit],
    notes: Option<&super::notes::RetrievalHandle>,
    mut check_cancelled: impl FnMut() -> Result<(), ApiError>,
) -> Result<Vec<retrieval::GroundedExcerpt>, ApiError> {
    let mut excerpts = select_verified_mixed_grounding(pack_hits, note_hits, |reference| {
        check_cancelled()?;
        let Some(notes) = notes else { return Ok(false) };
        let valid = notes.verify_source_reference(reference);
        if !valid {
            super::notes::mark_reference_stale(
                app,
                &reference.collection_id,
                reference.document_id.clone(),
            );
        }
        Ok(valid)
    })?;
    for excerpt in &mut excerpts {
        if let (Some(notes), retrieval::GroundedSource::LocalNote { reference }) =
            (notes, &mut excerpt.source)
        {
            reference.collection_label = notes.collection_label(&reference.collection_id);
        }
    }
    check_cancelled()?;
    Ok(excerpts)
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
    reconciliation: retrieval::KnowledgeReconciliation,
) -> KnowledgePackDto {
    KnowledgePackDto {
        stable_id: dataset.stable_id,
        label: dataset.label,
        download_size_bytes: dataset.download_size_bytes,
        status: reconciliation.status.into(),
        attribution: dataset.attribution.into(),
    }
}

#[tauri::command]
pub async fn knowledge_catalog(
    model_state: TauriState<'_, ModelDownloadState>,
    knowledge_state: TauriState<'_, State>,
) -> Result<Vec<KnowledgePackDto>, ApiError> {
    let store = model_state.store();
    let mut packs = Vec::new();
    for dataset in ente_ensu::config::defaults().knowledge_datasets {
        let lifecycle = knowledge_state.pack_lifecycle(&dataset.stable_id);
        let _lifecycle = lifecycle.lock().await;
        let indexes = Arc::clone(&knowledge_state.indexes);
        let reconcile_store = Arc::clone(&store);
        let reconcile_dataset = dataset.clone();
        let reconciliation = async_runtime::spawn_blocking(move || {
            reconcile_and_open(&reconcile_store, &indexes, &reconcile_dataset)
        })
        .await
        .map_err(|error| ApiError::other(error.to_string()))??;
        packs.push(pack_dto(dataset, reconciliation));
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

    Ok(pack_dto(dataset, reconciliation))
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RetrieveRequest {
    query: String,
    enabled_stable_ids: Vec<String>,
    enabled_note_collection_ids: Vec<String>,
    max_context_utf8_bytes: u32,
    retrieval_epoch: u64,
}

#[tauri::command]
pub async fn knowledge_retrieve(
    app: AppHandle,
    model_state: TauriState<'_, ModelDownloadState>,
    llm_state: TauriState<'_, crate::commands::llm::State>,
    input: RetrieveRequest,
) -> Result<Option<GroundedPromptContextDto>, ApiError> {
    let RetrieveRequest {
        query,
        enabled_stable_ids,
        enabled_note_collection_ids,
        max_context_utf8_bytes,
        retrieval_epoch,
    } = input;
    let knowledge_state = app.state::<State>();
    let selection = SourceSelection::new(enabled_stable_ids, enabled_note_collection_ids);
    let (note_collection_ids, notes) = app
        .try_state::<crate::commands::notes::State>()
        .map_or_else(
            || (Vec::new(), None),
            |state| {
                (
                    state
                        .available_index_collection_ids()
                        .into_iter()
                        .filter(|id| selection.note_collection_ids.contains(id))
                        .collect::<Vec<_>>(),
                    Some(state.retrieval_handle()),
                )
            },
        );
    if query.trim().is_empty()
        || (selection.pack_ids.is_empty() && note_collection_ids.is_empty())
        || max_context_utf8_bytes == 0
    {
        return Ok(None);
    }

    let defaults = ente_ensu::config::defaults();
    let datasets = defaults
        .knowledge_datasets
        .into_iter()
        .filter(|dataset| selection.pack_ids.contains(&dataset.stable_id))
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
        let context = crate::commands::llm::load_knowledge_embedding_context(
            &embedding_path,
            check_cancelled,
        )?;
        check_cancelled()?;
        let query_embedding = context
            .embed(query.trim())
            .map_err(crate::commands::llm::llm_api_error)?;
        check_cancelled()?;

        let indexes = indexes.lock().unwrap_or_else(PoisonError::into_inner);
        let mut pack_hits = Vec::<retrieval::KnowledgePromptHit>::new();
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
                    pack_hits.extend(dataset_hits.into_iter().map(|hit| {
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

        let mut note_hits = Vec::new();
        if let Some(notes) = &notes {
            for collection_id in &note_collection_ids {
                check_cancelled()?;
                match notes.search_collection(collection_id, &query_embedding) {
                    Ok(collection_hits) => note_hits.extend(collection_hits),
                    Err(error) => {
                        crate::commands::notes::mark_index_unreadable(&app, collection_id);
                        logging::log(
                            "Knowledge",
                            format!(
                                "Notes search skipped and queued for rebuild collection={collection_id} error={error}"
                            ),
                        );
                    }
                }
            }
        }
        check_cancelled()?;

        let context_budget = max_context_utf8_bytes.min(embedding.max_context_utf8_bytes);
        let excerpts = select_grounding(&app, &pack_hits, &note_hits, notes.as_ref(), check_cancelled)?;

        let candidates = ente_ensu::conversation::GroundingCandidates::new(vec![], excerpts, context_budget as usize)
            .map_err(|error| ApiError::new("conversation", error.to_string()))?;
        candidates.pack(context_budget as usize)
            .map(|context| context.map(|context| {
                let mut result = GroundedPromptContextDto::from(context);
                result.candidates = Some(candidates);
                result
            }))
            .map_err(|error| ApiError::new("conversation", error.to_string()))
    })
    .await
    .map_err(|_| ApiError::new("llm_thread", "Knowledge retrieval task failed"))?
}

pub(crate) async fn reload_for_followup(
    app: &AppHandle,
    reference: retrieval::IncludedPassage,
    selection: &SourceSelection,
    retrieval_epoch: u64,
) -> Result<Option<retrieval::ReferencedPassage>, ApiError> {
    if !selection.allows(&reference.locator) {
        return Ok(None);
    }
    let app = app.clone();
    let indexes = Arc::clone(&app.state::<State>().indexes);
    let (collection_ids, notes) = app
        .try_state::<crate::commands::notes::State>()
        .map_or_else(
            || (Vec::new(), None),
            |state| {
                (
                    state.available_index_collection_ids(),
                    Some(state.retrieval_handle()),
                )
            },
        );
    let cancellation_epoch = app.state::<crate::commands::llm::State>().retrieval_epoch();
    async_runtime::spawn_blocking(move || {
        let check_cancelled = || {
            if cancellation_epoch.load(Ordering::Relaxed) == retrieval_epoch {
                Ok(())
            } else {
                Err(ApiError::new("cancelled", "Knowledge reload cancelled"))
            }
        };
        check_cancelled()?;
        let mut packs = Vec::new();
        let mut note_hits = Vec::new();
        match &reference.locator {
            retrieval::PassageLocator::EnsuPack { dataset_id, .. } => {
                let indexes = indexes.lock().unwrap_or_else(PoisonError::into_inner);
                let Some(open) = indexes.get(dataset_id) else {
                    return Ok(None);
                };
                let Some(hit) = open
                    .index
                    .reload_passage(&reference.locator)
                    .map_err(retrieval_error)?
                else {
                    return Ok(None);
                };
                packs.push(retrieval::KnowledgePromptHit {
                    dataset_id: dataset_id.clone(),
                    hit,
                });
            }
            retrieval::PassageLocator::LocalNote(locator) => {
                let collection_id = &locator.collection_id;
                if !collection_ids.contains(collection_id) {
                    return Ok(None);
                }
                let Some(notes) = &notes else { return Ok(None) };
                match notes.reload_passage(locator) {
                    Ok(Some(hit)) => note_hits.push(hit),
                    Ok(None) => return Ok(None),
                    Err(error) => {
                        crate::commands::notes::mark_index_unreadable(&app, collection_id);
                        logging::log(
                            "Knowledge",
                            format!("Notes passage reload unavailable: {error}"),
                        );
                        return Ok(None);
                    }
                }
            }
        }
        check_cancelled()?;
        let Some(excerpt) =
            select_grounding(&app, &packs, &note_hits, notes.as_ref(), check_cancelled)?.pop()
        else {
            return Ok(None);
        };
        let Some(passages) = reference.verified_spans(&excerpt.text) else {
            return Ok(None);
        };
        check_cancelled()?;
        Ok(Some(retrieval::ReferencedPassage {
            reference,
            source: excerpt.source,
            passages,
        }))
    })
    .await
    .map_err(|_| ApiError::new("retrieval_thread", "Knowledge reload task failed"))?
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

#[cfg(test)]
mod tests {
    use super::*;
    use ente_ensu::notes::NotesSearchHit;

    const COLLECTION_ID: &str = "123e4567-e89b-12d3-a456-426614174000";

    fn note(index: usize) -> NotesSearchHit {
        NotesSearchHit {
            locator: ente_ensu::notes::NotePassageLocator {
                collection_id: COLLECTION_ID.to_owned(),
                document_id: format!("note-{index}.md"),
                indexed_revision: "a".repeat(64),
                shard_sha256: "b".repeat(64),
                chunk_index: 0,
            },
            collection_id: COLLECTION_ID.to_string(),
            document_id: format!("note-{index}.md"),
            revision: "a".repeat(64),
            score: 1.0 - index as f32 / 100.0,
            title: format!("Note {index}"),
            section: None,
            text: format!("passage {index}"),
        }
    }

    #[test]
    fn stale_top_notes_are_backfilled_with_verified_hits() {
        let notes = (0..6).map(note).collect::<Vec<_>>();

        let selected = select_verified_mixed_grounding(&[], &notes, |reference| {
            Ok(reference.document_id == "note-5.md")
        })
        .unwrap();

        assert_eq!(selected.len(), 1);
        assert!(matches!(
            &selected[0].source,
            retrieval::GroundedSource::LocalNote { reference }
                if reference.document_id == "note-5.md"
        ));
    }
}
