use crate::{TextEncoding, text};
use std::borrow::Cow;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ifd {
    Image(u16),
    Exif(u16),
    Gps(u16),
    Interop(u16),
}

impl Ifd {
    pub(crate) fn image(self) -> u16 {
        match self {
            Self::Image(n) | Self::Exif(n) | Self::Gps(n) | Self::Interop(n) => n,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Tag {
    pub ifd: Ifd,
    pub id: u16,
    pub field_type: u16,
    pub count: u32,
    pub value: Value,
}

impl Tag {
    pub fn name(&self) -> Option<&'static str> {
        name(self.ifd, self.id)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Unsigned(Vec<u32>),
    Signed(Vec<i32>),
    Rational(Vec<Rational>),
    Float(Vec<f64>),
    Ascii(Vec<u8>),
    Bytes(Vec<u8>),
    Omitted { bytes: u64 },
}

impl Value {
    pub fn number(&self, index: usize) -> Option<f64> {
        match self {
            Self::Unsigned(v) => v.get(index).map(|n| f64::from(*n)),
            Self::Signed(v) => v.get(index).map(|n| f64::from(*n)),
            Self::Rational(v) => v.get(index)?.as_f64(),
            Self::Float(v) => v.get(index).copied().filter(|n| n.is_finite()),
            _ => None,
        }
    }

    pub fn unsigned(&self) -> Option<u32> {
        match self {
            Self::Unsigned(v) if v.len() == 1 => Some(v[0]),
            _ => None,
        }
    }

    pub fn text(&self) -> Option<&str> {
        let Self::Ascii(bytes) = self else {
            return None;
        };
        let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
        std::str::from_utf8(&bytes[..end]).ok()
    }
    pub fn text_with(&self, encoding: TextEncoding) -> Option<Cow<'_, str>> {
        let Self::Ascii(bytes) = self else {
            return None;
        };
        let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
        text::decode(&bytes[..end], encoding)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rational {
    pub numerator: i64,
    pub denominator: i64,
}

impl Rational {
    pub fn as_f64(self) -> Option<f64> {
        (self.denominator != 0).then(|| self.numerator as f64 / self.denominator as f64)
    }
}

pub(crate) fn selected(ifd: Ifd, id: u16) -> bool {
    if ifd.image() != 0 {
        return false;
    }
    match ifd {
        Ifd::Image(_) => matches!(
            id,
            0x100 | 0x101 | 0x10e | 0x10f | 0x110 | 0x112 | 0x132 | 0x13b | 0x8298
        ),
        Ifd::Exif(_) => {
            matches!(id, 0x829a | 0x829d | 0x8827 | 0x9003 | 0x9004 | 0x9010..=0x9012 | 0x920a | 0x9290..=0x9292 | 0xa001..=0xa003 | 0xa401 | 0xa405 | 0xa434)
        }
        Ifd::Gps(_) => matches!(id, 1..=7 | 18),
        Ifd::Interop(_) => false,
    }
}

pub(crate) fn name(ifd: Ifd, id: u16) -> Option<&'static str> {
    Some(match ifd {
        Ifd::Gps(_) => match id {
            0 => "GPSVersionID",
            1 => "GPSLatitudeRef",
            2 => "GPSLatitude",
            3 => "GPSLongitudeRef",
            4 => "GPSLongitude",
            5 => "GPSAltitudeRef",
            6 => "GPSAltitude",
            7 => "GPSTimeStamp",
            8 => "GPSSatellites",
            9 => "GPSStatus",
            10 => "GPSMeasureMode",
            11 => "GPSDOP",
            12 => "GPSSpeedRef",
            13 => "GPSSpeed",
            14 => "GPSTrackRef",
            15 => "GPSTrack",
            16 => "GPSImgDirectionRef",
            17 => "GPSImgDirection",
            18 => "GPSMapDatum",
            29 => "GPSDateStamp",
            30 => "GPSDifferential",
            31 => "GPSHPositioningError",
            _ => return None,
        },
        Ifd::Interop(_) => match id {
            1 => "InteroperabilityIndex",
            2 => "InteroperabilityVersion",
            _ => return None,
        },
        Ifd::Image(_) | Ifd::Exif(_) => match id {
            0x100 => "ImageWidth",
            0x101 => "ImageLength",
            0x102 => "BitsPerSample",
            0x103 => "Compression",
            0x106 => "PhotometricInterpretation",
            0x10e => "ImageDescription",
            0x10f => "Make",
            0x110 => "Model",
            0x111 => "StripOffsets",
            0x112 => "Orientation",
            0x115 => "SamplesPerPixel",
            0x116 => "RowsPerStrip",
            0x117 => "StripByteCounts",
            0x11a => "XResolution",
            0x11b => "YResolution",
            0x11c => "PlanarConfiguration",
            0x128 => "ResolutionUnit",
            0x12d => "TransferFunction",
            0x131 => "Software",
            0x132 => "DateTime",
            0x13b => "Artist",
            0x13e => "WhitePoint",
            0x13f => "PrimaryChromaticities",
            0x14a => "SubIFDs",
            0x201 => "JPEGInterchangeFormat",
            0x202 => "JPEGInterchangeFormatLength",
            0x211 => "YCbCrCoefficients",
            0x212 => "YCbCrSubSampling",
            0x213 => "YCbCrPositioning",
            0x214 => "ReferenceBlackWhite",
            0x2bc => "XMP",
            0x8298 => "Copyright",
            0x829a => "ExposureTime",
            0x829d => "FNumber",
            0x8769 => "ExifIFDPointer",
            0x8822 => "ExposureProgram",
            0x8824 => "SpectralSensitivity",
            0x8825 => "GPSInfoIFDPointer",
            0x8827 => "ISOSpeedRatings",
            0x8830 => "SensitivityType",
            0x8831 => "StandardOutputSensitivity",
            0x8832 => "RecommendedExposureIndex",
            0x8833 => "ISOSpeed",
            0x9000 => "ExifVersion",
            0x9003 => "DateTimeOriginal",
            0x9004 => "DateTimeDigitized",
            0x9010 => "OffsetTime",
            0x9011 => "OffsetTimeOriginal",
            0x9012 => "OffsetTimeDigitized",
            0x9101 => "ComponentsConfiguration",
            0x9102 => "CompressedBitsPerPixel",
            0x9201 => "ShutterSpeedValue",
            0x9202 => "ApertureValue",
            0x9203 => "BrightnessValue",
            0x9204 => "ExposureBiasValue",
            0x9205 => "MaxApertureValue",
            0x9206 => "SubjectDistance",
            0x9207 => "MeteringMode",
            0x9208 => "LightSource",
            0x9209 => "Flash",
            0x920a => "FocalLength",
            0x9214 => "SubjectArea",
            0x927c => "MakerNote",
            0x9286 => "UserComment",
            0x9290 => "SubSecTime",
            0x9291 => "SubSecTimeOriginal",
            0x9292 => "SubSecTimeDigitized",
            0xa000 => "FlashpixVersion",
            0xa001 => "ColorSpace",
            0xa002 => "PixelXDimension",
            0xa003 => "PixelYDimension",
            0xa005 => "InteroperabilityIFDPointer",
            0xa20e => "FocalPlaneXResolution",
            0xa20f => "FocalPlaneYResolution",
            0xa210 => "FocalPlaneResolutionUnit",
            0xa217 => "SensingMethod",
            0xa300 => "FileSource",
            0xa301 => "SceneType",
            0xa401 => "CustomRendered",
            0xa402 => "ExposureMode",
            0xa403 => "WhiteBalance",
            0xa404 => "DigitalZoomRatio",
            0xa405 => "FocalLengthIn35mmFilm",
            0xa406 => "SceneCaptureType",
            0xa407 => "GainControl",
            0xa408 => "Contrast",
            0xa409 => "Saturation",
            0xa40a => "Sharpness",
            0xa420 => "ImageUniqueID",
            0xa430 => "CameraOwnerName",
            0xa431 => "BodySerialNumber",
            0xa432 => "LensSpecification",
            0xa433 => "LensMake",
            0xa434 => "LensModel",
            0xa435 => "LensSerialNumber",
            _ => return None,
        },
    })
}
