use serde::{Deserialize, Serialize};

use super::Result;
use super::input::RewindRequest;
use super::library::{Library, MICROS_PER_DAY};
use super::report::RewindReport;
use crate::memories::CityLookup;
use crate::ml_store::MlStore;

pub const REWIND_VERSION: u32 = 1;

const REQUIRED_ML_COVERAGE: f32 = 0.9;

pub(super) fn has_enough_ml(coverage: f32) -> bool {
    coverage >= REQUIRED_ML_COVERAGE
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RewindState {
    pub year: i32,
    pub version: u32,
    pub computed_at: i64,
    pub local_gallery_mode: bool,
    pub ml_coverage: Option<f32>,
    pub ml_chapters_pending: bool,
    pub is_final: bool,
    pub status: RewindStatus,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RewindStatus {
    NothingToShow,
    Ready { report: Box<RewindReport> },
}

fn nothing_to_cluster(
    request: &RewindRequest,
    library: &Library<'_>,
    store: &MlStore,
) -> Result<bool> {
    Ok(!store.has_faces_to_cluster(&library.file_ids_until_year_end(request))?)
}

pub(super) struct MlReadiness {
    coverage: Option<f32>,
    faces_clustered: bool,
    earlier_years_indexed: bool,
}

impl MlReadiness {
    pub(super) fn of(
        request: &RewindRequest,
        library: &Library<'_>,
        store: Option<&MlStore>,
    ) -> Result<Self> {
        let Some(store) = store else {
            return Ok(Self {
                coverage: None,
                faces_clustered: true,
                earlier_years_indexed: true,
            });
        };
        Ok(Self {
            coverage: Some(library.ml_coverage(store)?),
            faces_clustered: request.just_clustered || nothing_to_cluster(request, library, store)?,
            earlier_years_indexed: has_enough_ml(library.earlier_ml_coverage(request, store)?),
        })
    }

    fn chapters_ready(&self) -> bool {
        self.coverage.is_none_or(has_enough_ml) && self.faces_clustered
    }

    fn new_faces_ready(&self, showed_new_faces: bool) -> bool {
        self.earlier_years_indexed && (self.faces_clustered || showed_new_faces)
    }
}

impl RewindState {
    pub(super) fn applies_to(&self, request: &RewindRequest) -> bool {
        self.version == REWIND_VERSION
            && self.year == request.year
            && self.local_gallery_mode == request.local_gallery_mode
    }

    fn report(&self) -> Option<&RewindReport> {
        match &self.status {
            RewindStatus::Ready { report } => Some(report),
            RewindStatus::NothingToShow => None,
        }
    }

    pub(super) fn evaluate(
        request: &RewindRequest,
        library: &Library<'_>,
        store: Option<&MlStore>,
        cities: Option<&dyn CityLookup>,
        readiness: &MlReadiness,
        previous: Option<&RewindState>,
    ) -> Result<Self> {
        let shown_with_ml = previous
            .filter(|previous| previous.ml_coverage.is_some())
            .and_then(RewindState::report);
        let ml_ready = readiness.chapters_ready();
        let ml_chapters = ml_ready || shown_with_ml.is_some_and(RewindReport::shows_ml_chapters);
        let report = RewindReport::of(
            request,
            library,
            store,
            ml_chapters,
            readiness
                .new_faces_ready(shown_with_ml.is_some_and(|report| report.new_faces.is_some())),
            cities,
        )?;
        let year_files = |report: &RewindReport| report.totals.as_ref().map(|totals| totals.files);
        let settled = previous
            .filter(|previous| {
                previous.is_final
                    || (library.had_ended_at(previous.computed_at)
                        && request.now - previous.computed_at >= MICROS_PER_DAY)
            })
            .and_then(RewindState::report)
            .and_then(year_files)
            .is_some_and(|files| year_files(&report) == Some(files));
        let status = if report.is_empty() {
            RewindStatus::NothingToShow
        } else {
            RewindStatus::Ready {
                report: Box::new(report),
            }
        };
        let would_freeze = ml_ready
            && readiness.earlier_years_indexed
            && cities.is_some()
            && library.year_has_ended()
            && settled
            && matches!(status, RewindStatus::Ready { .. });
        let is_final = would_freeze
            && (!request.just_clustered
                || store.map_or(Ok(true), |store| {
                    nothing_to_cluster(request, library, store)
                })?);
        Ok(Self {
            year: request.year,
            version: REWIND_VERSION,
            computed_at: request.now,
            local_gallery_mode: request.local_gallery_mode,
            ml_coverage: readiness.coverage,
            ml_chapters_pending: !ml_chapters,
            is_final,
            status,
        })
    }
}
