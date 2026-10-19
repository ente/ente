use super::*;
use crate::notes::{NotePassageLocator, NoteSourceReference};
use crate::retrieval::{GroundedSource, PassageLocator};

fn hit(text: &str, id: &str) -> GroundedExcerpt {
    GroundedExcerpt {
        locator: PassageLocator::LocalNote(NotePassageLocator {
            collection_id: "123e4567-e89b-12d3-a456-426614174000".into(),
            document_id: id.into(),
            indexed_revision: "a".repeat(64),
            shard_sha256: "b".repeat(64),
            chunk_index: 0,
        }),
        source: GroundedSource::LocalNote {
            reference: NoteSourceReference {
                collection_id: "123e4567-e89b-12d3-a456-426614174000".into(),
                collection_label: None,
                document_id: id.into(),
                indexed_revision: "a".repeat(64),
                title: id.into(),
                section: None,
            },
        },
        score: 0.9,
        text: text.into(),
    }
}
fn measure(messages: &[ChatMessage]) -> Result<usize, PrepareError> {
    Ok(messages.iter().map(|m| m.content.chars().count() + 8).sum())
}

fn pack_hit(text: &str, title: &str, row: u64) -> GroundedExcerpt {
    GroundedExcerpt {
        locator: PassageLocator::EnsuPack {
            dataset_id: "simplewiki".into(),
            revision_sha256: "a".repeat(64),
            row,
        },
        source: GroundedSource::EnsuPack {
            citation: retrieval::SourceCitation {
                dataset_id: "simplewiki".into(),
                dataset_label: "Wikipedia".into(),
                credit: "Wikipedia".into(),
                title: title.into(),
                source_url: format!("https://example.com/{title}"),
                license_label: "CC BY-SA 4.0".into(),
                license_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
            },
        },
        score: 0.9,
        text: text.into(),
    }
}

fn followup_history(prior: &[GroundedExcerpt]) -> (Vec<Message>, Vec<AnswerEvidence>) {
    let old = retrieval::build_grounded_prompt_context(prior, MAX_GROUNDING_BYTES)
        .unwrap()
        .unwrap();
    let mut history: Vec<_> = (1..=3)
        .map(|i| Message {
            uuid: Uuid::from_u128(i),
            session_uuid: Uuid::from_u128(100),
            parent_message_uuid: (i > 1).then(|| Uuid::from_u128(i - 1)),
            sender: if i == 2 {
                Sender::Other
            } else {
                Sender::SelfUser
            },
            text: "Explain the sources.".into(),
            attachments: vec![],
            created_at: i as i64,
        })
        .collect();
    history[1].text =
        retrieval::finalize_grounded_assistant_text("See the cited sources.", &old.sources)
            .unwrap();
    let evidence = vec![AnswerEvidence {
        assistant_message_uuid: history[1].uuid,
        prefix_fingerprint: fingerprint(&history[..2]),
        passages: old.included_passages,
    }];
    (history, evidence)
}

fn fit_followup(
    prior: &[GroundedExcerpt],
    searched: Vec<GroundedExcerpt>,
    query: &str,
    input_budget: usize,
) -> GroundedPromptContext {
    let (mut history, evidence) = followup_history(prior);
    history.last_mut().unwrap().text = query.into();
    let reloaded = direct_followup_references(&history, &evidence, query, &searched)
        .into_iter()
        .map(|reference| {
            let hit = prior
                .iter()
                .find(|hit| hit.locator == reference.locator)
                .unwrap();
            ReferencedPassage {
                passages: reference.verified_spans(&hit.text).unwrap(),
                source: hit.source.clone(),
                reference,
            }
        })
        .collect();
    let candidates = GroundingCandidates::new(reloaded, searched, MAX_GROUNDING_BYTES).unwrap();
    let context = fit_grounding(
        &candidates.select_sources(Some(query)).unwrap(),
        "System",
        query,
        input_budget,
        measure,
    )
    .unwrap()
    .context
    .unwrap();
    assert!(context.text.len() <= MAX_GROUNDING_BYTES);
    assert!(
        measure(&answer_messages(
            &grounded_system("System", Some(&context)),
            None,
            &[],
            query
        ))
        .unwrap()
            <= input_budget
    );
    context
}

fn notes_at_limit() -> Vec<GroundedExcerpt> {
    ["cedar", "pine", "birch", "oak", "maple"]
        .iter()
        .map(|name| hit(&format!("{name} allows 30 days."), &format!("{name}.md")))
        .collect()
}

