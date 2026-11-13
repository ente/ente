use crate::rewind::library::Library;
use crate::rewind::percentile::top_per_mille;
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::Totals;

const TOTALS_CANDIDATES: usize = 24;

pub(in crate::rewind) fn totals(library: &Library<'_>, ranking: &Ranking<'_>) -> Option<Totals> {
    let files = u32::try_from(library.files().len()).unwrap_or(u32::MAX);
    (files > 0).then(|| Totals {
        files,
        top_per_mille: top_per_mille(files),
        file_ids: ranking.best(library.taken(), Spread::Months, TOTALS_CANDIDATES),
    })
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{photo, request};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;

    use super::totals;

    #[test]
    fn the_totals_photos_sample_every_month_first() {
        let files = (1..=12)
            .flat_map(|month| {
                (0..3).map(move |shot| {
                    photo(
                        100 * i64::from(month) + shot,
                        &format!("2026-{month:02}-0{}T10:00:00", shot + 1),
                    )
                })
            })
            .collect();
        let totals_request = request(files);
        let library = Library::of_year(&totals_request).unwrap();

        let totals = totals(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!(totals.files, 36);
        assert_eq!(totals.file_ids.len(), 24);
        assert_eq!(
            totals.file_ids[..12],
            [
                100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200
            ]
        );
    }
}
