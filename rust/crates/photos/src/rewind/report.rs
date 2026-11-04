use serde::{Deserialize, Serialize};

use super::chapters;
use super::library::Library;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewindReport {
    pub totals: Option<Totals>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Totals {
    pub files: u32,
}

impl RewindReport {
    pub(super) fn of(library: &Library<'_>) -> Self {
        Self {
            totals: chapters::totals(library),
        }
    }
}
