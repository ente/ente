use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::mtmd::{MtmdBitmap, MtmdInputText, mtmd_default_marker};
use llama_cpp_2::sampling::LlamaSampler;
use llama_cpp_2::token::LlamaToken;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;

use super::context::LocalContext;
use super::event::{EventSink, FinishReason, GenerationEvent, GenerationSummary, JobId};
use super::execution::{ExecutionContext, ExecutionState, MIN_GPU_PROMPT_TOKENS, MultimodalPrompt};
use super::template::build_chat_prompt;
use super::{Error, format_error, lock};

static JOB_COUNTER: AtomicI64 = AtomicI64::new(1);
static CANCEL_FLAGS: OnceLock<Mutex<HashMap<JobId, Arc<AtomicBool>>>> = OnceLock::new();

const DEFAULT_GENERATION_MAX_TOKENS: i32 = 8_192;

fn cancel_flags() -> &'static Mutex<HashMap<JobId, Arc<AtomicBool>>> {
    CANCEL_FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(super) fn register_job() -> (JobId, Arc<AtomicBool>) {
    let job_id = JOB_COUNTER.fetch_add(1, Ordering::Relaxed);
    let flag = Arc::new(AtomicBool::new(false));
    lock(cancel_flags()).insert(job_id, flag.clone());
    (job_id, flag)
}

fn cancel_all() {
    for flag in lock(cancel_flags()).values() {
        flag.store(true, Ordering::Relaxed);
    }
}

pub(super) fn check_cancelled(cancel_flag: &AtomicBool) -> Result<(), Error> {
    if cancel_flag.load(Ordering::Relaxed) {
        Err(Error::Cancelled)
    } else {
        Ok(())
    }
}

pub(super) struct JobGuard(pub(super) JobId);

