use crate::{
    CaptureDateTime, Dimensions, Format, Ifd, Iptc, Issue, Property, Rational, Statistics, Tag,
    Transform, Value, VideoRange, XmpStructure, namespace, photo,
};

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Metadata {
    pub format: Format,
    pub dimensions: Option<Dimensions>,
    pub transforms: Vec<Transform>,
    pub tags: Vec<Tag>,
    pub xmp: Vec<Property>,
    pub iptc: Vec<Iptc>,
    pub motion_video: Option<VideoRange>,
    pub issues: Vec<Issue>,
    pub statistics: Statistics,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StructuredMetadata {
    pub metadata: Metadata,
    pub xmp: XmpStructure,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Location {
    pub latitude: f64,
    pub longitude: f64,
}

impl Metadata {
    pub fn capture_date_time(&self) -> Option<CaptureDateTime> {
        photo::capture_date_time(self)
    }
    pub fn capture_date_time_with(
        &self,
        accept: impl FnMut(&mut CaptureDateTime) -> bool,
    ) -> Option<CaptureDateTime> {
        photo::capture_date_time_with(self, accept)
    }
    pub fn display_dimensions(&self) -> Option<Dimensions> {
        photo::display_dimensions(self)
    }
    pub fn tag(&self, ifd: Ifd, id: u16) -> Option<&Tag> {
        self.tags.iter().find(|tag| tag.ifd == ifd && tag.id == id)
    }
    pub fn property(&self, namespace: &str, name: &str) -> Option<&str> {
        self.xmp
            .iter()
            .find(|p| p.namespace == namespace && p.name == name)
            .map(|p| p.value.as_str())
    }

    pub fn properties<'a>(
        &'a self,
        namespace: &'a str,
        name: &'a str,
    ) -> impl Iterator<Item = &'a Property> {
        self.xmp
            .iter()
            .filter(move |p| p.namespace == namespace && p.name == name)
    }
    pub fn orientation(&self) -> Option<u32> {
        self.tag(Ifd::Image(0), 0x112)?.value.unsigned()
    }
    pub fn is_panorama(&self) -> bool {
        matches!(
            self.property(namespace::GPANO, "ProjectionType"),
            Some("cylindrical" | "equirectangular")
        ) || self
            .tag(Ifd::Exif(0), 0xa401)
            .and_then(|t| t.value.unsigned())
            == Some(6)
    }
    pub fn width(&self) -> Option<u32> {
        self.dimensions.map(|d| d.width)
    }
    pub fn height(&self) -> Option<u32> {
        self.dimensions.map(|d| d.height)
    }
    pub fn xmp_dimensions(&self) -> Option<Dimensions> {
        [
            (namespace::TIFF, "ImageWidth", "ImageLength"),
            (namespace::EXIF, "PixelXDimension", "PixelYDimension"),
        ]
        .into_iter()
        .find_map(|(ns, width, height)| {
            Dimensions::new(
                self.property(ns, width)?.trim().parse().ok()?,
                self.property(ns, height)?.trim().parse().ok()?,
            )
        })
    }
    pub fn camera_make(&self) -> Option<&str> {
        self.text(Ifd::Image(0), 0x10f)
    }
    pub fn camera_model(&self) -> Option<&str> {
        self.text(Ifd::Image(0), 0x110)
    }
    pub fn lens_model(&self) -> Option<&str> {
        self.text(Ifd::Exif(0), 0xa434)
    }
    pub fn exposure_time(&self) -> Option<Rational> {
        let Value::Rational(values) = &self.tag(Ifd::Exif(0), 0x829a)?.value else {
            return None;
        };
        let [value] = values.as_slice() else {
            return None;
        };
        (value.as_f64()? > 0.0).then_some(*value)
    }
    pub fn f_number(&self) -> Option<f64> {
        self.positive_number(0x829d)
    }
    pub fn focal_length(&self) -> Option<f64> {
        self.positive_number(0x920a)
    }
    pub fn iso_speed_ratings(&self) -> Option<&[u32]> {
        match &self.tag(Ifd::Exif(0), 0x8827)?.value {
            Value::Unsigned(values) => Some(values),
            _ => None,
        }
    }
    pub fn exif_description(&self) -> Option<&str> {
        self.text(Ifd::Image(0), 0x10e)
    }
    pub fn exif_location(&self) -> Option<Location> {
        let latitude_ref = self.tag(Ifd::Gps(0), 1);
        let longitude_ref = self.tag(Ifd::Gps(0), 3);
        if latitude_ref.is_some() != longitude_ref.is_some() {
            return None;
        }
        let coordinate = |id, reference: Option<&Tag>, positive, negative| {
            let tag = self.tag(Ifd::Gps(0), id)?;
            if tag.count != 3 {
                return None;
            }
            let parts = [
                tag.value.number(0)?,
                tag.value.number(1)?,
                tag.value.number(2)?,
            ];
            if parts[1].abs() >= 60.0 || parts[2].abs() >= 60.0 {
                return None;
            }
            let sign = match reference {
                Some(r) => hemisphere(r.value.text()?, positive, negative)?,
                None => {
                    if parts.iter().any(|v| *v < 0.0) {
                        -1.0
                    } else {
                        1.0
                    }
                }
            };
            Some(sign * (parts[0].abs() + parts[1].abs() / 60.0 + parts[2].abs() / 3600.0))
        };
        location(
            coordinate(2, latitude_ref, b'N', b'S')?,
            coordinate(4, longitude_ref, b'E', b'W')?,
        )
    }
    pub fn xmp_location(&self) -> Option<Location> {
        location(
            xmp_coordinate(
                self.property(namespace::EXIF, "GPSLatitude")?,
                self.property(namespace::EXIF, "GPSLatitudeRef"),
                b'N',
                b'S',
            )?,
            xmp_coordinate(
                self.property(namespace::EXIF, "GPSLongitude")?,
                self.property(namespace::EXIF, "GPSLongitudeRef"),
                b'E',
                b'W',
            )?,
        )
    }
    pub fn xmp_description(&self, language: Option<&str>) -> Option<&str> {
        let descriptions = || self.properties(namespace::DC, "description");
        language
            .and_then(|language| {
                descriptions().find(|p| {
                    p.language
                        .as_deref()
                        .is_some_and(|l| l.eq_ignore_ascii_case(language))
                })
            })
            .or_else(|| descriptions().find(|p| p.language.as_deref() == Some("x-default")))
            .or_else(|| descriptions().next())
            .map(|p| p.value.as_str())
    }

    pub(crate) fn tiff_dimensions(&self) -> Option<Dimensions> {
        let pair = |ifd, width, height| {
            Dimensions::new(
                self.tag(ifd, width)?.value.unsigned()?,
                self.tag(ifd, height)?.value.unsigned()?,
            )
        };
        pair(Ifd::Image(0), 0x100, 0x101).or_else(|| pair(Ifd::Exif(0), 0xa002, 0xa003))
    }

    pub(crate) fn text(&self, ifd: Ifd, id: u16) -> Option<&str> {
        let value = self.tag(ifd, id)?.value.text()?.trim();
        (!value.is_empty()).then_some(value)
    }

    fn positive_number(&self, id: u16) -> Option<f64> {
        let tag = self.tag(Ifd::Exif(0), id)?;
        let value = tag.value.number(0)?;
        (tag.count == 1 && value > 0.0).then_some(value)
    }
}