fn assert_full_passage(context: &GroundedPromptContext, hit: &GroundedExcerpt) {
    let index = context
        .included_passages
        .iter()
        .position(|reference| reference.locator == hit.locator)
        .unwrap();
    assert_eq!(context.sources[index], hit.source);
    assert_eq!(
        context.included_passages[index]
            .verified_spans(&hit.text)
            .unwrap(),
        vec![hit.text.trim()]
    );
    assert!(context.text.contains(hit.text.trim()));
}

#[test]
fn comparisons_retain_historical_passages_under_pressure() {
    let cedar = hit("Cedar permits 30 days.", "cedar.md");
    let juniper = hit(
        &format!("{}Juniper permits 21 days.", "Juniper details. ".repeat(30)),
        "juniper.md",
    );
    for (query, budget) in [
        ("Compare its deadline with Juniper.", 7000),
        ("Compare Juniper's return period with my policy.", 700),
        ("Compare Cedar and Juniper.", 700),
    ] {
        let context = fit_followup(
            std::slice::from_ref(&cedar),
            vec![juniper.clone()],
            query,
            budget,
        );
        assert_full_passage(&context, &cedar);
        if budget == 7000 {
            assert_full_passage(&context, &juniper);
        }
    }
}

#[test]
fn named_questions_switch_to_fresh_sources() {
    let cedar = hit("Cedar allows 30 days.", "cedar.md");
    for (query, fresh) in [
        (
            "What is Juniper's return period?",
            hit("Juniper allows 21 days.", "juniper.md"),
        ),
        (
            "What is Cedar's current deadline?",
            hit("Cedar now requires seven days.", "cedar.md"),
        ),
    ] {
        let context = fit_followup(
            std::slice::from_ref(&cedar),
            vec![fresh.clone()],
            query,
            7000,
        );
        assert_eq!(context.sources.len(), 1);
        assert_full_passage(&context, &fresh);
    }
}

#[test]
fn named_sources_take_priority_at_source_and_byte_limits() {
    let mut notes = notes_at_limit();
    notes.rotate_left(1);
    let cedar = notes.last().unwrap().clone();
    let atlas = hit(&"Atlas allows 21 days. ".repeat(40), "atlas.md");
    for prior in [
        notes,
        vec![
            cedar.clone(),
            hit(&"Unrelated detail. ".repeat(400), "pine.md"),
        ],
    ] {
        let context = fit_followup(&prior, vec![atlas.clone()], "Compare Cedar and Atlas", 7000);
        assert_full_passage(&context, &cedar);
        assert_full_passage(&context, &atlas);
        assert!(context.sources.len() <= retrieval::MAX_NOTES_GROUNDING_HITS);
    }
}

#[test]
fn personal_questions_keep_fresh_results_at_the_historical_note_limit() {
    let ledger = hit("Holiday spending: 1200 rupees.", "ledger-2026.md");
    for query in [
        "How much did I spend on my holiday?",
        "Compare my holiday costs across years.",
    ] {
        let context = fit_followup(&notes_at_limit(), vec![ledger.clone()], query, 700);
        assert_full_passage(&context, &ledger);
    }
}

#[test]
fn temporal_phrases_are_distinct_from_source_references() {
    for (question, expected) in [
        (
            "How much did I spend on my holiday these past few months?",
            false,
        ),
        ("What did I spend on holiday in those 2 weeks?", false),
        ("This year, compare its deadline with Juniper.", true),
        ("Compare that second policy with Juniper.", true),
    ] {
        assert_eq!(
            super::super::followup::refers_back(question),
            expected,
            "{question}"
        );
    }
}

#[test]
fn temporal_questions_keep_fresh_results_under_source_and_byte_limits() {
    let ledger = hit("Holiday spending: 1200 rupees.", "ledger-2026.md");
    for (prior, fresh, budget) in [
        (notes_at_limit(), ledger.clone(), 7000),
        (
            vec![hit(&"Cedar allows 30 days. ".repeat(320), "cedar.md")],
            ledger.clone(),
            7000,
        ),
        (
            vec![
                pack_hit("Mars is the fourth planet.", "Mars", 0),
                pack_hit("Venus is the second planet.", "Venus", 1),
            ],
            pack_hit(&ledger.text, "Ledger", 2),
            700,
        ),
    ] {
        let context = fit_followup(
            &prior,
            vec![fresh.clone()],
            "How much did I spend on my holiday this year?",
            budget,
        );
        assert_full_passage(&context, &fresh);
    }
}

