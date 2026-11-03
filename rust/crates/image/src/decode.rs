use std::{
    ffi::OsStr,
    fs::File,
    io::{BufRead, BufReader, Cursor, Read, Seek, SeekFrom},
    path::Path,
    sync::Once,
};

use ente_heic::{
    DecodeGuardrails, exif_orientation_hint, exif_orientation_hint_from_path,
    image_integration::{
        apply_exif_orientation_dynamic, register_image_decoder_hooks_with_guardrails,
    },
    path_extension_is_heif,
};
use exif::{In, Reader as ExifReader, Tag as ExifTag};
use image::{
    DynamicImage, ImageDecoder, ImageFormat, ImageReader, Limits, hooks::decoding_hook_registered,
    metadata::Orientation,
};
use jxl_oxide::integration::JxlDecoder;
use tiff::{
    ColorType as TiffColorType,
    decoder::{Decoder as TiffDecoder, DecodingResult as TiffDecodingResult},
    tags::Tag as TiffTag,
};

use crate::{
    color_management::apply_icc_profile_to_srgb,
    error::{ImageError, ImageResult},
    types::{DecodedImage, Dimensions},
};

static IMAGE_DECODER_HOOKS_INIT: Once = Once::new();

const BOUNDED_READER_OVERFLOW_MESSAGE: &str = "JPEG XL input exceeds configured max_input_bytes";

const MAX_DECODE_PIXELS: u64 = 210_000_000;
const MAX_DECODE_ALLOC_BYTES: u64 = 512 * 1024 * 1024;

fn ensure_within_decode_pixel_cap(width: u32, height: u32) -> image::ImageResult<()> {
    if u64::from(width) * u64::from(height) > MAX_DECODE_PIXELS {
        return Err(image::ImageError::Limits(
            image::error::LimitError::from_kind(image::error::LimitErrorKind::InsufficientMemory),
        ));
    }
    Ok(())
}

fn ensure_within_decode_alloc_cap(total_bytes: u64) -> image::ImageResult<()> {
    if total_bytes > MAX_DECODE_ALLOC_BYTES {
        return Err(image::ImageError::Limits(
            image::error::LimitError::from_kind(image::error::LimitErrorKind::InsufficientMemory),
        ));
    }
    Ok(())
}

struct DecodedDynamicImage {
    image: DynamicImage,
    icc_profile: Option<Vec<u8>>,
    orientation: Option<Orientation>,
}

impl DecodedDynamicImage {
    fn into_srgb(self) -> (DynamicImage, Option<Orientation>) {
        (
            apply_icc_profile_to_srgb(self.image, self.icc_profile.as_deref()),
            self.orientation,
        )
    }
}

pub fn decode_image_from_path(image_path: &str) -> ImageResult<DecodedImage> {
    let decoded_dynamic = decode_with_image_crate(image_path)?;
    let (decoded_dynamic, orientation) = decoded_dynamic.into_srgb();
    let oriented = if decoded_dynamic.color().bytes_per_pixel() > 3 {
        orient_decoded_image(
            DynamicImage::ImageRgb8(decoded_dynamic.into_rgb8()),
            image_path,
            orientation,
        )
        .into_rgb8()
    } else {
        orient_decoded_image(decoded_dynamic, image_path, orientation).into_rgb8()
    };

    Ok(DecodedImage {
        dimensions: Dimensions {
            width: oriented.width(),
            height: oriented.height(),
        },
        rgb: oriented.into_raw(),
    })
}

pub fn decode_image_from_bytes(image_bytes: &[u8]) -> ImageResult<DecodedImage> {
    let decoded_dynamic = decode_bytes_with_image_crate(image_bytes)?;
    let (decoded_dynamic, orientation) = decoded_dynamic.into_srgb();
    let oriented = if decoded_dynamic.color().bytes_per_pixel() > 3 {
        orient_decoded_image_from_bytes(
            DynamicImage::ImageRgb8(decoded_dynamic.into_rgb8()),
            image_bytes,
            orientation,
        )
        .into_rgb8()
    } else {
        orient_decoded_image_from_bytes(decoded_dynamic, image_bytes, orientation).into_rgb8()
    };

    Ok(DecodedImage {
        dimensions: Dimensions {
            width: oriented.width(),
            height: oriented.height(),
        },
        rgb: oriented.into_raw(),
    })
}

fn decode_with_image_crate(image_path: &str) -> ImageResult<DecodedDynamicImage> {
    init_image_decoders();

    let reader = ImageReader::open(image_path)
        .map_err(|e| ImageError::Decode(format!("failed to open image file '{image_path}': {e}")))?
        .with_guessed_format()
        .map_err(|e| ImageError::Decode(format!("failed to guess image format: {e}")))?;
    let guessed_format = reader.format();

    match decode_reader_with_image_crate(reader) {
        Ok(decoded) => Ok(decoded),
        Err(primary_error) if should_attempt_tiff_fallback(guessed_format) => {
            log::warn!(
                "image crate TIFF decode failed for '{image_path}': {primary_error}. Retrying with tiff crate fallback"
            );

            match decode_with_tiff_crate(image_path) {
                Ok(decoded) => Ok(decoded),
                Err(fallback_error) => Err(tiff_fallback_failure(primary_error, fallback_error)),
            }
        }
        Err(other) => Err(other.into()),
    }
}