impl Drop for JobGuard {
    fn drop(&mut self) {
        lock(cancel_flags()).remove(&self.0);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

struct SamplingParams {
    temperature: Option<f32>,
    top_p: Option<f32>,
    top_k: Option<i32>,
    repeat_penalty: Option<f32>,
    frequency_penalty: Option<f32>,
    presence_penalty: Option<f32>,
    seed: Option<i64>,
    grammar: Option<String>,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    pub messages: Vec<ChatMessage>,
    pub template_override: Option<String>,
    pub add_assistant: Option<bool>,
    pub image_paths: Option<Vec<String>>,
    pub mmproj_path: Option<String>,
    pub media_marker: Option<String>,
    pub max_tokens: Option<i32>,
    pub temperature: Option<f32>,
    pub top_p: Option<f32>,
    pub top_k: Option<i32>,
    pub repeat_penalty: Option<f32>,
    pub frequency_penalty: Option<f32>,
    pub presence_penalty: Option<f32>,
    pub seed: Option<i64>,
    pub stop_sequences: Option<Vec<String>>,
    pub grammar: Option<String>,
}

fn token_piece_string(model: &LlamaModel, token: LlamaToken) -> Option<String> {
    if token.0 < 0 {
        return None;
    }
    String::from_utf8(model.vocab().token_to_piece(token, true, None)).ok()
}

fn should_add_bos(model: &LlamaModel, prompt: &str) -> bool {
    if let Some(bos) = token_piece_string(model, model.vocab().bos())
        && !bos.is_empty()
        && prompt.starts_with(&bos)
    {
        return false;
    }
    true
}

fn tokenize_text_prompt(model: &LlamaModel, prompt: &str) -> Result<Vec<LlamaToken>, Error> {
    let tokens = model
        .vocab()
        .tokenize(prompt.as_bytes(), should_add_bos(model, prompt), true);
    if tokens.is_empty() {
        return Err(Error::InvalidInput("Prompt produced no tokens".to_string()));
    }
    Ok(tokens)
}

fn drain_utf8(pending: &mut Vec<u8>) -> String {
    let mut output = String::new();
    loop {
        match std::str::from_utf8(pending) {
            Ok(text) => {
                output.push_str(text);
                pending.clear();
                break;
            }
            Err(err) => {
                let valid_up_to = err.valid_up_to();
                if valid_up_to > 0 {
                    #[expect(clippy::expect_used, reason = "Utf8Error identifies a valid prefix")]
                    let valid =
                        std::str::from_utf8(&pending[..valid_up_to]).expect("valid UTF-8 prefix");
                    output.push_str(valid);
                    pending.drain(..valid_up_to);
                }

                match err.error_len() {
                    None => break,
                    Some(len) => {
                        let len = len.min(pending.len());
                        let lossy = String::from_utf8_lossy(&pending[..len]);
                        output.push_str(&lossy);
                        pending.drain(..len);
                    }
                }
            }
        }
    }
    output
}

struct DecodeStep {
    text: Option<String>,
    stop: bool,
}

struct StreamDecoder {
    pending_text: String,
    pending_bytes: Vec<u8>,
    stop_sequences: Vec<String>,
}

impl StreamDecoder {
    fn new(stop_sequences: &[String]) -> Self {
        Self {
            pending_text: String::new(),
            pending_bytes: Vec::new(),
            stop_sequences: stop_sequences.to_vec(),
        }
    }

    fn push_bytes(&mut self, bytes: &[u8]) -> DecodeStep {
        self.pending_bytes.extend_from_slice(bytes);
        self.pending_text
            .push_str(&drain_utf8(&mut self.pending_bytes));
        self.emit(false)
    }

    fn flush(&mut self) -> DecodeStep {
        self.pending_text
            .push_str(&String::from_utf8_lossy(&self.pending_bytes));
        self.pending_bytes.clear();
        self.emit(true)
    }

    fn emit(&mut self, final_piece: bool) -> DecodeStep {
        let stop_index = self
            .stop_sequences
            .iter()
            .filter(|stop| !stop.is_empty())
            .filter_map(|stop| self.pending_text.find(stop))
            .min();
        let keep = if stop_index.is_none() && !final_piece {
            self.stop_sequences
                .iter()
                .flat_map(|stop| {
                    stop.char_indices()
                        .skip(1)
                        .filter(|(end, _)| self.pending_text.ends_with(&stop[..*end]))
                        .map(|(end, _)| end)
                })
                .max()
                .unwrap_or(0)
        } else {
            0
        };
        let end = stop_index.unwrap_or(self.pending_text.len() - keep);
        let text = self.pending_text[..end].to_owned();
        if stop_index.is_some() {
            self.pending_text.clear();
        } else {
            self.pending_text.drain(..end);
        }
        DecodeStep {
            text: (!text.is_empty()).then_some(text),
            stop: stop_index.is_some(),
        }
    }
}

pub(super) fn token_batch(
    tokens: &[LlamaToken],
    start: i32,
    last_logits: bool,
    op: &'static str,
) -> Result<LlamaBatch<'static>, Error> {
    let mut batch = LlamaBatch::new(tokens.len(), 1);
    for (index, token) in tokens.iter().enumerate() {
        batch
            .add(
                *token,
                start + index as i32,
                &[0],
                last_logits && index + 1 == tokens.len(),
            )
            .map_err(|err| Error::Llama {
                op,
                message: err.to_string(),
            })?;
    }
    Ok(batch)
}

pub(super) fn decode_batch(
    ctx: &mut LlamaContext,
    batch: &mut LlamaBatch,
    synchronize: bool,
    op: &'static str,
) -> Result<(), Error> {
    ctx.decode(batch).map_err(|err| Error::Llama {
        op,
        message: err.to_string(),
    })?;
    if synchronize {
        let _ = ctx.get_logits();
    }
    Ok(())
}

struct GenerationCache<'a> {
    tokens: &'a mut Vec<LlamaToken>,
    multimodal: Option<MultimodalPrompt<'a>>,
}

struct GenerationJob<'a> {
    cancel_flag: &'a AtomicBool,
    sink: &'a mut dyn EventSink,
    job_id: JobId,
    max_tokens: usize,
    stop_sequences: &'a [String],
    prompt_tokens: i32,
    generated_tokens: i32,
    finish_reason: FinishReason,
}

