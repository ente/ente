use std::{
    collections::{HashMap, HashSet},
    fs,
    sync::Mutex,
};

use html_escape::decode_html_entities;
use once_cell::sync::Lazy;
use plsfix::fix_text;
use regex::Regex;

use crate::ml::error::{MlError, MlResult};

use super::CLIP_TEXT_TOKEN_COUNT;

const BPE_MERGES_END_EXCLUSIVE: usize = 49152 - 256 - 2 + 1;

static TOKEN_PATTERN: Lazy<Regex> = Lazy::new(|| {
    Regex::new(
        // Keep this aligned with MobileCLIP's Python tokenizer path
        // (open_clip SimpleTokenizer), including Unicode token classes.
        r"(?i)<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+",
    )
    .expect("valid clip tokenizer regex")
});

static WHITESPACE_PATTERN: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"\s+").expect("valid whitespace regex"));

struct TokenizerState {
    vocab_path: String,
    tokenizer: ClipTextTokenizer,
}

static TOKENIZER_STATE: Lazy<Mutex<Option<TokenizerState>>> = Lazy::new(|| Mutex::new(None));

pub(crate) fn tokenize_clip_text(text: &str, vocab_path: &str) -> MlResult<Vec<i32>> {
    let mut state = match TOKENIZER_STATE.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            let mut guard = poisoned.into_inner();
            *guard = None;
            guard
        }
    };

    let needs_reload = match state.as_ref() {
        Some(existing) => existing.vocab_path != vocab_path,
        None => true,
    };

    if needs_reload {
        let tokenizer = ClipTextTokenizer::from_vocab_path(vocab_path)?;
        *state = Some(TokenizerState {
            vocab_path: vocab_path.to_string(),
            tokenizer,
        });
    }

    let tokenizer = state
        .as_mut()
        .ok_or_else(|| MlError::Runtime("clip tokenizer state unavailable".to_string()))?;
    tokenizer.tokenizer.tokenize(text)
}

struct ClipTextTokenizer {
    byte_encoder: HashMap<u8, String>,
    encoder: HashMap<String, i32>,
    bpe_ranks: HashMap<(String, String), usize>,
    cache: HashMap<String, String>,
    sot: i32,
    eot: i32,
}

impl ClipTextTokenizer {
    fn from_vocab_path(vocab_path: &str) -> MlResult<Self> {
        let vocabulary = fs::read_to_string(vocab_path)
            .map_err(|e| MlError::Runtime(format!("failed to read clip vocab file: {e}")))?;
        Self::from_vocabulary(&vocabulary)
    }

    fn from_vocabulary(vocabulary: &str) -> MlResult<Self> {
        let (byte_encoder, byte_encoder_values) = bytes_to_unicode()?;

        let split = vocabulary.split('\n').collect::<Vec<_>>();
        if split.len() < BPE_MERGES_END_EXCLUSIVE {
            return Err(MlError::Runtime(format!(
                "invalid clip vocab: expected at least {BPE_MERGES_END_EXCLUSIVE} lines, got {}",
                split.len()
            )));
        }
        let merges_slice = &split[1..BPE_MERGES_END_EXCLUSIVE];

        let mut merges = Vec::<(String, String)>::new();
        for merge in merges_slice {
            let mut parts = merge.split_whitespace();
            let Some(first) = parts.next() else {
                continue;
            };
            let Some(second) = parts.next() else {
                continue;
            };
            merges.push((first.to_string(), second.to_string()));
        }

        let mut vocab = byte_encoder_values;
        let with_suffix = vocab
            .iter()
            .map(|value| format!("{value}</w>"))
            .collect::<Vec<_>>();
        vocab.extend(with_suffix);
        for (first, second) in &merges {
            vocab.push(format!("{first}{second}"));
        }
        vocab.push("<|startoftext|>".to_string());
        vocab.push("<|endoftext|>".to_string());

        let encoder = vocab
            .into_iter()
            .enumerate()
            .map(|(index, token)| (token, index as i32))
            .collect::<HashMap<_, _>>();

        let mut bpe_ranks = HashMap::with_capacity(merges.len());
        for (index, merge) in merges.into_iter().enumerate() {
            bpe_ranks.insert(merge, index);
        }

        let sot = *encoder
            .get("<|startoftext|>")
            .ok_or_else(|| MlError::Runtime("missing start token in vocab".to_string()))?;
        let eot = *encoder
            .get("<|endoftext|>")
            .ok_or_else(|| MlError::Runtime("missing end token in vocab".to_string()))?;

        let cache = HashMap::from([
            ("<|startoftext|>".to_string(), "<|startoftext|>".to_string()),
            ("<|endoftext|>".to_string(), "<|endoftext|>".to_string()),
        ]);

        Ok(Self {
            byte_encoder,
            encoder,
            bpe_ranks,
            cache,
            sot,
            eot,
        })
    }