fn decode_bytes_with_image_crate(image_bytes: &[u8]) -> ImageResult<DecodedDynamicImage> {
    init_image_decoders();

    let reader = ImageReader::new(Cursor::new(image_bytes))
        .with_guessed_format()
        .map_err(|e| ImageError::Decode(format!("failed to guess image format: {e}")))?;
    let guessed_format = reader.format();

    match decode_reader_with_image_crate(reader) {
        Ok(decoded) => Ok(decoded),
        Err(primary_error) if should_attempt_tiff_fallback(guessed_format) => {
            match decode_tiff_from_bytes(image_bytes) {
                Ok(decoded) => Ok(decoded),
                Err(fallback_error) => Err(tiff_fallback_failure(primary_error, fallback_error)),
            }
        }
        Err(other) => Err(other.into()),
    }
}

fn tiff_fallback_failure(
    primary_error: image::ImageError,
    fallback_error: ImageError,
) -> ImageError {
    let primary_message = primary_error.to_string();
    let primary_error = ImageError::from(primary_error);
    if matches!(primary_error, ImageError::TooLarge(_)) {
        return primary_error;
    }
    let ImageError::Decode(fallback_message) = fallback_error else {
        return fallback_error;
    };
    ImageError::Decode(format!(
        "failed to decode TIFF with image crate: {primary_message}; fallback with tiff crate also failed: {fallback_message}"
    ))
}

fn decode_reader_with_image_crate<R>(
    reader: ImageReader<R>,
) -> image::ImageResult<DecodedDynamicImage>
where
    R: BufRead + Seek,
{
    // ente_heic decodes lazily into DynamicImage's output buffer, so the
    // decoder must remain intact through `from_decoder`.
    let mut decoder = reader.into_decoder()?;
    let (width, height) = decoder.dimensions();
    ensure_within_decode_pixel_cap(width, height)?;
    ensure_within_decode_alloc_cap(decoder.total_bytes())?;
    let icc_profile = match decoder.icc_profile() {
        Ok(icc_profile) => icc_profile,
        Err(err) => {
            log::warn!("failed to read embedded ICC profile: {err}");
            None
        }
    };
    let orientation = match decoder.orientation() {
        Ok(orientation) => Some(orientation),
        Err(err) => {
            log::warn!("failed to read image orientation from decoder: {err}");
            None
        }
    };

    let mut limits = Limits::default();
    limits.reserve(decoder.total_bytes())?;
    decoder.set_limits(limits)?;

    Ok(DecodedDynamicImage {
        image: DynamicImage::from_decoder(decoder)?,
        icc_profile,
        orientation,
    })
}

fn should_attempt_tiff_fallback(format: Option<ImageFormat>) -> bool {
    matches!(format, Some(ImageFormat::Tiff))
}

fn decode_with_tiff_crate(image_path: &str) -> ImageResult<DecodedDynamicImage> {
    let file = File::open(image_path)
        .map_err(|e| ImageError::Decode(format!("failed to open TIFF file '{image_path}': {e}")))?;
    decode_tiff(BufReader::new(file), image_path)
}

fn decode_tiff_from_bytes(image_bytes: &[u8]) -> ImageResult<DecodedDynamicImage> {
    decode_tiff(Cursor::new(image_bytes), "<bytes>")
}

fn decode_tiff<R: Read + Seek>(reader: R, source: &str) -> ImageResult<DecodedDynamicImage> {
    let mut decoder = TiffDecoder::new(reader)
        .map_err(|e| ImageError::Decode(format!("failed to initialize TIFF decoder: {e}")))?;
    let (width, height) = decoder
        .dimensions()
        .map_err(|e| ImageError::Decode(format!("failed to read TIFF dimensions: {e}")))?;
    ensure_within_decode_pixel_cap(width, height)?;
    let color_type = decoder
        .colortype()
        .map_err(|e| ImageError::Decode(format!("failed to read TIFF color type: {e}")))?;
    let icc_profile = decoder.get_tag_u8_vec(TiffTag::IccProfile).ok();
    let orientation = decoder
        .find_tag_unsigned::<u16>(TiffTag::Orientation)
        .ok()
        .flatten()
        .and_then(|value| u8::try_from(value).ok())
        .and_then(Orientation::from_exif);
    let decoded = decoder.read_image().map_err(tiff_decode_error)?;

    Ok(DecodedDynamicImage {
        image: dynamic_image_from_tiff(source, width, height, color_type, decoded)?,
        icc_profile,
        orientation,
    })
}

fn tiff_decode_error(error: tiff::TiffError) -> ImageError {
    if matches!(error, tiff::TiffError::LimitsExceeded) {
        return ImageError::TooLarge(image::ImageError::Limits(
            image::error::LimitError::from_kind(image::error::LimitErrorKind::InsufficientMemory),
        ));
    }
    ImageError::Decode(format!("failed to decode TIFF image data: {error}"))
}

