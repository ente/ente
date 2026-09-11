use std::{fs::File, path::Path};

use ente_exif::{
    CaptureDateTime, DateTimePrecision, Dimensions, Error, Limits, Location, Mode, VideoRange,
};

#[derive(Debug)]
pub struct PhotoMetadata {
    pub dimensions: Option<Dimensions>,
    pub capture_date_time: Option<CaptureDateTime>,
    pub location: Option<Location>,
    pub motion_video: Option<VideoRange>,
    pub is_panorama: bool,
}

pub fn read_photo_metadata(path: impl AsRef<Path>) -> Result<PhotoMetadata, Error> {
    let metadata = ente_exif::read(&mut File::open(path)?, Mode::Summary, Limits::default())?;
    Ok(PhotoMetadata {
        dimensions: metadata.display_dimensions(),
        motion_video: metadata.motion_video,
        is_panorama: metadata.is_panorama(),
        capture_date_time: metadata.capture_date_time_with(|date| {
            date.precision == DateTimePrecision::Second
                && date.timestamp_micros != Some(0)
                && !(date.offset_time.is_none() && date.date_time == "1970-01-01T00:00:00")
                && date.date_time != "4501-01-01T00:00:00"
        }),
        location: metadata
            .exif_location()
            .filter(|location| location.latitude != 0.0 || location.longitude != 0.0)
            .or_else(|| metadata.xmp_location()),
    })
}