    fn tokenize(&mut self, text: &str) -> MlResult<Vec<i32>> {
        let encoded = self.encode(text)?;
        let max_text_tokens = CLIP_TEXT_TOKEN_COUNT - 2;
        let truncated_len = encoded.len().min(max_text_tokens);

        let mut tokens = Vec::with_capacity(CLIP_TEXT_TOKEN_COUNT);
        tokens.push(self.sot);
        tokens.extend_from_slice(&encoded[..truncated_len]);
        tokens.push(self.eot);
        while tokens.len() < CLIP_TEXT_TOKEN_COUNT {
            tokens.push(0);
        }
        Ok(tokens)
    }

    fn encode(&mut self, text: &str) -> MlResult<Vec<i32>> {
        let mut bpe_tokens = Vec::<i32>::new();
        let clean_text = whitespace_clean(&basic_clean(text)).to_lowercase();
        for matched in TOKEN_PATTERN.find_iter(&clean_text) {
            let mut token = String::new();
            for byte in matched.as_str().as_bytes() {
                let value = self.byte_encoder.get(byte).ok_or_else(|| {
                    MlError::Runtime(format!("missing byte encoding for byte {byte}"))
                })?;
                token.push_str(value);
            }

            let bpe = self.bpe(&token);
            for bpe_token in bpe.split(' ') {
                let token_id = self.encoder.get(bpe_token).ok_or_else(|| {
                    MlError::Runtime(format!("missing BPE token in encoder: {bpe_token}"))
                })?;
                bpe_tokens.push(*token_id);
            }
        }
        Ok(bpe_tokens)
    }

    fn bpe(&mut self, token: &str) -> String {
        if let Some(cached) = self.cache.get(token) {
            return cached.clone();
        }

        let mut word = token.chars().map(|ch| ch.to_string()).collect::<Vec<_>>();
        if word.is_empty() {
            return String::new();
        }
        let last = word.len() - 1;
        word[last] = format!("{}{}", word[last], "</w>");

        let mut pairs = get_pairs(&word);
        if pairs.is_empty() {
            return format!("{token}</w>");
        }

        loop {
            let mut bigram = pairs[0].clone();
            for pair in &pairs {
                let rank1 = self.bpe_ranks.get(pair).copied().unwrap_or(usize::MAX);
                let rank2 = self.bpe_ranks.get(&bigram).copied().unwrap_or(usize::MAX);
                if rank1 < rank2 {
                    bigram = pair.clone();
                }
            }

            if !self.bpe_ranks.contains_key(&bigram) {
                break;
            }

            let first = &bigram.0;
            let second = &bigram.1;
            let mut new_word = Vec::<String>::new();
            let mut i = 0usize;
            while i < word.len() {
                let j = index_of(&word[i..], first);
                let Some(j) = j else {
                    new_word.extend(word[i..].iter().cloned());
                    break;
                };

                new_word.extend(word[i..(i + j)].iter().cloned());
                i += j;

                if word[i] == *first && i < word.len() - 1 && word[i + 1] == *second {
                    new_word.push(format!("{first}{second}"));
                    i += 2;
                } else {
                    new_word.push(word[i].clone());
                    i += 1;
                }
            }

            word = new_word;
            if word.len() == 1 {
                break;
            }
            pairs = get_pairs(&word);
        }

        let word_str = word.join(" ");
        self.cache.insert(token.to_string(), word_str.clone());
        word_str
    }
}

