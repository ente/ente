use super::*;
use crate::retrieval::{self, GroundedExcerpt, GroundedPromptContext, ReferencedPassage};
use std::collections::{BTreeMap, BTreeSet};

pub const MAX_GROUNDING_BYTES: usize = 6000;
pub const MAX_CANDIDATE_BYTES: usize = 64 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GroundingCandidates {
    pub referenced: Vec<ReferencedPassage>,
    pub searched: Vec<GroundedExcerpt>,
    pub max_utf8_bytes: usize,
}

pub(super) fn named_source_keys<'a>(
    query: &str,
    sources: impl Iterator<Item = &'a retrieval::GroundedSource>,
) -> BTreeSet<(u8, &'a str, &'a str)> {
    let words = |text: &str| -> BTreeSet<String> {
        text.split(|c: char| !c.is_alphanumeric())
            .filter(|s| s.chars().count() >= 3)
            .map(str::to_lowercase)
            .filter(|s| !"the and source sources note notes policy policies document documents return access equipment".split_whitespace().any(|w| w == s))
            .collect()
    };
    let tokens = |text: &str| -> Vec<String> {
        text.split(|c: char| !c.is_alphanumeric())
            .filter(|s| !s.is_empty())
            .map(str::to_lowercase)
            .collect()
    };
    let query_tokens = tokens(query);
    let mut title_matches = Vec::new();
    let mut documents = BTreeMap::<_, BTreeSet<String>>::new();
    for source in sources {
        let title = match source {
            retrieval::GroundedSource::LocalNote { reference } => &reference.title,
            retrieval::GroundedSource::EnsuPack { citation } => &citation.title,
        };
        let mut label_words = words(title);
        if !label_words.is_empty() {
            let title = tokens(title);
            for (start, window) in query_tokens.windows(title.len()).enumerate() {
                if window == title {
                    title_matches.push((source.document_key(), start, start + title.len()));
                }
            }
        }
        if let retrieval::GroundedSource::LocalNote { reference } = source {
            label_words.extend(words(&reference.document_id));
        }
        documents
            .entry(source.document_key())
            .or_default()
            .extend(label_words);
    }
    let query_words = words(query);
    documents
        .iter()
        .filter(|(key, label)| {
            title_matches.iter().any(|(matched, start, end)| {
                matched == *key
                    && !title_matches.iter().any(|(_, other_start, other_end)| {
                        other_start <= start
                            && other_end >= end
                            && other_end - other_start > end - start
                    })
            }) || label.iter().any(|word| {
                query_words.contains(word)
                    && documents
                        .values()
                        .filter(|other| other.contains(word))
                        .count()
                        == 1
            })
        })
        .map(|(key, _)| *key)
        .collect()
}

enum PassageSlot {
    Historical {
        minimum: Box<ReferencedPassage>,
        current: Option<GroundedExcerpt>,
    },
    Current(GroundedExcerpt),
}

impl PassageSlot {
    fn locator(&self) -> &retrieval::PassageLocator {
        match self {
            Self::Historical { minimum, .. } => &minimum.reference.locator,
            Self::Current(current) => &current.locator,
        }
    }

    fn source(&self) -> &retrieval::GroundedSource {
        match self {
            Self::Historical { minimum, .. } => &minimum.source,
            Self::Current(current) => &current.source,
        }
    }

    fn minimum(&self) -> Option<&ReferencedPassage> {
        match self {
            Self::Historical { minimum, .. } => Some(minimum),
            Self::Current(_) => None,
        }
    }

    fn current(&self) -> Option<&GroundedExcerpt> {
        match self {
            Self::Historical { current, .. } => current.as_ref(),
            Self::Current(current) => Some(current),
        }
    }

