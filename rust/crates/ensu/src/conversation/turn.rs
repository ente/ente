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
    mut input: TurnInput,
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
    let current = input.messages.pop().ok_or(Error::InvalidHistory)?;
    if current.sender != Sender::SelfUser || current.text != input.expected_user_text {
        return Err(PrepareError::Stale);
    }
    let budget = resolve_generation_budget(input.context, input.output)?;
    let required = input
        .history_query
        .as_deref()
        .map(|query| requested_history(&input.messages, query, || effects.check_cancelled()))
        .transpose()?
        .flatten();
    effects.check_cancelled()?;
    let grounding_plan = input.candidates.select_sources(Some(
        input.history_query.as_deref().unwrap_or(&input.current),
    ))?;
    let grounding = fit_grounding_with_history(
        &grounding_plan,
        required.as_ref(),
        &input.system,
        &input.current,
        budget.input,
        |messages| {
            effects.check_cancelled()?;
            let tokens = effects.measure(messages)?;
            effects.check_cancelled()?;
            Ok(tokens)
        },
    )?;
    effects.check_current()?;
    input.system = grounded_system(&input.system, grounding.context.as_ref());
    if let Some(required) = required.filter(|_| grounding.history_included) {
        input.current = required.prepend_required(&input.current);
        input.history_query = None;
    }
    let preparation = Preparation::new(
        input.session,
        input.messages,
        input.system,
        input.current,
        budget.context,
        budget.output,
        input.state,
    )?
    .with_history_query(input.history_query);
    effects.check_current()?;
    Ok(PreparedTurn {
        preparation,
        budget,
        grounding,
    })
}
