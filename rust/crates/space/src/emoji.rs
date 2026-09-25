use std::sync::LazyLock;

use serde::Serialize;

mod data;

#[derive(Debug, Serialize)]
pub struct ReactionEmoji {
    pub emoji: String,
    pub name: String,
    pub group: u8,
    pub tags: Vec<String>,
    pub skins: Vec<ReactionEmojiVariant>,
}

#[derive(Debug, Serialize)]
pub struct ReactionEmojiVariant {
    pub emoji: String,
    pub name: String,
    pub tone: Vec<u8>,
}

const TONE_NAMES: [&str; 5] = [
    "light skin tone",
    "medium-light skin tone",
    "medium skin tone",
    "medium-dark skin tone",
    "dark skin tone",
];

pub fn reaction_emojis() -> &'static [ReactionEmoji] {
    static CATALOG: LazyLock<Vec<ReactionEmoji>> = LazyLock::new(catalog);
    &CATALOG
}

fn entry(
    emoji: impl Into<String>,
    name: impl Into<String>,
    group: u8,
    tags: &str,
) -> ReactionEmoji {
    ReactionEmoji {
        emoji: emoji.into(),
        name: name.into(),
        group,
        tags: tags.split_whitespace().map(str::to_owned).collect(),
        skins: Vec::new(),
    }
}

fn toned(emoji: &str, tone: u8) -> String {
    let boundary = emoji
        .char_indices()
        .nth(1)
        .map_or(emoji.len(), |(index, _)| index);
    let (first, rest) = emoji.split_at(boundary);
    format!(
        "{first}{}{}",
        ['🏻', '🏼', '🏽', '🏾', '🏿'][usize::from(tone - 1)],
        rest.trim_start_matches('\u{fe0f}')
    )
}

fn add_tones(entry: &mut ReactionEmoji) {
    for tone in 1..=5 {
        entry.skins.push(ReactionEmojiVariant {
            emoji: toned(&entry.emoji, tone),
            name: format!("{}, {}", entry.name, TONE_NAMES[usize::from(tone - 1)]),
            tone: vec![tone],
        });
    }
}

fn catalog() -> Vec<ReactionEmoji> {
    let mut entries = Vec::new();
    for &(group, emoji, name, tags, tones) in data::EMOJI {
        let mut item = entry(emoji, name, group, tags);
        if tones {
            add_tones(&mut item);
        }
        entries.push(item);
    }
    add_people(&mut entries);
    add_flags(&mut entries);
    entries.sort_by_key(|entry| entry.group);
    entries
}

