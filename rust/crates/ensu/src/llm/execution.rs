use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::context::params::LlamaContextParams;
use llama_cpp_2::context::session::{LlamaStateSeqFlags, SeqState};
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::mtmd::{MtmdContext, MtmdInputChunks};
use llama_cpp_2::token::LlamaToken;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

use super::generate::{decode_batch, token_batch};
use super::{Error, backend, lock};

const MAX_SNAPSHOT_BYTES: usize = 256 * 1024 * 1024;
pub(super) const MIN_GPU_PROMPT_TOKENS: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExecutionParams {
    pub allow_gpu: bool,
    pub n_threads: i32,
    pub n_threads_generation: i32,
    pub batch_size: u32,
}

#[derive(Clone, Copy)]
pub(super) struct MultimodalPrompt<'a> {
    pub context: &'a MtmdContext,
    pub chunks: &'a MtmdInputChunks,
}

impl MultimodalPrompt<'_> {
    pub fn eval(
        &self,
        ctx: &mut LlamaContext,
        batch_size: usize,
        synchronize: bool,
    ) -> Result<i32, Error> {
        let end = self
            .chunks
            .eval_chunks(self.context, ctx, 0, 0, batch_size as i32, true)
            .map_err(|err| Error::Llama {
                op: "Failed to evaluate multimodal prompt",
                message: err.to_string(),
            })?;
        if synchronize {
            let _ = ctx.get_logits();
        }
        Ok(end)
    }
}

#[derive(Clone, Copy)]
pub(super) enum ExecutionState<'a> {
    Stateless,
    Replay {
        tokens: &'a [LlamaToken],
        multimodal: Option<MultimodalPrompt<'a>>,
        cancelled: &'a AtomicBool,
    },
}

#[derive(Clone, Copy, Default)]
struct Request {
    params: Option<ExecutionParams>,
    revision: u64,
}

pub struct ExecutionControl {
    request: Mutex<Request>,
    available_memory: Box<dyn Fn() -> u64 + Send + Sync>,
    #[cfg(test)]
    snapshot_limit: usize,
}

impl ExecutionControl {
    pub fn new(available_memory: impl Fn() -> u64 + Send + Sync + 'static) -> Self {
        Self {
            request: Mutex::default(),
            available_memory: Box::new(available_memory),
            #[cfg(test)]
            snapshot_limit: MAX_SNAPSHOT_BYTES,
        }
    }

    fn snapshot(
        &self,
        ctx: &LlamaContext,
        flags: LlamaStateSeqFlags,
    ) -> Result<Option<SeqState>, Error> {
        let sequence = snapshot_sequence(ctx.model, flags);
        let size = ctx.state_seq_get_size_ext(sequence, flags);
        #[cfg(test)]
        let limit = self.snapshot_limit;
        #[cfg(not(test))]
        let limit = MAX_SNAPSHOT_BYTES;
        if size > limit {
            return Ok(None);
        }
        if !can_allocate_snapshot(size, (self.available_memory)()) {
            return Err(Error::InsufficientMemory);
        }
        ctx.state_seq_get(sequence, flags)
            .map(Some)
            .map_err(|err| Error::Llama {
                op: "Failed to preserve inference state",
                message: err.to_string(),
            })
    }

    pub fn set_params(&self, params: ExecutionParams) -> Result<(), Error> {
        if params.n_threads <= 0 || params.n_threads_generation <= 0 || params.batch_size == 0 {
            return Err(Error::InvalidInput(
                "Execution thread counts and batch size must be > 0".to_owned(),
            ));
        }
        let mut request = lock(&self.request);
        if request.params != Some(params) {
            request.params = Some(params);
            request.revision = request.revision.wrapping_add(1);
        }
        Ok(())
    }
}

pub(super) struct ExecutionContext<'a> {
    pub model: &'a LlamaModel,
    inner: Option<LlamaContext<'a>>,
    context_size: u32,
    batch_size: u32,
    pub control: Option<Arc<ExecutionControl>>,
    base: LlamaContextParams,
    applied: ExecutionParams,
    embeddings: bool,
}

