use crate::{
    DateTime, DateTimeKind, DateTimePrecision, DateTimeSource, Dimensions, Metadata, Transform,
    namespace,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptureDateTime {
    pub date_time: String,
    pub offset_time: Option<String>,
    pub timestamp_micros: Option<i64>,
    pub precision: DateTimePrecision,
    pub source: DateTimeSource,
}
pub fn capture_date_time(metadata: &Metadata) -> Option<CaptureDateTime> {
    capture_date_time_with(metadata, |_| true)
}
pub fn capture_date_time_with(
    metadata: &Metadata,
    mut accept: impl FnMut(&mut CaptureDateTime) -> bool,
) -> Option<CaptureDateTime> {
    use DateTimeKind::{Digitized, Modified, Original};
    use DateTimeSource::{Exif, Iptc, Xmp};
    [
        Xmp(namespace::EXIF, "DateTimeOriginal"),
        Iptc(55, 60),
        Exif(Original),
        Xmp(namespace::PHOTOSHOP, "DateCreated"),
        Xmp(namespace::EXIF, "DateTimeDigitized"),
        Iptc(62, 63),
        Exif(Digitized),
        Xmp(namespace::XMP, "CreateDate"),
        Xmp(namespace::XMP, "MetadataDate"),
        Xmp(namespace::TIFF, "DateTime"),
        Exif(Modified),
        Xmp(namespace::XMP, "ModifyDate"),
    ]
    .into_iter()
    .find_map(|source| {
        let value = metadata.date_time(source)?;
        let date = value.date_time;
        let local = DateTime {
            offset_minutes: None,
            ..date
        };
        let absolute = if matches!(
            value.precision,
            DateTimePrecision::Year | DateTimePrecision::Month | DateTimePrecision::Day
        ) {
            DateTime {
                offset_minutes: Some(0),
                ..date
            }
        } else {
            date
        };
        let mut result = CaptureDateTime {
            date_time: local.to_string(),
            offset_time: date.offset_minutes.map(|offset| {
                let minutes = offset.unsigned_abs();
                format!(
                    "{}{:02}:{:02}",
                    if offset < 0 { '-' } else { '+' },
                    minutes / 60,
                    minutes % 60
                )
            }),
            timestamp_micros: absolute.unix_micros(),
            precision: value.precision,
            source,
        };
        accept(&mut result).then_some(result)
    })
}
pub fn display_dimensions(metadata: &Metadata) -> Option<Dimensions> {
    let mut dimensions = metadata.dimensions.or_else(|| metadata.xmp_dimensions())?;
    let mut oriented = false;
    for transform in &metadata.transforms {
        match *transform {
            Transform::Orientation(value @ 1..=8) => {
                dimensions = dimensions.with_exif_orientation(u32::from(value));
                oriented = true;
            }
            Transform::Rotate(turns @ 0..=3) => {
                if turns % 2 != 0 {
                    std::mem::swap(&mut dimensions.width, &mut dimensions.height);
                }
                oriented |= turns != 0;
            }
            Transform::Mirror(0..=1) => oriented = true,
            Transform::Crop(crop) => dimensions = crop.cropped_dimensions(dimensions)?,
            _ => return None,
        }
    }
    if !oriented {
        let exif = metadata.dimensions.and(metadata.orientation());
        let orientation = exif.filter(|v| (1..=8).contains(v)).or_else(|| {
            metadata
                .property(namespace::TIFF, "Orientation")?
                .trim()
                .parse::<u32>()
                .ok()
                .filter(|v| (1..=8).contains(v))
        });
        dimensions = dimensions.with_exif_orientation(orientation.unwrap_or(1));
    }
    (dimensions.width != 0 && dimensions.height != 0).then_some(dimensions)
}
