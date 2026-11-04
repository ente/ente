use std::path::Path;

use ente_photos::rewind;
pub use ente_photos::rewind::{
    RewindFile, RewindFileType, RewindReport, RewindRequest, RewindState, RewindStatus, Totals,
};
use flutter_rust_bridge::frb;

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
}

#[frb(mirror(RewindFile))]
pub struct _RewindFile {
    pub id: i64,
    pub creation_time: i64,
    pub local_date_time: Option<String>,
    pub utc_offset_seconds: i32,
    pub file_type: RewindFileType,
}

#[frb(mirror(RewindFileType))]
pub enum _RewindFileType {
    Image,
    Video,
    LivePhoto,
    Other,
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
    Ready { report: RewindReport },
}

#[frb(mirror(RewindReport))]
pub struct _RewindReport {
    pub totals: Option<Totals>,
}

#[frb(mirror(Totals))]
pub struct _Totals {
    pub files: u32,
}

pub fn refresh_rewind(
    request: RewindRequest,
    store: Option<RustAutoOpaque<MlStore>>,
    cache_directory: String,
) -> Result<RewindState, RewindError> {
    let store = store.as_ref().map(RustAutoOpaque::blocking_read);
    Ok(rewind::refresh_rewind(
        &request,
        store.as_deref().map(|store| &store.inner),
        Path::new(&cache_directory),
    )?)
}

pub fn load_rewind(
    cache_directory: String,
    year: i32,
    local_gallery_mode: bool,
) -> Option<RewindState> {
    rewind::load_rewind(Path::new(&cache_directory), year, local_gallery_mode)
}

pub fn clear_rewind(cache_directory: String) -> Result<(), RewindError> {
    Ok(rewind::clear_rewind(Path::new(&cache_directory))?)
}

pub fn export_rewind_request(request: RewindRequest, path: String) -> Result<(), RewindError> {
    Ok(rewind::export_rewind_request(&request, Path::new(&path))?)
}