impl<'a> ExecutionContext<'a> {
    pub fn new(context: LlamaContext<'a>, base: LlamaContextParams, embeddings: bool) -> Self {
        let applied = ExecutionParams {
            allow_gpu: base.op_offload(),
            n_threads: base.n_threads_batch(),
            n_threads_generation: base.n_threads(),
            batch_size: base.n_ubatch(),
        };
        Self {
            model: context.model,
            context_size: context.n_ctx(),
            batch_size: context.n_batch(),
            inner: Some(context),
            control: None,
            base,
            applied,
            embeddings,
        }
    }

    pub fn get(&self) -> Result<&LlamaContext<'a>, Error> {
        self.inner
            .as_ref()
            .ok_or(Error::Unsupported("Inference context is unavailable"))
    }

    pub fn get_mut(&mut self) -> Result<&mut LlamaContext<'a>, Error> {
        self.inner
            .as_mut()
            .ok_or(Error::Unsupported("Inference context is unavailable"))
    }

    pub fn can_checkpoint_partially(&self) -> bool {
        self.model.is_recurrent() || self.model.is_hybrid()
    }

    pub fn n_ctx(&self) -> u32 {
        self.context_size
    }
    pub fn n_batch(&self) -> u32 {
        self.batch_size
    }

    pub fn clear_kv_cache(&mut self) {
        if let Some(context) = &mut self.inner {
            context.clear_kv_cache();
        }
    }

    fn request(&self) -> Request {
        self.control
            .as_ref()
            .map_or_else(Request::default, |control| *lock(&control.request))
    }

    fn effective_params(&self, mut params: ExecutionParams, allow_gpu: bool) -> ExecutionParams {
        params.batch_size = if self.embeddings {
            self.base.n_ubatch()
        } else {
            params.batch_size.min(self.base.n_ubatch())
        };
        if params.allow_gpu && !allow_gpu && !self.embeddings {
            params.batch_size = params.batch_size.min(MIN_GPU_PROMPT_TOKENS as u32);
        }
        params.allow_gpu &= allow_gpu;
        params
    }

    fn context_params(&self, params: ExecutionParams) -> LlamaContextParams {
        self.base
            .clone()
            .with_op_offload(params.allow_gpu)
            .with_offload_kqv(params.allow_gpu && self.base.offload_kqv())
            .with_n_threads_batch(params.n_threads)
            .with_n_threads(params.n_threads_generation)
            .with_n_ubatch(params.batch_size)
    }

    pub fn can_preserve_state(&self) -> bool {
        self.get()
            .ok()
            .zip(self.control.as_ref())
            .is_some_and(|(ctx, control)| {
                let flags = LlamaStateSeqFlags::empty();
                let size = ctx.state_seq_get_size_ext(snapshot_sequence(ctx.model, flags), flags);
                can_allocate_snapshot(size, (control.available_memory)())
            })
    }

    pub fn ensure_context(&mut self) -> Result<bool, Error> {
        if self.inner.is_some() {
            return Ok(false);
        }
        if let Some(control) = &self.control {
            self.check_reserve(control)?;
        }
        let params = self.effective_params(self.request().params.unwrap_or(self.applied), false);
        self.replace_context(params, None)?;
        Ok(true)
    }

    fn replace_context(
        &mut self,
        params: ExecutionParams,
        snapshot: Option<&SeqState>,
    ) -> Result<(), Error> {
        self.inner = None;
        let mut replacement = self
            .model
            .new_context(backend()?, self.context_params(params))
            .map_err(|err| Error::Llama {
                op: if snapshot.is_some() {
                    "Failed to switch inference execution"
                } else {
                    "Failed to recreate inference context"
                },
                message: err.to_string(),
            })?;
        if let Some(snapshot) = snapshot {
            replacement
                .state_seq_set(snapshot, 0)
                .map_err(|err| Error::Llama {
                    op: "Failed to restore inference state",
                    message: err.to_string(),
                })?;
        }
        self.inner = Some(replacement);
        self.applied = params;
        Ok(())
    }

    fn check_reserve(&self, control: &ExecutionControl) -> Result<(), Error> {
        if super::memory::has_required_work_reserve(Some((control.available_memory)())) {
            Ok(())
        } else {
            Err(Error::InsufficientMemory)
        }
    }

    fn replay(
        &mut self,
        control: &ExecutionControl,
        state: ExecutionState<'_>,
        allow_gpu: bool,
    ) -> Result<(), Error> {
        let ExecutionState::Replay {
            tokens,
            multimodal,
            cancelled,
        } = state
        else {
            self.check_reserve(control)?;
            let params =
                self.effective_params(self.request().params.unwrap_or(self.applied), allow_gpu);
            return self.replace_context(params, None);
        };
        let result = (|| {
            'restart: loop {
                super::generate::check_cancelled(cancelled)?;
                self.check_reserve(control)?;
                let request = self.request();
                let params =
                    self.effective_params(request.params.unwrap_or(self.applied), allow_gpu);
                self.replace_context(params, None)?;
                let batch_size = params.batch_size.min(self.n_batch()) as usize;
                let start = if let Some(prompt) = multimodal {
                    self.check_reserve(control)?;
                    super::generate::check_cancelled(cancelled)?;
                    if self.request().revision != request.revision {
                        continue 'restart;
                    }
                    let decoded = prompt.eval(self.get_mut()?, batch_size, params.allow_gpu);
                    super::generate::check_cancelled(cancelled)?;
                    if self.request().revision != request.revision {
                        continue 'restart;
                    }
                    self.check_reserve(control)?;
                    decoded?
                } else {
                    0
                };
                for (index, chunk) in tokens.chunks(batch_size).enumerate() {
                    super::generate::check_cancelled(cancelled)?;
                    if self.request().revision != request.revision {
                        continue 'restart;
                    }
                    let mut batch = token_batch(
                        chunk,
                        start + (index * batch_size) as i32,
                        true,
                        "Failed to rebuild inference state",
                    )?;
                    let decoded = decode_batch(
                        self.get_mut()?,
                        &mut batch,
                        params.allow_gpu,
                        "Failed to rebuild inference state",
                    );
                    if self.request().revision != request.revision {
                        continue 'restart;
                    }
                    decoded?;
                    self.check_reserve(control)?;
                }
                super::generate::check_cancelled(cancelled)?;
                return Ok(());
            }
        })();
        if result.is_err() {
            self.inner = None;
        }
        result
    }

    pub fn run<R>(
        &mut self,
        allow_gpu: bool,
        state: ExecutionState<'_>,
        mut operation: impl FnMut(&mut LlamaContext, usize, bool) -> Result<R, Error>,
    ) -> Result<R, Error> {
        let stateless = matches!(state, ExecutionState::Stateless);
        let (request, control, params) = loop {
            let request = self.request();
            let (Some(control), Some(requested)) = (self.control.clone(), request.params) else {
                let batch_size = self.n_batch() as usize;
                return operation(self.get_mut()?, batch_size, false);
            };
            let params = self.effective_params(requested, allow_gpu);
            if params != self.applied {
                let snapshot = if stateless {
                    None
                } else {
                    control.snapshot(self.get()?, LlamaStateSeqFlags::empty())?
                };
                if let Some(snapshot) = snapshot {
                    self.replace_context(params, Some(&snapshot))?;
                } else if !stateless
                    && self.applied.allow_gpu
                    && self.effective_params(requested, true) == self.applied
                {
                    break (request, control, self.applied);
                } else {
                    self.replay(&control, state, allow_gpu)?;
                    continue;
                }
            }
            break (request, control, params);
        };
        if !params.allow_gpu {
            let batch_size = params.batch_size.min(self.n_batch()) as usize;
            return operation(self.get_mut()?, batch_size, false);
        }
        let checkpoint_flags = if self.can_checkpoint_partially() {
            LlamaStateSeqFlags::PARTIAL_ONLY
        } else {
            LlamaStateSeqFlags::empty()
        };
        let checkpoint_end =
            u32::try_from(self.get()?.kv_cache_seq_pos_max(0)).map_or(0, |pos| pos + 1);
        let checkpoint = if stateless {
            None
        } else {
            control.snapshot(self.get()?, checkpoint_flags)?
        };
        if checkpoint.is_none() {
            self.check_reserve(&control)?;
        }
        let batch_size = params.batch_size.min(self.n_batch()) as usize;
        let result = operation(self.get_mut()?, batch_size, true);
        let synchronized = self.check_reserve(&control);
        let next = self.request();
        if next.revision != request.revision {
            let params = self.effective_params(next.params.unwrap_or(params), false);
            let checkpoint = match checkpoint {
                Some(checkpoint) if checkpoint.flags() == LlamaStateSeqFlags::PARTIAL_ONLY => {
                    if let Err(err) = self.get_mut()?.state_seq_set(&checkpoint, 0) {
                        self.inner = None;
                        return Err(Error::Llama {
                            op: "Failed to restore inference state",
                            message: err.to_string(),
                        });
                    }
                    if self
                        .get_mut()?
                        .clear_kv_cache_seq(Some(0), Some(checkpoint_end), None)
                        != Ok(true)
                    {
                        self.inner = None;
                        return Err(Error::Unsupported("Failed to roll back inference state"));
                    }
                    drop(checkpoint);
                    control.snapshot(self.get()?, LlamaStateSeqFlags::empty())?
                }
                checkpoint => checkpoint,
            };
            if let Some(checkpoint) = checkpoint {
                self.replace_context(params, Some(&checkpoint))?;
            } else {
                self.replay(&control, state, false)?;
            }
            let batch_size = self.applied.batch_size.min(self.n_batch()) as usize;
            return operation(self.get_mut()?, batch_size, false);
        }
        if let Err(err) = synchronized {
            self.inner = None;
            return Err(err);
        }
        if matches!(&result, Err(Error::Llama { .. })) {
            self.inner = None;
        }
        result
    }
}