fn dynamic_image_from_tiff(
    source: &str,
    width: u32,
    height: u32,
    color_type: TiffColorType,
    decoded: TiffDecodingResult,
) -> ImageResult<DynamicImage> {
    match (color_type, decoded) {
        (TiffColorType::Gray(8), TiffDecodingResult::U8(data)) => {
            let image = image::GrayImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "Gray(8)"))?;
            Ok(DynamicImage::ImageLuma8(image))
        }
        (TiffColorType::GrayA(8), TiffDecodingResult::U8(data)) => {
            let image = image::GrayAlphaImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "GrayA(8)"))?;
            Ok(DynamicImage::ImageLumaA8(image))
        }
        (TiffColorType::RGB(8), TiffDecodingResult::U8(data)) => {
            let image = image::RgbImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "RGB(8)"))?;
            Ok(DynamicImage::ImageRgb8(image))
        }
        (TiffColorType::RGBA(8), TiffDecodingResult::U8(data)) => {
            let image = image::RgbaImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "RGBA(8)"))?;
            Ok(DynamicImage::ImageRgba8(image))
        }
        (TiffColorType::Gray(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "Gray(16)"))?;
            Ok(DynamicImage::ImageLuma16(image))
        }
        (TiffColorType::GrayA(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "GrayA(16)"))?;
            Ok(DynamicImage::ImageLumaA16(image))
        }
        (TiffColorType::RGB(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "RGB(16)"))?;
            Ok(DynamicImage::ImageRgb16(image))
        }
        (TiffColorType::RGBA(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(source, width, height, "RGBA(16)"))?;
            Ok(DynamicImage::ImageRgba16(image))
        }
        (observed_color_type, observed_result_type) => Err(ImageError::Decode(format!(
            "unsupported TIFF pixel format for '{source}': color_type={observed_color_type:?}, sample_type={}",
            tiff_result_type_name(&observed_result_type)
        ))),
    }
}

fn tiff_buffer_mismatch_error(
    source: &str,
    width: u32,
    height: u32,
    color_type: &str,
) -> ImageError {
    ImageError::Decode(format!(
        "decoded TIFF buffer length does not match dimensions for '{source}': {width}x{height}, color_type={color_type}"
    ))
}

fn tiff_result_type_name(result: &TiffDecodingResult) -> &'static str {
    match result {
        TiffDecodingResult::U8(_) => "u8",
        TiffDecodingResult::U16(_) => "u16",
        _ => "unsupported",
    }
}

fn register_jxl_decoding_hook_with_guardrails(guardrails: DecodeGuardrails) -> bool {
    let decoder_hook_registered = image::hooks::register_decoding_hook(
        "jxl".into(),
        Box::new(move |reader| jxl_decoder_from_reader_with_guardrails(reader, &guardrails)),
    );

    if decoder_hook_registered {
        image::hooks::register_format_detection_hook("jxl".into(), &[0xFF, 0x0A], None);
        image::hooks::register_format_detection_hook(
            "jxl".into(),
            &[
                0x00, 0x00, 0x00, 0x0C, b'J', b'X', b'L', b' ', 0x0D, 0x0A, 0x87, 0x0A,
            ],
            None,
        );
    }

    decoder_hook_registered
}

fn jxl_decoder_from_reader_with_guardrails<'a, R>(
    mut reader: R,
    guardrails: &DecodeGuardrails,
) -> image::ImageResult<Box<dyn ImageDecoder + 'a>>
where
    R: Read + Seek + 'a,
{
    if let Some(max_input_bytes) = guardrails.max_input_bytes {
        let input_len = reader
            .seek(SeekFrom::End(0))
            .map_err(image::ImageError::IoError)?;
        if input_len > max_input_bytes {
            return Err(too_large_limit_error());
        }
        reader.rewind().map_err(image::ImageError::IoError)?;
    }

    let decoder = match JxlDecoder::new(BoundedReader::new(
        reader,
        guardrails.max_input_bytes.unwrap_or(u64::MAX),
    )) {
        Ok(decoder) => decoder,
        Err(image::ImageError::Decoding(err)) if bounded_reader_overflow(&err) => {
            return Err(too_large_limit_error());
        }
        Err(err) => return Err(err),
    };

    if let Some(max_pixels) = guardrails.max_pixels {
        let (width, height) = decoder.dimensions();
        if u64::from(width) * u64::from(height) > max_pixels {
            return Err(too_large_limit_error());
        }
    }

    Ok(Box::new(decoder))
}

fn bounded_reader_overflow(err: &image::error::DecodingError) -> bool {
    use std::error::Error as _;

    let mut source = err.source();
    while let Some(current) = source {
        if let Some(io_err) = current.downcast_ref::<std::io::Error>() {
            return io_err.kind() == std::io::ErrorKind::InvalidData
                && io_err.to_string().contains(BOUNDED_READER_OVERFLOW_MESSAGE);
        }
        source = current.source();
    }
    false
}

fn too_large_limit_error() -> image::ImageError {
    image::ImageError::Limits(image::error::LimitError::from_kind(
        image::error::LimitErrorKind::InsufficientMemory,
    ))
}

struct BoundedReader<R> {
    inner: R,
    bytes_left: u64,
}

impl<R> BoundedReader<R> {
    fn new(inner: R, max_bytes: u64) -> Self {
        Self {
            inner,
            bytes_left: max_bytes,
        }
    }
}