    fn minimum_coverage(&self) -> Result<ReferencedPassage, PrepareError> {
        let current = match self {
            Self::Historical {
                minimum,
                current: None,
            } => return Ok(minimum.as_ref().clone()),
            Self::Historical {
                current: Some(current),
                ..
            }
            | Self::Current(current) => current,
        };
        let text = retrieval::clean_passage_text(&current.text);
        let end = if let Some(old) = self.minimum() {
            let end = old
                .reference
                .spans
                .last()
                .ok_or_else(|| {
                    PrepareError::Backend("Historical source has no verified spans".into())
                })?
                .end_utf8 as usize;
            if end >= old.passages.join("\n[omitted source text]\n").len() {
                return Ok(old.clone());
            }
            end
        } else {
            text.chars()
                .next()
                .ok_or_else(|| PrepareError::Backend("Current source has no usable text".into()))?
                .len_utf8()
        };
        let passage = text[..end].to_owned();
        let reference = retrieval::IncludedPassage::prefix(current.locator.clone(), &passage)
            .map_err(retrieval_error)?;
        Ok(ReferencedPassage {
            reference,
            source: self.source().clone(),
            passages: vec![passage],
        })
    }
}

pub(super) struct GroundingPlan {
    slots: Vec<PassageSlot>,
    incidental: Vec<ReferencedPassage>,
    searched: Vec<GroundedExcerpt>,
    max_utf8_bytes: usize,
}

impl GroundingPlan {
    fn freeze(
        &self,
        context: Option<&GroundedPromptContext>,
    ) -> Result<Vec<ReferencedPassage>, PrepareError> {
        let Some(context) = context else {
            return Ok(Vec::new());
        };
        context
            .included_passages
            .iter()
            .zip(&context.sources)
            .map(|(reference, source)| {
                let passages = self
                    .searched
                    .iter()
                    .filter(|hit| {
                        hit.locator == reference.locator && hit.source.same_document(source)
                    })
                    .find_map(|hit| reference.verified_spans(&hit.text))
                    .or_else(|| {
                        self.slots
                            .iter()
                            .filter_map(|slot| slot.minimum())
                            .chain(&self.incidental)
                            .find(|old| {
                                old.reference == *reference && old.source.same_document(source)
                            })
                            .map(|old| old.passages.clone())
                    })
                    .ok_or_else(|| {
                        PrepareError::Backend("Fitted source coverage could not be verified".into())
                    })?;
                Ok(ReferencedPassage {
                    reference: reference.clone(),
                    source: source.clone(),
                    passages,
                })
            })
            .collect()
    }
}

struct SourceGroup<'a> {
    key: (u8, &'a str, &'a str),
    slots: Vec<PassageSlot>,
}

fn source_group<'a, 'b>(
    groups: &'a mut Vec<SourceGroup<'b>>,
    source: &'b retrieval::GroundedSource,
) -> &'a mut SourceGroup<'b> {
    let key = source.document_key();
    let index = groups
        .iter()
        .position(|group| group.key == key)
        .unwrap_or_else(|| {
            groups.push(SourceGroup {
                key,
                slots: Vec::new(),
            });
            groups.len() - 1
        });
    &mut groups[index]
}

fn retrieval_error(error: retrieval::RetrievalError) -> PrepareError {
    PrepareError::Backend(error.to_string())
}

