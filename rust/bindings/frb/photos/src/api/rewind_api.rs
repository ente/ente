use ente_photos::memories::CityLookup;
use ente_photos::rewind;
pub use ente_photos::rewind::{
    Badge, BusiestDay, ColourOfTheYear, CrowdFavourite, Favourites, LikedPhoto, NewFace, NewFaces,
    PeopleRace, Places, RacePerson, RewindBadge, RewindCity, RewindColour, RewindFile,
    RewindFileType, RewindLocation, RewindPerson, RewindReport, RewindRequest, RewindState,
    RewindStatus, RewindVisibility, Scrapbook, Spots, Totals, WeeklyHabit,
};
use flutter_rust_bridge::frb;

use super::location_api::LocationIndex;
use super::ml_db_api::MlStore;
use crate::frb_generated::RustAutoOpaque;

#[frb]
pub enum RewindError {
    Other { message: String },
}

impl From<rewind::Error> for RewindError {
    fn from(error: rewind::Error) -> Self {
        Self::Other {
            message: ente_core::error::chain(&error),
        }
    }
}

#[frb(mirror(RewindRequest))]
pub struct _RewindRequest {
    pub year: i32,
    pub now: i64,
    pub utc_offset_seconds: i32,
    pub season_start: i64,
    pub installed_at: i64,
    pub local_gallery_mode: bool,
    pub files: Vec<RewindFile>,
    pub people: Vec<RewindPerson>,
    pub me_person_id: Option<String>,
}

#[frb(mirror(RewindFile))]
pub struct _RewindFile {
    pub id: i64,
    pub creation_time: i64,
    pub local_date_time: Option<String>,
    pub utc_offset_seconds: i32,
    pub file_type: RewindFileType,
    pub location: Option<RewindLocation>,
    pub visibility: RewindVisibility,
    pub is_favourite: bool,
    pub is_junk: bool,
    pub is_screenshot: bool,
    pub shared_album_ids: Vec<i64>,
    pub like_count: u32,
}

#[frb(mirror(RewindFileType))]
pub enum _RewindFileType {
    Image,
    Video,
    LivePhoto,
    Other,
}

#[frb(mirror(RewindLocation))]
pub struct _RewindLocation {
    pub latitude: f64,
    pub longitude: f64,
}

#[frb(mirror(RewindVisibility))]
pub enum _RewindVisibility {
    Visible,
    Archived,
    Hidden,
}

#[frb(mirror(RewindPerson))]
pub struct _RewindPerson {
    pub id: String,
    pub is_ignored: bool,
    pub is_hidden_from_memories: bool,
}

#[frb(mirror(RewindState))]
pub struct _RewindState {
    pub year: i32,
    pub version: u32,
    pub computed_at: i64,
    pub local_gallery_mode: bool,
    pub ml_coverage: Option<f32>,
    pub is_final: bool,
    pub status: RewindStatus,
}

#[frb(mirror(RewindStatus))]
pub enum _RewindStatus {
    WaitingForMl,
    NothingToShow,
    Ready { report: Box<RewindReport> },
}

#[frb(mirror(RewindReport))]
pub struct _RewindReport {
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

#[frb(mirror(Totals))]
pub struct _Totals {
    pub files: u32,
    pub top_per_mille: Option<u32>,
}

#[frb(mirror(ColourOfTheYear))]
pub struct _ColourOfTheYear {
    pub colour: RewindColour,
    pub percent: u32,
    pub file_ids: Vec<i64>,
}

#[frb(mirror(RewindColour))]
pub enum _RewindColour {
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

#[frb(mirror(Places))]
pub struct _Places {
    pub cities: Vec<RewindCity>,
    pub distance_km: u32,
}

#[frb(mirror(RewindCity))]
pub struct _RewindCity {
    pub name: String,
    pub country: String,
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[frb(mirror(Spots))]
pub struct _Spots {
    pub spot_count: u32,
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[frb(mirror(PeopleRace))]
pub struct _PeopleRace {
    pub people: Vec<RacePerson>,
}

#[frb(mirror(RacePerson))]
pub struct _RacePerson {
    pub person_id: String,
    pub photo_count: u32,
    pub monthly_counts: Vec<u32>,
    pub face_ids: Vec<String>,
    pub file_ids: Vec<i64>,
}

#[frb(mirror(BusiestDay))]
pub struct _BusiestDay {
    pub month: u32,
    pub day: u32,
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[frb(mirror(NewFaces))]
pub struct _NewFaces {
    pub count: u32,
    pub faces: Vec<NewFace>,
}

#[frb(mirror(NewFace))]
pub struct _NewFace {
    pub person_id: Option<String>,
    pub cluster_id: Option<String>,
    pub face_ids: Vec<String>,
    pub file_ids: Vec<i64>,
}

#[frb(mirror(Favourites))]
pub struct _Favourites {
    pub photo_count: u32,
    pub file_ids: Vec<i64>,
}

#[frb(mirror(WeeklyHabit))]
pub struct _WeeklyHabit {
    pub weekday: u32,
    pub hour: u32,
    pub percent: u32,
}

#[frb(mirror(CrowdFavourite))]
pub struct _CrowdFavourite {
    pub photos: Vec<LikedPhoto>,
}

#[frb(mirror(LikedPhoto))]
pub struct _LikedPhoto {
    pub file_id: i64,
    pub like_count: u32,
}

#[frb(mirror(Badge))]
pub struct _Badge {
    pub id: RewindBadge,
    pub value: Option<u32>,
}

#[frb(mirror(RewindBadge))]
pub enum _RewindBadge {
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

#[frb(mirror(Scrapbook))]
pub struct _Scrapbook {
    pub file_ids: Vec<i64>,
}

pub fn compute_rewind(
    request: RewindRequest,
    store: Option<RustAutoOpaque<MlStore>>,
    cities: Option<RustAutoOpaque<LocationIndex>>,
    previous: Option<RewindState>,
) -> Result<RewindState, RewindError> {
    let store = store.as_ref().map(RustAutoOpaque::blocking_read);
    let cities = cities.as_ref().map(RustAutoOpaque::blocking_read);
    Ok(rewind::compute_rewind(
        &request,
        store.as_deref().map(|store| &store.inner),
        cities.as_deref().map(|cities| &cities.0 as &dyn CityLookup),
        previous.as_ref(),
    )?)
}

pub fn encode_rewind_state(state: RewindState) -> Result<Vec<u8>, RewindError> {
    Ok(rewind::encode_rewind_state(&state)?)
}

pub fn decode_rewind_state(
    bytes: Vec<u8>,
    year: i32,
    local_gallery_mode: bool,
) -> Option<RewindState> {
    rewind::decode_rewind_state(&bytes, year, local_gallery_mode)
}

pub fn encode_rewind_request(request: RewindRequest) -> Result<Vec<u8>, RewindError> {
    Ok(rewind::encode_rewind_request(&request)?)
}