impl GenerationJob<'_> {
    fn run(
        &mut self,
        ctx: &mut ExecutionContext,
        sampler: &mut LlamaSampler,
        cache: GenerationCache<'_>,
        mut pos: i32,
        mut logits_index: i32,
    ) -> Result<(), Error> {
        let mut decoder = StreamDecoder::new(self.stop_sequences);
        let mut stop_triggered = false;
        let n_ctx = ctx.n_ctx();

        self.finish_reason = FinishReason::OutputLimit;
        for sample_index in 0..self.max_tokens {
            check_cancelled(self.cancel_flag)?;

            let token = sampler.sample(ctx.get()?, logits_index);
            check_cancelled(self.cancel_flag)?;

            if ctx.model.vocab().is_eog(token) {
                self.generated_tokens = self.generated_tokens.saturating_add(1);
                self.finish_reason = FinishReason::Eog;
                break;
            }
            if pos >= n_ctx as i32 {
                self.finish_reason = FinishReason::ContextLimit;
                break;
            }
            self.generated_tokens = self.generated_tokens.saturating_add(1);

            let bytes = ctx.model.vocab().token_to_piece(token, true, None);
            let step = decoder.push_bytes(&bytes);

            if let Some(text) = step.text {
                self.emit_text(text, Some(token.0));
            }
            check_cancelled(self.cancel_flag)?;

            if step.stop {
                stop_triggered = true;
                self.finish_reason = FinishReason::StopSequence;
                break;
            }

            if sample_index + 1 == self.max_tokens {
                break;
            }

            let mut step_batch = token_batch(&[token], pos, true, "Failed to add token")?;
            let allow_gpu = ctx.can_checkpoint_partially();
            if let Err(err) = ctx.run(
                allow_gpu,
                ExecutionState::Replay {
                    tokens: cache.tokens,
                    multimodal: cache.multimodal,
                    cancelled: self.cancel_flag,
                },
                |ctx, _, synchronize| {
                    check_cancelled(self.cancel_flag)?;
                    decode_batch(ctx, &mut step_batch, synchronize, "Decode failed")
                },
            ) {
                ctx.clear_kv_cache();
                cache.tokens.clear();
                return Err(err);
            }
            cache.tokens.push(token);

            logits_index = 0;
            pos += 1;
        }

        if !stop_triggered {
            let step = decoder.flush();
            if step.stop {
                self.finish_reason = FinishReason::StopSequence;
            }
            if let Some(text) = step.text {
                self.emit_text(text, None);
            }
        }

        check_cancelled(self.cancel_flag)?;

        Ok(())
    }

    fn emit_text(&mut self, text: String, token_id: Option<i32>) {
        self.sink.add(GenerationEvent::Text {
            job_id: self.job_id,
            text,
            token_id,
        });
    }
}

fn build_sampler(
    model: &LlamaModel,
    request: &SamplingParams,
    context_size: i32,
) -> Result<LlamaSampler, Error> {
    let mut samplers = Vec::new();

    let mut repeat_penalty = request.repeat_penalty.unwrap_or(1.0);
    if repeat_penalty <= 0.0 {
        repeat_penalty = 1.0;
    }
    let mut frequency_penalty = request.frequency_penalty.unwrap_or(0.0);
    if frequency_penalty < 0.0 {
        frequency_penalty = 0.0;
    }
    let mut presence_penalty = request.presence_penalty.unwrap_or(0.0);
    if presence_penalty < 0.0 {
        presence_penalty = 0.0;
    }

    if (repeat_penalty - 1.0).abs() > f32::EPSILON
        || frequency_penalty != 0.0
        || presence_penalty != 0.0
    {
        samplers.push(LlamaSampler::penalties(
            model.vocab().n_tokens(),
            context_size,
            repeat_penalty,
            frequency_penalty,
            presence_penalty,
        ));
    }

    if let Some(grammar) = request.grammar.as_deref() {
        samplers.push(
            LlamaSampler::grammar(model, grammar, "root")
                .map_err(|err| Error::InvalidInput(format_error("Invalid grammar", err)))?,
        );
    }

    if let Some(top_k) = request.top_k
        && top_k > 0
    {
        samplers.push(LlamaSampler::top_k(top_k));
    }

    if let Some(top_p) = request.top_p
        && top_p > 0.0
        && top_p < 1.0
    {
        samplers.push(LlamaSampler::top_p(top_p, 1));
    }

    let temperature = request.temperature.unwrap_or(1.0);
    if temperature > 0.0 {
        samplers.push(LlamaSampler::temp(temperature));
        let seed = request.seed.unwrap_or(0);
        let seed = u32::try_from(seed).unwrap_or(0);
        samplers.push(LlamaSampler::dist(seed));
    } else {
        samplers.push(LlamaSampler::greedy());
    }

    Ok(LlamaSampler::chain_simple(samplers))
}

