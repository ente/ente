use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RewindRequest {
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

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RewindFile {
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RewindFileType {
    Image,
    Video,
    LivePhoto,
    Other,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct RewindLocation {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RewindVisibility {
    Visible,
    Archived,
    Hidden,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewindPerson {
    pub id: String,
    pub is_ignored: bool,
    pub is_hidden_from_memories: bool,
}
