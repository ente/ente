use super::*;

pub struct TurnInput {
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
}

pub struct PreparedTurn {
    pub preparation: Preparation,
    pub budget: GenerationBudget,
    pub grounding: FittedGrounding,
}

pub fn prepare_turn(
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
            let tokens = effects.measure(messages)?;
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
    .with_grounding(prompt_grounding);
    effects.check_current()?;
    Ok(PreparedTurn {
        preparation,
        budget,
        grounding,
    })
}
