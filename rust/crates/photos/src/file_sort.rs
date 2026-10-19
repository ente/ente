use icu_collator::options::{AlternateHandling, CaseLevel, CollatorOptions, Strength};
use icu_collator::preferences::CollationNumericOrdering;
use icu_collator::{Collator, CollatorBorrowed, CollatorPreferences};
use icu_locale_core::Locale;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Filename and file ID counts differ")]
    MismatchedEntries,
    #[error("Too many filenames to sort")]
    TooManyFiles,
    #[error("Invalid filename sorting locale: {0}")]
    InvalidLocale(String),
    #[error("Unable to initialize filename comparison: {0}")]
    Collator(String),
}

pub fn sorted_filename_indices(
    names: &[String],
    file_ids: &[i64],
    locale: &str,
    ascending: bool,
) -> Result<Vec<u32>, Error> {
    if names.len() != file_ids.len() {
        return Err(Error::MismatchedEntries);
    }
    let count = u32::try_from(names.len()).map_err(|_| Error::TooManyFiles)?;
    let collator = filename_collator(locale)?;
    // Cache ICU's collation work for the lifetime of this sort.
    let keys: Vec<Vec<u8>> = names
        .iter()
        .map(|name| {
            let mut key = Vec::new();
            let Ok(()) = collator.write_sort_key_to(name, &mut key);
            key
        })
        .collect();
    let mut indices: Vec<u32> = (0..count).collect();
    indices.sort_unstable_by(|&left, &right| {
        let first = left as usize;
        let second = right as usize;
        let result = keys[first].cmp(&keys[second]);
        let result = if ascending { result } else { result.reverse() };
        result
            .then_with(|| file_ids[first].cmp(&file_ids[second]))
            .then_with(|| left.cmp(&right))
    });
    Ok(indices)
}

fn filename_collator(locale: &str) -> Result<CollatorBorrowed<'static>, Error> {
    let locale = locale
        .parse::<Locale>()
        .map_err(|error| Error::InvalidLocale(error.to_string()))?;
    let mut preferences: CollatorPreferences = locale.into();
    preferences.numeric_ordering = Some(CollationNumericOrdering::True);
    let mut options = CollatorOptions::default();
    options.strength = Some(Strength::Primary);
    options.case_level = Some(CaseLevel::Off);
    options.alternate_handling = Some(AlternateHandling::NonIgnorable);
    Collator::try_new(preferences, options).map_err(|error| Error::Collator(error.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn indices(names: &[&str], ids: &[i64], locale: &str, ascending: bool) -> Vec<u32> {
        let names = names
            .iter()
            .map(|name| (*name).to_owned())
            .collect::<Vec<_>>();
        sorted_filename_indices(&names, ids, locale, ascending)
            .unwrap_or_else(|error| panic!("{error}"))
    }

    #[test]
    fn numeric_names_keep_ascending_ids_in_both_directions() {
        let names = ["IMG10.jpg", "img02.JPG", "IMG2.jpg", "IMG2.heic"];
        let ids = [30, 20, 10, 40];
        assert_eq!(indices(&names, &ids, "en-US", true), [3, 2, 1, 0]);
        assert_eq!(indices(&names, &ids, "en-US", false), [0, 2, 1, 3]);
    }

    #[test]
    fn collation_uses_the_requested_locale() {
        let names = ["z.jpg", "ä.jpg", "a.jpg"];
        let ids = [1, 2, 3];
        assert_eq!(indices(&names, &ids, "de-DE", true), [1, 2, 0]);
        assert_eq!(indices(&names, &ids, "sv-SE", true), [2, 0, 1]);
        assert_eq!(
            indices(&["café.jpg", "CAFE.jpg"], &[2, 1], "en-US", true),
            [1, 0]
        );
    }

    #[test]
    fn sort_keys_match_direct_comparison_for_numeric_and_unicode_names() {
        let names = [
            "IMG0.jpg".to_owned(),
            "IMG000.jpg".to_owned(),
            format!("IMG{}.jpg", "9".repeat(254)),
            format!("IMG1{}.jpg", "0".repeat(254)),
            "IMG10_2.jpg".to_owned(),
            "IMG2_10.jpg".to_owned(),
            "١2.jpg".to_owned(),
            "١02.jpg".to_owned(),
            "café.jpg".to_owned(),
            "cafe\u{301}.jpg".to_owned(),
            "ä.jpg".to_owned(),
            "z.jpg".to_owned(),
            "I.jpg".to_owned(),
            "ı.jpg".to_owned(),
        ];
        let ids: Vec<i64> = (0..names.len() as i64).collect();
        for locale in ["en-US", "sv-SE", "tr-TR"] {
            let collator = filename_collator(locale).unwrap_or_else(|error| panic!("{error}"));
            for ascending in [true, false] {
                let mut expected: Vec<u32> = (0..names.len() as u32).collect();
                expected.sort_unstable_by(|&a, &b| {
                    let comparison = collator.compare(&names[a as usize], &names[b as usize]);
                    let comparison = if ascending {
                        comparison
                    } else {
                        comparison.reverse()
                    };
                    comparison.then_with(|| a.cmp(&b))
                });
                let actual = sorted_filename_indices(&names, &ids, locale, ascending)
                    .unwrap_or_else(|error| panic!("{error}"));
                assert_eq!(actual, expected, "{locale}, ascending={ascending}");
            }
        }
    }
}
