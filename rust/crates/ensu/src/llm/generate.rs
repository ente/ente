use llama_cpp_2::TokenToStringError;
use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::{AddBos, LlamaChatMessage, LlamaChatTemplate, LlamaModel};
use llama_cpp_2::mtmd::{MtmdBitmap, MtmdInputText, mtmd_default_marker};
use llama_cpp_2::openai::OpenAIChatTemplateParams;
use llama_cpp_2::sampling::LlamaSampler;
use llama_cpp_2::token::LlamaToken;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Instant;

use super::context::Context;
use super::event::{EventSink, GenerationEvent, GenerationSummary, JobId};
use super::{Error, format_error};

static JOB_COUNTER: AtomicI64 = AtomicI64::new(1);
static CANCEL_FLAGS: OnceLock<Mutex<HashMap<JobId, Arc<AtomicBool>>>> = OnceLock::new();

const DEFAULT_GENERATION_MAX_TOKENS: i32 = 8_192;

fn cancel_flags() -> &'static Mutex<HashMap<JobId, Arc<AtomicBool>>> {
    CANCEL_FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn register_job() -> (JobId, Arc<AtomicBool>) {
    let job_id = JOB_COUNTER.fetch_add(1, Ordering::Relaxed);
    let flag = Arc::new(AtomicBool::new(false));
    cancel_flags().lock().insert(job_id, flag.clone());
    (job_id, flag)
}

fn cancel_all() {
    for flag in cancel_flags().lock().values() {
        flag.store(true, Ordering::Relaxed);
    }
}

fn check_cancelled(cancel_flag: &AtomicBool) -> Result<(), Error> {
    if cancel_flag.load(Ordering::Relaxed) {
        Err(Error::Cancelled)
    } else {
        Ok(())
    }
}

struct JobGuard(JobId);

