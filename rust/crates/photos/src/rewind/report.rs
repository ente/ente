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
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Totals {
    pub files: u32,
    pub top_percent: Option<u32>,
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
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Favourites {
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WeeklyHabit {
    pub weekday: u32,
    pub hour: u32,
    pub percent: u32,
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
        Ok(Self {
            totals: chapters::totals(library),
            colour: clip
                .as_ref()
                .and_then(|clip| chapters::colour(library, clip, &ranking)),
            places: cities.and_then(|cities| chapters::places(library, cities, &ranking)),
            spots: chapters::spots(library, &ranking),
            people_race: ml_people
                .and_then(|people| chapters::people_race(request, library, people, &ranking)),
            busiest_day: chapters::busiest_day(library, &ranking),
            new_faces: ml_people
                .and_then(|people| chapters::new_faces(request, library, people, &ranking)),
            favourites: chapters::favourites(library, &ranking),
            weekly_habit: chapters::weekly_habit(library),
            crowd_favourite: chapters::crowd_favourite(library, &ranking),
            badge: chapters::badge(request, library, ml_people, clip.as_ref()),
            scrapbook: chapters::scrapbook(library, &ranking),
        })
    }

    pub(super) fn is_empty(&self) -> bool {
        *self == Self::default()
    }

    pub(super) fn shows_ml_chapters(&self) -> bool {
        self.colour.is_some() || self.people_race.is_some() || self.new_faces.is_some()
    }
}
