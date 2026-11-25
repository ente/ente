use crate::tools::turn as tool_turn;
use std::sync::{Arc, Mutex};

use crate::db::{self, AttachmentMeta, Backend, ChatDb, chat::ConversationSnapshot};
use crate::llm::{self, EventSink, GenerationEvent, GenerationSummary, ToolOutcome};
use crate::todo::{Todo, follow_up::FollowUp};

use super::prompt::{Answer, save_prepared_reply};
use super::*;

pub(crate) struct TurnInput {
    pub session: Uuid,
    pub messages: Vec<Message>,
    pub expected_user_text: String,
    pub system: String,
    pub current: String,
    pub history_query: Option<String>,
    pub context: usize,
    pub output: Option<usize>,
    pub state: Option<ConversationState>,
    pub candidates: GroundingCandidates,
    pub tools: TurnTools,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct TurnTools {
    pub tools: Option<ToolRequest>,
    pub history: std::collections::HashMap<Uuid, ToolTurnHistory>,
    pub current_override: Option<String>,
}

pub(crate) struct PreparedTurn {
    pub preparation: Preparation,
    pub budget: GenerationBudget,
    pub grounding: FittedGrounding,
    pub tools: Option<ToolRequest>,
}

pub(crate) fn prepare_turn(
    input: TurnInput,
    effects: &mut impl Effects,
) -> Result<PreparedTurn, PrepareError> {
    prepare_turn_with_anchor(input, None, effects)
}

pub(super) fn prepare_turn_with_anchor(
    mut input: TurnInput,
    anchor: Option<GroundingAnchor>,
    effects: &mut impl Effects,
) -> Result<PreparedTurn, PrepareError> {
    effects.check_current()?;
    validate_path(&input.messages)?;
    if input
        .messages
        .first()
        .is_some_and(|message| message.session_uuid != input.session)
    {
        return Err(Error::InvalidHistory.into());
    }
    let current = input.messages.last().ok_or(Error::InvalidHistory)?;
    if current.sender != Sender::SelfUser || current.text != input.expected_user_text {
        return Err(PrepareError::Stale);
    }
    let budget = resolve_generation_budget(input.context, input.output)?;
    let asked = input
        .tools
        .current_override
        .take()
        .unwrap_or_else(|| input.current.clone());
    let tools = match input.tools.tools.take() {
        Some(tools)
            if effects.supports_tools()
                && effects.measure(
                    &answer_messages(&input.system, None, &[], &asked),
                    Some(&tools),
                )? <= budget.input =>
        {
            input.current = asked;
            Some(tools)
        }
        _ => None,
    };
    let required = input
        .history_query
        .as_deref()
        .map(|query| {
            requested_history(&input.messages[..input.messages.len() - 1], query, || {
                effects.check_cancelled()
            })
        })
        .transpose()?
        .flatten();
    effects.check_cancelled()?;
    let grounding_plan = input.candidates.select_sources(Some(
        input.history_query.as_deref().unwrap_or(&input.current),
    ))?;
    let placement = if effects.supports_partial_prompt_reuse() {
        GroundingPlacement::CurrentTurn
    } else {
        GroundingPlacement::System
    };
    let grounding = fit_grounding_with_history(
        &grounding_plan,
        required.as_ref(),
        &input.system,
        &input.current,
        budget.input,
        placement,
        |messages| {
            effects.check_cancelled()?;
            let tokens = effects.measure(messages, tools.as_ref())?;
            effects.check_cancelled()?;
            Ok(tokens)
        },
    )?;
    effects.check_current()?;
    if let Some(required) = required.filter(|_| grounding.history_included) {
        input.current = required.prepend_required(&input.current);
        input.history_query = None;
    }
    let prompt_grounding = match (placement, grounding.context.as_ref()) {
        (GroundingPlacement::CurrentTurn, Some(context)) => {
            Some(PromptGrounding::new(context, anchor, &input.messages)?)
        }
        _ => {
            (input.system, input.current) =
                placement.apply(&input.system, &input.current, grounding.context.as_ref());
            None
        }
    };
    input.messages.pop();
    let preparation = Preparation::new(
        input.session,
        input.messages,
        input.system,
        input.current,
        budget.context,
        budget.output,
        input.state,
    )?
    .with_history_query(input.history_query)
    .with_grounding(prompt_grounding)
    .with_tools(input.tools.history, tools.clone());
    effects.check_current()?;
    Ok(PreparedTurn {
        preparation,
        budget,
        grounding,
        tools,
    })
}

pub struct TurnRequest {
    pub session: Uuid,
    pub system: String,
    pub current: String,
    pub expected_user_text: String,
    pub history_query: Option<String>,
    pub context: usize,
    pub output: Option<usize>,
    pub candidates: GroundingCandidates,
}

pub struct TurnDraft<'a, B: Backend> {
    db: &'a ChatDb<B>,
    input: TurnInput,
    todos: Vec<Todo>,
}