impl LocalContext {
    pub fn measure_text_chat_prompt(&self, request: &ChatRequest) -> Result<usize, Error> {
        if request
            .image_paths
            .as_ref()
            .is_some_and(|paths| !paths.is_empty())
        {
            return Err(Error::Unsupported(
                "Text measurement does not count image positions",
            ));
        }
        self.with_model(|model| {
            let prompt = build_chat_prompt(
                model,
                request.messages.clone(),
                request.template_override.clone(),
                request.add_assistant.unwrap_or(true),
            )?;
            Ok(tokenize_text_prompt(model, &prompt)?.len())
        })
    }

    pub fn generate_chat_stream(
        &self,
        request: ChatRequest,
        sink: &mut dyn EventSink,
        job_id: JobId,
        cancel_flag: Arc<AtomicBool>,
        start: Instant,
    ) -> Result<GenerationSummary, Error> {
        generate_chat_stream(self, request, sink, job_id, cancel_flag, start)
    }

    pub fn truncate_text_chat_messages(
        &self,
        messages: Vec<ChatMessage>,
        max_tokens: u32,
    ) -> Result<Vec<ChatMessage>, Error> {
        let max_tokens = max_tokens.min(self.context_size());
        let mut request = ChatRequest {
            messages,
            ..Default::default()
        };
        loop {
            let tokens = self.measure_text_chat_prompt(&request)?;
            if tokens <= max_tokens as usize {
                return Ok(request.messages);
            }
            let index = request
                .messages
                .iter()
                .rposition(|message| message.role != "system")
                .ok_or(Error::PromptTooLong {
                    tokens,
                    context_size: max_tokens,
                })?;
            let content = std::mem::take(&mut request.messages[index].content);
            let tokens = self.measure_text_chat_prompt(&request)?;
            if tokens > max_tokens as usize {
                if request.messages[..index]
                    .iter()
                    .all(|message| message.role == "system")
                {
                    return Err(Error::PromptTooLong {
                        tokens,
                        context_size: max_tokens,
                    });
                }
                request.messages.remove(index);
                continue;
            }
            let (mut low, mut high) = (0, content.len());
            while low < high {
                let end = content.ceil_char_boundary(low + (high - low).div_ceil(2));
                request.messages[index].content = content[..end].to_owned();
                if self.measure_text_chat_prompt(&request)? <= max_tokens as usize {
                    low = end;
                } else {
                    high = content.floor_char_boundary(end - 1);
                }
            }
            request.messages[index].content = content[..low].to_owned();
            return Ok(request.messages);
        }
    }
}