fn add_people(entries: &mut Vec<ReactionEmoji>) {
    for (symbol, role, tags) in [
        ("⚕️", "health worker", "doctor nurse medical hospital"),
        ("🎓", "student", "school college study graduation"),
        ("🏫", "teacher", "school professor instructor"),
        ("⚖️", "judge", "court justice law"),
        ("🌾", "farmer", "farming garden agriculture"),
        ("🍳", "cook", "chef kitchen cooking"),
        ("🔧", "mechanic", "repair tools"),
        ("🏭", "factory worker", "industrial manufacturing"),
        ("💼", "office worker", "business job employee"),
        ("🔬", "scientist", "research chemistry laboratory"),
        ("💻", "technologist", "developer programmer coder computer"),
        ("🎤", "singer", "music musician performer"),
        ("🎨", "artist", "painting painter creative"),
        ("✈️", "pilot", "aviation plane flying"),
        ("🚀", "astronaut", "space rocket"),
        ("🚒", "firefighter", "fire rescue emergency"),
        ("🦰", "red hair", "redhead ginger"),
        ("🦱", "curly hair", "curls"),
        ("🦳", "white hair", "gray grey"),
        ("🦲", "bald", "hairless"),
        ("🦯", "with a white cane", "blind accessibility walking"),
        (
            "🦼",
            "in a powered wheelchair",
            "accessibility disability mobility",
        ),
        (
            "🦽",
            "in a manual wheelchair",
            "accessibility disability mobility",
        ),
    ] {
        for (person, name) in [("🧑", "person"), ("👨", "man"), ("👩", "woman")] {
            let mut item = entry(
                format!("{person}\u{200d}{symbol}"),
                format!("{name} {role}"),
                1,
                tags,
            );
            add_tones(&mut item);
            entries.push(item);
        }
    }
    for (base, label, tags, tones) in [
        ("🙍", "frowning", "sad unhappy", true),
        ("🙎", "pouting", "upset angry", true),
        ("🙅", "gesturing no", "stop denied refuse", true),
        ("🙆", "gesturing OK", "okay yes accepted", true),
        ("💁", "tipping hand", "help information sassy", true),
        ("🙋", "raising hand", "question answer volunteer", true),
        ("🧏", "deaf", "hearing accessibility", true),
        ("🙇", "bowing", "sorry thanks respect", true),
        ("🤦", "facepalm", "disbelief frustrated", true),
        ("🤷", "shrugging", "dunno unsure whatever", true),
        ("👮", "police officer", "cop law", true),
        ("🕵️", "detective", "spy investigate", true),
        ("💂", "guard", "security soldier", true),
        ("👷", "construction worker", "builder hardhat", true),
        ("👳", "wearing a turban", "headwear", true),
        ("🤵", "in a tuxedo", "groom suit wedding", true),
        ("👰", "wearing a veil", "bride wedding", true),
        ("🦸", "superhero", "hero superpower", true),
        ("🦹", "supervillain", "villain evil", true),
        ("🧙", "mage", "wizard witch magic", true),
        ("🧚", "fairy", "wings magic", true),
        ("🧛", "vampire", "dracula halloween", true),
        ("🧜", "merperson", "mermaid merman ocean", true),
        ("🧝", "elf", "fantasy magic", true),
        ("🧞", "genie", "wish magic", false),
        ("🧟", "zombie", "undead halloween", false),
        ("💆", "getting a massage", "spa relax", true),
        ("💇", "getting a haircut", "barber salon", true),
        ("🚶", "walking", "pedestrian stroll", true),
        ("🧍", "standing", "stand upright", true),
        ("🧎", "kneeling", "kneel", true),
        ("🏃", "running", "runner jogging exercise", true),
        ("🧖", "in a sauna", "steam spa relax", true),
        ("🧗", "climbing", "climber rock", true),
        ("🏌️", "golfing", "golf sport", true),
        ("🏄", "surfing", "surf wave ocean", true),
        ("🚣", "rowing", "boat paddle", true),
        ("🏊", "swimming", "swim pool water", true),
        ("⛹️", "bouncing a ball", "basketball sport", true),
        ("🏋️", "lifting weights", "gym strong workout", true),
        ("🚴", "cycling", "bike bicycle sport", true),
        ("🚵", "mountain biking", "bike bicycle sport", true),
        ("🤸", "cartwheeling", "gymnastics sport", true),
        ("🤽", "playing water polo", "pool sport", true),
        ("🤾", "playing handball", "ball sport", true),
        ("🤹", "juggling", "circus skill", true),
        ("🧘", "in lotus pose", "yoga meditation relax", true),
        ("🧔", "with a beard", "bearded facial hair", true),
        ("👱", "with blond hair", "blonde hair", true),
    ] {
        for (gender, name) in [("♂️", "man"), ("♀️", "woman")] {
            let mut item = entry(
                format!("{base}\u{200d}{gender}"),
                format!("{name} {label}"),
                1,
                tags,
            );
            if tones {
                add_tones(&mut item);
            }
            entries.push(item);
        }
    }
    for (person, name) in [("🧑", "person"), ("👨", "man"), ("👩", "woman")] {
        let mut item = entry(
            format!("{person}\u{200d}🍼"),
            format!("{name} feeding a baby"),
            1,
            "parent bottle milk newborn",
        );
        add_tones(&mut item);
        entries.push(item);
    }
    let facing_right: Vec<_> = entries
        .iter()
        .filter(|entry| {
            entry.emoji.starts_with(['🚶', '🏃', '🧎'])
                || entry.emoji.contains(['🦯', '🦼', '🦽']) && entry.emoji.contains('\u{200d}')
        })
        .map(|source| {
            let mut item = entry(
                format!("{}\u{200d}➡️", source.emoji),
                format!("{} facing right", source.name),
                1,
                &source.tags.join(" "),
            );
            add_tones(&mut item);
            item
        })
        .collect();
    entries.extend(facing_right);
    for (symbol, name, person, middle, tags) in [
        ("👯", "bunny eared dancers", "🧑", "🐰", "party dance"),
        (
            "👯\u{200d}♂️",
            "men with bunny ears",
            "👨",
            "🐰",
            "party dance",
        ),
        (
            "👯\u{200d}♀️",
            "women with bunny ears",
            "👩",
            "🐰",
            "party dance",
        ),
        ("🤼", "wrestlers", "🧑", "🫯", "wrestling sport"),
        (
            "🤼\u{200d}♂️",
            "men wrestling",
            "👨",
            "🫯",
            "wrestling sport",
        ),
        (
            "🤼\u{200d}♀️",
            "women wrestling",
            "👩",
            "🫯",
            "wrestling sport",
        ),
    ] {
        let mut item = entry(symbol, name, 1, tags);
        for left in 1..=5 {
            for right in 1..=5 {
                let emoji = if left == right {
                    toned(symbol, left)
                } else {
                    format!(
                        "{}\u{200d}{middle}\u{200d}{}",
                        toned(person, left),
                        toned(person, right)
                    )
                };
                item.skins.push(ReactionEmojiVariant {
                    emoji,
                    name: format!(
                        "{}, {}, {}",
                        item.name,
                        TONE_NAMES[usize::from(left - 1)],
                        TONE_NAMES[usize::from(right - 1)]
                    ),
                    tone: vec![left, right],
                });
            }
        }
        entries.push(item);
    }
    add_couples(entries);
    add_families(entries);
}

