use super::timing::Deadline;
use super::{COMPLETE_TOOL, LIST_TOOL, ListFilter, SAVE_TOOL};
use crate::llm::{ToolCall, ToolValue};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct When {
    pub quote: String,
    pub deadline: Option<Deadline>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Target {
    Named(String),
    Position(i64),
    Unspecified,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Intent {
    Save {
        title: Option<String>,
        when: Option<When>,
    },
    List {
        filter: Option<ListFilter>,
        query: Option<String>,
    },
    Complete {
        target: Target,
        sure: bool,
    },
}

impl Intent {
    pub(crate) fn to_call(&self) -> ToolCall {
        let text = |value: &str| ToolValue::Text(value.to_owned());
        let (name, arguments) = match self {
            Self::Save { title, when } => (
                SAVE_TOOL,
                vec![
                    ("title", title.as_deref().map(text)),
                    ("when", when.as_ref().map(|when| text(&when.quote))),
                ],
            ),
            Self::List { filter, query } => (
                LIST_TOOL,
                vec![
                    ("filter", filter.map(|filter| text(filter.name()))),
                    ("query", query.as_deref().map(text)),
                ],
            ),
            Self::Complete { target, .. } => (
                COMPLETE_TOOL,
                match target {
                    Target::Named(task) => vec![("task", Some(text(task)))],
                    Target::Position(number) => {
                        vec![("number", Some(ToolValue::Integer(*number)))]
                    }
                    Target::Unspecified => Vec::new(),
                },
            ),
        };
        ToolCall {
            name: name.into(),
            arguments: arguments
                .into_iter()
                .filter_map(|(name, value)| Some((name.to_owned(), value?)))
                .collect(),
        }
    }

    pub(crate) fn unsure(&self) -> bool {
        matches!(self, Self::Complete { sure: false, .. })
    }
}
