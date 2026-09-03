use std::path::Path;

use ente_image::decode::decode_image_from_path;

use super::OcrError;
use crate::cv;
use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct WorkingSizeCap {
    max_side: u32,
    max_pixels: u32,
}

pub(crate) const REGIONS_CAP: WorkingSizeCap = WorkingSizeCap {
    max_side: 1280,
    max_pixels: 2_000_000,
};

impl WorkingSizeCap {
    fn scale(self, width: u32, height: u32) -> f64 {
        let longest = f64::from(width.max(height));
        let pixels = f64::from(width) * f64::from(height);
        (f64::from(self.max_side) / longest)
            .min((f64::from(self.max_pixels) / pixels).sqrt())
            .min(1.0)
    }

    pub(crate) fn working_size(self, width: u32, height: u32) -> (u32, u32) {
        let scale = self.scale(width, height);
        if scale >= 1.0 {
            return (width, height);
        }
        let scaled = |side: u32| ((f64::from(side) * scale).round() as u32).max(1);
        (scaled(width), scaled(height))
    }
}

#[derive(Debug)]
pub(crate) struct SourceImage {
    pub(crate) decoded_width: u32,
    pub(crate) decoded_height: u32,
    pub(crate) working: ImageU8,
}

pub(crate) fn load_source(image_path: &str, cap: WorkingSizeCap) -> Result<SourceImage, OcrError> {
    if !Path::new(image_path).is_file() {
        return Err(OcrError::ImageNotFound(image_path.to_string()));
    }
    let decoded = decode_image_from_path(image_path).map_err(MlError::from)?;
    let (width, height) = (decoded.dimensions.width, decoded.dimensions.height);
    let full =
        ImageU8::new(to_side(width)?, to_side(height)?, 3, decoded.rgb).map_err(MlError::Image)?;
    let (working_width, working_height) = cap.working_size(width, height);
    let working = if (working_width, working_height) == (width, height) {
        full
    } else {
        cv::resize_u8(
            &full,
            to_side(working_width)?,
            to_side(working_height)?,
            cv::Interp::Area,
        )
        .map_err(MlError::Image)?
    };
    Ok(SourceImage {
        decoded_width: width,
        decoded_height: height,
        working,
    })
}

fn to_side(value: u32) -> MlResult<i32> {
    i32::try_from(value).map_err(|_| MlError::Image(format!("image side {value} is too large")))
}

#[cfg(test)]
mod tests {
    use std::fs::File;
    use std::io::BufWriter;
    use std::path::Path;

    use image::ExtendedColorType;
    use image::ImageEncoder;
    use image::codecs::png::{CompressionType, FilterType, PngEncoder};

    use super::*;

    const FULL_TEXT_CAP: WorkingSizeCap = WorkingSizeCap {
        max_side: 4096,
        max_pixels: 12_000_000,
    };

    fn write_png(dir: &Path, name: &str, width: u32, height: u32) -> String {
        let path = dir.join(name);
        let writer = BufWriter::new(File::create(&path).unwrap());
        let pixels = vec![128u8; (width * height * 3) as usize];
        PngEncoder::new_with_quality(writer, CompressionType::Fast, FilterType::NoFilter)
            .write_image(&pixels, width, height, ExtendedColorType::Rgb8)
            .unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn wide_image_is_capped_at_the_longest_side() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_png(dir.path(), "wide.png", 5000, 1000);

        let source = load_source(&path, FULL_TEXT_CAP).unwrap();

        assert_eq!((source.decoded_width, source.decoded_height), (5000, 1000));
        assert_eq!(source.working.width, 4096);
        assert_eq!(source.working.height, 819);
        assert_eq!(source.working.channels, 3);
    }

    #[test]
    fn square_image_is_capped_at_the_pixel_budget() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_png(dir.path(), "square.png", 4000, 4000);

        let source = load_source(&path, FULL_TEXT_CAP).unwrap();

        let pixels = source.working.width as u64 * source.working.height as u64;
        assert!(pixels <= 12_000_000, "{pixels}");
        assert!(pixels > 11_900_000, "{pixels}");
        assert_eq!(source.working.width, source.working.height);
    }

    #[test]
    fn small_image_is_kept_as_is() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_png(dir.path(), "small.png", 640, 480);

        let source = load_source(&path, REGIONS_CAP).unwrap();

        assert_eq!((source.decoded_width, source.decoded_height), (640, 480));
        assert_eq!((source.working.width, source.working.height), (640, 480));
        assert_eq!(source.working.data.len(), 640 * 480 * 3);
    }

    #[test]
    fn missing_file_is_reported_before_decoding() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir
            .path()
            .join("missing.jpg")
            .to_string_lossy()
            .into_owned();

        let error = load_source(&path, REGIONS_CAP).unwrap_err();

        assert!(
            matches!(&error, OcrError::ImageNotFound(reported) if reported == &path),
            "{error}"
        );
    }

    #[test]
    fn regions_cap_applies_the_smaller_of_both_limits() {
        assert_eq!(REGIONS_CAP.working_size(5000, 1000), (1280, 256));
        assert_eq!(REGIONS_CAP.working_size(2000, 2000), (1280, 1280));
        assert_eq!(REGIONS_CAP.working_size(1280, 960), (1280, 960));
        assert_eq!(FULL_TEXT_CAP.working_size(4000, 3000), (4000, 3000));
        assert_eq!(FULL_TEXT_CAP.working_size(5000, 3000), (4096, 2458));
        assert_eq!(FULL_TEXT_CAP.working_size(4000, 4000), (3464, 3464));
        assert_eq!(FULL_TEXT_CAP.working_size(1, 9000), (1, 4096));
    }
}