fn add_couples(entries: &mut Vec<ReactionEmoji>) {
    for (symbol, name, first, middle, last) in [
        ("🤝", "handshake", "🫱", "", "🫲"),
        (
            "👫",
            "woman and man holding hands",
            "👩",
            "🤝\u{200d}",
            "👨",
        ),
        ("👬", "men holding hands", "👨", "🤝\u{200d}", "👨"),
        ("👭", "women holding hands", "👩", "🤝\u{200d}", "👩"),
        (
            "🧑\u{200d}🤝\u{200d}🧑",
            "people holding hands",
            "🧑",
            "🤝\u{200d}",
            "🧑",
        ),
        ("💑", "couple with a heart", "🧑", "❤️\u{200d}", "🧑"),
        ("💏", "couple kissing", "🧑", "❤️\u{200d}💋\u{200d}", "🧑"),
        (
            "👩\u{200d}❤️\u{200d}👨",
            "woman and man with a heart",
            "👩",
            "❤️\u{200d}",
            "👨",
        ),
        (
            "👨\u{200d}❤️\u{200d}👨",
            "men with a heart",
            "👨",
            "❤️\u{200d}",
            "👨",
        ),
        (
            "👩\u{200d}❤️\u{200d}👩",
            "women with a heart",
            "👩",
            "❤️\u{200d}",
            "👩",
        ),
        (
            "👩\u{200d}❤️\u{200d}💋\u{200d}👨",
            "woman and man kissing",
            "👩",
            "❤️\u{200d}💋\u{200d}",
            "👨",
        ),
        (
            "👨\u{200d}❤️\u{200d}💋\u{200d}👨",
            "men kissing",
            "👨",
            "❤️\u{200d}💋\u{200d}",
            "👨",
        ),
        (
            "👩\u{200d}❤️\u{200d}💋\u{200d}👩",
            "women kissing",
            "👩",
            "❤️\u{200d}💋\u{200d}",
            "👩",
        ),
    ] {
        let mut item = entry(symbol, name, 1, "love together relationship friendship");
        for left in 1..=5 {
            for right in 1..=5 {
                let emoji = if left == right && symbol.chars().count() == 1 {
                    toned(symbol, left)
                } else {
                    format!(
                        "{}\u{200d}{middle}{}",
                        toned(first, left),
                        toned(last, right)
                    )
                };
                item.skins.push(ReactionEmojiVariant {
                    emoji,
                    name: format!(
                        "{name}, {}, {}",
                        TONE_NAMES[usize::from(left - 1)],
                        TONE_NAMES[usize::from(right - 1)]
                    ),
                    tone: vec![left, right],
                });
            }
        }
        entries.push(item);
    }
}

fn add_families(entries: &mut Vec<ReactionEmoji>) {
    for (parents, names) in [
        ("👨\u{200d}👩", "mother and father"),
        ("👨\u{200d}👨", "two fathers"),
        ("👩\u{200d}👩", "two mothers"),
        ("👨", "father"),
        ("👩", "mother"),
    ] {
        for (children, label) in [
            ("👦", "son"),
            ("👧", "daughter"),
            ("👧\u{200d}👦", "daughter and son"),
            ("👦\u{200d}👦", "sons"),
            ("👧\u{200d}👧", "daughters"),
        ] {
            entries.push(entry(
                format!("{parents}\u{200d}{children}"),
                format!("family with {names} and {label}"),
                1,
                "family parent child children",
            ));
        }
    }
    for (parents, label) in [("🧑", "one adult"), ("🧑\u{200d}🧑", "two adults")] {
        for (children, name) in [("🧒", "one child"), ("🧒\u{200d}🧒", "two children")] {
            entries.push(entry(
                format!("{parents}\u{200d}{children}"),
                format!("family with {label} and {name}"),
                1,
                "family parent children",
            ));
        }
    }
}

fn add_flags(entries: &mut Vec<ReactionEmoji>) {
    let letters: Vec<_> = "🇦🇧🇨🇩🇪🇫🇬🇭🇮🇯🇰🇱🇲🇳🇴🇵🇶🇷🇸🇹🇺🇻🇼🇽🇾🇿".chars().collect();
    for &(code, name) in data::FLAGS {
        let emoji: String = code
            .bytes()
            .map(|byte| letters[usize::from(byte - b'A')])
            .collect();
        entries.push(entry(emoji, format!("{name} flag"), 9, code));
    }
    for (emoji, name) in [
        (
            "🏴\u{e0067}\u{e0062}\u{e0065}\u{e006e}\u{e0067}\u{e007f}",
            "England",
        ),
        (
            "🏴\u{e0067}\u{e0062}\u{e0073}\u{e0063}\u{e0074}\u{e007f}",
            "Scotland",
        ),
        (
            "🏴\u{e0067}\u{e0062}\u{e0077}\u{e006c}\u{e0073}\u{e007f}",
            "Wales",
        ),
    ] {
        entries.push(entry(emoji, format!("{name} flag"), 9, "UK Britain"));
    }
}
