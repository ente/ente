use super::Todo;

const IGNORED: &[&str] = &[
    "a",
    "an",
    "the",
    "my",
    "to",
    "do",
    "todo",
    "todos",
    "task",
    "tasks",
    "item",
    "one",
    "off",
    "as",
    "done",
    "complete",
    "completed",
    "mark",
    "finished",
    "finish",
    "tick",
    "check",
    "list",
];

fn words(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .map(str::to_owned)
        .collect()
}

/// Tasks whose titles match `query`. An exact title match wins; otherwise
/// every meaningful query word must start a word of the title.
pub(crate) fn find_tasks<'a>(todos: &'a [Todo], query: &str) -> Vec<&'a Todo> {
    let all = words(query);
    let query: Vec<_> = all
        .iter()
        .filter(|word| !IGNORED.contains(&word.as_str()))
        .cloned()
        .collect();
    if query.is_empty() {
        return Vec::new();
    }
    let exact: Vec<_> = todos
        .iter()
        .filter(|todo| {
            let title = words(&todo.title);
            title == all || title == query
        })
        .collect();
    if !exact.is_empty() {
        return exact;
    }
    todos
        .iter()
        .filter(|todo| {
            let title = words(&todo.title);
            query.iter().all(|word| {
                title
                    .iter()
                    .any(|candidate| candidate.starts_with(word.as_str()))
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn todo(title: &str) -> Todo {
        Todo {
            id: Uuid::new_v4(),
            title: title.into(),
            due_at_ms: None,
            completed_at_ms: None,
            created_at_ms: 0,
            updated_at_ms: 0,
            version: 1,
        }
    }

    #[test]
    fn exact_titles_win_and_partial_queries_need_every_word() {
        let todos = [
            todo("Call mom"),
            todo("Call mom about the trip"),
            todo("Buy milk"),
        ];
        let titles = |query: &str| {
            find_tasks(&todos, query)
                .iter()
                .map(|t| t.title.clone())
                .collect::<Vec<_>>()
        };
        assert_eq!(titles("call mom"), ["Call mom"]);
        assert_eq!(titles("the Buy milk task"), ["Buy milk"]);
        assert_eq!(titles("mom trip"), ["Call mom about the trip"]);
        assert_eq!(titles("call"), ["Call mom", "Call mom about the trip"]);
        assert!(titles("the task").is_empty());
        assert!(titles("dentist").is_empty());
    }
}
