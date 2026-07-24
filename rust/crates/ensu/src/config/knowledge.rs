pub(crate) const KNOWLEDGE_LICENSE_LABEL: &str = "CC BY-SA 4.0";
pub(crate) const KNOWLEDGE_LICENSE_URL: &str = "https://creativecommons.org/licenses/by-sa/4.0/";

pub(crate) const KNOWLEDGE_MANIFEST_FILE: &str = "manifest.json";
pub(crate) const KNOWLEDGE_VECTORS_FILE: &str = "vectors.i8";
pub(crate) const KNOWLEDGE_META_FILE: &str = "meta.zst";
pub(crate) const KNOWLEDGE_OFFSETS_FILE: &str = "meta.offsets";
pub(crate) const KNOWLEDGE_ARTIFACT_FILENAMES: [&str; 4] = [
    KNOWLEDGE_MANIFEST_FILE,
    KNOWLEDGE_VECTORS_FILE,
    KNOWLEDGE_META_FILE,
    KNOWLEDGE_OFFSETS_FILE,
];

const EMBEDDING_MODEL_IDENTITY: &str =
    "ggml-org/embeddinggemma-300M-GGUF:embeddinggemma-300M-Q8_0.gguf";
const DOCUMENT_PROMPT: &str = "title: {title} | text: {text}";
const QUERY_PROMPT: &str = "task: search result | query: {query}";
const EMBEDDING_MODEL_URL: &str = "https://huggingface.co/ente-ai/embeddinggemma-300m-gguf/resolve/957b55764bd672f51240ac026e3a23ac9459ee3c/embeddinggemma-300M-Q8_0.gguf";
const EMBEDDING_MODEL_SHA256: &str =
    "b5ce9d77a3fc4b3b39ccb5643c36777911cc4eb46a66962eadfa3f5f60490d63";
const EMBEDDING_TARGET_ID: &str = "embeddinggemma-300m-q8-0";
const SOURCE_DIM: u32 = 768;
const RETRIEVAL_DIM: u32 = 512;
const EMBEDDING_CONTEXT_SIZE: u32 = 2_048;
const MAX_HITS: u32 = 3;
const MAX_CONTEXT_UTF8_BYTES: u32 = 6_000;
const MODIFICATION_NOTICE: &str = "Adapted by Ente";