struct ToolSession {
    request: ToolRequest,
    follow_up: FollowUp,
}

struct TurnState {
    prepared: PreparationResult,
    outcome: Option<ToolOutcome>,
    text: String,
}

pub struct Turn {
    budget: GenerationBudget,
    grounding: FittedGrounding,
    cache: Option<Arc<GroundingCache>>,
    tools: Option<ToolSession>,
    state: Mutex<TurnState>,
}

impl<B: Backend> TurnDraft<'_, B> {
    pub fn prepare(
        self,
        cache: Option<Arc<GroundingCache>>,
        effects: &mut impl Effects,
    ) -> Result<Turn, PrepareError> {
        let mut prepared = match &cache {
            Some(cache) => cache.prepare_turn(self.input, effects)?,
            None => prepare_turn(self.input, effects)?,
        };
        let result = prepared.preparation.run(effects)?;
        effects.check_current()?;
        let tools = prepared.tools.map(|request| ToolSession {
            follow_up: FollowUp::new(self.todos, self.db.now_ms(), request.quote_source.clone()),
            request,
        });
        Ok(Turn {
            budget: prepared.budget,
            grounding: prepared.grounding,
            cache,
            tools,
            state: Mutex::new(TurnState {
                prepared: result,
                outcome: None,
                text: String::new(),
            }),
        })
    }
}