fn snapshot_sequence(model: &LlamaModel, flags: LlamaStateSeqFlags) -> i32 {
    if flags == LlamaStateSeqFlags::empty() && !model.is_recurrent() && !model.is_hybrid() {
        -1
    } else {
        0
    }
}

fn can_allocate_snapshot(size: usize, available_bytes: u64) -> bool {
    size <= MAX_SNAPSHOT_BYTES
        && available_bytes
            .checked_sub(size as u64)
            .is_some_and(|remaining| super::memory::has_required_work_reserve(Some(remaining)))
}

#[cfg(test)]
mod tests {
    use super::super::{Model, ModelLoadParams, ModelRef};
    use super::*;
    use llama_cpp_2::context::params::KvCacheType;
    use llama_cpp_2::llama_batch::LlamaBatch;
    use std::num::NonZeroU32;
    use std::sync::atomic::{AtomicU64, Ordering};

    const BACKGROUND: ExecutionParams = ExecutionParams {
        allow_gpu: false,
        n_threads: 2,
        n_threads_generation: 2,
        batch_size: 32,
    };

    fn model() -> ModelRef {
        Model::load(ModelLoadParams {
            model_path: std::env::var("ENSU_TEST_MODEL").unwrap(),
            n_gpu_layers: Some(0),
            use_mmap: None,
            use_mlock: None,
        })
        .unwrap()
    }

