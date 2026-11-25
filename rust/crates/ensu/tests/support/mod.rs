use std::time::{Duration, Instant};

use ente_ensu::conversation::{
    ConversationState, Effects, GroundingCache, GroundingCandidates, PrepareError, Reply, TurnInput,
};
use ente_ensu::db::chat::{ConversationSnapshot, FinishedReply};
use ente_ensu::db::{ChatDb, SqliteBackend};
use ente_ensu::llm::{
    self, ChatMessage, ChatRequest, Context, ContextParams, ContextRef, GenerationEvent,
    GenerationSummary, ToolRequest,
};

pub fn model_context(ctx_size: i32) -> ContextRef {
    if let Ok(directory) = std::env::var("ENSU_TEST_BACKEND_DIR") {
        llm::init_backend_from_directory(&directory).unwrap();
    }
    let model = llm::Model::load(llm::ModelLoadParams {
        model_path: std::env::var("ENSU_TEST_MODEL").unwrap(),
        n_gpu_layers: Some(99),
        use_mmap: None,
        use_mlock: None,
    })
    .unwrap();
    Context::new(
        &model,
        ContextParams {
            context_size: Some(ctx_size),
            n_threads: Some(4),
            n_threads_generation: None,
            n_batch: Some(256),
        },
    )
    .unwrap()
}

struct ModelEffects<'a>(&'a Context);

impl Effects for ModelEffects<'_> {
    fn supports_tools(&self) -> bool {
        self.0.supports_tools()
    }

    fn supports_partial_prompt_reuse(&self) -> bool {
        self.0.supports_partial_prompt_reuse()
    }

    fn check_current(&mut self) -> Result<(), PrepareError> {
        Ok(())
    }

    fn measure(
        &mut self,
        messages: &[ChatMessage],
        tools: Option<&ToolRequest>,
    ) -> Result<usize, PrepareError> {
        self.0
            .measure_text_chat_prompt(&ChatRequest {
                messages: messages.to_vec(),
                tools: tools.cloned(),
                ..Default::default()
            })
            .map_err(|error| PrepareError::Backend(error.to_string()))
    }

    fn summarize(
        &mut self,
        _: Vec<ChatMessage>,
        _: usize,
    ) -> Result<(String, llm::FinishReason), PrepareError> {
        panic!("measurement history must fit without summarization")
    }

    fn checkpoint(&mut self, _: &ConversationState) -> Result<(), PrepareError> {
        panic!("measurement history must fit without checkpoints")
    }
}

pub fn system_prompt() -> String {
    let defaults = ente_ensu::config::defaults();
    defaults
        .mobile_system_prompt_body
        .replace(&defaults.system_prompt_date_placeholder, "2026-11-12")
}

pub struct TurnRun {
    pub summary: GenerationSummary,
    pub reply: String,
    pub finished: FinishedReply,
    pub events: Vec<(Duration, GenerationEvent)>,
}

pub fn run_turn(
    db: &ChatDb<SqliteBackend>,
    context: &Context,
    cache: &GroundingCache,
    snapshot: &ConversationSnapshot,
    system: &str,
    output: usize,
    tune: impl FnOnce(&mut ChatRequest),
) -> TurnRun {
    let user = snapshot.messages().last().unwrap();
    let mut effects = ModelEffects(context);
    let mut prepared = cache
        .prepare_turn(
            TurnInput {
                session: snapshot.session_uuid(),
                messages: snapshot.messages().to_vec(),
                expected_user_text: user.text.clone(),
                system: system.to_owned(),
                current: user.text.clone(),
                history_query: None,
                context: context.context_size() as usize,
                output: Some(output),
                state: snapshot.state().cloned(),
                candidates: GroundingCandidates {
                    referenced: Vec::new(),
                    searched: Vec::new(),
                    max_utf8_bytes: 0,
                },
                tools: db.turn_tools(snapshot, &user.text).unwrap(),
            },
            &mut effects,
        )
        .unwrap();
    let mut result = prepared.preparation.run(&mut effects).unwrap();
    effects.check_current().unwrap();
    let mut request = ChatRequest {
        messages: result.messages.clone(),
        tools: prepared.tools,
        temperature: Some(0.0),
        max_tokens: Some(prepared.budget.output.try_into().unwrap()),
        ..Default::default()
    };
    tune(&mut request);
    let exchange = request
        .tools
        .clone()
        .map(|tools| db.tool_exchange(snapshot, tools));
    let mut events = Vec::new();
    let mut reply = String::new();
    let started = Instant::now();
    let summary = context
        .generate_with_tools(request, exchange.as_ref(), &mut |event| {
            let elapsed = started.elapsed();
            if let GenerationEvent::Text { text, .. } = &event {
                reply.push_str(text);
            }
            events.push((elapsed, event));
        })
        .unwrap_or_else(|error| panic!("generation failed for {:?}: {error}", user.text));
    let finished = cache
        .finish(
            db,
            snapshot,
            &mut result,
            Reply {
                text: &reply,
                sources: &[],
                passages: vec![],
                attachments: vec![],
                tools: exchange.as_ref(),
            },
        )
        .unwrap()
        .reply;
    TurnRun {
        summary,
        reply,
        finished,
        events,
    }
}