#[test]
fn named_pack_comparisons_retain_articles_cited_through_multiple_sections() {
    let prior: Vec<_> = [
        ("History", "Mars has been observed since antiquity."),
        ("Geography", "Mars has two polar ice caps."),
    ]
    .into_iter()
    .enumerate()
    .map(|(row, (section, text))| {
        let mut hit = pack_hit(text, &format!("Mars — {section}"), row as u64);
        if let GroundedSource::EnsuPack { citation } = &mut hit.source {
            citation.source_url = format!("https://simple.wikipedia.org/wiki/Mars#{section}");
        }
        hit
    })
    .collect();
    let jupiter = pack_hit("Jupiter is the fifth planet.", "Jupiter", 2);
    let context = fit_followup(
        &prior,
        vec![jupiter.clone()],
        "Compare Mars and Jupiter",
        700,
    );
    assert_full_passage(&context, &prior[0]);
    assert_full_passage(&context, &jupiter);
    assert_eq!(context.sources.len(), 2);

    let context = fit_followup(&prior, vec![], "Tell me more about Mars", 7000);
    assert_eq!(
        context.sources,
        prior
            .iter()
            .map(|hit| hit.source.clone())
            .collect::<Vec<_>>()
    );
}

#[test]
fn unnamed_questions_keep_available_historical_passages() {
    let notes = notes_at_limit();
    let biology = hit(
        "Photosynthesis converts light into energy.",
        "biology-chapter-seven.md",
    );
    let old = retrieval::build_grounded_prompt_context(&notes, MAX_GROUNDING_BYTES)
        .unwrap()
        .unwrap();
    let context = fit_followup(
        &notes,
        vec![biology.clone()],
        "How does photosynthesis work?",
        7000,
    );
    assert_full_passage(&context, &biology);
    assert!(
        context
            .included_passages
            .contains(&old.included_passages[0])
    );
    assert_eq!(context.sources.len(), retrieval::MAX_NOTES_GROUNDING_HITS);

    let context = fit_followup(&notes, vec![], "And the deadline?", 7000);
    assert_eq!(context.included_passages, old.included_passages);
}

#[test]
fn followups_keep_new_chunks_of_retained_sources_at_hit_limits() {
    let notes: Vec<_> = (0..3)
        .map(|index| {
            let mut note = hit(&format!("Cedar background section {index}."), "cedar.md");
            if let PassageLocator::LocalNote(locator) = &mut note.locator {
                locator.chunk_index = index;
            }
            note
        })
        .chain([
            hit("Pine background.", "pine.md"),
            hit("Birch background.", "birch.md"),
        ])
        .collect();
    let mut fresh = notes[0].clone();
    if let PassageLocator::LocalNote(locator) = &mut fresh.locator {
        locator.chunk_index = 3;
    }
    fresh.text = "Cedar warranty duration: 24 months.".into();
    let context = fit_followup(
        &notes,
        vec![notes[0].clone(), fresh.clone()],
        "And in Cedar, how long is its warranty?",
        700,
    );
    assert_full_passage(&context, &fresh);
    assert_full_passage(&context, &notes[0]);
    assert!(context.included_passages.len() <= retrieval::MAX_NOTES_GROUNDING_HITS);

    let prior = [
        pack_hit("Mars is the fourth planet.", "Mars", 0),
        pack_hit("Venus is the second planet.", "Venus", 1),
    ];
    let fresh = [
        pack_hit("Its radius is 3389.5 kilometers.", "Mars", 2),
        pack_hit("Its radius is 6051.8 kilometers.", "Venus", 3),
    ];
    let context = fit_followup(&prior, fresh.to_vec(), "Which of them is larger?", 700);
    for hit in &fresh {
        assert_full_passage(&context, hit);
    }
}