impl<R: Read> Read for BoundedReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let count = self.inner.read(buf)?;
        if count as u64 > self.bytes_left {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                BOUNDED_READER_OVERFLOW_MESSAGE,
            ));
        }
        self.bytes_left -= count as u64;
        Ok(count)
    }
}

fn init_image_decoders() {
    IMAGE_DECODER_HOOKS_INIT.call_once(|| {
        let guardrails = DecodeGuardrails {
            max_input_bytes: Some(128 * 1024 * 1024),
            max_pixels: Some(256_000_000),
            max_temp_spool_bytes: Some(256 * 1024 * 1024),
            temp_spool_directory: None,
        };
        let registration = register_image_decoder_hooks_with_guardrails(guardrails.clone());

        let heic_hook_active = decoding_hook_registered(OsStr::new("heic"));
        let heif_hook_active = decoding_hook_registered(OsStr::new("heif"));
        let avif_hook_active = decoding_hook_registered(OsStr::new("avif"));
        let jxl_registered_now = register_jxl_decoding_hook_with_guardrails(guardrails);
        let jxl_hook_active = decoding_hook_registered(OsStr::new("jxl"));
        let has_heif_family_support = heic_hook_active || heif_hook_active;

        if !has_heif_family_support {
            log::warn!(
                "failed to activate HEIF/HEIC decoder hooks; registration_result=(heic:{}, heif:{}, avif:{}), active_hooks=(heic:{}, heif:{}, avif:{})",
                registration.heic_decoder_hook_registered,
                registration.heif_decoder_hook_registered,
                registration.avif_decoder_hook_registered,
                heic_hook_active,
                heif_hook_active,
                avif_hook_active,
            );
        } else if !registration.all_decoder_hooks_registered() {
            log::warn!(
                "ente_heic decoder hooks only partially registered (usually because another initializer registered first); registration_result=(heic:{}, heif:{}, avif:{}), active_hooks=(heic:{}, heif:{}, avif:{})",
                registration.heic_decoder_hook_registered,
                registration.heif_decoder_hook_registered,
                registration.avif_decoder_hook_registered,
                heic_hook_active,
                heif_hook_active,
                avif_hook_active,
            );
        }

        debug_assert!(
            heic_hook_active || heif_hook_active || avif_hook_active,
            "no ente_heic image decoder hooks are active"
        );

        if !jxl_hook_active {
            log::warn!(
                "failed to activate JPEG XL decoder hook; registered_now={jxl_registered_now}, active_hook={jxl_hook_active}"
            );
        }

        debug_assert!(jxl_hook_active, "JPEG XL image decoder hook is not active");
    });
}

fn orient_decoded_image(
    image: DynamicImage,
    image_path: &str,
    decoder_orientation: Option<Orientation>,
) -> DynamicImage {
    let path = Path::new(image_path);
    if path_extension_is_heif(path) {
        return apply_heif_exif_orientation_hint(image, path);
    }
    if file_looks_like_jxl(path) {
        return image;
    }

    match decoder_orientation {
        Some(orientation) => apply_exif_orientation_dynamic(image, orientation.to_exif()),
        None => apply_standard_exif_orientation(image, image_path),
    }
}

fn orient_decoded_image_from_bytes(
    image: DynamicImage,
    image_bytes: &[u8],
    decoder_orientation: Option<Orientation>,
) -> DynamicImage {
    if bytes_look_like_heif(image_bytes) {
        return apply_heif_exif_orientation_hint_from_bytes(image, image_bytes);
    }
    if bytes_look_like_jxl(image_bytes) {
        return image;
    }

    match decoder_orientation {
        Some(orientation) => apply_exif_orientation_dynamic(image, orientation.to_exif()),
        None => apply_standard_exif_orientation_from_bytes(image, image_bytes),
    }
}

fn apply_heif_exif_orientation_hint(image: DynamicImage, image_path: &Path) -> DynamicImage {
    let hint = match exif_orientation_hint_from_path(image_path) {
        Ok(hint) => hint,
        Err(err) => {
            log::warn!(
                "failed to inspect HEIF EXIF orientation for '{}': {}",
                image_path.display(),
                err
            );
            return image;
        }
    };

    if let Some(orientation) = hint.orientation_to_apply() {
        return apply_exif_orientation_dynamic(image, orientation);
    }

    image
}

fn apply_heif_exif_orientation_hint_from_bytes(
    image: DynamicImage,
    image_bytes: &[u8],
) -> DynamicImage {
    let hint = exif_orientation_hint(image_bytes);

    if let Some(orientation) = hint.orientation_to_apply() {
        return apply_exif_orientation_dynamic(image, orientation);
    }

    image
}

fn apply_standard_exif_orientation(image: DynamicImage, image_path: &str) -> DynamicImage {
    match read_exif_orientation_from_path(image_path) {
        Some(orientation) => apply_exif_orientation_dynamic(image, orientation),
        None => image,
    }
}

fn apply_standard_exif_orientation_from_bytes(
    image: DynamicImage,
    image_bytes: &[u8],
) -> DynamicImage {
    match read_exif_orientation_from_bytes(image_bytes) {
        Some(orientation) => apply_exif_orientation_dynamic(image, orientation),
        None => image,
    }
}

