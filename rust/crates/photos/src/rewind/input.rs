use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewindRequest {
    pub year: i32,
    pub now: i64,
    pub utc_offset_seconds: i32,
    pub season_start: i64,
    pub installed_at: i64,
    pub local_gallery_mode: bool,
    pub files: Vec<RewindFile>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewindFile {
    pub id: i64,
    pub creation_time: i64,
    pub local_date_time: Option<String>,
    pub utc_offset_seconds: i32,
    pub file_type: RewindFileType,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RewindFileType {
    Image,
    Video,
    LivePhoto,
    Other,
}