impl GroundingCandidates {
    pub(super) fn select_sources(
        &self,
        query: Option<&str>,
    ) -> Result<GroundingPlan, PrepareError> {
        self.validate()?;
        let query = query.filter(|query| query.len() <= super::lookup::LOOKUP_MAX_QUERY_BYTES);
        let named = named_source_keys(
            query.unwrap_or_default(),
            self.referenced
                .iter()
                .map(|r| &r.source)
                .chain(self.searched.iter().map(|r| &r.source)),
        );
        let historical: BTreeSet<_> = self
            .referenced
            .iter()
            .map(|old| old.source.document_key())
            .collect();
        let compares_owned_source = query.is_some_and(super::followup::compares_owned_source)
            && self
                .searched
                .iter()
                .any(|hit| named.contains(&hit.source.document_key()));
        let refers_back = !historical.is_empty()
            && (query.is_some_and(super::followup::refers_back)
                || compares_owned_source
                || self
                    .searched
                    .iter()
                    .all(|hit| retrieval::clean_passage_text(&hit.text).is_empty()));
        let mut searched = self.searched.clone();
        searched.sort_by_key(|hit| {
            self.referenced
                .iter()
                .any(|old| old.reference.locator == hit.locator)
        });
        let mut groups: Vec<SourceGroup> = Vec::new();
        for old in &self.referenced {
            let group = source_group(&mut groups, &old.source);
            if !group
                .slots
                .iter()
                .any(|slot| slot.locator() == &old.reference.locator)
            {
                group.slots.push(PassageSlot::Historical {
                    minimum: Box::new(old.clone()),
                    current: None,
                });
            }
        }
        for hit in &searched {
            if let Some(slot) = groups
                .iter_mut()
                .flat_map(|group| &mut group.slots)
                .find(|slot| slot.locator() == &hit.locator)
            {
                if let PassageSlot::Historical { minimum, current } = slot
                    && current.is_none()
                    && minimum.source.same_document(&hit.source)
                    && minimum.reference.verified_spans(&hit.text).is_some()
                {
                    *current = Some(hit.clone());
                }
                continue;
            }
            let key = hit.source.document_key();
            let selected = query.is_some()
                && (named.contains(&key)
                    || (!historical.is_empty()
                        && (named.is_empty() || groups.iter().any(|group| group.key == key))));
            if selected && !retrieval::clean_passage_text(&hit.text).is_empty() {
                source_group(&mut groups, &hit.source)
                    .slots
                    .push(PassageSlot::Current(hit.clone()));
            }
        }
        if query.is_some() {
            for group in &mut groups {
                group.slots.sort_by_key(|slot| {
                    searched
                        .iter()
                        .position(|hit| &hit.locator == slot.locator())
                        .unwrap_or(usize::MAX)
                });
            }
            let antecedent = self
                .referenced
                .iter()
                .find(|old| named.contains(&old.source.document_key()))
                .or_else(|| self.referenced.first())
                .map(|old| old.source.document_key());
            groups.sort_by_key(|group| {
                let current = searched
                    .iter()
                    .position(|hit| hit.source.document_key() == group.key);
                if named.contains(&group.key) {
                    (0, 0)
                } else if refers_back && antecedent.as_ref() == Some(&group.key) {
                    (1, 0)
                } else if refers_back && historical.contains(&group.key) {
                    current.map_or((3, 0), |index| (2, index))
                } else if named.is_empty()
                    && let Some(index) = current
                {
                    (4, index)
                } else {
                    (5, 0)
                }
            });
        }
        let mut prioritized = Vec::new();
        for (group_index, group) in groups.into_iter().enumerate() {
            let primary = query.is_none()
                || named.contains(&group.key)
                || (refers_back && historical.contains(&group.key));
            for (slot_index, slot) in group.slots.into_iter().enumerate() {
                let primary =
                    primary || (!refers_back && named.is_empty() && slot.current().is_some());
                prioritized.push(((!primary, slot_index > 0, group_index), slot));
            }
        }
        prioritized.sort_by_key(|(priority, _)| *priority);
        searched.sort_by_key(|hit| {
            prioritized
                .iter()
                .position(|(_, slot)| slot.locator() == &hit.locator)
                .unwrap_or(usize::MAX)
        });
        let mut packs = 0;
        let mut notes = 0;
        let mut slots = Vec::new();
        let mut incidental = Vec::new();
        for ((is_incidental, _, _), slot) in prioritized {
            let (count, limit) = match slot.source() {
                retrieval::GroundedSource::EnsuPack { .. } => {
                    (&mut packs, retrieval::MAX_PACK_HITS)
                }
                retrieval::GroundedSource::LocalNote { .. } => {
                    (&mut notes, retrieval::MAX_NOTES_GROUNDING_HITS)
                }
            };
            if *count == limit {
                continue;
            }
            *count += 1;
            if !is_incidental {
                slots.push(slot);
            } else if let PassageSlot::Historical { minimum, .. } = slot {
                incidental.push(*minimum);
            }
        }
        Ok(GroundingPlan {
            slots,
            incidental,
            searched,
            max_utf8_bytes: self.max_utf8_bytes,
        })
    }

