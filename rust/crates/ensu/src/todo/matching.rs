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

const CHOICE_CHARS: usize = 60;

pub(crate) fn choice_label(title: &str) -> Option<String> {
    let label: String = title
        .chars()
        .map(|c| if c == '<' { '‹' } else { c })
        .filter(|c| !c.is_control())
        .take(CHOICE_CHARS)
        .collect();
    let label = label.trim();
    (!label.is_empty()).then(|| label.to_owned())
}

const FILLER: &[&str] = &[
    "i", "me", "we", "you", "it", "is", "was", "be", "been", "have", "has", "had", "just", "and",
    "or", "for", "of", "on", "in", "at", "with", "about", "from", "her", "his", "him", "their",
    "them", "our", "your", "this", "that", "up", "now", "today", "already", "can", "could",
    "would", "will", "should", "also", "then", "so", "ok", "okay", "yes", "thanks", "thank",
    "again", "please", "try", "what", "s", "ve", "m", "ll", "re", "d", "t",
];

pub(super) fn content_words(text: &str) -> Vec<String> {
    words(text)
        .into_iter()
        .filter(|word| !IGNORED.contains(&word.as_str()) && !FILLER.contains(&word.as_str()))
        .collect()
}

fn same_word(a: &str, b: &str) -> bool {
    if a == b {
        return true;
    }
    let shared = a.chars().zip(b.chars()).take_while(|(x, y)| x == y).count();
    shared >= 4 && shared + 3 >= a.chars().count().max(b.chars().count())
}

pub(crate) fn mentions_task(title: &str, text: &str, skip: &dyn Fn(&str) -> bool) -> bool {
    let title = content_words(title);
    let rest = usize::from(title.len() > 1);
    let mut distinctive: Vec<_> = title.iter().skip(rest).filter(|word| !skip(word)).collect();
    if distinctive.is_empty() {
        distinctive = title.iter().take(1).filter(|word| !skip(word)).collect();
    }
    let text: Vec<_> = content_words(text)
        .into_iter()
        .filter(|word| !skip(word))
        .collect();
    !distinctive.is_empty()
        && distinctive
            .iter()
            .all(|word| text.iter().any(|other| same_word(word, other)))
}

pub(crate) fn spells_out(title: &str, text: &str) -> bool {
    let text = words(text);
    let title: Vec<_> = words(title)
        .into_iter()
        .filter(|word| !is_ignored(word))
        .collect();
    !title.is_empty()
        && title
            .iter()
            .all(|word| text.iter().any(|other| same_word(word, other)))
}

const REFERRING: &[&str] = &[
    "it", "that", "this", "them", "those", "these", "one", "ones",
];

pub fn names_another(task: &str, text: &str) -> bool {
    let said: Vec<_> = content_words(text)
        .into_iter()
        .filter(|word| !super::timing::mentions_time(word))
        .collect();
    !said.is_empty()
        && !words(text)
            .iter()
            .any(|word| REFERRING.contains(&word.as_str()))
        && !content_words(task)
            .iter()
            .any(|word| said.iter().any(|other| same_word(word, other)))
}

const RETRY: &[&str] = &[
    "can", "could", "you", "please", "try", "retry", "that", "it", "again", "once", "more",
];

pub fn asks_again(text: &str) -> bool {
    let words = words(text);
    words.iter().all(|word| RETRY.contains(&word.as_str()))
        && words.iter().any(|word| word == "again" || word == "retry")
}

pub(crate) fn is_ignored(word: &str) -> bool {
    IGNORED.contains(&word)
}

pub(crate) fn has_search_words(query: &str) -> bool {
    let words = words(query);
    words != ["to", "dos"] && words.iter().any(|word| !is_ignored(word))
}

