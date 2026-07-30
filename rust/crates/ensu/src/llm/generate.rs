use llama_cpp_2::TokenToStringError;
use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::{AddBos, LlamaChatMessage, LlamaChatTemplate, LlamaModel};
use llama_cpp_2::mtmd::{MtmdBitmap, MtmdInputText, mtmd_default_marker};
use llama_cpp_2::openai::OpenAIChatTemplateParams;
use llama_cpp_2::sampling::LlamaSampler;
use llama_cpp_2::token::LlamaToken;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;

use super::context::Context;
use super::event::{EventSink, GenerationEvent, GenerationSummary, JobId};
use super::{Error, format_error, lock};

static JOB_COUNTER: AtomicI64 = AtomicI64::new(1);
static CANCEL_FLAGS: OnceLock<Mutex<HashMap<JobId, Arc<AtomicBool>>>> = OnceLock::new();

const DEFAULT_GENERATION_MAX_TOKENS: i32 = 8_192;

fn cancel_flags() -> &'static Mutex<HashMap<JobId, Arc<AtomicBool>>> {
    CANCEL_FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn register_job() -> (JobId, Arc<AtomicBool>) {
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
    let mut generated_tokens_count: i32 = 0;

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

                let keep = append_only_prefix_len(cached_tokens, &prompt_tokens);

                if keep == 0 {
                    ctx.clear_kv_cache();
                    cached_tokens.clear();
                }

                let mut token_offset = keep;
                let mut logits_index: i32 = 0;
                while token_offset < prompt_tokens.len() {
                    check_cancelled(&cancel_flag)?;
                    let end = (token_offset + n_batch).min(prompt_tokens.len());
                    let chunk = &prompt_tokens[token_offset..end];
                    let mut batch = LlamaBatch::new(chunk.len(), 1);
                    for (idx, token) in chunk.iter().enumerate() {
                        let pos = (token_offset + idx) as i32;
                        let logits = token_offset + idx + 1 == prompt_tokens.len();
                        batch
                            .add(*token, pos, &[0], logits)
                            .map_err(|err| Error::Llama {
                                op: "Failed to add prompt token",
                                message: err.to_string(),
                            })?;
                    }

                    if let Err(err) = ctx.decode(&mut batch) {
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

                let mut sampler = build_sampler(ctx.model, &sampler_request)?;
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
                    Some(cached_tokens),
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

            ctx.clear_kv_cache();
            cached_tokens.clear();
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
            context.invalidate_cache();
            Err(Error::Panicked)
        }
    };
    result?;

    let summary = GenerationSummary {
        job_id,
        prompt_tokens: Some(prompt_tokens_count),
        generated_tokens: Some(generated_tokens_count),
        total_time_ms: Some(start.elapsed().as_millis() as i64),
    };

    sink.add(GenerationEvent::Done {
        summary: summary.clone(),
    });

    Ok(summary)
}

fn append_only_prefix_len(cached: &[LlamaToken], prompt: &[LlamaToken]) -> usize {
    if !cached.is_empty() && cached.len() < prompt.len() && prompt.starts_with(cached) {
        cached.len()
    } else {
        0
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
    use super::{StreamDecoder, append_only_prefix_len};
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
    fn only_strict_extensions_reuse_cache() {
        assert_eq!(append_only_prefix_len(&[], &tokens(&[1])), 0);
        assert_eq!(
            append_only_prefix_len(&tokens(&[1, 2]), &tokens(&[1, 2])),
            0
        );
        assert_eq!(
            append_only_prefix_len(&tokens(&[1, 2, 3]), &tokens(&[1, 2])),
            0
        );
        assert_eq!(
            append_only_prefix_len(&tokens(&[1, 2]), &tokens(&[1, 3, 4])),
            0
        );
        assert_eq!(
            append_only_prefix_len(&tokens(&[1, 2]), &tokens(&[1, 2, 3])),
            2
        );
    }
}