fn read_exif_orientation_from_path(image_path: &str) -> Option<u8> {
    let file = File::open(image_path).ok()?;
    let mut reader = BufReader::new(file);
    let exif = ExifReader::new().read_from_container(&mut reader).ok()?;

    exif.get_field(ExifTag::Orientation, In::PRIMARY)
        .and_then(|field| field.value.get_uint(0))
        .and_then(|value| u8::try_from(value).ok())
        .filter(|value| (1..=8).contains(value))
}

fn read_exif_orientation_from_bytes(image_bytes: &[u8]) -> Option<u8> {
    let mut reader = BufReader::new(Cursor::new(image_bytes));
    let exif = ExifReader::new().read_from_container(&mut reader).ok()?;

    exif.get_field(ExifTag::Orientation, In::PRIMARY)
        .and_then(|field| field.value.get_uint(0))
        .and_then(|value| u8::try_from(value).ok())
        .filter(|value| (1..=8).contains(value))
}

// jxl-oxide applies codestream orientation; ignore redundant container EXIF.
fn bytes_look_like_jxl(image_bytes: &[u8]) -> bool {
    const BARE_CODESTREAM_SIGNATURE: [u8; 2] = [0xFF, 0x0A];
    const CONTAINER_SIGNATURE: [u8; 12] = [
        0x00, 0x00, 0x00, 0x0C, b'J', b'X', b'L', b' ', 0x0D, 0x0A, 0x87, 0x0A,
    ];

    image_bytes.starts_with(&BARE_CODESTREAM_SIGNATURE)
        || image_bytes.starts_with(&CONTAINER_SIGNATURE)
}

fn file_looks_like_jxl(path: &Path) -> bool {
    let Ok(file) = File::open(path) else {
        return false;
    };
    let mut signature = Vec::with_capacity(12);
    if file.take(12).read_to_end(&mut signature).is_err() {
        return false;
    }
    bytes_look_like_jxl(&signature)
}

fn bytes_look_like_heif(image_bytes: &[u8]) -> bool {
    if image_bytes.len() < 12 || &image_bytes[4..8] != b"ftyp" {
        return false;
    }

    matches!(
        &image_bytes[8..12],
        b"heic"
            | b"heix"
            | b"hevc"
            | b"hevx"
            | b"heim"
            | b"heis"
            | b"hevm"
            | b"hevs"
            | b"mif1"
            | b"msf1"
    )
}

#[cfg(test)]
mod tests {
    use std::{
        ffi::OsStr,
        io::{Cursor, Read, Seek, SeekFrom},
    };

    use image::hooks::decoding_hook_registered;
    use image::{ColorType, ImageEncoder, ImageFormat, codecs::png::PngEncoder};
    use moxcms::ColorProfile;
    use tiff::{
        encoder::{TiffEncoder, colortype},
        tags::ExtraSamples,
    };

    use super::{
        DecodeGuardrails, bytes_look_like_heif, decode_image_from_bytes, decode_image_from_path,
        decode_tiff_from_bytes, ensure_within_decode_pixel_cap, init_image_decoders,
        should_attempt_tiff_fallback,
    };
    use crate::ImageError;

    #[test]
    fn attempts_tiff_fallback_for_tiff_format() {
        assert!(should_attempt_tiff_fallback(Some(ImageFormat::Tiff)));
    }

    #[test]
    fn skips_tiff_fallback_for_non_tiff_formats() {
        assert!(!should_attempt_tiff_fallback(None));
        assert!(!should_attempt_tiff_fallback(Some(ImageFormat::Jpeg)));
        assert!(!should_attempt_tiff_fallback(Some(ImageFormat::Png)));
        assert!(!should_attempt_tiff_fallback(Some(ImageFormat::Avif)));
    }

    #[test]
    fn tiff_primary_and_fallback_decoders_keep_rgb_samples_in_order() {
        let rgb = [255, 0, 0, 0, 255, 128];
        let mut encoded = Cursor::new(Vec::new());
        {
            let mut encoder = TiffEncoder::new(&mut encoded).unwrap();
            encoder
                .new_image::<colortype::RGB8>(2, 1)
                .unwrap()
                .write_data(&rgb)
                .unwrap();
        }
        let bytes = encoded.into_inner();

        let fallback = decode_tiff_from_bytes(&bytes).unwrap();
        assert_eq!(fallback.image.into_rgb8().into_raw(), rgb);

        let primary = decode_image_from_bytes(&bytes).unwrap();
        assert_eq!(primary.dimensions.width, 2);
        assert_eq!(primary.dimensions.height, 1);
        assert_eq!(primary.rgb, rgb);
    }

    #[test]
    fn tiff_unspecified_extra_sample_keeps_rgb_channels() {
        let mut encoded = Cursor::new(Vec::new());
        {
            let mut encoder = TiffEncoder::new(&mut encoded).unwrap();
            let mut image = encoder.new_image::<colortype::RGB8>(1, 1).unwrap();
            image.extra_samples(&[ExtraSamples::Unspecified]).unwrap();
            image.write_data(&[17, 34, 51, 68]).unwrap();
        }
        let bytes = encoded.into_inner();

        assert_eq!(
            decode_tiff_from_bytes(&bytes)
                .unwrap()
                .image
                .into_rgb8()
                .into_raw(),
            [17, 34, 51]
        );
        assert_eq!(decode_image_from_bytes(&bytes).unwrap().rgb, [17, 34, 51]);
    }

