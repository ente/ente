use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::context::params::LlamaContextParams;
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::mtmd::{MtmdContext, MtmdContextParams, mtmd_default_marker};
use llama_cpp_2::token::LlamaToken;
use parking_lot::{Mutex, MutexGuard};
use self_cell::self_cell;
use serde::{Deserialize, Serialize};
use std::ffi::CString;
use std::num::NonZeroU32;
use std::path::Path;
use std::sync::Arc;

use super::model::ModelRef;
use super::{Error, backend, format_error};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextParams {
    pub context_size: Option<i32>,
    pub n_threads: Option<i32>,
    pub n_batch: Option<i32>,
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

pub struct Context {
    cell: Mutex<ContextCell>,
    mtmd_context: Mutex<Option<CachedMtmdContext>>,
    /// Tokens currently held in the KV cache, in order. Kept in sync with
    /// what has actually been decoded so the next generation can reuse the
    /// longest common prefix instead of re-decoding the whole prompt.
    cached_tokens: Mutex<Vec<LlamaToken>>,
    /// Whether the model uses sliding-window attention for any layer.
    /// SWA KV cells older than the window are overwritten as decoding
    /// advances, so prefix reuse must not roll back more than one position
    /// (see `swa_safe_prefix_len` in generate.rs).
    swa: bool,
}

pub type ContextRef = Arc<Context>;

unsafe impl Send for Context {}
unsafe impl Sync for Context {}

impl Context {
    fn try_new(
        owner: ModelRef,
        swa: bool,
        builder: impl for<'a> FnOnce(&'a ModelRef) -> Result<LlamaContext<'a>, Error>,
    ) -> Result<Self, Error> {
        ContextCell::try_new(owner, builder).map(|cell| Context {
            cell: Mutex::new(cell),
            mtmd_context: Mutex::new(None),
            cached_tokens: Mutex::new(Vec::new()),
            swa,
        })
    }

    /// Bookkeeping for the tokens currently decoded into the KV cache.
    ///
    /// Lock ordering: when both are needed, `cell` (via
    /// [`Self::with_context_mut`]) is locked before `cached_tokens`.
    pub(super) fn cached_tokens(&self) -> MutexGuard<'_, Vec<LlamaToken>> {
        self.cached_tokens.lock()
    }

    /// Whether the model behind this context uses sliding-window attention.
    pub(super) fn uses_swa(&self) -> bool {
        self.swa
    }

    pub(super) fn with_context_mut<R>(
        &self,
        func: impl for<'a, 'b> FnOnce(&'b mut LlamaContext<'a>) -> R,
    ) -> R {
        let mut guard = self.cell.lock();
        guard.with_dependent_mut(|_owner, context| func(context))
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
        let mut guard = self.mtmd_context.lock();

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

        let swa = model_uses_swa(model.model());
        let context = Context::try_new(Arc::clone(model), swa, |model| {
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

    pub fn prewarm_multimodal(
        &self,
        mmproj_path: String,
        media_marker: Option<String>,
    ) -> Result<(), Error> {
        let marker = media_marker.unwrap_or_else(|| mtmd_default_marker().to_string());
        self.with_context_mut(|ctx| {
            self.cached_mtmd_context(ctx.model, &mmproj_path, &marker)
                .map(|_| ())
        })
    }
}

/// Whether the model uses sliding-window attention (SWA) for any layer.
///
/// Detected from GGUF metadata (`<arch>.attention.sliding_window`), because
/// llama-cpp-2 exposes neither `llama_model_n_swa` nor
/// `llama_memory_seq_pos_min`. A missing key means no SWA; unreadable or
/// unparseable metadata is treated as SWA, which only costs prefix reuse on
/// rollbacks, never correctness.
fn model_uses_swa(model: &LlamaModel) -> bool {
    let Ok(arch) = model.meta_val_str("general.architecture") else {
        return true;
    };
    match model.meta_val_str(&format!("{arch}.attention.sliding_window")) {
        Ok(value) => value.trim().parse::<i64>().map(|n| n > 0).unwrap_or(true),
        Err(_) => false,
    }
}