pub(super) fn command_clauses(text: &str) -> Vec<Vec<String>> {
    let mut outside = String::new();
    let mut quote = None;
    let chars: Vec<_> = text.chars().collect();
    for (index, &c) in chars.iter().enumerate() {
        if quote == Some(c) {
            quote = None;
        } else if quote.is_some() {
            continue;
        } else if matches!(c, '"' | '“' | '‘')
            || c == '\'' && (index == 0 || !chars[index - 1].is_alphanumeric())
        {
            quote = Some(match c {
                '“' => '”',
                '‘' => '’',
                _ => c,
            });
            outside.push_str(" quoted ");
        } else if matches!(c, ';' | '\n') {
            outside.push_str(" then ");
        } else {
            outside.push(c);
        }
    }
    let outside = outside.to_lowercase();
    let words: Vec<_> = outside
        .split(|c: char| !c.is_alphanumeric() && c != '\'')
        .filter(|word| !word.is_empty())
        .collect();
    words
        .split(|word| matches!(*word, "and" | "then" | "but"))
        .map(|clause| {
            clause
                .iter()
                .copied()
                .skip_while(|word| {
                    matches!(*word, "please" | "can" | "could" | "would" | "you" | "also")
                })
                .map(str::to_owned)
                .collect()
        })
        .collect()
}

pub(crate) fn unsupported_task_change(text: &str, todos: &[Todo]) -> bool {
    command_clauses(text).iter().any(|clause| {
        clause.first().is_some_and(|command| {
            matches!(
                command.as_str(),
                "edit" | "delete" | "remove" | "reschedule" | "rename" | "move" | "change"
            )
        })
    }) && (words(text).iter().any(|word| {
        matches!(
            word.as_str(),
            "task" | "tasks" | "todo" | "todos" | "list" | "item"
        )
    }) || todos
        .iter()
        .any(|todo| mentions_task(&todo.title, text, &|_| false)))
}

pub(crate) fn find_tasks<'a>(todos: &[&'a Todo], query: &str) -> Vec<&'a Todo> {
    let labelled: Vec<_> = todos
        .iter()
        .copied()
        .filter(|todo| choice_label(&todo.title).as_deref() == Some(query.trim()))
        .collect();
    if !labelled.is_empty() {
        return labelled;
    }
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
        .copied()
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
        .copied()
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

    fn names(title: &str, text: &str) -> bool {
        mentions_task(title, text, &|_| false)
    }
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
    fn tasks_are_found_by_title_words_or_choice_label() {
        let todos = [
            todo("Call mom"),
            todo("Call mom about the trip"),
            todo("Buy milk"),
        ];
        let titles = |query: &str| {
            find_tasks(&todos.iter().collect::<Vec<_>>(), query)
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

        let long = format!("Call {}", "x".repeat(100));
        let todos = [todo("Call mom"), todo(&long), todo("Fix <div> bug")];
        let todos: Vec<_> = todos.iter().collect();
        let label = choice_label(&long).unwrap();
        assert_eq!(label.chars().count(), CHOICE_CHARS);
        assert_eq!(find_tasks(&todos, &label)[0].title, long);
        assert_eq!(
            find_tasks(&todos, "Fix ‹div> bug")[0].title,
            "Fix <div> bug"
        );
        assert_eq!(choice_label(" \n "), None);
        assert!(!has_search_words("To Dos"));
        assert!(has_search_words("dos"));
        assert!(has_search_words("dos libros"));
    }

    #[test]
    fn tasks_are_mentioned_by_distinctive_words() {
        assert!(names(
            "Call Vidhi about Aadhar",
            "I have talked to Vidhi for her Aadhar"
        ));
        assert!(names("Finish the report", "I finished the report"));
        assert!(names("Renew passport", "renewed my passports today"));
        assert!(names("Laundry", "Laundry's done"));
        assert!(!names("Call the bank", "I called mom"));
        assert!(!names("Call Vidhi about Aadhar", "Can you try again?"));
        assert!(!names("Buy milk", "Bought the bread"));
    }
}