    #[test]
    fn detects_heif_brand_in_bytes() {
        let bytes = b"\0\0\0\x18ftypheic\0\0\0\0";

        assert!(bytes_look_like_heif(bytes));
    }

    #[test]
    fn skips_non_heif_bytes() {
        assert!(!bytes_look_like_heif(b"not an image"));
    }

    #[test]
    fn admits_panoramas_and_phone_photos_within_the_pixel_cap() {
        ensure_within_decode_pixel_cap(20_000, 1_000).unwrap();
        ensure_within_decode_pixel_cap(8_064, 6_024).unwrap();
        ensure_within_decode_pixel_cap(8_000, 8_000).unwrap();
        ensure_within_decode_pixel_cap(21_000, 10_000).unwrap();
        assert!(ensure_within_decode_pixel_cap(21_000, 10_001).is_err());
        assert!(ensure_within_decode_pixel_cap(u32::MAX, u32::MAX).is_err());
    }

    #[test]
    fn rejects_images_exceeding_the_pixel_cap() {
        let bytes = header_only_png(
            300_000,
            1_000,
            ::png::ColorType::Grayscale,
            ::png::BitDepth::Eight,
        );

        assert!(matches!(
            decode_image_from_bytes(&bytes),
            Err(ImageError::TooLarge(_))
        ));
    }

    #[test]
    fn rejects_decoder_output_exceeding_the_alloc_cap() {
        let bytes = header_only_png(
            9_000,
            7_600,
            ::png::ColorType::Rgba,
            ::png::BitDepth::Sixteen,
        );

        assert!(matches!(
            decode_image_from_bytes(&bytes),
            Err(ImageError::TooLarge(_))
        ));
    }

    #[test]
    fn rejects_tiffs_exceeding_the_pixel_cap() {
        let bytes = header_only_gray_tiff(220_000, 1_000, 500);

        assert!(matches!(
            decode_tiff_from_bytes(&bytes),
            Err(ImageError::TooLarge(_))
        ));
        assert!(matches!(
            decode_image_from_bytes(&bytes),
            Err(ImageError::TooLarge(_))
        ));
    }

    #[test]
    fn rejects_over_cap_tiff_output_as_too_large() {
        let bytes = header_only_rgba16_tiff(9_000, 7_600);

        assert!(matches!(
            decode_tiff_from_bytes(&bytes),
            Err(ImageError::TooLarge(_))
        ));
        assert!(matches!(
            decode_image_from_bytes(&bytes),
            Err(ImageError::TooLarge(_))
        ));
    }

    #[test]
    fn rejects_over_cap_planar_tiff_as_too_large() {
        let bytes = planar_rgba16_header_only_tiff(9_000, 7_600, 3_800);

        assert!(matches!(
            decode_image_from_bytes(&bytes),
            Err(ImageError::TooLarge(_))
        ));
    }