fn generate_chat_stream(
    context: &LocalContext,
    request: ChatRequest,
    sink: &mut dyn EventSink,
    job_id: JobId,
    cancel_flag: Arc<AtomicBool>,
    start: Instant,
) -> Result<GenerationSummary, Error> {
    let ChatRequest {
        messages,
        template_override,
        add_assistant,
        image_paths,
        mmproj_path,
        media_marker,
        max_tokens,
        temperature,
        top_p,
        top_k,
        repeat_penalty,
        frequency_penalty,
        presence_penalty,
        seed,
        stop_sequences,
        grammar,
    } = request;

    let max_tokens = max_tokens.unwrap_or(DEFAULT_GENERATION_MAX_TOKENS);
    let max_tokens = usize::try_from(max_tokens.max(0)).unwrap_or(0);
    let stop_sequences = stop_sequences.unwrap_or_default();

    let mut job = GenerationJob {
        cancel_flag: &cancel_flag,
        sink,
        job_id,
        max_tokens,
        stop_sequences: &stop_sequences,
        prompt_tokens: 0,
        generated_tokens: 0,
        finish_reason: FinishReason::Unknown,
    };

    let result = match catch_unwind(AssertUnwindSafe(|| {
        context.with_context_and_cache_mut(|ctx, cached_tokens| -> Result<(), Error> {
            let add_assistant = add_assistant.unwrap_or(true);
            let mut messages = messages;
            let image_paths = image_paths.unwrap_or_default();
            let marker = media_marker
                .clone()
                .unwrap_or_else(|| mtmd_default_marker().to_string());

            if !image_paths.is_empty() {
                let mut marker_count = messages
                    .iter()
                    .map(|message| message.content.matches(&marker).count())
                    .sum::<usize>();
                if marker_count == 0 {
                    let target_index = messages
                        .iter()
                        .rposition(|message| message.role == "user")
                        .or_else(|| messages.len().checked_sub(1))
                        .ok_or_else(|| {
                            Error::InvalidInput("No chat messages provided".to_string())
                        })?;
                    if !messages[target_index].content.ends_with('\n') {
                        messages[target_index].content.push('\n');
                    }
                    messages[target_index].content.push_str(&marker);
                    marker_count = messages
                        .iter()
                        .map(|message| message.content.matches(&marker).count())
                        .sum();
                }
                if marker_count != image_paths.len() {
                    return Err(Error::InvalidInput(format!(
                        "Found {marker_count} media markers but {} images were provided",
                        image_paths.len()
                    )));
                }
            }

            let prompt = build_chat_prompt(ctx.model, messages, template_override, add_assistant)?;

            let sampler_request = SamplingParams {
                temperature,
                top_p,
                top_k,
                repeat_penalty,
                frequency_penalty,
                presence_penalty,
                seed,
                grammar: grammar.clone(),
            };

            if image_paths.is_empty() {
                let prompt_tokens = tokenize_text_prompt(ctx.model, &prompt)?;

                let n_ctx = ctx.n_ctx();
                if prompt_tokens.len() as u32 > n_ctx {
                    return Err(Error::PromptTooLong {
                        tokens: prompt_tokens.len(),
                        context_size: n_ctx,
                    });
                }
                job.prompt_tokens =
                    i32::try_from(prompt_tokens.len()).map_err(|_| Error::PromptTooLong {
                        tokens: prompt_tokens.len(),
                        context_size: n_ctx,
                    })?;

                let n_batch = ctx.n_batch() as usize;
                if n_batch == 0 {
                    return Err(Error::InvalidInput("Context batch size is 0".to_string()));
                }

                let keep = prepare_prompt_cache(ctx.get_mut()?, cached_tokens, &prompt_tokens);
                let allow_gpu = !cfg!(target_os = "ios")
                    || ctx.can_checkpoint_partially()
                    || prompt_tokens.len() - keep >= MIN_GPU_PROMPT_TOKENS;

                job.sink.add(GenerationEvent::PromptProgress {
                    job_id,
                    processed_tokens: keep as i32,
                    total_tokens: job.prompt_tokens,
                });
                let mut token_offset = keep;
                let mut logits_index: i32 = 0;
                while token_offset < prompt_tokens.len() {
                    check_cancelled(&cancel_flag)?;
                    let decoded = ctx.run(
                        allow_gpu,
                        ExecutionState::Replay {
                            tokens: cached_tokens,
                            multimodal: None,
                            cancelled: &cancel_flag,
                        },
                        |ctx, batch_size, synchronize| {
                            check_cancelled(&cancel_flag)?;
                            let end = (token_offset + batch_size).min(prompt_tokens.len());
                            let chunk = &prompt_tokens[token_offset..end];
                            let mut batch = token_batch(
                                chunk,
                                token_offset as i32,
                                end == prompt_tokens.len() || synchronize,
                                "Failed to add prompt token",
                            )?;
                            decode_batch(ctx, &mut batch, synchronize, "Prompt decode failed")?;
                            check_cancelled(&cancel_flag)?;
                            Ok(end)
                        },
                    );
                    let end = match decoded {
                        Ok(end) => end,
                        Err(err) => {
                            ctx.clear_kv_cache();
                            cached_tokens.clear();
                            return Err(err);
                        }
                    };
                    let chunk = &prompt_tokens[token_offset..end];
                    cached_tokens.extend_from_slice(chunk);

                    if end == prompt_tokens.len() {
                        logits_index = (chunk.len() - 1) as i32;
                    }
                    token_offset = end;
                    job.sink.add(GenerationEvent::PromptProgress {
                        job_id,
                        processed_tokens: end as i32,
                        total_tokens: job.prompt_tokens,
                    });
                }

                let mut sampler = build_sampler(ctx.model, &sampler_request, ctx.n_ctx() as i32)?;
                sampler.accept_many(prompt_tokens.iter());

                let pos = prompt_tokens.len() as i32;
                job.run(
                    ctx,
                    &mut sampler,
                    GenerationCache {
                        tokens: cached_tokens,
                        multimodal: None,
                    },
                    pos,
                    logits_index,
                )?;

                return Ok(());
            }

            let mmproj_path = mmproj_path.ok_or_else(|| {
                Error::InvalidInput(
                    "mmproj_path is required when image_paths are provided".to_string(),
                )
            })?;
            let mtmd_ctx = context.cached_mtmd_context(ctx.model, &mmproj_path, &marker)?;

            let mut bitmaps = Vec::with_capacity(image_paths.len());
            for image_path in &image_paths {
                check_cancelled(&cancel_flag)?;
                if !Path::new(image_path).exists() {
                    return Err(Error::NotFound {
                        what: "Image file",
                        path: image_path.clone(),
                    });
                }
                let bitmap =
                    MtmdBitmap::from_file(&mtmd_ctx, image_path, false).map_err(|err| {
                        Error::Llama {
                            op: "Failed to load image",
                            message: err.to_string(),
                        }
                    })?;
                if bitmap.is_audio() {
                    return Err(Error::Unsupported("Audio inputs are not supported"));
                }
                bitmaps.push(bitmap);
            }
            let bitmap_refs = bitmaps.iter().collect::<Vec<_>>();

            let add_special = should_add_bos(ctx.model, &prompt);
            let input_text = MtmdInputText {
                text: prompt,
                add_special,
                parse_special: true,
            };

            let chunks =
                mtmd_ctx
                    .tokenize(input_text, &bitmap_refs)
                    .map_err(|err| Error::Llama {
                        op: "Failed to tokenize multimodal input",
                        message: err.to_string(),
                    })?;

            if chunks.is_empty() {
                return Err(Error::InvalidInput("Prompt produced no tokens".to_string()));
            }

            let n_ctx = ctx.n_ctx();
            let total_positions = chunks.total_positions();
            if total_positions as u32 > n_ctx {
                return Err(Error::PromptTooLong {
                    tokens: total_positions as usize,
                    context_size: n_ctx,
                });
            }
            job.prompt_tokens =
                i32::try_from(chunks.total_tokens()).map_err(|_| Error::PromptTooLong {
                    tokens: chunks.total_tokens(),
                    context_size: n_ctx,
                })?;

            let n_batch = ctx.n_batch() as i32;
            if n_batch <= 0 {
                return Err(Error::InvalidInput("Context batch size is 0".to_string()));
            }

            ctx.clear_kv_cache();
            cached_tokens.clear();
            check_cancelled(&cancel_flag)?;

            let multimodal = MultimodalPrompt {
                context: &mtmd_ctx,
                chunks: &chunks,
            };
            let n_past = ctx.run(
                true,
                ExecutionState::Replay {
                    tokens: &[],
                    multimodal: None,
                    cancelled: &cancel_flag,
                },
                |ctx, batch_size, synchronize| {
                    check_cancelled(&cancel_flag)?;
                    multimodal.eval(ctx, batch_size, synchronize)
                },
            )?;
            check_cancelled(&cancel_flag)?;

            let mut sampler = build_sampler(ctx.model, &sampler_request, ctx.n_ctx() as i32)?;
            let mut prompt_tokens = Vec::new();
            for index in 0..chunks.len() {
                if let Some(chunk) = chunks.get(index)
                    && let Some(tokens) = chunk.text_tokens()
                {
                    prompt_tokens.extend_from_slice(tokens);
                }
            }
            sampler.accept_many(prompt_tokens.iter());

            job.run(
                ctx,
                &mut sampler,
                GenerationCache {
                    tokens: &mut Vec::new(),
                    multimodal: Some(multimodal),
                },
                n_past,
                -1,
            )?;

            Ok(())
        })
    })) {
        Ok(inner) => inner,
        Err(_) => {
            context.invalidate_cache();
            Err(Error::Panicked)
        }
    };
    result?;

    let summary = GenerationSummary {
        job_id,
        prompt_tokens: Some(job.prompt_tokens),
        generated_tokens: Some(job.generated_tokens),
        total_time_ms: Some(start.elapsed().as_millis() as i64),
        finish_reason: job.finish_reason,
    };

    Ok(summary)
}

