use crate::rewind::library::Library;
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::Scrapbook;

const SCRAPBOOK_MINIMUM_CANDIDATES: usize = 6;
const SCRAPBOOK_CANDIDATES: usize = 12;

pub(in crate::rewind) fn scrapbook(
    library: &Library<'_>,
    ranking: &Ranking<'_>,
) -> Option<Scrapbook> {
    let file_ids = ranking.best(library.taken(), Spread::Months, SCRAPBOOK_CANDIDATES);
    (file_ids.len() >= SCRAPBOOK_MINIMUM_CANDIDATES).then_some(Scrapbook { file_ids })
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{daily_photos, request};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;

    use super::scrapbook;

    #[test]
    fn the_scrapbook_spans_the_months_favourites_first_and_skips_junk() {
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 120);
        files[100].is_favourite = true;
        files[50].like_count = 5;
        for file in &mut files[..10] {
            file.is_junk = true;
        }
        let scrapbook_request = request(files);
        let library = Library::of_year(&scrapbook_request).unwrap();

        let file_ids = scrapbook(&library, &Ranking::new(None, None))
            .unwrap()
            .file_ids;

        assert_eq!(file_ids[..5], [101, 51, 11, 60, 91]);
        assert_eq!(file_ids.len(), 12);

        let small = request(daily_photos(1, "2026-01-01T10:00:00", 5));
        let library = Library::of_year(&small).unwrap();
        assert_eq!(scrapbook(&library, &Ranking::new(None, None)), None);
    }
}