    pub fn new(
        referenced: Vec<ReferencedPassage>,
        mut searched: Vec<GroundedExcerpt>,
        max_utf8_bytes: usize,
    ) -> Result<Self, PrepareError> {
        for hit in &mut searched {
            hit.text = retrieval::clean_passage_text(&hit.text);
            let mut end = hit.text.len().min(MAX_GROUNDING_BYTES);
            while !hit.text.is_char_boundary(end) {
                end -= 1;
            }
            hit.text.truncate(end);
        }
        let result = Self {
            referenced,
            searched,
            max_utf8_bytes: max_utf8_bytes.min(MAX_GROUNDING_BYTES),
        };
        result.validate()?;
        Ok(result)
    }

    pub fn validate(&self) -> Result<(), PrepareError> {
        let packs = self
            .searched
            .iter()
            .filter(|hit| matches!(hit.source, retrieval::GroundedSource::EnsuPack { .. }))
            .count();
        if self.referenced.len() > retrieval::MAX_GROUNDING_HITS
            || self.searched.len() > retrieval::MAX_GROUNDING_HITS
            || packs > retrieval::MAX_PACK_HITS
            || self.searched.len().saturating_sub(packs) > retrieval::MAX_NOTES_GROUNDING_HITS
            || self.max_utf8_bytes > MAX_GROUNDING_BYTES
            || self
                .searched
                .iter()
                .any(|h| h.text.len() > MAX_GROUNDING_BYTES || !h.score.is_finite())
            || self
                .referenced
                .iter()
                .flat_map(|r| &r.passages)
                .any(|passage| passage.len() > MAX_GROUNDING_BYTES)
            || serde_json::to_vec(self)
                .map_err(|e| PrepareError::Backend(e.to_string()))?
                .len()
                > MAX_CANDIDATE_BYTES
        {
            return Err(PrepareError::Backend(
                "Source candidates exceed the supported preparation limits".into(),
            ));
        }
        retrieval::build_followup_prompt_context(&self.referenced, &[], usize::MAX)
            .map_err(retrieval_error)?;
        for hit in &self.searched {
            retrieval::build_grounded_prompt_context(std::slice::from_ref(hit), usize::MAX)
                .map_err(retrieval_error)?;
        }
        Ok(())
    }

    pub fn pack(&self, budget: usize) -> Result<Option<GroundedPromptContext>, PrepareError> {
        retrieval::build_followup_prompt_context(
            &self.referenced,
            &self.searched,
            budget.min(self.max_utf8_bytes),
        )
        .map_err(retrieval_error)
    }
}

pub struct FittedGrounding {
    pub history_included: bool,
    pub context: Option<GroundedPromptContext>,
    pub repacked: bool,
    pub evidence_tokens: usize,
}

pub(super) fn grounded_system(system: &str, context: Option<&GroundedPromptContext>) -> String {
    context.map_or_else(
        || system.to_owned(),
        |context| format!("{system}\n\n{}", context.text),
    )
}

pub(super) fn fit_grounding_with_history(
    candidates: &GroundingPlan,
    history: Option<&HistoryLookup>,
    system: &str,
    current: &str,
    input_budget: usize,
    mut measure: impl FnMut(&[ChatMessage]) -> Result<usize, PrepareError>,
) -> Result<FittedGrounding, PrepareError> {
    let recovered = match history.map(|history| history.prepend_required(current)) {
        Some(recovered)
            if measure(&answer_messages(system, None, &[], &recovered))? <= input_budget =>
        {
            Some(recovered)
        }
        _ => None,
    };
    let mut fitted = fit_grounding(
        candidates,
        system,
        recovered.as_deref().unwrap_or(current),
        input_budget,
        measure,
    )?;
    fitted.history_included = recovered.is_some();
    Ok(fitted)
}

