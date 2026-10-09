#![cfg(test)]

use std::cell::Cell;
use std::rc::Rc;
use std::sync::Arc;
use std::thread;

use ente_ensu::llm::{self, ChatMessage, ChatRequest, Context, ContextParams, GenerationEvent};
use ente_image::image_compression::{EncodedImageFormat, encode_rgb};

fn init_test_backend() {
    if let Ok(directory) = std::env::var("ENSU_TEST_BACKEND_DIR") {
        llm::init_backend_from_directory(&directory).unwrap();
    }
}

fn model() -> llm::ModelRef {
    init_test_backend();
    llm::Model::load(llm::ModelLoadParams {
        model_path: std::env::var("ENSU_TEST_MODEL").unwrap(),
        n_gpu_layers: Some(99),
        use_mmap: None,
        use_mlock: None,
    })
    .unwrap()
}

fn context() -> llm::ContextRef {
    Context::new(
        &model(),
        ContextParams {
            context_size: Some(512),
            n_threads: Some(4),
            n_batch: Some(256),
        },
    )
    .unwrap()
}

fn request() -> ChatRequest {
    ChatRequest {
        messages: vec![ChatMessage {
            role: "user".to_owned(),
            content: "Count from one to five.".to_owned(),
        }],
        temperature: Some(0.0),
        max_tokens: Some(16),
        ..Default::default()
    }
}