    fn header_only_png(
        width: u32,
        height: u32,
        color: ::png::ColorType,
        depth: ::png::BitDepth,
    ) -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut encoder = ::png::Encoder::new(&mut bytes, width, height);
        encoder.set_color(color);
        encoder.set_depth(depth);
        let mut writer = encoder.write_header().unwrap();
        writer.write_chunk(::png::chunk::IDAT, &[]).unwrap();
        writer.finish().unwrap();
        bytes
    }

    fn header_only_gray_tiff(width: u32, height: u32, rows_per_strip: u32) -> Vec<u8> {
        let strips = height / rows_per_strip;
        let strip_bytes = width * rows_per_strip;
        let ifd_offset = 8u32;
        let ifd_bytes = 2 + 9 * 12 + 4;
        let strip_offsets_offset = ifd_offset + ifd_bytes;
        let strip_counts_offset = strip_offsets_offset + strips * 4;
        let strip_offset = strip_counts_offset + strips * 4;

        let entries: [(u16, u16, u32, u32); 9] = [
            (256, 4, 1, width),
            (257, 4, 1, height),
            (258, 3, 1, 8),
            (259, 3, 1, 1),
            (262, 3, 1, 1),
            (273, 4, strips, strip_offsets_offset),
            (277, 3, 1, 1),
            (278, 4, 1, rows_per_strip),
            (279, 4, strips, strip_counts_offset),
        ];

        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"II");
        bytes.extend_from_slice(&42u16.to_le_bytes());
        bytes.extend_from_slice(&ifd_offset.to_le_bytes());
        bytes.extend_from_slice(&(entries.len() as u16).to_le_bytes());
        for (tag, field_type, count, value) in entries {
            bytes.extend_from_slice(&tag.to_le_bytes());
            bytes.extend_from_slice(&field_type.to_le_bytes());
            bytes.extend_from_slice(&count.to_le_bytes());
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(&0u32.to_le_bytes());
        for strip in 0..strips {
            bytes.extend_from_slice(&(strip_offset + strip * strip_bytes).to_le_bytes());
        }
        for _ in 0..strips {
            bytes.extend_from_slice(&strip_bytes.to_le_bytes());
        }
        bytes
    }

    fn header_only_rgba16_tiff(width: u32, height: u32) -> Vec<u8> {
        let ifd_offset = 8u32;
        let ifd_bytes = 2 + 9 * 12 + 4;
        let bits_offset = ifd_offset + ifd_bytes;
        let strip_offset = bits_offset + 8;

        let entries: [(u16, u16, u32, u32); 9] = [
            (256, 4, 1, width),
            (257, 4, 1, height),
            (258, 3, 4, bits_offset),
            (259, 3, 1, 1),
            (262, 3, 1, 2),
            (273, 4, 1, strip_offset),
            (277, 3, 1, 4),
            (279, 4, 1, width * height * 8),
            (338, 3, 1, 0),
        ];

        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"II");
        bytes.extend_from_slice(&42u16.to_le_bytes());
        bytes.extend_from_slice(&ifd_offset.to_le_bytes());
        bytes.extend_from_slice(&(entries.len() as u16).to_le_bytes());
        for (tag, field_type, count, value) in entries {
            bytes.extend_from_slice(&tag.to_le_bytes());
            bytes.extend_from_slice(&field_type.to_le_bytes());
            bytes.extend_from_slice(&count.to_le_bytes());
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(&0u32.to_le_bytes());
        for _ in 0..4 {
            bytes.extend_from_slice(&16u16.to_le_bytes());
        }
        bytes
    }

    fn planar_rgba16_header_only_tiff(width: u32, height: u32, rows_per_strip: u32) -> Vec<u8> {
        let strips_per_plane = height / rows_per_strip;
        let strips = 4 * strips_per_plane;
        let strip_bytes = width * rows_per_strip * 2;
        let ifd_offset = 8u32;
        let ifd_bytes = 2 + 11 * 12 + 4;
        let bits_offset = ifd_offset + ifd_bytes;
        let strip_offsets_offset = bits_offset + 8;
        let strip_counts_offset = strip_offsets_offset + strips * 4;
        let strip_offset = strip_counts_offset + strips * 4;

        let entries: [(u16, u16, u32, u32); 11] = [
            (256, 4, 1, width),
            (257, 4, 1, height),
            (258, 3, 4, bits_offset),
            (259, 3, 1, 1),
            (262, 3, 1, 2),
            (273, 4, strips, strip_offsets_offset),
            (277, 3, 1, 4),
            (278, 4, 1, rows_per_strip),
            (279, 4, strips, strip_counts_offset),
            (284, 3, 1, 2),
            (338, 3, 1, 0),
        ];

        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"II");
        bytes.extend_from_slice(&42u16.to_le_bytes());
        bytes.extend_from_slice(&ifd_offset.to_le_bytes());
        bytes.extend_from_slice(&(entries.len() as u16).to_le_bytes());
        for (tag, field_type, count, value) in entries {
            bytes.extend_from_slice(&tag.to_le_bytes());
            bytes.extend_from_slice(&field_type.to_le_bytes());
            bytes.extend_from_slice(&count.to_le_bytes());
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(&0u32.to_le_bytes());
        for _ in 0..4 {
            bytes.extend_from_slice(&16u16.to_le_bytes());
        }
        for strip in 0..strips {
            bytes.extend_from_slice(&(strip_offset + strip * strip_bytes).to_le_bytes());
        }
        for _ in 0..strips {
            bytes.extend_from_slice(&strip_bytes.to_le_bytes());
        }
        bytes
    }

    #[test]
    fn registers_jxl_decoder_hook() {
        init_image_decoders();

        assert!(decoding_hook_registered(OsStr::new("jxl")));
    }

    #[test]
    fn registers_heif_family_decoder_hooks() {
        init_image_decoders();

        assert!(decoding_hook_registered(OsStr::new("heic")));
        assert!(decoding_hook_registered(OsStr::new("heif")));
        assert!(decoding_hook_registered(OsStr::new("avif")));
    }

    #[test]
    fn decode_applies_embedded_png_display_p3_profile() {
        let display_p3_icc = ColorProfile::new_display_p3().encode().unwrap();
        let png = encode_rgb8_png_with_icc([128, 0, 0], display_p3_icc);

        let decoded = decode_image_from_bytes(&png).unwrap();

        assert_eq!(decoded.dimensions.width, 1);
        assert_eq!(decoded.dimensions.height, 1);
        assert!(
            decoded.rgb[0] > 128,
            "expected red channel to move into sRGB"
        );
        assert_eq!(decoded.rgb[1], 0);
        assert_eq!(decoded.rgb[2], 0);
    }

    #[test]
    fn decode_leaves_embedded_png_srgb_profile_unchanged() {
        let srgb_icc = ColorProfile::new_srgb().encode().unwrap();
        let png = encode_rgb8_png_with_icc([128, 64, 32], srgb_icc);

        let decoded = decode_image_from_bytes(&png).unwrap();

        assert_eq!(decoded.rgb, vec![128, 64, 32]);
    }

    #[test]
    fn detects_jxl_signatures() {
        assert!(super::bytes_look_like_jxl(&[0xFF, 0x0A, 0x00]));
        assert!(super::bytes_look_like_jxl(&[
            0x00, 0x00, 0x00, 0x0C, b'J', b'X', b'L', b' ', 0x0D, 0x0A, 0x87, 0x0A, 0x00
        ]));
        assert!(!super::bytes_look_like_jxl(b"not an image"));
    }

    #[test]
    fn decode_applies_orientation_reported_by_png_decoder() {
        let mut encoded = Vec::new();
        let mut encoder = PngEncoder::new(&mut encoded);
        encoder.set_exif_metadata(exif_orientation(6)).unwrap();
        encoder
            .write_image(&[255, 0, 0, 0, 255, 0], 2, 1, ColorType::Rgb8.into())
            .unwrap();

        let decoded = decode_image_from_bytes(&encoded).unwrap();

        assert_eq!(decoded.dimensions.width, 1);
        assert_eq!(decoded.dimensions.height, 2);
        assert_eq!(decoded.rgb, vec![255, 0, 0, 0, 255, 0]);
    }

    #[test]
    fn decode_applies_orientation_to_grayscale_before_rgb_expansion() {
        let mut encoded = Vec::new();
        let mut encoder = PngEncoder::new(&mut encoded);
        encoder.set_exif_metadata(exif_orientation(6)).unwrap();
        encoder
            .write_image(&[255, 0], 2, 1, ColorType::L8.into())
            .unwrap();

        let decoded = decode_image_from_bytes(&encoded).unwrap();

        assert_eq!(decoded.dimensions.width, 1);
        assert_eq!(decoded.dimensions.height, 2);
        assert_eq!(decoded.rgb, vec![255, 255, 255, 0, 0, 0]);
    }

    fn encode_rgb8_png_with_icc(pixel: [u8; 3], icc_profile: Vec<u8>) -> Vec<u8> {
        let mut encoded = Vec::new();
        let mut encoder = PngEncoder::new(&mut encoded);
        encoder.set_icc_profile(icc_profile).unwrap();
        encoder
            .write_image(&pixel, 1, 1, ColorType::Rgb8.into())
            .unwrap();
        encoded
    }

    fn exif_orientation(orientation: u16) -> Vec<u8> {
        // Little-endian TIFF with one inline SHORT orientation and no next IFD.
        let mut exif = vec![
            b'I', b'I', 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0,
        ];
        exif[18..20].copy_from_slice(&orientation.to_le_bytes());
        exif
    }

    fn jxl_hook_guardrails(
        max_input_bytes: Option<u64>,
        max_pixels: Option<u64>,
    ) -> DecodeGuardrails {
        DecodeGuardrails {
            max_input_bytes,
            max_pixels,
            max_temp_spool_bytes: None,
            temp_spool_directory: None,
        }
    }

    #[test]
    fn rejects_jxl_inputs_exceeding_the_input_cap() {
        let guardrails = jxl_hook_guardrails(Some(4), None);

        let decoder =
            super::jxl_decoder_from_reader_with_guardrails(Cursor::new([0u8; 16]), &guardrails);
        assert!(matches!(decoder.err(), Some(image::ImageError::Limits(_))));
    }

    struct UnderreportingReader {
        remaining: usize,
    }

    impl Read for UnderreportingReader {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            let count = buf.len().min(self.remaining);
            buf[..count].fill(0);
            self.remaining -= count;
            Ok(count)
        }
    }

    impl Seek for UnderreportingReader {
        fn seek(&mut self, pos: SeekFrom) -> std::io::Result<u64> {
            match pos {
                SeekFrom::End(0) => Ok(4),
                SeekFrom::Start(0) => {
                    self.remaining = 16;
                    Ok(0)
                }
                _ => Err(std::io::Error::new(
                    std::io::ErrorKind::Unsupported,
                    "unsupported seek",
                )),
            }
        }
    }

    #[test]
    fn rejects_jxl_inputs_exceeding_the_input_cap_when_the_source_underreports_its_length() {
        let guardrails = jxl_hook_guardrails(Some(4), None);

        let decoder = super::jxl_decoder_from_reader_with_guardrails(
            UnderreportingReader { remaining: 16 },
            &guardrails,
        );
        assert!(matches!(decoder.err(), Some(image::ImageError::Limits(_))));
    }

    #[test]
    fn rejects_jxl_inputs_exceeding_the_production_cap_through_the_public_path() {
        let temp = tempfile::Builder::new().suffix(".jxl").tempfile().unwrap();
        std::fs::write(temp.path(), [0xFF, 0x0A]).unwrap();
        let file = std::fs::OpenOptions::new()
            .write(true)
            .open(temp.path())
            .unwrap();
        file.set_len(128 * 1024 * 1024 + 1).unwrap();
        drop(file);

        assert!(matches!(
            decode_image_from_path(temp.path().to_str().unwrap()),
            Err(ImageError::TooLarge(_))
        ));
    }

    #[test]
    fn bounded_reader_errors_once_the_input_cap_is_exceeded() {
        let mut reader = super::BoundedReader::new(Cursor::new([7u8; 16]), 8);
        let mut buf = [0u8; 4];

        assert_eq!(reader.read(&mut buf).unwrap(), 4);
        assert_eq!(reader.read(&mut buf).unwrap(), 4);
        assert!(
            reader
                .read(&mut buf)
                .unwrap_err()
                .to_string()
                .contains("max_input_bytes")
        );
    }
}