impl Drop for JobGuard {
    fn drop(&mut self) {
        cancel_flags().lock().remove(&self.0);
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

#[derive(Debug, Clone, Serialize, Deserialize)]
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

fn token_piece_bytes(model: &LlamaModel, token: LlamaToken) -> Result<Vec<u8>, TokenToStringError> {
    match model.token_to_piece_bytes(token, 8, true, None) {
        Err(TokenToStringError::InsufficientBufferSpace(required)) => model.token_to_piece_bytes(
            token,
            (-required)
                .try_into()
                .expect("error buffer size is positive"),
            true,
            None,
        ),
        result => result,
    }
}

fn token_piece_string(model: &LlamaModel, token: LlamaToken) -> Option<String> {
    String::from_utf8(token_piece_bytes(model, token).ok()?).ok()
}

fn build_chat_prompt(
    model: &LlamaModel,
    messages: Vec<ChatMessage>,
    template_override: Option<String>,
    add_assistant: bool,
) -> Result<String, Error> {
    let template_text = match template_override {
        Some(template) => template,
        None => model
            .chat_template(None)
            .ok()
            .and_then(|template| template.to_string().ok())
            .unwrap_or_else(|| "chatml".to_string()),
    };
    let template = LlamaChatTemplate::new(&template_text)
        .map_err(|err| Error::InvalidInput(format_error("Invalid chat template", err)))?;

    if template_text.contains("enable_thinking") {
        let messages_json = serde_json::to_string(&messages)
            .map_err(|err| Error::InvalidInput(format_error("Invalid chat messages", err)))?;
        let params = OpenAIChatTemplateParams {
            messages_json: &messages_json,
            tools_json: None,
            tool_choice: None,
            json_schema: None,
            grammar: None,
            reasoning_format: None,
            chat_template_kwargs: Some(r#"{"enable_thinking":false}"#),
            add_generation_prompt: add_assistant,
            use_jinja: true,
            parallel_tool_calls: false,
            enable_thinking: false,
            add_bos: false,
            add_eos: false,
            parse_tool_calls: false,
        };
        let result = model
            .apply_chat_template_oaicompat(&template, &params)
            .map_err(|err| Error::Llama {
                op: "Failed to apply chat template",
                message: err.to_string(),
            })?;
        return Ok(result.prompt);
    }

    let chat_messages = messages
        .into_iter()
        .map(|message| {
            LlamaChatMessage::new(message.role, message.content)
                .map_err(|err| Error::InvalidInput(format_error("Invalid chat message", err)))
        })
        .collect::<Result<Vec<_>, Error>>()?;

    model
        .apply_chat_template(&template, &chat_messages, add_assistant)
        .map_err(|err| Error::Llama {
            op: "Failed to apply chat template",
            message: err.to_string(),
        })
}

fn should_add_bos(model: &LlamaModel, prompt: &str) -> AddBos {
    if let Some(bos) = token_piece_string(model, model.token_bos())
        && !bos.is_empty()
        && prompt.starts_with(&bos)
    {
        return AddBos::Never;
    }
    AddBos::Always
}

fn find_stop_index(text: &str, stop_sequences: &[String], start: usize) -> Option<usize> {
    let mut found: Option<usize> = None;
    let search = &text[start.min(text.len())..];

    for stop in stop_sequences {
        if stop.is_empty() {
            continue;
        }
        if let Some(idx) = search.find(stop) {
            let idx = start + idx;
            found = match found {
                Some(existing) if existing <= idx => Some(existing),
                _ => Some(idx),
            };
        }
    }

    found
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

/// Incremental UTF-8 streaming decoder with stop-sequence handling.
struct StreamDecoder {
    generated_text: String,
    pending_bytes: Vec<u8>,
    stop_sequences: Vec<String>,
    max_stop_len: usize,
}

impl StreamDecoder {
    fn new(stop_sequences: &[String]) -> Self {
        let max_stop_len = stop_sequences.iter().map(|s| s.len()).max().unwrap_or(0);
        Self {
            generated_text: String::new(),
            pending_bytes: Vec::new(),
            stop_sequences: stop_sequences.to_vec(),
            max_stop_len,
        }
    }

    fn push_bytes(&mut self, bytes: &[u8]) -> DecodeStep {
        if !bytes.is_empty() {
            self.pending_bytes.extend_from_slice(bytes);
        }
        let piece = drain_utf8(&mut self.pending_bytes);
        self.push_text(piece)
    }

    fn flush(&mut self) -> DecodeStep {
        if self.pending_bytes.is_empty() {
            return DecodeStep {
                text: None,
                stop: false,
            };
        }
        let piece = String::from_utf8_lossy(&self.pending_bytes).to_string();
        self.pending_bytes.clear();
        self.push_text(piece)
    }

    fn push_text(&mut self, piece: String) -> DecodeStep {
        if piece.is_empty() {
            return DecodeStep {
                text: None,
                stop: false,
            };
        }

        let prev_len = self.generated_text.len();
        self.generated_text.push_str(&piece);

        if self.max_stop_len > 0 {
            let search_start = prev_len.saturating_sub(self.max_stop_len);
            if let Some(stop_index) =
                find_stop_index(&self.generated_text, &self.stop_sequences, search_start)
            {
                let new_piece = self.generated_text[prev_len..stop_index].to_string();
                self.generated_text.truncate(stop_index);
                return DecodeStep {
                    text: if new_piece.is_empty() {
                        None
                    } else {
                        Some(new_piece)
                    },
                    stop: true,
                };
            }
        }

        DecodeStep {
            text: Some(piece),
            stop: false,
        }
    }
}

/// Length of the longest common prefix of `cached` and `prompt`.
fn common_prefix_len(cached: &[LlamaToken], prompt: &[LlamaToken]) -> usize {
    cached
        .iter()
        .zip(prompt.iter())
        .take_while(|(cached, prompt)| cached == prompt)
        .count()
}

/// Length of the longest common prefix of `cached` and `prompt`, capped so
/// that at least one prompt token is always left to decode: sampling needs
/// fresh logits, which only a decode produces.
fn reusable_prefix_len(cached: &[LlamaToken], prompt: &[LlamaToken]) -> usize {
    common_prefix_len(cached, prompt).min(prompt.len().saturating_sub(1))
}

/// Cap the reusable prefix for sliding-window-attention models.
///
/// An SWA layer's KV cache physically holds only about the last `n_swa`
/// positions (llama.cpp sizes it to `n_swa + n_ubatch` and overwrites cells
/// that fall out of the window as decoding advances), yet partial
/// `seq_rm` still reports success. Re-decoding from a point more than one
/// position before the cache end would therefore attend over history that
/// is no longer present and silently corrupt the output; llama-server
/// forces a full re-process in the same situation. Rolling back zero or
/// one positions needs exactly the window the cache is guaranteed to still
/// hold, so those stay allowed (covering pure extension and the
/// identical-prompt case).
fn swa_safe_prefix_len(cached_len: usize, keep: usize, swa: bool) -> usize {
    if swa && cached_len > keep + 1 {
        0
    } else {
        keep
    }
}

/// Prepare the KV cache for a new prompt: keep the longest reusable prefix,
/// evict everything past it, and return the number of positions kept.
/// `cached` is updated to mirror the KV cache contents. `swa` must be true
/// for sliding-window-attention models (see [`swa_safe_prefix_len`]).
fn apply_prefix_reuse(
    ctx: &mut LlamaContext,
    cached: &mut Vec<LlamaToken>,
    prompt: &[LlamaToken],
    swa: bool,
) -> usize {
    let keep = swa_safe_prefix_len(cached.len(), reusable_prefix_len(cached, prompt), swa);
    // Reusable when we keep a non-empty prefix and, if the cache is longer,
    // its diverged tail can actually be evicted. Nothing reusable and a failed
    // partial removal (or a length that does not fit the API type) both fall
    // through to the single full-reset path below.
    let reusable = keep > 0
        && (cached.len() <= keep
            || u32::try_from(keep)
                .ok()
                .and_then(|p0| ctx.clear_kv_cache_seq(Some(0), Some(p0), None).ok())
                .unwrap_or(false));
    if !reusable {
        ctx.clear_kv_cache();
        cached.clear();
        return 0;
    }
    cached.truncate(keep);
    keep
}

/// Decode `prompt_tokens[keep..]` into the KV cache in `n_batch`-sized
/// chunks, extending `cached_tokens` only after each successful decode (so
/// on cancel or error the bookkeeping reflects exactly what reached the
/// cache). With `want_logits` the last prompt token requests logits (needed
/// before sampling); returns that token's index within its chunk, or 0 when
/// nothing was decoded.
fn decode_prompt_suffix(
    ctx: &mut LlamaContext,
    cached_tokens: &mut Vec<LlamaToken>,
    prompt_tokens: &[LlamaToken],
    keep: usize,
    n_batch: usize,
    cancel_flag: &AtomicBool,
    want_logits: bool,
) -> Result<i32, Error> {
    let mut token_offset = keep;
    let mut logits_index: i32 = 0;
    while token_offset < prompt_tokens.len() {
        check_cancelled(cancel_flag)?;
        let end = (token_offset + n_batch).min(prompt_tokens.len());
        let chunk = &prompt_tokens[token_offset..end];
        let mut batch = LlamaBatch::new(chunk.len(), 1);
        for (idx, token) in chunk.iter().enumerate() {
            let pos = (token_offset + idx) as i32;
            let logits = want_logits && token_offset + idx + 1 == prompt_tokens.len();
            batch
                .add(*token, pos, &[0], logits)
                .map_err(|err| Error::Llama {
                    op: "Failed to add prompt token",
                    message: err.to_string(),
                })?;
        }
        if let Err(err) = ctx.decode(&mut batch) {
            // The KV cache state is uncertain after a failed decode; drop it
            // so the next generation starts from a clean slate.
            ctx.clear_kv_cache();
            cached_tokens.clear();
            return Err(Error::Llama {
                op: "Prompt decode failed",
                message: err.to_string(),
            });
        }
        cached_tokens.extend_from_slice(chunk);
        if end == prompt_tokens.len() {
            logits_index = (chunk.len() - 1) as i32;
        }
        token_offset = end;
    }
    Ok(logits_index)
}

#[allow(clippy::too_many_arguments)]
fn run_generation_loop(
    ctx: &mut LlamaContext,
    sampler: &mut LlamaSampler,
    cancel_flag: &AtomicBool,
    sink: &mut dyn EventSink,
    job_id: JobId,
    max_tokens: usize,
    stop_sequences: &[String],
    generated_tokens_count: &mut i32,
    mut cached_tokens: Option<&mut Vec<LlamaToken>>,
    mut pos: i32,
    mut logits_index: i32,
) -> Result<(), Error> {
    let mut decoder = StreamDecoder::new(stop_sequences);
    let mut stop_triggered = false;
    let n_ctx = ctx.n_ctx();

    for _ in 0..max_tokens {
        if cancel_flag.load(Ordering::Relaxed) {
            return Err(Error::Cancelled);
        }
        if pos >= n_ctx as i32 {
            break;
        }

        let token = sampler.sample(ctx, logits_index);
        sampler.accept(token);
        *generated_tokens_count = generated_tokens_count.saturating_add(1);

        if ctx.model.is_eog_token(token) {
            break;
        }

        let bytes = token_piece_bytes(ctx.model, token).map_err(|err| Error::Llama {
            op: "Detokenize failed",
            message: err.to_string(),
        })?;
        let step = decoder.push_bytes(&bytes);

        if let Some(text) = step.text {
            sink.add(GenerationEvent::Text {
                job_id,
                text,
                token_id: Some(token.0),
            });
        }

        if step.stop {
            stop_triggered = true;
            break;
        }

        let mut step_batch = LlamaBatch::new(1, 1);
        step_batch
            .add(token, pos, &[0], true)
            .map_err(|err| Error::Llama {
                op: "Failed to add token",
                message: err.to_string(),
            })?;
        if let Err(err) = ctx.decode(&mut step_batch) {
            // The KV cache state is uncertain after a failed decode; drop it
            // so the next generation starts from a clean slate.
            ctx.clear_kv_cache();
            if let Some(cached) = cached_tokens.as_deref_mut() {
                cached.clear();
            }
            return Err(Error::Llama {
                op: "Decode failed",
                message: err.to_string(),
            });
        }
        if let Some(cached) = cached_tokens.as_deref_mut() {
            cached.push(token);
        }

        logits_index = 0;
        pos += 1;
    }

    if !stop_triggered {
        let step = decoder.flush();
        if let Some(text) = step.text {
            sink.add(GenerationEvent::Text {
                job_id,
                text,
                token_id: None,
            });
        }
    }

    Ok(())
}

fn build_sampler(model: &LlamaModel, request: &SamplingParams) -> Result<LlamaSampler, Error> {
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
            -1,
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

impl Context {
    pub fn generate_chat_stream(
        &self,
        request: ChatRequest,
        sink: &mut dyn EventSink,
    ) -> Result<GenerationSummary, Error> {
        generate_chat_stream(self, request, sink)
    }
}

fn generate_chat_stream(
    context: &Context,
    request: ChatRequest,
    sink: &mut dyn EventSink,
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

    let (job_id, cancel_flag) = register_job();
    let _job_guard = JobGuard(job_id);
    let start = Instant::now();

    sink.add(GenerationEvent::Text {
        job_id,
        text: String::new(),
        token_id: None,
    });

    let max_tokens = max_tokens.unwrap_or(DEFAULT_GENERATION_MAX_TOKENS);
    let max_tokens = usize::try_from(max_tokens.max(0)).unwrap_or(0);
    let stop_sequences = stop_sequences.unwrap_or_default();

    let mut prompt_tokens_count: i32 = 0;
    let mut decoded_prompt_tokens_count: i32 = 0;
    let mut generated_tokens_count: i32 = 0;

    let result = match catch_unwind(AssertUnwindSafe(|| {
        context.with_context_mut(|ctx| -> Result<(), Error> {
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
                let add_bos = should_add_bos(ctx.model, &prompt);
                let prompt_tokens =
                    ctx.model
                        .str_to_token(&prompt, add_bos)
                        .map_err(|err| Error::Llama {
                            op: "Tokenize failed",
                            message: err.to_string(),
                        })?;

                if prompt_tokens.is_empty() {
                    return Err(Error::InvalidInput("Prompt produced no tokens".to_string()));
                }

                let n_ctx = ctx.n_ctx();
                if prompt_tokens.len() as u32 > n_ctx {
                    return Err(Error::PromptTooLong {
                        tokens: prompt_tokens.len(),
                        context_size: n_ctx,
                    });
                }
                prompt_tokens_count =
                    i32::try_from(prompt_tokens.len()).map_err(|_| Error::PromptTooLong {
                        tokens: prompt_tokens.len(),
                        context_size: n_ctx,
                    })?;

                let n_batch = ctx.n_batch() as usize;
                if n_batch == 0 {
                    return Err(Error::InvalidInput("Context batch size is 0".to_string()));
                }

                // Reuse the longest common prefix already in the KV cache and
                // only decode the remainder of the prompt.
                let mut cached_tokens = context.cached_tokens();
                let keep =
                    apply_prefix_reuse(ctx, &mut cached_tokens, &prompt_tokens, context.uses_swa());
                decoded_prompt_tokens_count = (prompt_tokens.len() - keep) as i32;

                let logits_index = decode_prompt_suffix(
                    ctx,
                    &mut cached_tokens,
                    &prompt_tokens,
                    keep,
                    n_batch,
                    &cancel_flag,
                    true,
                )?;

                let mut sampler = build_sampler(ctx.model, &sampler_request)?;
                // Accept the full prompt (not just the decoded suffix) so
                // penalty state is identical whether or not a cached prefix
                // was reused.
                sampler.accept_many(prompt_tokens.iter());

                let pos = prompt_tokens.len() as i32;
                run_generation_loop(
                    ctx,
                    &mut sampler,
                    &cancel_flag,
                    sink,
                    job_id,
                    max_tokens,
                    &stop_sequences,
                    &mut generated_tokens_count,
                    Some(&mut cached_tokens),
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
                    MtmdBitmap::from_file(&mtmd_ctx, image_path).map_err(|err| Error::Llama {
                        op: "Failed to load image",
                        message: err.to_string(),
                    })?;
                if bitmap.is_audio() {
                    return Err(Error::Unsupported("Audio inputs are not supported"));
                }
                bitmaps.push(bitmap);
            }
            let bitmap_refs = bitmaps.iter().collect::<Vec<_>>();

            let add_special = matches!(should_add_bos(ctx.model, &prompt), AddBos::Always);
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
            prompt_tokens_count =
                i32::try_from(chunks.total_tokens()).map_err(|_| Error::PromptTooLong {
                    tokens: chunks.total_tokens(),
                    context_size: n_ctx,
                })?;

            let n_batch = ctx.n_batch() as i32;
            if n_batch <= 0 {
                return Err(Error::InvalidInput("Context batch size is 0".to_string()));
            }

            // Multimodal prompts always start from a cold cache: prefix
            // matching across image embeddings is not attempted, and the
            // bookkeeping stays empty so the next text-only generation does
            // a full decode instead of reusing positions that contain image
            // embeddings.
            ctx.clear_kv_cache();
            context.cached_tokens().clear();
            decoded_prompt_tokens_count = prompt_tokens_count;
            check_cancelled(&cancel_flag)?;

            let n_past = chunks
                .eval_chunks(&mtmd_ctx, ctx, 0, 0, n_batch, true)
                .map_err(|err| Error::Llama {
                    op: "Failed to evaluate multimodal prompt",
                    message: err.to_string(),
                })?;
            check_cancelled(&cancel_flag)?;

            let mut sampler = build_sampler(ctx.model, &sampler_request)?;
            let mut prompt_tokens = Vec::new();
            for index in 0..chunks.len() {
                if let Some(chunk) = chunks.get(index)
                    && let Some(tokens) = chunk.text_tokens()
                {
                    prompt_tokens.extend_from_slice(tokens);
                }
            }
            sampler.accept_many(prompt_tokens.iter());

            run_generation_loop(
                ctx,
                &mut sampler,
                &cancel_flag,
                sink,
                job_id,
                max_tokens,
                &stop_sequences,
                &mut generated_tokens_count,
                None,
                n_past,
                -1,
            )?;

            Ok(())
        })
    })) {
        Ok(inner) => inner,
        Err(_) => {
            // After a panic the KV cache and the bookkeeping may disagree.
            // Empty the bookkeeping so the next generation clears the cache
            // and starts cold.
            context.cached_tokens().clear();
            Err(Error::Panicked)
        }
    };
    result?;

    let summary = GenerationSummary {
        job_id,
        prompt_tokens: Some(prompt_tokens_count),
        decoded_prompt_tokens: Some(decoded_prompt_tokens_count),
        generated_tokens: Some(generated_tokens_count),
        total_time_ms: Some(start.elapsed().as_millis() as i64),
    };

    sink.add(GenerationEvent::Done {
        summary: summary.clone(),
    });

    Ok(summary)
}

pub fn cancel(job_id: JobId) {
    if job_id <= 0 {
        cancel_all();
        return;
    }
    if let Some(flag) = cancel_flags().lock().get(&job_id) {
        flag.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::{StreamDecoder, reusable_prefix_len, swa_safe_prefix_len};
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
    fn prefix_len_empty_cache() {
        assert_eq!(reusable_prefix_len(&[], &tokens(&[1, 2, 3])), 0);
    }

    #[test]
    fn prefix_len_empty_prompt() {
        assert_eq!(reusable_prefix_len(&tokens(&[1, 2, 3]), &[]), 0);
    }

    #[test]
    fn prefix_len_identical_prompt_leaves_one_token_to_decode() {
        // Sampling needs logits, so the last prompt token must be re-decoded
        // even when the whole prompt is already cached.
        assert_eq!(
            reusable_prefix_len(&tokens(&[1, 2, 3]), &tokens(&[1, 2, 3])),
            2
        );
    }

    #[test]
    fn prefix_len_divergence_at_start() {
        assert_eq!(
            reusable_prefix_len(&tokens(&[9, 2, 3]), &tokens(&[1, 2, 3])),
            0
        );
    }

    #[test]
    fn prefix_len_divergence_in_middle() {
        assert_eq!(
            reusable_prefix_len(&tokens(&[1, 2, 9, 4]), &tokens(&[1, 2, 3, 4, 5])),
            2
        );
    }

    #[test]
    fn prefix_len_divergence_at_end_of_cache() {
        assert_eq!(
            reusable_prefix_len(&tokens(&[1, 2, 3, 9]), &tokens(&[1, 2, 3, 4, 5])),
            3
        );
    }

    #[test]
    fn prefix_len_prompt_extends_cache() {
        // The typical warm case: the new prompt is old prompt + reply + new
        // message, so the whole cache is reusable.
        assert_eq!(
            reusable_prefix_len(&tokens(&[1, 2, 3]), &tokens(&[1, 2, 3, 4, 5])),
            3
        );
    }

    #[test]
    fn prefix_len_prompt_shorter_than_cache() {
        // The prompt is a strict prefix of the cache; everything except the
        // final prompt token is reusable.
        assert_eq!(
            reusable_prefix_len(&tokens(&[1, 2, 3, 4, 5]), &tokens(&[1, 2, 3])),
            2
        );
    }

    #[test]
    fn prefix_len_single_token_prompt() {
        assert_eq!(reusable_prefix_len(&tokens(&[1, 2]), &tokens(&[1])), 0);
    }

    #[test]
    fn swa_allows_pure_extension() {
        // cached=[..3], prompt extends it: keep == cached_len, no rollback.
        assert_eq!(swa_safe_prefix_len(3, 3, true), 3);
    }

    #[test]
    fn swa_allows_one_token_rollback() {
        // The identical-prompt case: keep == cached_len - 1. The SWA cache
        // is guaranteed to retain exactly the window this decode needs.
        assert_eq!(swa_safe_prefix_len(4, 3, true), 3);
    }

    #[test]
    fn swa_rejects_deeper_rollback() {
        // Rolling back two or more positions may attend over SWA cells
        // that were already overwritten: force a full re-decode.
        assert_eq!(swa_safe_prefix_len(5, 3, true), 0);
        assert_eq!(swa_safe_prefix_len(100, 1, true), 0);
    }

    #[test]
    fn non_swa_keeps_any_rollback() {
        assert_eq!(swa_safe_prefix_len(100, 1, false), 1);
        assert_eq!(swa_safe_prefix_len(5, 3, false), 3);
    }

    /// Mirrors the bookkeeping of the prefill loop: the cache is truncated to
    /// the reusable prefix up front and extended chunk by chunk only after a
    /// chunk decodes successfully. A partial decode (cancel between chunks)
    /// must leave `cached` holding exactly the tokens that were decoded.
    #[test]
    fn cached_tokens_bookkeeping_on_partial_decode() {
        let mut cached = tokens(&[1, 2, 3, 8, 9]);
        let prompt = tokens(&[1, 2, 3, 4, 5, 6, 7]);
        let n_batch = 2;

        let keep = reusable_prefix_len(&cached, &prompt);
        assert_eq!(keep, 3);
        cached.truncate(keep);

        // Decode chunks of n_batch tokens, cancelling before the last chunk.
        let mut token_offset = keep;
        let mut decoded_chunks = 0;
        while token_offset < prompt.len() {
            if decoded_chunks == 1 {
                break; // simulated cancel between chunks
            }
            let end = (token_offset + n_batch).min(prompt.len());
            cached.extend_from_slice(&prompt[token_offset..end]);
            decoded_chunks += 1;
            token_offset = end;
        }

        assert_eq!(cached, tokens(&[1, 2, 3, 4, 5]));

        // The next attempt with the same prompt resumes from what was
        // actually decoded.
        let keep = reusable_prefix_len(&cached, &prompt);
        assert_eq!(keep, 5);
    }

    /// End-to-end equivalence of cold and warm generation. Requires a real
    /// model; run with:
    /// `cargo test -p ente-ensu kv_reuse_equivalence -- --ignored --nocapture`
    /// Override the model path with the `ENSU_TEST_MODEL` env var.
    #[test]
    #[ignore]
    fn kv_reuse_equivalence() {
        use crate::llm::{
            ChatMessage, ChatRequest, Context, ContextParams, EventSink, GenerationEvent,
            GenerationSummary, Model, ModelLoadParams,
        };

        struct Collect(String);
        impl EventSink for Collect {
            fn add(&mut self, event: GenerationEvent) {
                if let GenerationEvent::Text { text, .. } = event {
                    self.0.push_str(&text);
                }
            }
        }

        fn request(messages: Vec<ChatMessage>) -> ChatRequest {
            ChatRequest {
                messages,
                template_override: None,
                add_assistant: Some(true),
                image_paths: None,
                mmproj_path: None,
                media_marker: None,
                max_tokens: Some(48),
                // temperature 0 selects the greedy sampler, making output
                // deterministic for a given KV/logits state.
                temperature: Some(0.0),
                top_p: None,
                top_k: None,
                repeat_penalty: None,
                frequency_penalty: None,
                presence_penalty: None,
                seed: None,
                stop_sequences: None,
                grammar: None,
            }
        }

        fn message(role: &str, content: &str) -> ChatMessage {
            ChatMessage {
                role: role.to_string(),
                content: content.to_string(),
            }
        }

        fn run(context: &Context, messages: Vec<ChatMessage>) -> (String, GenerationSummary) {
            let mut sink = Collect(String::new());
            let summary = context
                .generate_chat_stream(request(messages), &mut sink)
                .expect("generation failed");
            (sink.0, summary)
        }

        let model_path = std::env::var("ENSU_TEST_MODEL").unwrap_or_else(|_| {
            let home = std::env::var("HOME").expect("HOME not set");
            format!("{home}/.local/share/io.ente.ensu/models/gemma-4-E4B-it-Q4_K_M.gguf")
        });
        assert!(
            std::path::Path::new(&model_path).exists(),
            "model not found at {model_path}; set ENSU_TEST_MODEL"
        );

        let model = Model::load(ModelLoadParams {
            model_path,
            n_gpu_layers: Some(0),
            use_mmap: None,
            use_mlock: None,
        })
        .expect("model load failed");

        let context_params = ContextParams {
            context_size: Some(2048),
            n_threads: None,
            n_batch: None,
        };

        let turn1 = vec![message("user", "Name the three primary colors.")];

        // Warm path: two turns on the same context; the second turn should
        // reuse the KV prefix from the first.
        let warm_context = Context::new(&model, context_params.clone()).expect("context failed");
        let (reply1, _summary1) = run(&warm_context, turn1.clone());
        assert!(!reply1.is_empty());

        let mut turn2 = turn1.clone();
        turn2.push(message("assistant", &reply1));
        turn2.push(message("user", "Now name two secondary colors."));

        let (warm_text, warm_summary) = run(&warm_context, turn2.clone());
        drop(warm_context);

        // Cold path: the same second turn on a fresh context.
        let cold_context = Context::new(&model, context_params).expect("context failed");
        let (cold_text, cold_summary) = run(&cold_context, turn2);

        assert_eq!(
            warm_text, cold_text,
            "warm output must be byte-identical to cold output"
        );

        let cold_decoded = cold_summary.decoded_prompt_tokens.expect("count missing");
        let warm_decoded = warm_summary.decoded_prompt_tokens.expect("count missing");
        assert_eq!(
            Some(cold_decoded),
            cold_summary.prompt_tokens,
            "cold run must decode the full prompt"
        );
        assert!(
            warm_decoded < cold_decoded,
            "warm run must decode fewer prompt tokens ({warm_decoded} vs {cold_decoded})"
        );
    }
}
