use std::cmp::Reverse;

use crate::rewind::library::{Library, YearFile};
use crate::rewind::ranking::Ranking;
use crate::rewind::report::Warp;

const WARP_PANELS: usize = 240;
const WARP_MINIMUM_PANELS: usize = 48;

pub(in crate::rewind) fn warp(
    library: &Library<'_>,
    ranking: &Ranking<'_>,
    year_photos: &[i64],
) -> Option<Warp> {
    let first = library
        .taken()
        .filter(|file| ranking.is_showable(file))
        .min_by_key(|file| (file.local_time, file.id()))?;
    let mut pool: Vec<&YearFile> = year_photos
        .iter()
        .filter(|&&id| id != first.id())
        .filter_map(|&id| library.get(id))
        .collect();
    if pool.len() + 1 < WARP_MINIMUM_PANELS {
        return None;
    }
    pool.sort_by_key(|file| (Reverse(file.local_time), file.id()));
    let wanted = WARP_PANELS - 1;
    let panels: Vec<&YearFile> = if pool.len() <= wanted {
        pool
    } else {
        (0..wanted)
            .map(|panel| pool[panel * (pool.len() - 1) / (wanted - 1)])
            .collect()
    };
    Some(Warp {
        file_ids: panels
            .into_iter()
            .chain(std::iter::once(first))
            .map(YearFile::id)
            .collect(),
    })
}

#[cfg(test)]
mod tests {
    use crate::rewind::chapters::year_photos;
    use crate::rewind::fixtures::{daily_photos, request};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;

    use super::warp;

    #[test]
    fn the_tunnel_runs_from_the_newest_photo_back_to_the_first() {
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 300);
        files[0].is_junk = true;
        files[299].is_favourite = true;
        let year = request(files);
        let library = Library::of_year(&year).unwrap();
        let ranking = Ranking::new(None, None);

        let tunnel = warp(&library, &ranking, &year_photos(&library, &ranking)).unwrap();

        assert_eq!(tunnel.file_ids.len(), 240);
        assert_eq!(tunnel.file_ids.first(), Some(&300));
        assert_eq!(tunnel.file_ids.last(), Some(&2));
        assert!(tunnel.file_ids.windows(2).all(|pair| pair[0] > pair[1]));
    }

    #[test]
    fn a_small_year_has_no_tunnel() {
        let small = request(daily_photos(1, "2026-01-01T10:00:00", 47));
        let library = Library::of_year(&small).unwrap();
        let ranking = Ranking::new(None, None);
        assert_eq!(
            warp(&library, &ranking, &year_photos(&library, &ranking)),
            None
        );
    }
}