fn prepare_prompt_cache(
    ctx: &mut LlamaContext,
    cached: &mut Vec<LlamaToken>,
    prompt: &[LlamaToken],
) -> usize {
    let can_rewind =
        !ctx.model.is_recurrent() && !ctx.model.is_hybrid() && ctx.kv_cache_seq_pos_min(0) == 0;
    let mut keep = reusable_prefix_len(cached, prompt, can_rewind);
    if keep > 0
        && keep < cached.len()
        && !matches!(
            ctx.clear_kv_cache_seq(Some(0), Some(keep as u32), None),
            Ok(true)
        )
    {
        keep = 0;
    }
    if keep == 0 {
        ctx.clear_kv_cache();
    }
    cached.truncate(keep);
    keep
}

fn reusable_prefix_len(cached: &[LlamaToken], prompt: &[LlamaToken], can_rewind: bool) -> usize {
    let keep = cached
        .iter()
        .zip(prompt)
        .take_while(|(cached, prompt)| cached == prompt)
        .count()
        .min(prompt.len().saturating_sub(1));
    if !can_rewind && keep < cached.len() {
        0
    } else {
        keep
    }
}

pub fn cancel(job_id: JobId) {
    if job_id <= 0 {
        cancel_all();
        return;
    }
    if let Some(flag) = lock(cancel_flags()).get(&job_id) {
        flag.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::{StreamDecoder, reusable_prefix_len};
    use llama_cpp_2::token::LlamaToken;

    fn tokens(ids: &[i32]) -> Vec<LlamaToken> {
        ids.iter().copied().map(LlamaToken).collect()
    }

    #[test]
    fn stream_decoder_emits_complete_utf8() {
        let mut decoder = StreamDecoder::new(&[]);
        let step = decoder.push_bytes(&[0xF0, 0x9F]);
        assert!(step.text.is_none());
        assert!(!step.stop);

        let step = decoder.push_bytes(&[0x99, 0x82]);
        assert_eq!(step.text.as_deref(), Some("🙂"));
        assert!(!step.stop);
    }

    #[test]
    fn stop_sequences_are_withheld_across_stream_boundaries() {
        for (pieces, stops, expected, stopped) in [
            (
                vec!["hello <", "END", "> ignored"],
                vec!["<END>"],
                "hello ",
                true,
            ),
            (vec!["🙂é", "FIN rest"], vec!["éFIN"], "🙂", true),
            (vec!["hello <EN"], vec!["<END>"], "hello <EN", false),
            (vec!["hello <E", "lse"], vec!["<END>"], "hello <Else", false),
            (
                vec!["before STOP after END"],
                vec!["END", "STOP"],
                "before ",
                true,
            ),
            (vec!["hello", " world"], vec![""], "hello world", false),
            (
                vec!["{\"fragment", "_start_byte\":0"],
                vec!["{\"fragment_start_byte\":"],
                "",
                true,
            ),
        ] {
            let mut decoder =
                StreamDecoder::new(&stops.into_iter().map(str::to_owned).collect::<Vec<_>>());
            let mut output = String::new();
            let mut did_stop = false;
            for piece in pieces {
                let step = decoder.push_bytes(piece.as_bytes());
                output.push_str(step.text.as_deref().unwrap_or(""));
                if step.stop {
                    did_stop = true;
                    break;
                }
            }
            if !did_stop {
                let step = decoder.flush();
                output.push_str(step.text.as_deref().unwrap_or(""));
                did_stop = step.stop;
            }
            assert_eq!(output, expected);
            assert_eq!(did_stop, stopped);
        }
    }

    #[test]
    #[ignore = "requires ENSU_TEST_SWA_MODEL"]
    fn restored_sliding_window_cache_only_reuses_retained_history() {
        use super::{prepare_prompt_cache, token_batch};
        use crate::llm::execution::{ExecutionContext, ExecutionState};
        use crate::llm::{ExecutionControl, ExecutionParams, Model, ModelLoadParams, backend};
        use llama_cpp_2::context::{params::LlamaContextParams, session::LlamaStateSeqFlags};
        use std::num::NonZeroU32;
        use std::sync::{Arc, atomic::AtomicBool};

        let model = Model::load(ModelLoadParams {
            model_path: std::env::var("ENSU_TEST_SWA_MODEL").unwrap(),
            n_gpu_layers: Some(0),
            use_mmap: None,
            use_mlock: None,
        })
        .unwrap();
        assert!(!model.model().is_hybrid() && !model.model().is_recurrent());
        let params = LlamaContextParams::default()
            .with_n_ctx(NonZeroU32::new(2048))
            .with_n_threads(4)
            .with_n_threads_batch(4)
            .with_n_batch(512)
            .with_n_ubatch(512)
            .with_op_offload(false)
            .with_offload_kqv(false);
        let mut context = model
            .model()
            .new_context(backend().unwrap(), params.clone())
            .unwrap();
        let phrase = model.model().vocab().tokenize(
            b"The quick brown fox jumped over the lazy dog. ",
            true,
            true,
        );
        let mut cached: Vec<_> = phrase.into_iter().cycle().take(1024).collect();
        for (offset, chunk) in cached.chunks(512).enumerate() {
            let mut batch = token_batch(
                chunk,
                (offset * 512) as i32,
                true,
                "Failed to add test token",
            )
            .unwrap();
            context.decode(&mut batch).unwrap();
        }
        let snapshot = context
            .state_seq_get(0, LlamaStateSeqFlags::empty())
            .unwrap();
        let mut restored = model
            .model()
            .new_context(backend().unwrap(), params.clone())
            .unwrap();
        for (prefix, expected) in [(100, 0), (1024, 1024)] {
            restored.state_seq_set(&snapshot, 0).unwrap();
            assert!(restored.kv_cache_seq_pos_min(0) > 0);
            let mut prompt = cached[..prefix].to_vec();
            prompt.push(LlamaToken(cached[prefix % cached.len()].0 + 1));
            let mut reused = cached.clone();
            assert_eq!(
                prepare_prompt_cache(&mut restored, &mut reused, &prompt),
                expected
            );
            assert_eq!(reused.len(), expected);
            if expected == 0 {
                assert_eq!(restored.kv_cache_seq_pos_max(0), -1);
            }
        }

        let full = context
            .state_seq_get(-1, LlamaStateSeqFlags::empty())
            .unwrap();
        restored.state_seq_set(&full, 0).unwrap();
        let mut switching = ExecutionContext::new(restored, params, false);
        let control = Arc::new(ExecutionControl::new(|| u64::MAX));
        control
            .set_params(ExecutionParams {
                allow_gpu: false,
                n_threads: 4,
                n_threads_generation: 4,
                batch_size: 256,
            })
            .unwrap();
        switching.control = Some(control);
        let cancelled = AtomicBool::new(false);
        switching
            .run(
                false,
                ExecutionState::Replay {
                    tokens: &cached,
                    multimodal: None,
                    cancelled: &cancelled,
                },
                |_, _, _| Ok(()),
            )
            .unwrap();
        assert_eq!(switching.get().unwrap().kv_cache_seq_pos_min(0), 0);
        let start = cached.len();
        for position in start..start + 8 {
            let token = cached[position % start];
            let mut batch =
                token_batch(&[token], position as i32, true, "Failed to add test token").unwrap();
            context.decode(&mut batch).unwrap();
            switching
                .run(
                    false,
                    ExecutionState::Replay {
                        tokens: &cached,
                        multimodal: None,
                        cancelled: &cancelled,
                    },
                    |ctx, _, _| {
                        ctx.decode(&mut batch).unwrap();
                        Ok(())
                    },
                )
                .unwrap();
            assert!(
                context
                    .get_logits()
                    .iter()
                    .zip(switching.get().unwrap().get_logits())
                    .all(|(a, b)| (a - b).abs() < 1e-5)
            );
            cached.push(token);
        }
    }

    #[test]
    fn reuses_only_supported_prompt_prefixes() {
        for (cached, prompt, rewind, append_only) in [
            (vec![], vec![1], 0, 0),
            (vec![1, 2], vec![], 0, 0),
            (vec![1], vec![1], 0, 0),
            (vec![1, 2], vec![1], 0, 0),
            (vec![1, 2], vec![1, 2], 1, 0),
            (vec![1, 2, 3], vec![1, 2], 1, 0),
            (vec![1, 2, 3], vec![1, 2, 4, 5], 2, 0),
            (vec![1, 2], vec![1, 3, 4], 1, 0),
            (vec![1, 2], vec![1, 2, 3], 2, 2),
            (vec![1, 2], vec![9, 2, 3], 0, 0),
        ] {
            for (can_rewind, expected) in [(true, rewind), (false, append_only)] {
                assert_eq!(
                    reusable_prefix_len(&tokens(&cached), &tokens(&prompt), can_rewind),
                    expected,
                    "cached={cached:?}, prompt={prompt:?}, can_rewind={can_rewind}"
                );
            }
        }
    }
}