impl Turn {
    pub fn begin<'a, B: Backend>(
        db: &'a ChatDb<B>,
        snapshot: &ConversationSnapshot,
        request: TurnRequest,
    ) -> db::Result<TurnDraft<'a, B>> {
        let tools = tool_turn::turn_tools(db, snapshot, &request.expected_user_text)?;
        Ok(TurnDraft {
            db,
            input: TurnInput {
                session: request.session,
                messages: snapshot.messages().to_vec(),
                expected_user_text: request.expected_user_text,
                system: request.system,
                current: request.current,
                history_query: request.history_query,
                context: request.context,
                output: request.output,
                state: snapshot.state().cloned(),
                candidates: request.candidates,
                tools,
            },
            todos: snapshot.todos().to_vec(),
        })
    }

    fn state(&self) -> std::sync::MutexGuard<'_, TurnState> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub fn messages(&self) -> Vec<ChatMessage> {
        self.state().prepared.messages.clone()
    }

    pub fn max_tokens(&self) -> usize {
        self.budget.output
    }

    pub fn budget(&self) -> &GenerationBudget {
        &self.budget
    }

    pub fn grounding(&self) -> &FittedGrounding {
        &self.grounding
    }

    pub fn tools(&self) -> Option<&ToolRequest> {
        self.tools.as_ref().map(|session| &session.request)
    }

    pub fn tools_mut(&mut self) -> Option<&mut ToolRequest> {
        self.tools.as_mut().map(|session| &mut session.request)
    }

    #[cfg(all(test, feature = "sqlite"))]
    pub(super) fn has_outcome(&self) -> bool {
        self.state().outcome.is_some()
    }

    pub fn is_saved(&self) -> bool {
        self.state().prepared.is_saved()
    }

    pub fn generate(
        &self,
        runner: &mut dyn PassRunner,
        mut request: ChatRequest,
        sink: &mut dyn EventSink,
    ) -> Result<GenerationSummary, llm::Error> {
        {
            let mut state = self.state();
            state.outcome = None;
            state.text.clear();
        }
        request.tools = self.tools().cloned();
        let mut text = String::new();
        let mut tee = |event| {
            if let GenerationEvent::Text { text: piece, .. } = &event {
                text.extend(piece.chars().filter(|&c| c != '\0'));
            }
            sink.add(event);
        };
        let first = runner.pass(request.clone(), &mut tee)?;
        let summary = if let Some(mut next) = self.tools.as_ref().and_then(|session| {
            first
                .tools
                .as_ref()
                .and_then(|outcome| session.follow_up.next(&request, outcome))
        }) {
            let output = request
                .max_tokens
                .unwrap_or(8192)
                .saturating_sub(first.generated_tokens.unwrap_or(i32::MAX))
                .max(0);
            if output > 0
                && runner.measure(&next)?.saturating_add(output as usize) <= runner.context_size()
            {
                if runner.cancelled() {
                    return Err(llm::Error::Cancelled);
                }
                next.max_tokens = Some(output);
                merge(first, runner.pass(next, &mut tee)?)
            } else {
                first
            }
        } else {
            first
        };
        {
            let mut state = self.state();
            state.outcome = summary.tools.clone();
            state.text = text;
        }
        sink.add(GenerationEvent::Done {
            summary: summary.clone(),
        });
        Ok(summary)
    }

    pub fn finish<B: Backend>(
        &self,
        db: &ChatDb<B>,
        snapshot: &ConversationSnapshot,
        text: &str,
        attachments: Vec<AttachmentMeta>,
    ) -> db::Result<FinishedTurn> {
        let mut state = self.state();
        let TurnState {
            prepared,
            outcome,
            text: streamed,
        } = &mut *state;
        let calls = outcome.as_ref().filter(|outcome| !outcome.calls.is_empty());
        let text = if calls.is_some() { streamed } else { text };
        let (sources, passages) = self
            .grounding
            .context
            .as_ref()
            .map(|grounded| {
                (
                    grounded.sources.as_slice(),
                    grounded.included_passages.clone(),
                )
            })
            .unwrap_or_default();
        let finished = save_prepared_reply(
            self.cache.as_deref(),
            db,
            snapshot,
            prepared,
            Answer {
                text,
                sources,
                passages,
                attachments,
                outcome: calls,
            },
            &|outcome, now| {
                self.tools
                    .as_ref()
                    .is_none_or(|tools| tools.follow_up.can_finish(outcome, now))
            },
        )?;
        *outcome = None;
        Ok(finished)
    }
}

fn merge(mut first: GenerationSummary, mut second: GenerationSummary) -> GenerationSummary {
    if let Some(mut outcome) = first.tools.take() {
        if let Some(later) = second.tools.take() {
            if !later.calls.is_empty() {
                outcome.calls.extend(later.calls);
                outcome.call_probability = outcome
                    .call_probability
                    .zip(later.call_probability)
                    .map(|(first, second)| first.min(second));
            }
            outcome.abstained |= later.abstained;
            outcome.rejected_steps += later.rejected_steps;
        }
        second.tools = Some(outcome);
    }
    second.prompt_tokens = first
        .prompt_tokens
        .zip(second.prompt_tokens)
        .map(|(first, second)| first + second);
    second.generated_tokens = first
        .generated_tokens
        .zip(second.generated_tokens)
        .map(|(first, second)| first + second);
    second
}
