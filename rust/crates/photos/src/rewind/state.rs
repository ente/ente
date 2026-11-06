use serde::{Deserialize, Serialize};

use super::Result;
use super::input::RewindRequest;
use super::library::Library;
use super::report::RewindReport;
use crate::memories::CityLookup;
use crate::ml_store::MlStore;

pub const REWIND_VERSION: u32 = 1;

const REQUIRED_ML_COVERAGE: f32 = 0.9;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RewindState {
    pub year: i32,
    pub version: u32,
    pub computed_at: i64,
    pub local_gallery_mode: bool,
    pub ml_coverage: Option<f32>,
    pub is_final: bool,
    pub status: RewindStatus,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RewindStatus {
    WaitingForMl,
    NothingToShow,
    Ready { report: Box<RewindReport> },
}

impl RewindState {
    pub(super) fn applies_to(&self, request: &RewindRequest) -> bool {
        self.version == REWIND_VERSION
            && self.year == request.year
            && self.local_gallery_mode == request.local_gallery_mode
    }

    pub(super) fn evaluate(
        request: &RewindRequest,
        library: &Library<'_>,
        store: Option<&MlStore>,
        cities: Option<&dyn CityLookup>,
        ml_coverage: Option<f32>,
        was_ready: bool,
        showed_ml_chapters: bool,
    ) -> Result<Self> {
        let ml_ready = ml_coverage.is_none_or(|coverage| coverage >= REQUIRED_ML_COVERAGE);
        let shows_without_ml =
            library.year_has_ended() && request.installed_at < request.season_start;
        let status = if was_ready || ml_ready || shows_without_ml {
            let ml_chapters = ml_ready || showed_ml_chapters;
            let report = RewindReport::of(request, library, store, ml_chapters, cities)?;
            if report.is_empty() {
                RewindStatus::NothingToShow
            } else {
                RewindStatus::Ready {
                    report: Box::new(report),
                }
            }
        } else {
            RewindStatus::WaitingForMl
        };
        let is_final = ml_ready
            && cities.is_some()
            && library.year_has_ended()
            && matches!(status, RewindStatus::Ready { .. });
        Ok(Self {
            year: request.year,
            version: REWIND_VERSION,
            computed_at: request.now,
            local_gallery_mode: request.local_gallery_mode,
            ml_coverage,
            is_final,
            status,
        })
    }
}