fn location(latitude: f64, longitude: f64) -> Option<Location> {
    ((-90.0..=90.0).contains(&latitude) && (-180.0..=180.0).contains(&longitude)).then_some(
        Location {
            latitude,
            longitude,
        },
    )
}

fn hemisphere(value: &str, positive: u8, negative: u8) -> Option<f64> {
    match value.trim().as_bytes() {
        [v] if v.to_ascii_uppercase() == positive => Some(1.0),
        [v] if v.to_ascii_uppercase() == negative => Some(-1.0),
        _ => None,
    }
}

fn xmp_coordinate(value: &str, reference: Option<&str>, positive: u8, negative: u8) -> Option<f64> {
    let value = value.trim();
    let (value, sign) = if value.as_bytes().last().is_some_and(u8::is_ascii_alphabetic) {
        let (value, suffix) = value.split_at(value.len() - 1);
        (value, hemisphere(suffix, positive, negative)?)
    } else {
        (value, hemisphere(reference?, positive, negative)?)
    };
    let mut parts = value.split(',');
    let degrees = parts.next()?.trim().parse::<f64>().ok()?;
    let mut coordinate = degrees;
    for divisor in [60.0, 3600.0] {
        if let Some(part) = parts.next() {
            let part = part.trim().parse::<f64>().ok()?;
            if !(0.0..60.0).contains(&part) {
                return None;
            }
            coordinate += part / divisor;
        }
    }
    if degrees < 0.0 || parts.next().is_some() {
        return None;
    }
    Some(sign * coordinate)
}
