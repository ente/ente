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
const MAX_HITS: u32 = 2;
const MAX_CONTEXT_UTF8_BYTES: u32 = 6_000;
const MODIFICATION_NOTICE: &str = "Adapted by Ente";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KnowledgeEmbeddingConfig {
    pub model_url: String,
    pub model_size: u64,
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

#[derive(Debug, Clone, PartialEq, Eq)]
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
    pub artifact_sizes: Vec<u64>,
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

pub(crate) fn format_knowledge_document_prompt(title: &str, text: &str) -> String {
    #[expect(
        clippy::expect_used,
        reason = "The fixed prompt contains the title placeholder"
    )]
    let (prefix, remainder) = DOCUMENT_PROMPT
        .split_once("{title}")
        .expect("knowledge document prompt contains a title placeholder");
    #[expect(
        clippy::expect_used,
        reason = "The fixed prompt contains the text placeholder after the title"
    )]
    let (middle, suffix) = remainder
        .split_once("{text}")
        .expect("knowledge document prompt contains a text placeholder");
    [prefix, title, middle, text, suffix].concat()
}

pub(crate) fn knowledge_embedding_config() -> KnowledgeEmbeddingConfig {
    KnowledgeEmbeddingConfig {
        model_url: EMBEDDING_MODEL_URL.to_owned(),
        model_size: 333_590_944,
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
            current_download_identity: "simplewiki-2026-10-01".to_owned(),
            artifact_base_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/resolve/1a24af36cb29b41326d24fd8486e12388a2f55e5/simplewiki/data/".to_owned(),
            artifact_sizes: vec![1_237, 135_822_336, 33_622_894, 16_592],
            artifact_sha256: vec![
                "b7f96b451d244e788ad6ff37a3fc9f256ee1d2561d66e01fa21231fa8d4cd9f8".to_owned(),
                "ef7638ee02ccdfc3f7ef0a39cb47b81d6d1d348d2752f68887200cb624e02436".to_owned(),
                "738442ff836a9f5bf77df918bfba6bcb54d9936dcdb0556c70310ffed260a0ff".to_owned(),
                "aac8aa9d837d6d1954dd3dfb0ab8e72c0f6b5bbbe64f26d19236e747f53dc967".to_owned(),
            ],
            download_size_bytes: 169_463_059,
            max_chars: 600,
            source_url_template: "https://simple.wikipedia.org/wiki/{title}".to_owned(),
            relevance_threshold: 0.55,
            attribution: AttributionConfig {
                credit: "Simple English Wikipedia contributors".to_owned(),
                license_label: KNOWLEDGE_LICENSE_LABEL.to_owned(),
                license_url: KNOWLEDGE_LICENSE_URL.to_owned(),
                public_pack_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/tree/1a24af36cb29b41326d24fd8486e12388a2f55e5/simplewiki".to_owned(),
                modification_notice: MODIFICATION_NOTICE.to_owned(),
            },
        },
        KnowledgeDatasetConfig {
            stable_id: "wikibooks".to_owned(),
            label: "Wikibooks".to_owned(),
            current_download_identity: "enwikibooks-2026-10-01".to_owned(),
            artifact_base_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/resolve/1a24af36cb29b41326d24fd8486e12388a2f55e5/wikibooks/data/".to_owned(),
            artifact_sizes: vec![1_243, 128_000_000, 74_618_756, 15_640],
            artifact_sha256: vec![
                "2f60ff59c7715267541de63a822c742acc23b21b36f087a0d642ee0b9d7a8662".to_owned(),
                "3bea664593c44c5c296e3f09457bb06a0698d3e37353a366bd9c9e257b9b3319".to_owned(),
                "2dbbdeb96f0595fbe7adda43a450ff029bb509a764e0a48d7602ddb1d64eebee".to_owned(),
                "cf4690985df33f5409ac63149e2777c8b4f66a53f7bc942b32137aa21b5ea9c6".to_owned(),
            ],
            download_size_bytes: 202_635_639,
            max_chars: 1_400,
            source_url_template: "https://en.wikibooks.org/wiki/{title}".to_owned(),
            relevance_threshold: 0.58,
            attribution: AttributionConfig {
                credit: "Wikibooks contributors".to_owned(),
                license_label: KNOWLEDGE_LICENSE_LABEL.to_owned(),
                license_url: KNOWLEDGE_LICENSE_URL.to_owned(),
                public_pack_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/tree/1a24af36cb29b41326d24fd8486e12388a2f55e5/wikibooks".to_owned(),
                modification_notice: MODIFICATION_NOTICE.to_owned(),
            },
        },
        KnowledgeDatasetConfig {
            stable_id: "fullwiki".to_owned(),
            label: "English Wikipedia".to_owned(),
            current_download_identity: "enwiki-2026-10-01".to_owned(),
            artifact_base_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/resolve/1a24af36cb29b41326d24fd8486e12388a2f55e5/fullwiki/data/".to_owned(),
            artifact_sizes: vec![2_071, 270_491_136, 93_564_307, 33_032],
            artifact_sha256: vec![
                "8e5c2b7daa2af68de01815fba940dab065f8d8fac0a81d9787ab5f7bc4771e51".to_owned(),
                "2f64f11d739c540e6db471dc001401e2594c4237d773abafd5d75cb30613ca63".to_owned(),
                "d41f86cafc5debef310dca6863bd8377b4693c1b7e868c6570402e86d4f240c3".to_owned(),
                "f328cd85f9ee871a965fb0d9979ce9aafc835d952cbc01af73e69194b95265aa".to_owned(),
            ],
            download_size_bytes: 364_090_546,
            max_chars: 600,
            source_url_template: "https://en.wikipedia.org/wiki/{title}".to_owned(),
            relevance_threshold: 0.55,
            attribution: AttributionConfig {
                credit: "English Wikipedia contributors".to_owned(),
                license_label: KNOWLEDGE_LICENSE_LABEL.to_owned(),
                license_url: KNOWLEDGE_LICENSE_URL.to_owned(),
                public_pack_url: "https://huggingface.co/datasets/ente-ai/ensu-knowledge-packs/tree/1a24af36cb29b41326d24fd8486e12388a2f55e5/fullwiki".to_owned(),
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
    use std::collections::HashSet;

    use super::*;

    #[test]
    fn artifact_urls_append_only_fixed_names() {
        let urls = knowledge_artifact_urls(&knowledge_datasets()[0]);
        assert_eq!(
            urls.each_ref()
                .map(|url| url.rsplit('/').next().unwrap().to_owned()),
            KNOWLEDGE_ARTIFACT_FILENAMES.map(str::to_owned)
        );
    }

    #[test]
    fn pinned_catalog_and_embedding_are_valid() {
        let datasets = knowledge_datasets();
        let embedding = knowledge_embedding_config();

        assert_eq!(
            datasets
                .iter()
                .map(|dataset| dataset.stable_id.as_str())
                .collect::<HashSet<_>>()
                .len(),
            datasets.len()
        );
        assert!(datasets.iter().all(|dataset| {
            dataset.artifact_sizes.iter().sum::<u64>()
                == u64::try_from(dataset.download_size_bytes).unwrap()
        }));
        assert!(datasets.iter().all(|dataset| {
            dataset.artifact_sizes.len() == KNOWLEDGE_ARTIFACT_FILENAMES.len()
                && dataset.artifact_sha256.len() == KNOWLEDGE_ARTIFACT_FILENAMES.len()
                && dataset
                    .artifact_sha256
                    .iter()
                    .all(|sha256| sha256.len() == 64)
        }));
        assert_eq!(embedding.model_sha256.len(), 64);
        assert!(datasets.iter().all(|dataset| {
            is_path_safe_component(&dataset.stable_id)
                && is_path_safe_component(&dataset.current_download_identity)
        }));
        assert!(knowledge_dataset("missing").is_none());
    }
}