fn fit_grounding(
    candidates: &GroundingPlan,
    system: &str,
    current: &str,
    input_budget: usize,
    mut measure: impl FnMut(&[ChatMessage]) -> Result<usize, PrepareError>,
) -> Result<FittedGrounding, PrepareError> {
    let base = measure(&answer_messages(system, None, &[], current))?;
    let room = input_budget
        .checked_sub(base)
        .ok_or(PrepareError::CurrentInputTooLarge)?;
    let mut count_context = |context: Option<&GroundedPromptContext>| {
        measure(&answer_messages(
            &grounded_system(system, context),
            None,
            &[],
            current,
        ))
    };
    let mut selected = candidates
        .slots
        .iter()
        .map(PassageSlot::minimum_coverage)
        .collect::<Result<Vec<_>, _>>()?;
    let preferred_hits = |count: usize| -> Vec<GroundedExcerpt> {
        candidates.slots[..count]
            .iter()
            .filter_map(|slot| slot.current().cloned())
            .collect()
    };
    let preferred = retrieval::build_followup_prompt_context(
        &selected,
        &preferred_hits(selected.len()),
        usize::MAX,
    )
    .map_err(retrieval_error)?;
    let preferred_tokens = count_context(preferred.as_ref())?.saturating_sub(base);
    let allowance = 1500.min(input_budget / 4).max(preferred_tokens).min(room);
    let ceiling = base.saturating_add(allowance).min(input_budget);

    let (minimum, minimum_count) = loop {
        let minimum = retrieval::build_followup_prompt_context(&selected, &[], usize::MAX)
            .map_err(retrieval_error)?;
        let count = count_context(minimum.as_ref())?;
        if minimum
            .as_ref()
            .is_none_or(|context| context.text.len() <= candidates.max_utf8_bytes)
            && count <= ceiling
        {
            break (minimum, count);
        }
        if selected.pop().is_none() {
            return Err(PrepareError::CurrentInputTooLarge);
        }
    };
    let demoted = selected.len() != candidates.slots.len();
    let (preferred, preferred_count, reduced) = fit_coverage(
        &selected,
        &preferred_hits(selected.len()),
        candidates.max_utf8_bytes,
        minimum,
        minimum_count,
        ceiling,
        &mut count_context,
    )?;
    let (context, count, optional_reduced) = if reduced {
        (preferred, preferred_count, false)
    } else {
        let mut fixed = candidates.freeze(preferred.as_ref())?;
        let mut context = preferred;
        let mut count = preferred_count;
        for old in &candidates.incidental {
            fixed.push(old.clone());
            let extended = retrieval::build_followup_prompt_context(&fixed, &[], usize::MAX)
                .map_err(retrieval_error)?;
            if extended
                .as_ref()
                .is_some_and(|context| context.text.len() > candidates.max_utf8_bytes)
            {
                fixed.pop();
                continue;
            }
            let extended_count = count_context(extended.as_ref())?;
            if extended_count > ceiling {
                fixed.pop();
                continue;
            }
            context = extended;
            count = extended_count;
        }
        fit_coverage(
            &fixed,
            &candidates.searched,
            candidates.max_utf8_bytes,
            context,
            count,
            ceiling,
            &mut count_context,
        )?
    };
    Ok(FittedGrounding {
        context,
        repacked: demoted || reduced || optional_reduced,
        evidence_tokens: count.saturating_sub(base),
        history_included: false,
    })
}

fn fit_coverage(
    selected: &[ReferencedPassage],
    searched: &[GroundedExcerpt],
    max_bytes: usize,
    minimum: Option<GroundedPromptContext>,
    minimum_count: usize,
    ceiling: usize,
    count_context: &mut impl FnMut(Option<&GroundedPromptContext>) -> Result<usize, PrepareError>,
) -> Result<(Option<GroundedPromptContext>, usize, bool), PrepareError> {
    let full = retrieval::build_followup_prompt_context(selected, searched, max_bytes)
        .map_err(retrieval_error)?;
    let full_count = count_context(full.as_ref())?;
    if full_count <= ceiling {
        return Ok((full, full_count, false));
    }
    let mut lower = minimum.as_ref().map_or(0, |context| context.text.len());
    let mut upper = full.as_ref().map_or(0, |context| context.text.len());
    let mut best = minimum;
    let mut best_count = minimum_count;
    while lower + 1 < upper {
        let budget = lower + (upper - lower) / 2;
        let packed = retrieval::build_followup_prompt_context(selected, searched, budget)
            .map_err(retrieval_error)?;
        let count = count_context(packed.as_ref())?;
        if count <= ceiling {
            lower = budget;
            best = packed;
            best_count = count;
        } else {
            upper = budget;
        }
    }
    Ok((best, best_count, true))
}

#[cfg(test)]
#[path = "grounding_tests.rs"]
mod tests;