    fn native_context(model: &ModelRef, params: LlamaContextParams) -> LlamaContext<'_> {
        model
            .model()
            .new_context(backend().unwrap(), params)
            .unwrap()
    }

    fn execution_control(snapshot_limit: usize) -> (Arc<ExecutionControl>, Arc<AtomicU64>) {
        let available = Arc::new(AtomicU64::new(u64::MAX));
        let memory = available.clone();
        let mut control = ExecutionControl::new(move || memory.load(Ordering::Relaxed));
        control.snapshot_limit = snapshot_limit;
        (Arc::new(control), available)
    }

    fn token_batch(tokens: &[LlamaToken], start: usize) -> LlamaBatch<'static> {
        super::token_batch(tokens, start as i32, true, "Failed to add test token").unwrap()
    }

    fn assert_logits_eq(actual: &[f32], expected: &[f32], tolerance: f32) {
        assert_eq!(actual.len(), expected.len());
        assert!(
            actual
                .iter()
                .zip(expected)
                .all(|(a, b)| (a - b).abs() < tolerance)
        );
    }

    #[test]
    fn snapshots_are_bounded_and_preserve_work_reserve() {
        let reserve = 256 * 1024 * 1024;
        for (size, available, expected) in [
            (0, 0, false),
            (1024, 1023, false),
            (1024, reserve + 1023, false),
            (1024, reserve + 1024, true),
            (
                MAX_SNAPSHOT_BYTES,
                reserve + MAX_SNAPSHOT_BYTES as u64,
                true,
            ),
            (MAX_SNAPSHOT_BYTES + 1, u64::MAX, false),
            (usize::MAX, u64::MAX, false),
        ] {
            assert_eq!(can_allocate_snapshot(size, available), expected);
        }
    }

    #[test]
    #[ignore = "requires ENSU_TEST_MODEL"]
    fn oversized_transitions_rebuild_prefix_and_preserve_cancellation() {
        let model = model();
        let params = LlamaContextParams::default()
            .with_n_ctx(NonZeroU32::new(512))
            .with_n_batch(64)
            .with_n_ubatch(32)
            .with_op_offload(false)
            .with_offload_kqv(false)
            .with_n_threads(2)
            .with_n_threads_batch(2);
        let tokens = model.model().vocab().tokenize(
            b"Count from one to ten, spelling out each number.",
            true,
            true,
        );
        let mut baseline = native_context(&model, params.clone());
        let mut batch = token_batch(&tokens, 0);
        baseline.decode(&mut batch).unwrap();
        let expected = baseline.get_logits().to_vec();
        let (control, available) = execution_control(1);
        let cancelled = AtomicBool::new(false);
        let replay = ExecutionState::Replay {
            tokens: &tokens,
            multimodal: None,
            cancelled: &cancelled,
        };
        for gpu in [false, true] {
            let mut context = ExecutionContext::new(
                native_context(&model, params.clone()),
                params.clone().with_n_ubatch(64),
                false,
            );
            context.applied = BACKGROUND;
            context.control = Some(control.clone());
            context.get_mut().unwrap().decode(&mut batch).unwrap();
            let foreground = ExecutionParams {
                allow_gpu: gpu,
                n_threads: 4,
                n_threads_generation: 4,
                batch_size: 64,
            };
            control.set_params(foreground).unwrap();
            context
                .run(true, replay, |ctx, size, synchronize| {
                    assert_eq!(size, 64);
                    assert_eq!(synchronize, gpu);
                    assert_eq!(ctx.n_ubatch(), 64);
                    assert_eq!(ctx.kv_cache_seq_pos_max(0), tokens.len() as i32 - 1);
                    assert_logits_eq(ctx.get_logits(), &expected, 1e-4);
                    Ok(())
                })
                .unwrap();
            assert_eq!(context.applied, foreground);
            if gpu {
                context
                    .run(false, replay, |ctx, size, synchronize| {
                        assert_eq!(size, 64);
                        assert_eq!(ctx.n_ubatch(), 64);
                        assert!(synchronize);
                        Ok(())
                    })
                    .unwrap();
                assert_eq!(context.applied, foreground);
                let mut calls = 0;
                context
                    .run(true, replay, |ctx, size, synchronize| {
                        calls += 1;
                        if synchronize {
                            control.set_params(BACKGROUND).unwrap();
                            return Err(Error::Unsupported("simulated GPU interruption"));
                        }
                        assert_eq!(size, 32);
                        assert_logits_eq(ctx.get_logits(), &expected, 1e-4);
                        Ok(())
                    })
                    .unwrap();
                assert_eq!(calls, 2);
                assert_eq!(context.applied, BACKGROUND);
            }
            let next = ExecutionParams {
                n_threads: 3,
                ..foreground
            };
            control.set_params(next).unwrap();
            available.store(0, Ordering::Relaxed);
            assert!(
                context
                    .run::<()>(true, replay, |_, _, _| panic!(
                        "low memory must stop replay"
                    ))
                    .is_err()
            );
            available.store(u64::MAX, Ordering::Relaxed);
            assert!(context.ensure_context().unwrap());
            control.set_params(foreground).unwrap();
            cancelled.store(true, Ordering::Relaxed);
            assert!(matches!(
                context.run::<()>(true, replay, |_, _, _| panic!("cancelled replay must stop")),
                Err(Error::Cancelled)
            ));
            cancelled.store(false, Ordering::Relaxed);
            assert!(context.get().is_err());
        }
    }

    #[test]
    #[ignore = "requires ENSU_TEST_MODEL and ENSU_TEST_MMPROJ"]
    fn oversized_image_handoffs_preserve_output_and_recover_after_interruption() {
        use super::super::{ChatMessage, ChatRequest, Context, ContextParams, GenerationEvent};
        use ente_image::image_compression::{EncodedImageFormat, encode_rgb};

        let model = model();
        let directory = tempfile::tempdir().unwrap();
        let image = directory.path().join("red.png");
        std::fs::write(
            &image,
            encode_rgb(
                &[255, 0, 0].repeat(64 * 64),
                64,
                64,
                EncodedImageFormat::Png,
            )
            .unwrap(),
        )
        .unwrap();
        let request = ChatRequest {
            messages: vec![ChatMessage {
                role: "user".to_owned(),
                content: "Describe the color of this image, then count from one to ten.".to_owned(),
            }],
            image_paths: Some(vec![image.to_str().unwrap().to_owned()]),
            mmproj_path: Some(std::env::var("ENSU_TEST_MMPROJ").unwrap()),
            temperature: Some(0.0),
            max_tokens: Some(16),
            ..Default::default()
        };
        for allow_gpu in [false, true] {
            let context = Context::new(
                &model,
                ContextParams {
                    context_size: Some(4096),
                    n_threads: Some(4),
                    n_threads_generation: Some(4),
                    n_batch: Some(128),
                },
            )
            .unwrap();
            let (control, available) = execution_control(1);
            let foreground = ExecutionParams {
                allow_gpu,
                n_threads: 4,
                n_threads_generation: 4,
                batch_size: 128,
            };
            control.set_params(foreground).unwrap();
            context.set_execution_control(control.clone()).unwrap();
            let mut expected = String::new();
            let baseline = context
                .generate_chat_stream(request.clone(), &mut |event| {
                    if let GenerationEvent::Text { text, .. } = event {
                        expected.push_str(&text);
                    }
                })
                .unwrap();
            assert!(!expected.is_empty());
            let mut actual = String::new();
            let mut steps = 0;
            let result = context
                .generate_chat_stream(request.clone(), &mut |event| {
                    if let GenerationEvent::Text { text, .. } = event
                        && !text.is_empty()
                    {
                        actual.push_str(&text);
                        if steps == 0 {
                            control.set_params(BACKGROUND).unwrap();
                        } else if steps == 3 {
                            control.set_params(foreground).unwrap();
                        }
                        steps += 1;
                    }
                })
                .unwrap();
            assert!(steps > 4);
            assert_eq!(actual, expected);
            assert_eq!(result.generated_tokens, baseline.generated_tokens);
            assert_eq!(result.finish_reason, baseline.finish_reason);

            if !allow_gpu {
                let cancelled = context.generate_chat_stream(request.clone(), &mut |event| {
                    if let GenerationEvent::Text { job_id, text, .. } = event
                        && !text.is_empty()
                    {
                        control.set_params(BACKGROUND).unwrap();
                        super::super::cancel(job_id);
                    }
                });
                assert!(matches!(cancelled, Err(Error::Cancelled)));
                control.set_params(foreground).unwrap();
                let failure = context.generate_chat_stream(request.clone(), &mut |event| {
                    if let GenerationEvent::Text { text, .. } = event
                        && !text.is_empty()
                    {
                        control.set_params(BACKGROUND).unwrap();
                        available.store(0, Ordering::Relaxed);
                    }
                });
                assert!(matches!(failure, Err(Error::InsufficientMemory)));
                available.store(u64::MAX, Ordering::Relaxed);
                control.set_params(foreground).unwrap();
                actual.clear();
                context
                    .generate_chat_stream(request.clone(), &mut |event| {
                        if let GenerationEvent::Text { text, .. } = event {
                            actual.push_str(&text);
                        }
                    })
                    .unwrap();
                assert_eq!(actual, expected);
            }
        }
    }

    #[test]
    #[ignore = "requires ENSU_TEST_MODEL"]
    fn failed_gpu_operations_and_stateless_transitions_recover() {
        let model = model();
        let params = LlamaContextParams::default()
            .with_n_ctx(NonZeroU32::new(512))
            .with_n_batch(64)
            .with_n_ubatch(64)
            .with_n_threads(4)
            .with_n_threads_batch(4)
            .with_op_offload(true)
            .with_offload_kqv(false);
        let mut context =
            ExecutionContext::new(native_context(&model, params.clone()), params, false);
        let (control, _) = execution_control(MAX_SNAPSHOT_BYTES);
        control.set_params(context.applied).unwrap();
        context.control = Some(control);
        let request = context.request();
        let tokens = model.model().vocab().tokenize(
            b"Count from one to ten, spelling out each number.",
            true,
            true,
        );
        let decode = |ctx: &mut LlamaContext, _: usize, synchronize: bool| {
            assert!(synchronize);
            let mut batch = token_batch(&tokens, 0);
            decode_batch(ctx, &mut batch, synchronize, "Prompt decode failed")?;
            Ok(ctx.get_logits().to_vec())
        };
        let cancel_flag = AtomicBool::new(false);
        let empty = ExecutionState::Replay {
            tokens: &[],
            multimodal: None,
            cancelled: &cancel_flag,
        };
        let replay = ExecutionState::Replay {
            tokens: &tokens,
            multimodal: None,
            cancelled: &cancel_flag,
        };
        let expected = context.run(true, empty, decode).unwrap();
        let position = context.get().unwrap().kv_cache_seq_pos_max(0);

        let cancelled = context.run::<()>(true, replay, |_, _, _| Err(Error::Cancelled));
        assert!(matches!(cancelled, Err(Error::Cancelled)));
        assert!(!context.ensure_context().unwrap());
        assert_eq!(context.get().unwrap().kv_cache_seq_pos_max(0), position);
        assert_logits_eq(context.get().unwrap().get_logits(), &expected, 1e-5);

        let failed = context.run::<()>(true, replay, |_, _, _| {
            Err(Error::Llama {
                op: "Decode failed",
                message: "injected backend failure".into(),
            })
        });
        assert!(matches!(failed, Err(Error::Llama { .. })));
        assert!(context.ensure_context().unwrap());
        let actual = context.run(true, empty, decode).unwrap();
        assert_logits_eq(&actual, &expected, 1e-5);
        assert_eq!(context.request().revision, request.revision);
        assert_eq!(context.request().params, request.params);
        assert!(!context.ensure_context().unwrap());

        let (control, _) = execution_control(1);
        control.set_params(request.params.unwrap()).unwrap();
        context.control = Some(control.clone());
        context.clear_kv_cache();
        let mut calls = 0;
        let actual = context
            .run(true, ExecutionState::Stateless, |ctx, _, synchronize| {
                calls += 1;
                let mut batch = token_batch(&tokens, 0);
                decode_batch(ctx, &mut batch, synchronize, "Stateless decode failed")?;
                if calls == 1 {
                    control.set_params(BACKGROUND).unwrap();
                }
                Ok(ctx.get_logits().to_vec())
            })
            .unwrap();
        assert_eq!(calls, 2);
        assert_eq!(context.applied, BACKGROUND);
        assert_logits_eq(&actual, &expected, 1e-4);
    }

    #[test]
    #[ignore = "requires ENSU_TEST_MODEL"]
    fn transition_during_decode_replays_only_the_uncommitted_batch() {
        let model = model();
        let foreground = ExecutionParams {
            allow_gpu: true,
            n_threads: 4,
            n_threads_generation: 4,
            batch_size: 64,
        };
        let params = LlamaContextParams::default()
            .with_n_ctx(NonZeroU32::new(512))
            .with_n_batch(64)
            .with_n_ubatch(64)
            .with_n_threads(4)
            .with_n_threads_batch(4);
        let context = native_context(&model, params.clone());
        let mut context = ExecutionContext::new(context, params.clone(), false);
        let mut baseline = native_context(
            &model,
            params
                .with_op_offload(false)
                .with_offload_kqv(false)
                .with_n_threads(2)
                .with_n_threads_batch(2)
                .with_n_ubatch(32),
        );
        let (control, available) = execution_control(MAX_SNAPSHOT_BYTES);
        control.set_params(foreground).unwrap();
        context.control = Some(control.clone());
        let text = "Count from one to five. ".repeat(16);
        let tokens = model.model().vocab().tokenize(text.as_bytes(), true, true);
        let cancel_flag = AtomicBool::new(false);
        let empty = ExecutionState::Replay {
            tokens: &[],
            multimodal: None,
            cancelled: &cancel_flag,
        };
        let mut calls = 0;
        let mut sizes = Vec::new();
        let end = context
            .run(true, empty, |ctx, batch_size, synchronize| {
                calls += 1;
                sizes.push(batch_size);
                let count = batch_size.min(tokens.len());
                let mut batch = token_batch(&tokens[..count], 0);
                ctx.decode(&mut batch).unwrap();
                if synchronize {
                    let _ = ctx.get_logits();
                }
                control.set_params(BACKGROUND).unwrap();
                Ok(count)
            })
            .unwrap();
        assert_eq!(calls, 2);
        assert_eq!(sizes, [64, 32]);
        assert_eq!(end, 32);
        let mut batch = token_batch(&tokens[..end], 0);
        baseline.decode(&mut batch).unwrap();
        let index = (end - 1) as i32;
        let actual = context.get().unwrap().get_logits_ith(index);
        let expected = baseline.get_logits_ith(index);
        assert_logits_eq(actual, expected, 1e-5);

        let replay = ExecutionState::Replay {
            tokens: &tokens[..end],
            multimodal: None,
            cancelled: &cancel_flag,
        };
        let saved = control
            .snapshot(context.get().unwrap(), LlamaStateSeqFlags::empty())
            .unwrap()
            .unwrap();
        available.store(0, Ordering::Relaxed);
        control.set_params(foreground).unwrap();
        assert!(
            context
                .run::<()>(true, replay, |_, _, _| {
                    panic!("decode must not start without checkpoint memory")
                })
                .is_err()
        );
        assert!(context.get().is_ok());
        assert!(
            control
                .snapshot(context.get().unwrap(), LlamaStateSeqFlags::PARTIAL_ONLY)
                .is_err()
        );
        available.store(u64::MAX, Ordering::Relaxed);
        assert!(
            context
                .run(true, replay, |_, _, _| {
                    available.store(0, Ordering::Relaxed);
                    Ok(())
                })
                .is_err()
        );
        assert!(context.get().is_err());
        for bytes in [0, 256 * 1024 * 1024 - 1] {
            available.store(bytes, Ordering::Relaxed);
            assert!(context.ensure_context().is_err());
            assert!(context.get().is_err());
        }
        available.store(u64::MAX, Ordering::Relaxed);
        let base = context.base.clone();
        context.base = base.clone().with_type_k(KvCacheType::F32);
        assert!(matches!(
            context.replace_context(foreground, Some(&saved)),
            Err(Error::Llama {
                op: "Failed to restore inference state",
                ..
            })
        ));
        assert!(context.get().is_err());
        context.base = base;
        control.set_params(foreground).unwrap();
        available.store(400 * 1024 * 1024, Ordering::Relaxed);
        assert!(context.ensure_context().unwrap());
        assert_eq!(context.applied.batch_size, MIN_GPU_PROMPT_TOKENS as u32);
        assert_eq!(
            context.get().unwrap().n_ubatch(),
            MIN_GPU_PROMPT_TOKENS as u32
        );
        assert_eq!(context.applied.n_threads, foreground.n_threads);
        assert!(!context.applied.allow_gpu);
        assert!(!context.ensure_context().unwrap());
        context.get_mut().unwrap().decode(&mut batch).unwrap();
        assert_logits_eq(context.get().unwrap().get_logits_ith(index), expected, 1e-5);

        available.store(u64::MAX, Ordering::Relaxed);
        for (start, allow_gpu) in [(32, true), (64, false)] {
            control.set_params(foreground).unwrap();
            let mut calls = 0;
            let end = context
                .run(
                    allow_gpu,
                    ExecutionState::Replay {
                        tokens: &tokens[..start],
                        multimodal: None,
                        cancelled: &cancel_flag,
                    },
                    |ctx, batch_size, synchronize| {
                        calls += 1;
                        let end = (start + batch_size).min(tokens.len());
                        let mut batch = token_batch(&tokens[start..end], start);
                        ctx.decode(&mut batch).unwrap();
                        if synchronize {
                            let _ = ctx.get_logits();
                        }
                        control.set_params(BACKGROUND).unwrap();
                        Ok(end)
                    },
                )
                .unwrap();
            assert_eq!(calls, if allow_gpu { 2 } else { 1 });
            assert_eq!(end, start + 32);
            let mut batch = token_batch(&tokens[start..end], start);
            baseline.decode(&mut batch).unwrap();
            assert_logits_eq(
                context.get().unwrap().get_logits_ith(31),
                baseline.get_logits_ith(31),
                1e-5,
            );
        }
    }
}
