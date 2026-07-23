use std::collections::HashMap;

use ente_photos::{
    VideoIndex as CoreVideoIndex, extract_motion_video_file_from_path, extract_xmp_from_path,
    get_motion_video_index_from_path,
};

#[derive(Clone, Debug)]
pub struct VideoIndex {
    pub start: i64,
    pub end: i64,
}

impl TryFrom<CoreVideoIndex> for VideoIndex {
    type Error = String;

    fn try_from(value: CoreVideoIndex) -> Result<Self, Self::Error> {
        let start = i64::try_from(value.start)
            .map_err(|_| "video index start does not fit i64".to_string())?;
        let end =
            i64::try_from(value.end).map_err(|_| "video index end does not fit i64".to_string())?;
        Ok(Self { start, end })
    }
}

impl TryFrom<VideoIndex> for CoreVideoIndex {
    type Error = String;

    fn try_from(value: VideoIndex) -> Result<Self, Self::Error> {
        if value.start < 0 || value.end < 0 {
            return Err("video index cannot be negative".to_string());
        }
        let start = usize::try_from(value.start)
            .map_err(|_| "video index start does not fit usize".to_string())?;
        let end = usize::try_from(value.end)
            .map_err(|_| "video index end does not fit usize".to_string())?;
        Ok(Self { start, end })
    }
}

pub fn get_motion_video_index(file_path: String) -> Result<Option<VideoIndex>, String> {
    let result = get_motion_video_index_from_path(file_path)
        .map_err(|err| format!("failed to get motion video index: {err}"))?;

    result.map(TryInto::try_into).transpose()
}

pub fn extract_motion_video_file(
    file_path: String,
    destination_directory: String,
    file_name: Option<String>,
    index: Option<VideoIndex>,
) -> Result<Option<String>, String> {
    let file_name = file_name.unwrap_or_else(|| "motionphoto.mp4".to_string());
    let core_index = index.map(TryInto::try_into).transpose()?;
    let output = extract_motion_video_file_from_path(
        file_path,
        destination_directory,
        &file_name,
        core_index,
    )
    .map_err(|err| format!("failed to extract motion video file: {err}"))?;

    Ok(output.map(|path| path.to_string_lossy().to_string()))
}

pub fn extract_xmp(file_path: String) -> Result<HashMap<String, String>, String> {
    extract_xmp_from_path(file_path).map_err(|err| format!("failed to extract xmp: {err}"))
}
