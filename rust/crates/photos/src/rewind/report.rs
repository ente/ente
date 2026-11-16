use serde::{Deserialize, Serialize};

use super::Result;
use super::chapters;
use super::clip::Clip;
use super::input::RewindRequest;
use super::library::Library;
use super::people::People;
use super::ranking::Ranking;
use crate::memories::{CityLookup, ClipVectors};
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
    pub tour: Option<Tour>,
    pub globe: Option<Globe>,
    pub mosaic: Option<Mosaic>,
    pub timelapse: Option<Timelapse>,
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
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Timelapse {
    pub person_id: String,
    pub is_me: bool,
    pub photo_count: u32,
    pub frames: Vec<TimelapseFrame>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Warp {
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TimelapseFrame {
    pub file_id: i64,
    pub month: u32,
    pub day: u32,
    pub left_eye_x: u32,
    pub left_eye_y: u32,
    pub right_eye_x: u32,
    pub right_eye_y: u32,
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
            tour: located_cities
                .as_deref()
                .and_then(|cities| chapters::tour(cities, &ranking)),
            globe: located_cities
                .as_deref()
                .zip(cities)
                .and_then(|(located, lookup)| chapters::globe(located, lookup, &ranking)),
            mosaic: chapters::mosaic(request, library, ml_people, &ranking, &year_photos),
            timelapse: ml_people
                .and_then(|people| chapters::timelapse(request, library, people, &ranking)),
            warp: chapters::warp(library, &ranking, &year_photos),
        })
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
            || self.timelapse.is_some()
            || self.mosaic.as_ref().is_some_and(|mosaic| {
                mosaic.me_person_id.is_some() || mosaic.top_person_id.is_some()
            })
    }
}
