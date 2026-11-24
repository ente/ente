use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use super::Result;
use super::chapters;
use super::clip::Clip;
use super::input::RewindRequest;
use super::library::Library;
use super::people::People;
use super::ranking::Ranking;
use crate::memories::{CityLookup, ClipVectors};
use crate::ml_db::try_file_id_from_face_id;
use crate::ml_store::{FillState, Index, MlStore};

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewindReport {
    pub totals: Option<Totals>,
    pub colour: Option<ColourOfTheYear>,
    pub places: Option<Places>,
    pub spots: Option<Spots>,
    pub people_race: Option<PeopleRace>,
    pub busiest_day: Option<BusiestDay>,
    pub new_faces: Option<NewFaces>,
    pub favourites: Option<Favourites>,
    pub weekly_habit: Option<WeeklyHabit>,
    pub crowd_favourite: Option<CrowdFavourite>,
    pub badge: Option<Badge>,
    pub scrapbook: Option<Scrapbook>,
    pub finale: Option<Finale>,
    pub tour: Option<Tour>,
    pub globe: Option<Globe>,
    pub mosaic: Option<Mosaic>,
    pub warp: Option<Warp>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Totals {
    pub files: u32,
    pub top_percent: Option<u32>,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ColourOfTheYear {
    pub colour: RewindColour,
    pub percent: u32,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RewindColour {
    CherryBomb,
    TangerinePop,
    LemonDrop,
    Pistachio,
    BerryBlue,
    LavenderFizz,
    Bubblegum,
    HotCocoa,
    Marshmallow,
    MidnightCola,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Places {
    pub cities: Vec<RewindCity>,
    pub distance_km: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewindCity {
    pub name: String,
    pub country: String,
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Spots {
    pub spot_count: u32,
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PeopleRace {
    pub people: Vec<RacePerson>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RacePerson {
    pub person_id: String,
    pub photo_count: u32,
    pub monthly_counts: Vec<u32>,
    pub face_ids: Vec<String>,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BusiestDay {
    pub month: u32,
    pub day: u32,
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NewFaces {
    pub count: u32,
    pub faces: Vec<NewFace>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NewFace {
    pub person_id: Option<String>,
    pub cluster_id: Option<String>,
    pub face_ids: Vec<String>,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Favourites {
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WeeklyHabit {
    pub weekday: u32,
    pub hour: u32,
    pub percent: u32,
    pub hour_file_ids: Vec<i64>,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CrowdFavourite {
    pub photos: Vec<LikedPhoto>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LikedPhoto {
    pub file_id: i64,
    pub like_count: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Badge {
    pub id: RewindBadge,
    pub value: Option<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RewindBadge {
    SunChaser,
    ConsistencyChamp,
    UnpaidPhotographer,
    MainCharacter,
    EarlyBird,
    NightOwl,
    WeekendStar,
    Pawparazzi,
    Foodie,
    PlantParent,
    BuildingBuff,
    ScreenshotCollector,
    HobbyHopper,
    IndoorKid,
    OutOfOffice,
    FullThrottle,
    EventHopper,
    AlwaysRolling,
    FitCheck,
    ArtLover,
    LimitedEdition,
    HappySnapper,
    OpeningCredits,
    GuestStar,
    MixedBag,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Scrapbook {
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Finale {
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tour {
    pub stops: Vec<TourStop>,
    pub city_count: u32,
    pub country_count: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TourStop {
    pub city: String,
    pub country_code: String,
    pub month: u32,
    pub day: u32,
    pub photo_count: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Globe {
    pub rows: Vec<u32>,
    pub land: Vec<u8>,
    pub visited: Vec<u8>,
    pub places: Vec<GlobePlace>,
    pub route: Vec<u32>,
    pub distance_km: u32,
    pub city_count: u32,
    pub country_count: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GlobePlace {
    pub name: String,
    pub country_code: String,
    pub latitude_microdegrees: i32,
    pub longitude_microdegrees: i32,
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Mosaic {
    pub file_ids: Vec<i64>,
    pub me_person_id: Option<String>,
    pub me_face_ids: Vec<String>,
    pub top_person_id: Option<String>,
    pub top_face_ids: Vec<String>,
    pub cluster_id: Option<String>,
    #[serde(default)]
    pub cluster_face_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Warp {
    pub file_ids: Vec<i64>,
}

impl RewindReport {
    pub(super) fn of(
        request: &RewindRequest,
        library: &Library<'_>,
        store: Option<&MlStore>,
        ml_chapters: bool,
        cities: Option<&dyn CityLookup>,
    ) -> Result<Self> {
        let people = store
            .map(|store| People::load(request, library, store))
            .transpose()?;
        let ml_store = store.filter(|_| ml_chapters);
        let clip = ml_store
            .map(|store| Clip::load(library, store))
            .transpose()?;
        let vectors = ml_store.filter(|store| {
            store
                .fill_state(Index::Clip)
                .is_ok_and(|state| state == FillState::Filled)
        });
        let ranking = Ranking::new(
            people.as_ref(),
            vectors.map(|store| store as &dyn ClipVectors),
        );
        let ml_people = people.as_ref().filter(|_| ml_chapters);
        let located_cities = cities.and_then(|cities| chapters::cities(library, cities));
        let year_photos = chapters::year_photos(library, &ranking);
        Ok(Self {
            totals: chapters::totals(library, &ranking),
            colour: clip
                .as_ref()
                .and_then(|clip| chapters::colour(library, clip, &ranking)),
            places: located_cities
                .as_deref()
                .and_then(|cities| chapters::places(cities, &ranking)),
            spots: chapters::spots(library, &ranking),
            people_race: ml_people
                .and_then(|people| chapters::people_race(request, library, people, &ranking)),
            busiest_day: chapters::busiest_day(library, &ranking),
            new_faces: ml_people
                .and_then(|people| chapters::new_faces(request, library, people, &ranking)),
            favourites: chapters::favourites(library, &ranking),
            weekly_habit: chapters::weekly_habit(library, &ranking),
            crowd_favourite: chapters::crowd_favourite(library, &ranking),
            badge: chapters::badge(request, library, ml_people, clip.as_ref()),
            scrapbook: chapters::scrapbook(library, &ranking),
            finale: chapters::finale(library, &ranking),
            tour: located_cities
                .as_deref()
                .and_then(|cities| chapters::tour(cities, &ranking)),
            globe: located_cities
                .as_deref()
                .zip(cities)
                .and_then(|(located, lookup)| chapters::globe(located, lookup, &ranking)),
            mosaic: chapters::mosaic(request, library, ml_people, &ranking, &year_photos),
            warp: chapters::warp(library, &ranking, &year_photos),
        })
    }

    pub fn file_ids(&self) -> Vec<i64> {
        let Self {
            totals,
            colour,
            places,
            spots,
            people_race,
            busiest_day,
            new_faces,
            favourites,
            weekly_habit,
            crowd_favourite,
            badge: _,
            scrapbook,
            finale,
            tour: _,
            globe,
            mosaic,
            warp,
        } = self;
        let face_ids = std::iter::empty()
            .chain(
                people_race
                    .iter()
                    .flat_map(|race| &race.people)
                    .flat_map(|person| &person.face_ids),
            )
            .chain(
                new_faces
                    .iter()
                    .flat_map(|new_faces| &new_faces.faces)
                    .flat_map(|face| &face.face_ids),
            )
            .chain(mosaic.iter().flat_map(|mosaic| {
                mosaic
                    .me_face_ids
                    .iter()
                    .chain(&mosaic.top_face_ids)
                    .chain(&mosaic.cluster_face_ids)
            }));
        let ids: BTreeSet<i64> = std::iter::empty()
            .chain(totals.iter().flat_map(|totals| &totals.file_ids))
            .chain(colour.iter().flat_map(|colour| &colour.file_ids))
            .chain(
                places
                    .iter()
                    .flat_map(|places| &places.cities)
                    .flat_map(|city| &city.file_ids),
            )
            .chain(spots.iter().flat_map(|spots| &spots.file_ids))
            .chain(
                people_race
                    .iter()
                    .flat_map(|race| &race.people)
                    .flat_map(|person| &person.file_ids),
            )
            .chain(busiest_day.iter().flat_map(|day| &day.file_ids))
            .chain(
                new_faces
                    .iter()
                    .flat_map(|new_faces| &new_faces.faces)
                    .flat_map(|face| &face.file_ids),
            )
            .chain(
                favourites
                    .iter()
                    .flat_map(|favourites| &favourites.file_ids),
            )
            .chain(
                weekly_habit
                    .iter()
                    .flat_map(|habit| habit.hour_file_ids.iter().chain(&habit.file_ids)),
            )
            .chain(
                crowd_favourite
                    .iter()
                    .flat_map(|crowd| &crowd.photos)
                    .map(|photo| &photo.file_id),
            )
            .chain(scrapbook.iter().flat_map(|scrapbook| &scrapbook.file_ids))
            .chain(finale.iter().flat_map(|finale| &finale.file_ids))
            .chain(
                globe
                    .iter()
                    .flat_map(|globe| &globe.places)
                    .flat_map(|place| &place.file_ids),
            )
            .chain(mosaic.iter().flat_map(|mosaic| &mosaic.file_ids))
            .chain(warp.iter().flat_map(|warp| &warp.file_ids))
            .copied()
            .chain(
                face_ids
                    .map(String::as_str)
                    .filter_map(try_file_id_from_face_id),
            )
            .collect();
        ids.into_iter().collect()
    }

    pub(super) fn is_empty(&self) -> bool {
        *self == Self::default()
    }

    pub(super) fn shows_ml_chapters(&self) -> bool {
        self.colour.is_some()
            || self.people_race.is_some()
            || self.new_faces.is_some()
            || self
                .badge
                .is_some_and(|badge| chapters::badge_uses_ml(badge.id))
            || self.mosaic.as_ref().is_some_and(|mosaic| {
                mosaic.me_person_id.is_some()
                    || mosaic.top_person_id.is_some()
                    || mosaic.cluster_id.is_some()
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_ids_cover_every_section_and_face_once_in_order() {
        let report = RewindReport {
            totals: Some(Totals {
                files: 3,
                top_percent: None,
                file_ids: vec![30, 1],
            }),
            colour: Some(ColourOfTheYear {
                colour: RewindColour::BerryBlue,
                percent: 40,
                file_ids: vec![2],
            }),
            places: Some(Places {
                cities: vec![RewindCity {
                    name: "Pune".into(),
                    country: "India".into(),
                    photo_count: 1,
                    file_ids: vec![3],
                }],
                distance_km: 0,
            }),
            spots: Some(Spots {
                spot_count: 1,
                photo_count: 1,
                file_ids: vec![4],
            }),
            people_race: Some(PeopleRace {
                people: vec![RacePerson {
                    person_id: "person".into(),
                    photo_count: 1,
                    monthly_counts: vec![1],
                    face_ids: vec!["99_face".into()],
                    file_ids: vec![5],
                }],
            }),
            busiest_day: Some(BusiestDay {
                month: 1,
                day: 1,
                photo_count: 1,
                file_ids: vec![6],
            }),
            new_faces: Some(NewFaces {
                count: 1,
                faces: vec![NewFace {
                    person_id: None,
                    cluster_id: Some("cluster".into()),
                    face_ids: vec!["98_face".into()],
                    file_ids: vec![7],
                }],
            }),
            favourites: Some(Favourites {
                photo_count: 1,
                file_ids: vec![8],
            }),
            weekly_habit: Some(WeeklyHabit {
                weekday: 1,
                hour: 9,
                percent: 10,
                hour_file_ids: vec![9],
                file_ids: vec![10],
            }),
            crowd_favourite: Some(CrowdFavourite {
                photos: vec![LikedPhoto {
                    file_id: 11,
                    like_count: 2,
                }],
            }),
            badge: Some(Badge {
                id: RewindBadge::MixedBag,
                value: None,
            }),
            scrapbook: Some(Scrapbook { file_ids: vec![12] }),
            finale: Some(Finale { file_ids: vec![13] }),
            tour: None,
            globe: Some(Globe {
                rows: vec![],
                land: vec![],
                visited: vec![],
                places: vec![GlobePlace {
                    name: "Pune".into(),
                    country_code: "IN".into(),
                    latitude_microdegrees: 0,
                    longitude_microdegrees: 0,
                    photo_count: 1,
                    file_ids: vec![14],
                }],
                route: vec![],
                distance_km: 0,
                city_count: 1,
                country_count: 1,
            }),
            mosaic: Some(Mosaic {
                file_ids: vec![15, 1],
                me_person_id: None,
                me_face_ids: vec!["97_face".into()],
                top_person_id: None,
                top_face_ids: vec!["96_face".into()],
                cluster_id: None,
                cluster_face_ids: vec!["95_face".into(), "not a face".into(), "5_face".into()],
            }),
            warp: Some(Warp {
                file_ids: vec![16, 2],
            }),
        };

        assert_eq!(
            report.file_ids(),
            vec![
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 30, 95, 96, 97, 98, 99
            ]
        );
    }

    #[test]
    fn an_empty_report_has_no_file_ids() {
        assert!(RewindReport::default().file_ids().is_empty());
    }
}
