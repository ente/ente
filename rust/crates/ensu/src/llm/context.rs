use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::context::params::{LlamaContextParams, LlamaPoolingType};
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::mtmd::{MtmdContext, MtmdContextParams, mtmd_default_marker};
use llama_cpp_2::token::LlamaToken;
use self_cell::self_cell;
use serde::{Deserialize, Serialize};
use std::ffi::CString;
use std::num::NonZeroU32;
use std::path::Path;
use std::sync::{Arc, Mutex};

use super::model::ModelRef;
use super::{Error, backend, format_error, lock};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextParams {
    pub context_size: Option<i32>,
    pub n_threads: Option<i32>,
    pub n_batch: Option<i32>,
}

#[derive(Debug)]
pub struct EmbeddingContextParams {
    pub context_size: u32,
    pub n_threads: Option<i32>,
    pub batch_size: u32,
    pub micro_batch_size: u32,
    pub source_dim: u32,
    pub dim: u32,
    pub query_prompt: String,
}

self_cell!(
    struct ContextCell {
        owner: ModelRef,

        #[covariant]
        dependent: LlamaContext,
    }
);

#[derive(Debug, Clone, PartialEq, Eq)]
struct MtmdCacheKey {
    mmproj_path: String,
    media_marker: String,
    use_gpu: bool,
    print_timings: bool,
    n_threads: i32,
}

struct CachedMtmdContext {
    key: MtmdCacheKey,
    context: Arc<MtmdContext>,
}

struct ContextState {
    cell: ContextCell,
    cached_tokens: Vec<LlamaToken>,
}

pub struct Context {
    state: Mutex<ContextState>,
    mtmd_context: Mutex<Option<CachedMtmdContext>>,
    embedding_params: Option<EmbeddingContextParams>,
}

pub type ContextRef = Arc<Context>;

unsafe impl Send for Context {}
unsafe impl Sync for Context {}

impl Context {
    fn try_new(
        owner: ModelRef,
        embedding_params: Option<EmbeddingContextParams>,
        builder: impl for<'a> FnOnce(&'a ModelRef) -> Result<LlamaContext<'a>, Error>,
    ) -> Result<Self, Error> {
        ContextCell::try_new(owner, builder).map(|cell| Context {
            state: Mutex::new(ContextState {
                cell,
                cached_tokens: Vec::new(),
            }),
            mtmd_context: Mutex::new(None),
            embedding_params,
        })
    }

    pub(super) fn with_context_and_cache_mut<R>(
        &self,
        func: impl for<'a, 'b> FnOnce(&'b mut LlamaContext<'a>, &'b mut Vec<LlamaToken>) -> R,
    ) -> R {
        let mut state = lock(&self.state);
        let ContextState {
            cell,
            cached_tokens,
        } = &mut *state;
        cell.with_dependent_mut(|_owner, context| func(context, cached_tokens))
    }

    pub(super) fn embedding_params(&self) -> Option<&EmbeddingContextParams> {
        self.embedding_params.as_ref()
    }

    pub(super) fn cached_mtmd_context(
        &self,
        model: &LlamaModel,
        mmproj_path: &str,
        marker: &str,
    ) -> Result<Arc<MtmdContext>, Error> {
        if !Path::new(mmproj_path).exists() {
            return Err(Error::NotFound {
                what: "mmproj file",
                path: mmproj_path.to_string(),
            });
        }

        let (key, params) = mtmd_cache_key_and_params(mmproj_path, marker)?;
        let mut guard = lock(&self.mtmd_context);

        if let Some(cached) = guard.as_ref()
            && cached.key == key
        {
            return Ok(cached.context.clone());
        }

        let mtmd_ctx = Arc::new(
            MtmdContext::init_from_file(mmproj_path, model, &params).map_err(|err| {
                Error::Llama {
                    op: "Failed to initialize mmproj",
                    message: err.to_string(),
                }
            })?,
        );

        if !mtmd_ctx.support_vision() {
            return Err(Error::Unsupported("Model does not support vision input"));
        }

        *guard = Some(CachedMtmdContext {
            key,
            context: mtmd_ctx.clone(),
        });
        Ok(mtmd_ctx)
    }

    pub(super) fn invalidate_cache(&self) {
        lock(&self.state).cached_tokens.clear();
    }
}