#[derive(Debug, Clone, PartialEq)]
pub struct KnowledgeEmbeddingConfig {
    pub model_url: String,
    pub model_sha256: String,
    pub target_id: String,
    pub source_dim: u32,
    pub dim: u32,
    pub query_prompt: String,
    pub context_size: u32,
    pub batch_size: u32,
    pub micro_batch_size: u32,
    pub max_hits: u32,
    pub max_context_utf8_bytes: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AttributionConfig {
    pub credit: String,
    pub license_label: String,
    pub license_url: String,
    pub public_pack_url: String,
    pub modification_notice: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct KnowledgeDatasetConfig {
    pub stable_id: String,
    pub label: String,
    pub current_download_identity: String,
    pub artifact_base_url: String,
    pub artifact_sha256: Vec<String>,
    pub download_size_bytes: i64,
    pub max_chars: u32,
    pub source_url_template: String,
    pub relevance_threshold: f32,
    pub attribution: AttributionConfig,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KnowledgeIndexContract {
    pub model: String,
    pub source_dim: u32,
    pub matryoshka: bool,
    pub doc_prompt: String,
    pub query_prompt: String,
    pub dim: u32,
    pub quant: String,
    pub scale: u32,
    pub meta_codec: String,
    pub meta_rows_per_block: u32,
}

pub(crate) fn knowledge_index_contract() -> KnowledgeIndexContract {
    KnowledgeIndexContract {
        model: EMBEDDING_MODEL_IDENTITY.to_owned(),
        source_dim: SOURCE_DIM,
        matryoshka: true,
        doc_prompt: DOCUMENT_PROMPT.to_owned(),
        query_prompt: QUERY_PROMPT.to_owned(),
        dim: RETRIEVAL_DIM,
        quant: "int8".to_owned(),
        scale: 127,
        meta_codec: "zstd-blocks".to_owned(),
        meta_rows_per_block: 128,
    }
}

pub(crate) fn knowledge_embedding_config() -> KnowledgeEmbeddingConfig {
    KnowledgeEmbeddingConfig {
        model_url: EMBEDDING_MODEL_URL.to_owned(),
        model_sha256: EMBEDDING_MODEL_SHA256.to_owned(),
        target_id: EMBEDDING_TARGET_ID.to_owned(),
        source_dim: SOURCE_DIM,
        dim: RETRIEVAL_DIM,
        query_prompt: QUERY_PROMPT.to_owned(),
        context_size: EMBEDDING_CONTEXT_SIZE,
        batch_size: EMBEDDING_CONTEXT_SIZE,
        micro_batch_size: EMBEDDING_CONTEXT_SIZE,
        max_hits: MAX_HITS,
        max_context_utf8_bytes: MAX_CONTEXT_UTF8_BYTES,
    }
}

pub(crate) fn knowledge_datasets() -> Vec<KnowledgeDatasetConfig> {
    vec![
        KnowledgeDatasetConfig {
            stable_id: "simplewiki".to_owned(),
            label: "Simple English Wikipedia".to_owned(),
            current_download_identity: "simplewiki-2026-07-02".to_owned(),
            artifact_base_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/resolve/a13b90e443dcdc1561ac777ea17ee6ed4703e35f/simplewiki/data/".to_owned(),
            artifact_sha256: vec![
                "118dfc77aef7c7186c8b15551ec94e8b8878fde0b3ca20c97cc8222e5b70b309".to_owned(),
                "ed90f60e757784fd4752652139299be792948628be5d7455847333f362d30cd5".to_owned(),
                "d16e84f734fb5f216acd89ed4451c35f6b9777d4d85e1a1f883ec4c44a984471".to_owned(),
                "51530bed206223347f12b7cf931df0172746c5732da76ebae3ae355f85031e3f".to_owned(),
            ],
            download_size_bytes: 167_849_446,
            max_chars: 600,
            source_url_template: "https://simple.wikipedia.org/wiki/{title}".to_owned(),
            relevance_threshold: 0.5,
            attribution: AttributionConfig {
                credit: "Simple English Wikipedia contributors".to_owned(),
                license_label: KNOWLEDGE_LICENSE_LABEL.to_owned(),
                license_url: KNOWLEDGE_LICENSE_URL.to_owned(),
                public_pack_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/tree/a13b90e443dcdc1561ac777ea17ee6ed4703e35f/simplewiki".to_owned(),
                modification_notice: MODIFICATION_NOTICE.to_owned(),
            },
        },
        KnowledgeDatasetConfig {
            stable_id: "wikibooks".to_owned(),
            label: "Wikibooks".to_owned(),
            current_download_identity: "enwikibooks-2026-07-02".to_owned(),
            artifact_base_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/resolve/a13b90e443dcdc1561ac777ea17ee6ed4703e35f/wikibooks/data/".to_owned(),
            artifact_sha256: vec![
                "2076386cdc215ca4950aa92c4b6bcac605a63e76fda4989677eb5f9a637bba14".to_owned(),
                "bcf4f5d15b78470def1908aaddcb2abae17fbe7752d60c90d11fd4d951b0b591".to_owned(),
                "6c071ac25729f43f69c614489e38e3a7a2406febf679ad6272609ad48447daf2".to_owned(),
                "58f0c01aff935c04cc301fa94633235ab8aa1dd31e0320855ecc1d57bd2f606f".to_owned(),
            ],
            download_size_bytes: 202_595_475,
            max_chars: 1_400,
            source_url_template: "https://en.wikibooks.org/wiki/{title}".to_owned(),
            relevance_threshold: 0.5,
            attribution: AttributionConfig {
                credit: "Wikibooks contributors".to_owned(),
                license_label: KNOWLEDGE_LICENSE_LABEL.to_owned(),
                license_url: KNOWLEDGE_LICENSE_URL.to_owned(),
                public_pack_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/tree/a13b90e443dcdc1561ac777ea17ee6ed4703e35f/wikibooks".to_owned(),
                modification_notice: MODIFICATION_NOTICE.to_owned(),
            },
        },
    ]
}

pub fn knowledge_dataset(stable_id: &str) -> Option<KnowledgeDatasetConfig> {
    knowledge_datasets()
        .into_iter()
        .find(|dataset| dataset.stable_id == stable_id)
}

pub(crate) fn knowledge_artifact_urls(dataset: &KnowledgeDatasetConfig) -> [String; 4] {
    KNOWLEDGE_ARTIFACT_FILENAMES.map(|name| format!("{}{name}", dataset.artifact_base_url))
}

pub(crate) fn is_path_safe_component(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 255
        && value != "."
        && value != ".."
        && !value.chars().any(|character| {
            character.is_control() || character == '/' || character == '\\' || character == ':'
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn artifact_urls_append_only_fixed_names() {
        let urls = knowledge_artifact_urls(&knowledge_datasets()[0]);
        assert_eq!(
            urls.each_ref()
                .map(|url| url.rsplit('/').next().unwrap().to_owned()),
            KNOWLEDGE_ARTIFACT_FILENAMES.map(str::to_owned)
        );
        assert!(urls.iter().all(|url| {
            url.contains("/resolve/a13b90e443dcdc1561ac777ea17ee6ed4703e35f/simplewiki/data/")
        }));
    }

    #[test]
    fn pinned_catalog_and_embedding_are_valid() {
        let datasets = knowledge_datasets();
        let embedding = knowledge_embedding_config();

        assert_eq!(datasets.len(), 2);
        assert_eq!(datasets[0].stable_id, "simplewiki");
        assert_eq!(datasets[1].stable_id, "wikibooks");
        assert!(
            datasets
                .iter()
                .all(|dataset| dataset.attribution.modification_notice == "Adapted by Ente")
        );
        assert_eq!(datasets[0].download_size_bytes, 167_849_446);
        assert_eq!(datasets[1].download_size_bytes, 202_595_475);
        assert!(datasets.iter().all(|dataset| {
            dataset.artifact_sha256.len() == KNOWLEDGE_ARTIFACT_FILENAMES.len()
                && dataset
                    .artifact_sha256
                    .iter()
                    .all(|sha256| sha256.len() == 64)
        }));
        assert_eq!(embedding.model_sha256.len(), 64);
        assert_eq!(knowledge_index_contract().source_dim, 768);
        assert_eq!(knowledge_index_contract().dim, 512);
        assert!(datasets.iter().all(|dataset| {
            is_path_safe_component(&dataset.stable_id)
                && is_path_safe_component(&dataset.current_download_identity)
        }));
        assert!(knowledge_dataset("missing").is_none());
    }
}