#[test]
fn public_context_is_send_and_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<Context>();
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL"]
fn callbacks_stay_on_caller_and_accept_non_send_state() {
    let context = context();
    let caller = thread::current().id();
    let count = Rc::new(Cell::new(0));
    let mut done = false;
    context
        .generate_chat_stream(request(), &mut |event| {
            assert_eq!(thread::current().id(), caller);
            assert_eq!(context.context_size(), 512);
            count.set(count.get() + 1);
            if let GenerationEvent::Done { .. } = event {
                done = true;
                assert!(context.measure_text_chat_prompt(&request()).unwrap() > 0);
            }
        })
        .unwrap();
    assert!(done && count.get() > 2);
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL"]
fn callback_panic_returns_an_error_and_context_recovers() {
    let context = context();
    let result = context.generate_chat_stream(request(), &mut |event| {
        if let GenerationEvent::Text { text, .. } = event
            && !text.is_empty()
        {
            panic!("callback failure");
        }
    });
    assert!(matches!(result, Err(llm::Error::Panicked)));
    let mut output = String::new();
    context
        .generate_chat_stream(request(), &mut |event| {
            if let GenerationEvent::Text { text, .. } = event {
                output.push_str(&text);
            }
        })
        .unwrap();
    assert!(!output.is_empty());
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL"]
fn cancellation_is_acknowledged_before_another_text_event() {
    let context = context();
    for cancel_immediately in [true, false] {
        let mut cancelled = false;
        let mut done = false;
        let result = context.generate_chat_stream(request(), &mut |event| match event {
            GenerationEvent::Text { job_id, text, .. } => {
                assert!(!cancelled);
                if cancel_immediately || !text.is_empty() {
                    llm::cancel(job_id);
                    cancelled = true;
                }
            }
            GenerationEvent::Done { .. } => done = true,
        });
        assert!(cancelled && !done);
        assert!(matches!(result, Err(llm::Error::Cancelled)));
    }
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL"]
fn concurrent_generations_preserve_output_and_can_drop_caller_model() {
    let owner = model();
    let context = Context::new(
        &owner,
        ContextParams {
            context_size: Some(512),
            n_threads: Some(4),
            n_batch: Some(256),
        },
    )
    .unwrap();
    drop(owner);
    let mut runs = Vec::new();
    for _ in 0..4 {
        let context = context.clone();
        runs.push(thread::spawn(move || {
            let mut output = String::new();
            context
                .generate_chat_stream(request(), &mut |event| {
                    if let GenerationEvent::Text { text, .. } = event {
                        output.push_str(&text);
                    }
                })
                .unwrap();
            output
        }));
    }
    let outputs: Vec<_> = runs.into_iter().map(|run| run.join().unwrap()).collect();
    assert!(!outputs[0].is_empty());
    assert!(outputs.windows(2).all(|pair| pair[0] == pair[1]));
}

#[test]
#[ignore = "requires ENSU_TEST_EMBED_MODEL"]
fn concurrent_embeddings_match_serial_results() {
    init_test_backend();
    let model = llm::Model::load(llm::ModelLoadParams {
        model_path: std::env::var("ENSU_TEST_EMBED_MODEL").unwrap(),
        n_gpu_layers: Some(99),
        use_mmap: None,
        use_mlock: None,
    })
    .unwrap();
    let context = Context::new_knowledge_embedding(&model, Some(4)).unwrap();
    drop(model);
    let expected = Arc::new(context.embed("How do volcanoes form?").unwrap());
    assert_eq!(expected.len(), 512);
    let mut runs = Vec::new();
    for _ in 0..4 {
        let context = context.clone();
        let expected = expected.clone();
        runs.push(thread::spawn(move || {
            for _ in 0..3 {
                let actual = context.embed("How do volcanoes form?").unwrap();
                for (left, right) in actual.iter().zip(expected.iter()) {
                    assert!((left - right).abs() < 1e-5);
                }
            }
        }));
    }
    for run in runs {
        run.join().unwrap();
    }
}

fn collect(context: &llm::ContextRef, request: ChatRequest) -> (String, llm::GenerationSummary) {
    let mut output = String::new();
    let summary = context
        .generate_chat_stream(request, &mut |event| {
            if let GenerationEvent::Text { text, .. } = event {
                output.push_str(&text);
            }
        })
        .unwrap();
    assert!(!output.is_empty());
    for thinking_marker in ["<think>", "<|think|>", "<|channel>thought"] {
        assert!(
            !output.contains(thinking_marker),
            "Unexpected reasoning: {output}"
        );
    }
    (output, summary)
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL set to this device's RAM-tier default"]
fn default_model_counts_truncates_unicode_and_recovers_from_context_limits() {
    let context = context();
    let mut chat = request();
    chat.messages[0].content = "Reply with a short greeting: नमस्ते, 你好, hello 🐈.".to_owned();
    let measured = context.measure_text_chat_prompt(&chat).unwrap();
    let (_, summary) = collect(&context, chat.clone());
    assert_eq!(summary.prompt_tokens.unwrap() as usize, measured);

    chat.messages[0].content = "नमस्ते 🐈 你好 ".repeat(1_000);
    assert!(matches!(
        context.generate_chat_stream(chat.clone(), &mut |_| {}),
        Err(llm::Error::PromptTooLong { .. })
    ));
    let truncated = context
        .truncate_text_chat_messages(chat.messages.clone(), 128)
        .unwrap();
    assert!(chat.messages[0].content.starts_with(&truncated[0].content));
    chat.messages = truncated;
    assert!(context.measure_text_chat_prompt(&chat).unwrap() <= 128);
    collect(&context, chat);
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL set to this device's RAM-tier default"]
fn default_model_reuses_multi_turn_cache_and_reloads() {
    let owner = model();
    let params = ContextParams {
        context_size: Some(512),
        n_threads: Some(4),
        n_batch: Some(256),
    };
    let warm = Context::new(&owner, params.clone()).unwrap();
    let first = request();
    let (answer, _) = collect(&warm, first.clone());
    let mut followup = first;
    followup.messages.push(ChatMessage {
        role: "assistant".to_owned(),
        content: answer,
    });
    followup.messages.push(ChatMessage {
        role: "user".to_owned(),
        content: "What comes next?".to_owned(),
    });
    let (cached, _) = collect(&warm, followup.clone());
    drop(warm);
    let fresh = Context::new(&owner, params).unwrap();
    let (uncached, _) = collect(&fresh, followup);
    assert_eq!(cached, uncached);
    drop(fresh);
    drop(owner);
    collect(&context(), request());
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL and ENSU_TEST_MMPROJ for this device's RAM-tier default"]
fn default_model_handles_wide_and_tall_images_and_projector_reloads() {
    let owner = model();
    let context = Context::new(
        &owner,
        ContextParams {
            context_size: Some(4096),
            n_threads: Some(4),
            n_batch: Some(256),
        },
    )
    .unwrap();
    let mmproj = std::env::var("ENSU_TEST_MMPROJ").unwrap();
    let directory = tempfile::tempdir().unwrap();
    for (name, width, height) in [("wide.png", 1024, 96), ("tall.png", 96, 1024)] {
        let path = directory.path().join(name);
        let rgb = [255, 0, 0].repeat((width * height) as usize);
        let bytes = encode_rgb(&rgb, width, height, EncodedImageFormat::Png).unwrap();
        std::fs::write(&path, bytes).unwrap();
        context.prewarm_multimodal(mmproj.clone(), None).unwrap();
        let mut chat = request();
        chat.messages[0].content = "Describe the colour in this image.".to_owned();
        chat.image_paths = Some(vec![path.to_str().unwrap().to_owned()]);
        chat.mmproj_path = Some(mmproj.clone());
        collect(&context, chat.clone());
        context.release_multimodal();
        chat.messages[0].content.push_str("\n<__media__>");
        collect(&context, chat);
        collect(&context, request());
    }
}
