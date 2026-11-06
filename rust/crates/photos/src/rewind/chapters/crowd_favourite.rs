use std::cmp::Reverse;

use crate::rewind::library::Library;
use crate::rewind::ranking::Ranking;
use crate::rewind::report::{CrowdFavourite, LikedPhoto};

const CROWD_FAVOURITE_MINIMUM_LIKES: u32 = 3;
const CROWD_FAVOURITE_PHOTOS: usize = 5;

pub(in crate::rewind) fn crowd_favourite(
    library: &Library<'_>,
    ranking: &Ranking<'_>,
) -> Option<CrowdFavourite> {
    let mut liked: Vec<_> = library
        .files()
        .iter()
        .filter(|file| file.file.like_count >= CROWD_FAVOURITE_MINIMUM_LIKES)
        .filter(|file| ranking.is_showable(file))
        .collect();
    liked.sort_by_key(|file| {
        (
            Reverse(file.file.like_count),
            file.file.creation_time,
            file.id(),
        )
    });
    let photos: Vec<LikedPhoto> = liked
        .into_iter()
        .take(CROWD_FAVOURITE_PHOTOS)
        .map(|file| LikedPhoto {
            file_id: file.id(),
            like_count: file.file.like_count,
        })
        .collect();
    (!photos.is_empty()).then_some(CrowdFavourite { photos })
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{daily_photos, request};
    use crate::rewind::input::RewindVisibility;
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;
    use crate::rewind::report::LikedPhoto;

    use super::crowd_favourite;

    #[test]
    fn the_most_liked_showable_photos_lead_and_few_likes_never_count() {
        let mut files = daily_photos(1, "2026-02-01T10:00:00", 9);
        for (file, likes) in files.iter_mut().zip([2, 3, 9, 5, 5, 4, 3, 3, 20]) {
            file.like_count = likes;
        }
        files[8].visibility = RewindVisibility::Hidden;
        let liked = request(files);
        let library = Library::of_year(&liked).unwrap();

        let photos = crowd_favourite(&library, &Ranking::new(None, None))
            .unwrap()
            .photos;

        let expected: Vec<LikedPhoto> = [(3, 9), (4, 5), (5, 5), (6, 4), (2, 3)]
            .map(|(file_id, like_count)| LikedPhoto {
                file_id,
                like_count,
            })
            .to_vec();
        assert_eq!(photos, expected);

        let unliked = request(daily_photos(1, "2026-02-01T10:00:00", 9));
        let library = Library::of_year(&unliked).unwrap();
        assert_eq!(crowd_favourite(&library, &Ranking::new(None, None)), None);
    }
}