#[test]
fn fresh_followup_results_survive_byte_and_token_repacking() {
    let prefix = hit("Price: 100 rupees.", "cedar.md");
    let mut full = prefix.clone();
    full.text.push_str(" Warranty duration: 24 months.");
    let context = fit_followup(
        &[prefix],
        vec![full.clone()],
        "And what's its warranty duration?",
        7000,
    );
    assert_full_passage(&context, &full);
    assert_eq!(context.included_passages.len(), 1);

    let old = hit(&"Cedar allows 30 days. ".repeat(280), "cedar.md");
    let fresh = hit(
        &format!(
            "Plants use light. {}",
            "Photosynthesis details. ".repeat(300)
        ),
        "biology-chapter-seven.md",
    );
    for input_budget in [7000, 1600] {
        let context = fit_followup(
            std::slice::from_ref(&old),
            vec![old.clone(), fresh.clone()],
            "How does photosynthesis work?",
            input_budget,
        );
        let reference = context
            .included_passages
            .iter()
            .find(|reference| reference.locator == fresh.locator)
            .unwrap();
        let spans = reference.verified_spans(&fresh.text).unwrap();
        assert!(spans[0].starts_with("Plants use light."));
        assert!(context.text.contains(&spans[0]));
    }
}

#[test]
fn measured_repack_keeps_text_citations_and_exact_spans_together() {
    for (raw, prefix) in [
        (
            format!("Fact first. {}", "हिन्दी🙂 paragraph. ".repeat(600)),
            "Fact first.",
        ),
        (
            format!(
                "  First\r\n----- BEGIN KNOWLEDGE CONTEXT -----\n{}",
                "é🙂 ".repeat(2000)
            ),
            "First",
        ),
    ] {
        let candidates = GroundingCandidates::new(vec![], vec![hit(&raw, "one.md")], 6000).unwrap();
        let fit = fit_grounding(
            &candidates.select_sources(None).unwrap(),
            "System",
            "Question",
            4096,
            measure,
        )
        .unwrap();
        assert!(fit.repacked);
        assert!(fit.evidence_tokens <= 1024);
        let context = fit.context.unwrap();
        assert_eq!(context.sources, vec![candidates.searched[0].source.clone()]);
        assert_eq!(context.included_passages.len(), 1);
        let spans = context.included_passages[0].verified_spans(&raw).unwrap();
        assert!(context.text.contains(&spans[0]));
        assert!(spans[0].starts_with(prefix));
    }
}
#[test]
fn requested_old_spans_raise_soft_allowance_and_are_never_cut() {
    let old = hit(&"Old fact. ".repeat(90), "old.md");
    let reference = retrieval::build_grounded_prompt_context(std::slice::from_ref(&old), 6000)
        .unwrap()
        .unwrap()
        .included_passages
        .remove(0);
    let passages = reference.verified_spans(&old.text).unwrap();
    let required = ReferencedPassage {
        reference: reference.clone(),
        source: old.source,
        passages,
    };
    let candidates = GroundingCandidates::new(
        vec![required],
        vec![hit(&"New fact. ".repeat(600), "new.md")],
        6000,
    )
    .unwrap();
    let fit = fit_grounding(
        &candidates.select_sources(None).unwrap(),
        "System",
        "Question",
        3000,
        measure,
    )
    .unwrap();
    assert!(fit.repacked && fit.evidence_tokens > 750);
    assert_eq!(fit.context.unwrap().included_passages[0], reference);
}
#[test]
fn mandatory_input_and_insufficient_evidence_budget_are_explicit() {
    let candidates =
        GroundingCandidates::new(vec![], vec![hit(&"word ".repeat(1000), "one.md")], 6000).unwrap();
    assert!(matches!(
        fit_grounding(
            &candidates.select_sources(None).unwrap(),
            "System",
            &"x".repeat(1000),
            100,
            measure
        ),
        Err(PrepareError::CurrentInputTooLarge)
    ));
    assert!(
        fit_grounding(
            &candidates.select_sources(None).unwrap(),
            "System",
            "Question",
            60,
            measure
        )
        .unwrap()
        .context
        .is_none()
    );
}
#[test]
fn candidate_limits_are_enforced() {
    let hit = hit("text", "one.md");
    assert!(GroundingCandidates::new(vec![], vec![hit.clone(); 8], 6000).is_err());
    let mut candidates = GroundingCandidates::new(vec![], vec![hit], 6000).unwrap();
    candidates.searched[0].text = "x".repeat(6001);
    assert!(candidates.validate().is_err());
}
#[test]
fn named_comparison_keeps_both_complete_passages_before_optional_hits() {
    let cedar = hit(
        &format!("{}Cedar permits 30 days.", "Cedar details. ".repeat(45)),
        "cedar-policy.md",
    );
    let juniper = hit(
        &format!("{}Juniper permits 21 days.", "Juniper details. ".repeat(25)),
        "juniper-policy.md",
    );
    let candidates = GroundingCandidates::new(
        vec![],
        vec![
            cedar.clone(),
            juniper.clone(),
            hit(&"Unrelated details. ".repeat(200), "glacier-policy.md"),
        ],
        6000,
    )
    .unwrap();
    let plan = candidates
        .select_sources(Some("Is the Juniper period longer than Cedar?"))
        .unwrap();
    let fit = fit_grounding(&plan, "System", "Compare Cedar and Juniper.", 2500, measure).unwrap();
    assert!(fit.repacked);
    let context = fit.context.unwrap();
    for hit in [&cedar, &juniper] {
        assert_full_passage(&context, hit);
    }
}