fn mtmd_cache_key_and_params(
    mmproj_path: &str,
    marker: &str,
) -> Result<(MtmdCacheKey, MtmdContextParams), Error> {
    let media_marker = CString::new(marker.to_string())
        .map_err(|err| Error::InvalidInput(format_error("Invalid media marker", err)))?;
    let params = MtmdContextParams {
        use_gpu: false,
        print_timings: false,
        media_marker,
        ..Default::default()
    };
    let marker = params
        .media_marker
        .to_str()
        .map_err(|err| Error::InvalidInput(format_error("Invalid media marker", err)))?
        .to_string();
    let key = MtmdCacheKey {
        mmproj_path: mmproj_path.to_string(),
        media_marker: marker,
        use_gpu: params.use_gpu,
        print_timings: params.print_timings,
        n_threads: params.n_threads,
    };
    Ok((key, params))
}

impl Context {
    pub fn new(model: &ModelRef, params: ContextParams) -> Result<ContextRef, Error> {
        let mut context_params = LlamaContextParams::default();

        if let Some(context_size) = params.context_size {
            let context_size = u32::try_from(context_size)
                .map_err(|_| Error::InvalidInput("context_size must be > 0".to_string()))?;
            let context_size = NonZeroU32::new(context_size)
                .ok_or_else(|| Error::InvalidInput("context_size must be > 0".to_string()))?;
            context_params = context_params.with_n_ctx(Some(context_size));
        }

        if let Some(n_threads) = params.n_threads {
            if n_threads <= 0 {
                return Err(Error::InvalidInput("n_threads must be > 0".to_string()));
            }
            context_params = context_params
                .with_n_threads(n_threads)
                .with_n_threads_batch(n_threads);
        }

        if let Some(n_batch) = params.n_batch {
            let n_batch = u32::try_from(n_batch)
                .map_err(|_| Error::InvalidInput("n_batch must be > 0".to_string()))?;
            context_params = context_params.with_n_batch(n_batch);
        }

        let context = Context::try_new(Arc::clone(model), None, |model| {
            let backend = backend()?;
            model
                .model()
                .new_context(backend, context_params)
                .map_err(|err| Error::Llama {
                    op: "Failed to create context",
                    message: err.to_string(),
                })
        })?;

        Ok(Arc::new(context))
    }

    pub fn new_embedding(
        model: &ModelRef,
        params: EmbeddingContextParams,
    ) -> Result<ContextRef, Error> {
        let context_size = NonZeroU32::new(params.context_size)
            .ok_or_else(|| Error::InvalidInput("context_size must be > 0".to_string()))?;
        if params.batch_size == 0 {
            return Err(Error::InvalidInput("batch_size must be > 0".to_string()));
        }
        if params.micro_batch_size == 0 {
            return Err(Error::InvalidInput(
                "micro_batch_size must be > 0".to_string(),
            ));
        }
        if params.source_dim == 0 || params.dim == 0 || params.dim > params.source_dim {
            return Err(Error::InvalidInput(
                "embedding dimensions must satisfy 0 < dim <= source_dim".to_string(),
            ));
        }
        if params.query_prompt.match_indices("{query}").count() != 1 {
            return Err(Error::InvalidInput(
                "query_prompt must contain exactly one {query} placeholder".to_string(),
            ));
        }

        let mut context_params = LlamaContextParams::default()
            .with_embeddings(true)
            .with_pooling_type(LlamaPoolingType::Mean)
            .with_n_ctx(Some(context_size))
            .with_n_batch(params.batch_size)
            .with_n_ubatch(params.micro_batch_size);
        if let Some(n_threads) = params.n_threads {
            if n_threads <= 0 {
                return Err(Error::InvalidInput("n_threads must be > 0".to_string()));
            }
            context_params = context_params
                .with_n_threads(n_threads)
                .with_n_threads_batch(n_threads);
        }

        let context = Context::try_new(Arc::clone(model), Some(params), |model| {
            let backend = backend()?;
            model
                .model()
                .new_context(backend, context_params)
                .map_err(|err| Error::Llama {
                    op: "Failed to create embedding context",
                    message: err.to_string(),
                })
        })?;

        Ok(Arc::new(context))
    }

    pub fn new_knowledge_embedding(
        model: &ModelRef,
        n_threads: Option<i32>,
    ) -> Result<ContextRef, Error> {
        let config = crate::config::knowledge_embedding_config();
        Self::new_embedding(
            model,
            EmbeddingContextParams {
                context_size: config.context_size,
                n_threads,
                batch_size: config.batch_size,
                micro_batch_size: config.micro_batch_size,
                source_dim: config.source_dim,
                dim: config.dim,
                query_prompt: config.query_prompt,
            },
        )
    }

    pub fn prewarm_multimodal(
        &self,
        mmproj_path: String,
        media_marker: Option<String>,
    ) -> Result<(), Error> {
        let marker = media_marker.unwrap_or_else(|| mtmd_default_marker().to_string());
        self.with_context_and_cache_mut(|ctx, _| {
            self.cached_mtmd_context(ctx.model, &mmproj_path, &marker)
                .map(|_| ())
        })
    }
}
