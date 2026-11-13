use ente_ensu::llm::{
    ChatMessage, ChatRequest, Context, ContextParams, ContextRef, Error, GenerationEvent, Model,
    ModelLoadParams, ModelRef, cancel,
};

fn context(model: &ModelRef) -> Result<ContextRef, Error> {
    Context::new(
        model,
        ContextParams {
            context_size: Some(2048),
            n_threads: Some(4),
            n_threads_generation: None,
            n_batch: Some(128),
        },
    )
}

fn message(role: &str, content: &str) -> ChatMessage {
    ChatMessage {
        role: role.into(),
        content: content.into(),
    }
}

fn request(messages: Vec<ChatMessage>) -> ChatRequest {
    ChatRequest {
        messages,
        temperature: Some(0.0),
        max_tokens: Some(16),
        ..Default::default()
    }
}

fn generate(ctx: &Context, request: ChatRequest) -> Result<(String, i32), Error> {
    let mut text = String::new();
    let mut reused = None;
    ctx.generate_chat_stream(request, &mut |event| match event {
        GenerationEvent::PromptProgress {
            processed_tokens, ..
        } => {
            reused.get_or_insert(processed_tokens);
        }
        GenerationEvent::Text { text: piece, .. } => text.push_str(&piece),
        _ => {}
    })?;
    Ok((text, reused.unwrap_or(0)))
}

fn check_against_fresh(
    model: &ModelRef,
    cached: &Context,
    request: ChatRequest,
) -> Result<String, Error> {
    let (actual, reused) = generate(cached, request.clone())?;
    let fresh = context(model)?;
    let (expected, cold_reused) = generate(&fresh, request)?;
    assert!(!actual.is_empty());
    assert_eq!(actual, expected, "cache reuse must preserve greedy output");
    assert_eq!(cold_reused, 0);
    assert!(reused > 0);
    Ok(actual)
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL pointing to a local attention GGUF model"]
fn cached_generation_matches_fresh_after_retry_edit_branch_and_cancellation() -> Result<(), Error> {
    let model = Model::load(ModelLoadParams {
        model_path: std::env::var("ENSU_TEST_MODEL").unwrap(),
        n_gpu_layers: Some(0),
        use_mmap: Some(true),
        use_mlock: Some(false),
    })?;
    let cached = context(&model)?;
    let early = vec![
        message(
            "system",
            "Answer briefly and follow the user's instructions.",
        ),
        message("user", "What is 2 + 2? Reply with just the number."),
    ];
    let mut history = early.clone();
    history.push(message("assistant", "4"));
    let facts = "The garden has green trees and red flowers. ".repeat(70);
    history.push(message(
        "user",
        &format!("{facts}\nWhat is 6 + 6? Reply with just the number."),
    ));
    let original = request(history.clone());
    assert!(cached.measure_text_chat_prompt(&original)? > 512);
    let (_, cold_reused) = generate(&cached, original.clone())?;
    assert_eq!(cold_reused, 0);

    check_against_fresh(&model, &cached, original.clone())?;
    let last = history.len() - 1;
    history[last].content = format!("{facts}\nWhat is 7 + 7? Reply with just the number.");
    let answer = check_against_fresh(&model, &cached, request(history.clone()))?;
    history.push(message("assistant", &answer));
    history.push(message(
        "user",
        "What is 8 + 8? Reply with just the number.",
    ));
    check_against_fresh(&model, &cached, request(history))?;
    check_against_fresh(&model, &cached, request(early))?;

    let mut request = original;
    request.messages.last_mut().unwrap().content =
        format!("{facts}\nCount from one to twenty, spelling out each number.");
    for during_prompt in [true, false] {
        let interrupted = context(&model)?;
        let mut pieces = 0;
        let result = interrupted.generate_chat_stream(request.clone(), &mut |event| match event {
            GenerationEvent::PromptProgress {
                job_id,
                processed_tokens,
                total_tokens,
            } if during_prompt && processed_tokens > 0 && processed_tokens < total_tokens => {
                cancel(job_id)
            }
            GenerationEvent::Text { job_id, text, .. } if !during_prompt && !text.is_empty() => {
                pieces += 1;
                if pieces == 2 {
                    cancel(job_id);
                }
            }
            _ => {}
        });
        assert!(matches!(result, Err(Error::Cancelled)));
        check_against_fresh(&model, &interrupted, request.clone())?;
    }
    Ok(())
}