fn prior_history() -> Vec<Message> {
    vec![Message {
        uuid: Uuid::from_u128(1),
        session_uuid: Uuid::from_u128(100),
        parent_message_uuid: None,
        sender: Sender::SelfUser,
        text: "My reservation code is ZX-82Q.".into(),
        attachments: vec![],
        created_at: 1,
    }]
}

#[test]
fn explicit_history_displaces_optional_search_without_losing_original_text() {
    let history = prior_history();
    let query = "What was the reservation code I gave earlier?";
    let required = requested_history(&history, query, || Ok(()))
        .unwrap()
        .unwrap();
    assert_eq!(required.excerpts[0].text, history[0].text);
    let current = required.prepend_required(query);
    let budget = measure(&answer_messages("System", None, &[], &current)).unwrap() + 1;
    let candidates = GroundingCandidates::new(
        vec![],
        vec![hit(&"Optional search. ".repeat(100), "extra.md")],
        6000,
    )
    .unwrap();
    let fit = fit_grounding_with_history(
        &candidates.select_sources(None).unwrap(),
        Some(&required),
        "System",
        query,
        budget,
        measure,
    )
    .unwrap();
    assert!(fit.context.is_none());
    assert_eq!(fit.evidence_tokens, 0);
    assert!(
        fit_grounding_with_history(
            &candidates.select_sources(None).unwrap(),
            Some(&required),
            "System",
            query,
            budget - 2,
            measure
        )
        .is_ok_and(|fit| !fit.history_included)
    );
}

#[test]
fn source_system_and_required_history_are_measured_in_final_roles() {
    let query = "What was the reservation code I gave earlier, and what is the new rule?";
    let history = requested_history(&prior_history(), query, || Ok(()))
        .unwrap()
        .unwrap();
    let c = GroundingCandidates::new(
        vec![],
        vec![hit("The new rule is 21 days.", "current.md")],
        6000,
    )
    .unwrap();
    let fitted = fit_grounding_with_history(
        &c.select_sources(None).unwrap(),
        Some(&history),
        "System",
        query,
        4096,
        |messages| {
            if messages[0].content.contains("BEGIN KNOWLEDGE CONTEXT") {
                assert_eq!(messages[0].role, "system");
                assert!(messages.last().unwrap().content.contains("ZX-82Q"));
            }
            assert!(
                !messages
                    .last()
                    .unwrap()
                    .content
                    .contains("BEGIN KNOWLEDGE CONTEXT")
            );
            measure(messages)
        },
    )
    .unwrap();
    assert!(grounded_system("System", fitted.context.as_ref()).contains("The new rule"));
    let final_text = history.prepend_required(query);
    assert!(final_text.contains("ZX-82Q"));
    assert!(final_text.ends_with(query));
}

#[test]
fn followups_use_last_available_evidence_until_its_history_changes() {
    let (mut history, evidence) = followup_history(&[hit("Archived policy fact.", "cedar.md")]);
    for i in 4..=5 {
        history.push(Message {
            uuid: Uuid::from_u128(i),
            parent_message_uuid: Some(Uuid::from_u128(i - 1)),
            sender: if i == 4 {
                Sender::Other
            } else {
                Sender::SelfUser
            },
            ..history[2].clone()
        });
    }
    assert_eq!(
        direct_followup_references(&history, &evidence, "And the deadline?", &[]),
        evidence[0].passages
    );
    history[0].text = "Edited history".into();
    assert!(direct_followup_references(&history, &evidence, "And the deadline?", &[]).is_empty());
}