fn basic_clean(text: &str) -> String {
    let fixed = fix_text(text, None);
    let decoded_once = decode_html_entities(&fixed).to_string();
    let decoded_twice = decode_html_entities(&decoded_once).to_string();
    decoded_twice.trim().to_string()
}

fn whitespace_clean(text: &str) -> String {
    let replaced = WHITESPACE_PATTERN.replace_all(text, " ");
    replaced.trim().to_string()
}

fn get_pairs(word: &[String]) -> Vec<(String, String)> {
    if word.len() < 2 {
        return Vec::new();
    }
    let mut seen = HashSet::<(String, String)>::new();
    let mut pairs = Vec::<(String, String)>::new();
    let mut previous = word[0].clone();
    for current in word.iter().skip(1) {
        let pair = (previous.clone(), current.clone());
        if seen.insert(pair.clone()) {
            pairs.push(pair);
        }
        previous = current.clone();
    }
    pairs
}

fn index_of(values: &[String], needle: &str) -> Option<usize> {
    values.iter().position(|value| value == needle)
}

fn bytes_to_unicode() -> MlResult<(HashMap<u8, String>, Vec<String>)> {
    let mut bs = Vec::<u32>::new();
    for code in b'!'..=b'~' {
        bs.push(code as u32);
    }
    for code in ('¡' as u32)..=('¬' as u32) {
        bs.push(code);
    }
    for code in ('®' as u32)..=('ÿ' as u32) {
        bs.push(code);
    }

    let mut cs = bs.clone();
    let mut n = 0u32;
    for b in 0u32..256u32 {
        if !bs.contains(&b) {
            bs.push(b);
            cs.push(256 + n);
            n += 1;
        }
    }

    let mut ds = Vec::<String>::with_capacity(cs.len());
    for code in cs {
        let ch = char::from_u32(code).ok_or_else(|| {
            MlError::Runtime(format!(
                "invalid unicode scalar generated for byte map: {code}"
            ))
        })?;
        ds.push(ch.to_string());
    }

    let mut byte_encoder = HashMap::<u8, String>::new();
    for (index, byte_value) in bs.iter().enumerate() {
        let key = *byte_value as u8;
        byte_encoder.insert(key, ds[index].clone());
    }

    Ok((byte_encoder, ds))
}

#[cfg(test)]
mod tests {
    use super::{ClipTextTokenizer, TOKEN_PATTERN, basic_clean, whitespace_clean};

    fn cleaned_tokens(text: &str) -> Vec<String> {
        let clean_text = whitespace_clean(&basic_clean(text)).to_lowercase();
        TOKEN_PATTERN
            .find_iter(&clean_text)
            .map(|matched| matched.as_str().to_string())
            .collect()
    }

    #[test]
    fn basic_clean_matches_ftfy_style_repairs() {
        assert_eq!(basic_clean(" âœ” No problems "), "✔ No problems");
        assert_eq!(basic_clean("Tom &amp;amp; Jerry"), "Tom & Jerry");
    }

    #[test]
    fn token_pattern_matches_mobileclip_python_behavior() {
        assert_eq!(
            cleaned_tokens("İstanbul"),
            vec![
                "i".to_string(),
                "\u{307}".to_string(),
                "stanbul".to_string(),
            ],
        );
        assert_eq!(cleaned_tokens("ſtyle"), vec!["ſtyle".to_string()]);
        assert_eq!(cleaned_tokens("Kelvin"), vec!["kelvin".to_string()]);
        assert_eq!(
            cleaned_tokens("1234"),
            vec![
                "1".to_string(),
                "2".to_string(),
                "3".to_string(),
                "4".to_string(),
            ],
        );
    }

    #[test]
    fn rejects_incomplete_bpe_vocabulary_file() {
        let truncated_vocab = "#version: 0.2\na b";
        let err = match ClipTextTokenizer::from_vocabulary(truncated_vocab) {
            Ok(_) => panic!("expected incomplete vocab to fail"),
            Err(err) => err,
        };
        assert!(
            err.to_string().contains("invalid clip vocab"),
            "unexpected error: {err}",
        );
    }
}
