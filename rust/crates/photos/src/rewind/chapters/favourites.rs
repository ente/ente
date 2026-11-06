use super::count;
use crate::rewind::library::Library;
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::Favourites;

const FAVOURITES_MINIMUM: usize = 3;
const FAVOURITES_CANDIDATES: usize = 12;

pub(in crate::rewind) fn favourites(
    library: &Library<'_>,
    ranking: &Ranking<'_>,
) -> Option<Favourites> {
    let favourites: Vec<_> = library
        .eligible()
        .filter(|file| file.file.is_favourite)
        .collect();
    if favourites.len() < FAVOURITES_MINIMUM {
        return None;
    }
    let file_ids = ranking.best(
        favourites.iter().copied(),
        Spread::Days,
        FAVOURITES_CANDIDATES,
    );
    (file_ids.len() >= FAVOURITES_MINIMUM).then(|| Favourites {
        photo_count: count(favourites.len()),
        file_ids,
    })
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{daily_photos, request};
    use crate::rewind::input::{RewindFileType, RewindVisibility};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;
    use crate::rewind::report::Favourites;

    use super::favourites;

    #[test]
    fn favourites_count_archived_ones_but_only_show_visible_photos() {
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 8);
        for file in &mut files[..6] {
            file.is_favourite = true;
        }
        files[0].visibility = RewindVisibility::Archived;
        files[1].file_type = RewindFileType::Video;
        files[2].visibility = RewindVisibility::Hidden;
        files[3].like_count = 4;
        let favourites_request = request(files);
        let library = Library::of_year(&favourites_request).unwrap();

        assert_eq!(
            favourites(&library, &Ranking::new(None, None)),
            Some(Favourites {
                photo_count: 5,
                file_ids: vec![4, 5, 6],
            })
        );
    }

    #[test]
    fn too_few_showable_favourites_or_offline_mode_skip_the_chapter() {
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 8);
        for file in &mut files[..3] {
            file.is_favourite = true;
        }
        files[0].visibility = RewindVisibility::Archived;
        let archived = request(files);
        let library = Library::of_year(&archived).unwrap();
        assert_eq!(favourites(&library, &Ranking::new(None, None)), None);

        let mut offline = request(daily_photos(1, "2026-01-01T10:00:00", 8));
        offline.local_gallery_mode = true;
        let library = Library::of_year(&offline).unwrap();
        assert_eq!(favourites(&library, &Ranking::new(None, None)), None);
    }
}
