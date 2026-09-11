use super::location_api::LocationCoordinate;

#[derive(Clone, Debug)]
pub struct PhotoMetadata {
    pub dimensions: Option<Dimensions>,
    pub capture_date_time: Option<CaptureDateTime>,
    pub location: Option<LocationCoordinate>,
    pub motion_video_start: Option<u64>,
    pub is_panorama: bool,
}

#[derive(Clone, Debug)]
pub struct Dimensions {
    pub width: u32,
    pub height: u32,
}

#[derive(Clone, Debug)]
pub struct CaptureDateTime {
    pub date_time: String,
    pub offset_time: Option<String>,
    pub timestamp_micros: Option<i64>,
}

pub fn read_photo_metadata(file_path: String) -> Result<PhotoMetadata, String> {
    let metadata =
        ente_photos::metadata::read_photo_metadata(file_path).map_err(|error| error.to_string())?;
    Ok(PhotoMetadata {
        motion_video_start: metadata.motion_video.map(|video| video.start),
        is_panorama: metadata.is_panorama,
        dimensions: metadata.dimensions.map(|dimensions| Dimensions {
            width: dimensions.width,
            height: dimensions.height,
        }),
        capture_date_time: metadata.capture_date_time.map(|date| CaptureDateTime {
            date_time: date.date_time,
            offset_time: date.offset_time,
            timestamp_micros: date.timestamp_micros,
        }),
        location: metadata.location.map(|location| LocationCoordinate {
            latitude: location.latitude,
            longitude: location.longitude,
        }),
    })
}
