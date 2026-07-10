use std::{
    any::Any,
    ffi::OsStr,
    fs::File,
    io::{BufRead, BufReader, Cursor, Read, Seek, SeekFrom},
    panic::{self, AssertUnwindSafe},
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
};
use jxl_oxide::integration::register_image_decoding_hook as register_jxl_decoding_hook;
use rawler::{
    decoders::{
        Decoder as RawDecoder, FormatHint as RawFormatHint, Orientation as RawOrientation,
        RawDecodeParams, WellKnownIFD,
    },
    formats::{
        bmff::Bmff,
        tiff::{GenericTiffReader, IFD, ifd::DataMode, reader::TiffReader},
    },
    imgop::develop::RawDevelop,
    rawsource::RawSource,
    tags::TiffCommonTag as RawTiffCommonTag,
};
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

const RAW_MAX_INPUT_BYTES: u64 = 256 * 1024 * 1024;
/// RAW development goes through a planar f32 intermediate (~12 bytes per pixel)
/// on top of the u16 mosaic and Rgb16 output, so peak memory is roughly 18
/// bytes per pixel. 200M pixels keeps headroom above the largest current
/// sensors (Phase One IQ4 at ~151MP) while bounding worst-case allocations.
const RAW_MAX_PIXELS: u128 = 200_000_000;
/// Matches rawler 0.7.2's `alloc_image!` guard. The CRX decoder bypasses that
/// macro but allocates multiple line and wavelet buffers proportional to one
/// side, so total pixels alone is not a sufficient allocation bound.
const RAW_MAX_DIMENSION: usize = 50_000;
const RAW_EXTENSIONS: &[&str] = &[
    "3fr", "ari", "arw", "cr2", "cr3", "crm", "crw", "dcr", "dcs", "dng", "erf", "fff", "iiq",
    "kdc", "mef", "mos", "mrw", "nef", "nrw", "orf", "ori", "pef", "qtk", "raf", "raw", "rw2",
    "rwl", "srw", "x3f",
];
/// Magic-byte prefixes of RAW containers that must be routed to the RAW
/// pipeline first. The list need not be exhaustive: formats missed here are
/// still caught by the RAW extension routing or by the RAW fallback after an
/// image crate failure.
///
/// TIFF magic is deliberately absent even though most RAW formats
/// (NEF/ARW/CR2/DNG/PEF/SRW/...) are TIFF containers whose first IFD is often
/// a decodable thumbnail the image crate would "successfully" decode. TIFF
/// containers are instead pre-screened with [`tiff_looks_like_camera_raw`]:
/// only TIFFs carrying the camera markers rawler dispatches on stay RAW
/// candidates, and plain TIFFs skip the RAW pipeline (and the full-input
/// reads and copies a failed rawler probe would cost) entirely.
const RAW_MAGIC_PREFIXES: &[&[u8]] = &[
    b"II\x1a\0", // Canon CRW
    b"IIU\0",    // Panasonic RW2/RWL
    b"IIRO",     // Olympus ORF
    b"IIRS",     // Olympus ORF
    b"MMOR",     // Olympus ORF (big-endian)
    b"FUJIFILM", // Fujifilm RAF
    b"FOVb",     // Sigma X3F
    b"\0MRM",    // Minolta MRW
];
const TIFF_MAGIC_LITTLE_ENDIAN: &[u8] = b"II*\0";
const TIFF_MAGIC_BIG_ENDIAN: &[u8] = b"MM\0*";

/// IFD tags rawler's TIFF probe dispatches on, mirrored by
/// [`tiff_looks_like_camera_raw`] (see rawler 0.7.2 `get_decoder`): `Make`
/// drives the main dispatch table, `Model` catches the Kodak DCS560C special
/// case, `DNGVersion` selects the DNG decoder, and `Software == "Camera
/// Library"` identifies Leaf MOS backs that carry neither Make nor Model.
const TIFF_TAG_MAKE: u16 = 0x010F;
const TIFF_TAG_MODEL: u16 = 0x0110;
const TIFF_TAG_SOFTWARE: u16 = 0x0131;
const TIFF_TAG_DNG_VERSION: u16 = 0xC612;
const TIFF_ASCII_TYPE: u16 = 2;
const LEAF_MOS_SOFTWARE: &str = "Camera Library";
/// Walk limits for the TIFF pre-screen. Real files stay far below both;
/// exceeding them aborts the walk conservatively (treat as RAW candidate).
const TIFF_PRESCREEN_MAX_IFDS: usize = 32;
const TIFF_PRESCREEN_MAX_ENTRIES_PER_IFD: u16 = 4096;
/// "Camera Library" is 14 bytes plus a NUL terminator; a longer `Software`
/// value cannot equal it under rawler's exact comparison.
const TIFF_PRESCREEN_MAX_SOFTWARE_BYTES: u32 = 64;

struct DecodedDynamicImage {
    image: DynamicImage,
    icc_profile: Option<Vec<u8>>,
}

impl DecodedDynamicImage {
    fn into_srgb(self) -> DynamicImage {
        apply_icc_profile_to_srgb(self.image, self.icc_profile.as_deref())
    }
}

pub fn decode_image_from_path(image_path: &str) -> ImageResult<DecodedImage> {
    let oriented = decode_dynamic_from_path(image_path)?.into_rgb8();

    Ok(DecodedImage {
        dimensions: Dimensions {
            width: oriented.width(),
            height: oriented.height(),
        },
        rgb: oriented.into_raw(),
    })
}

pub fn decode_image_from_bytes(image_bytes: &[u8]) -> ImageResult<DecodedImage> {
    let oriented = decode_dynamic_from_bytes(image_bytes)?.into_rgb8();

    Ok(DecodedImage {
        dimensions: Dimensions {
            width: oriented.width(),
            height: oriented.height(),
        },
        rgb: oriented.into_raw(),
    })
}

/// Decode an image from a path and apply EXIF orientation.
///
/// RAW candidates go to the RAW pipeline first (see [`RAW_MAGIC_PREFIXES`] for
/// why the image crate must not see them first). For TIFF containers, "magic
/// says RAW" additionally requires camera markers in the IFD chain (see
/// [`tiff_looks_like_camera_raw`]); marker-less TIFFs go straight to the
/// image crate. How RAW failures are handled depends on the strength of the
/// RAW signal:
///
/// - Extension and magic both say RAW: the file is committed to the RAW
///   pipeline and every failure — oversized input, unmatched camera model,
///   decode/develop error — is a hard error. Falling back would let the image
///   crate decode the embedded preview of a TIFF-based RAW and silently
///   return a thumbnail-sized image.
/// - Only one signal says RAW (a camera-marker TIFF without a RAW extension —
///   typically a `.tif` export that kept its camera EXIF — or a misnamed file
///   whose magic disagrees): the RAW attempt is opportunistic and any RAW
///   failure falls back to the image crate. This matters because rawler's
///   probe dispatches TIFF containers on the EXIF `Make` tag alone, so a
///   plain TIFF exported from a camera photo can pass the probe and only
///   fail later in `raw_image()` — such files must keep decoding as TIFFs.
///
/// The size guardrail runs before the RAW source is constructed because
/// constructing it materializes the entire input (`RawSource::new` mmaps with
/// populate, `RawSource::new_from_slice` copies, and a failed probe copies
/// the buffer again for the naked-RAW lookup).
fn decode_dynamic_from_path(image_path: &str) -> ImageResult<DynamicImage> {
    let extension_is_raw = path_extension_is_raw(Path::new(image_path));
    let magic_is_raw = file_magic_looks_like_raw(image_path);
    if !extension_is_raw && !magic_is_raw {
        let decoded = decode_with_image_crate(image_path)?;
        return Ok(orient_decoded_image(decoded, image_path));
    }

    let input_bytes = std::fs::metadata(image_path)
        .map(|metadata| metadata.len())
        .unwrap_or(0);

    if extension_is_raw && magic_is_raw {
        validate_raw_input_size(input_bytes, image_path)?;
        // Hard-error domain: RAWs from camera models newer than the pinned
        // rawler's model database land on the ProbeRejected arm by design —
        // better no result than a silently indexed thumbnail. If that proves
        // too strict, a follow-up could serve the embedded JPEG preview
        // (rawler's `Decoder::full_image`) when `raw_image` fails for a
        // matched model; probe rejections carry no decoder and would need a
        // generic preview extraction instead.
        return match decode_raw_from_path(image_path)? {
            RawDecodeOutcome::Decoded(decoded) => Ok(decoded),
            RawDecodeOutcome::ProbeRejected(probe_error) => Err(ImageError::Decode(format!(
                "'{image_path}' looks like a camera RAW but no RAW decoder matched (camera model not supported by rawler?), refusing thumbnail fallback: {probe_error}"
            ))),
        };
    }

    let raw_failure = if input_bytes <= RAW_MAX_INPUT_BYTES {
        match decode_raw_from_path(image_path) {
            Ok(RawDecodeOutcome::Decoded(decoded)) => return Ok(decoded),
            Ok(RawDecodeOutcome::ProbeRejected(probe_error)) => probe_error,
            Err(ImageError::Decode(raw_error)) => raw_error,
            Err(other) => return Err(other),
        }
    } else {
        format!("RAW decode skipped: {input_bytes} bytes exceeds {RAW_MAX_INPUT_BYTES} bytes")
    };

    match decode_with_image_crate(image_path) {
        Ok(decoded) => Ok(orient_decoded_image(decoded, image_path)),
        Err(ImageError::Decode(fallback_error)) => Err(ImageError::Decode(format!(
            "{raw_failure}; image crate fallback also failed: {fallback_error}"
        ))),
        Err(other) => Err(other),
    }
}

/// Decode an image from bytes and apply EXIF orientation.
///
/// Mirrors [`decode_dynamic_from_path`], but bytes carry no file name, so
/// there is never a second RAW signal to corroborate the magic bytes: the RAW
/// attempt is always opportunistic and any RAW failure falls back to the
/// image crate. TIFF-magic bytes reach the RAW branch only when the
/// pre-screen finds camera markers (see [`tiff_looks_like_camera_raw`]);
/// marker-less TIFFs decode via the image crate directly. Bytes that don't
/// look like RAW still get a RAW fallback after an image crate failure, to
/// catch RAW containers whose magic is not in [`RAW_MAGIC_PREFIXES`].
/// Oversized input skips the RAW attempt entirely so that
/// `RawSource::new_from_slice` never copies more than
/// [`RAW_MAX_INPUT_BYTES`].
fn decode_dynamic_from_bytes(image_bytes: &[u8]) -> ImageResult<DynamicImage> {
    let within_raw_size_limit = image_bytes.len() as u64 <= RAW_MAX_INPUT_BYTES;

    if bytes_look_like_raw(image_bytes) {
        let raw_failure = if within_raw_size_limit {
            match decode_raw_from_bytes(image_bytes) {
                Ok(RawDecodeOutcome::Decoded(decoded)) => return Ok(decoded),
                Ok(RawDecodeOutcome::ProbeRejected(probe_error)) => probe_error,
                Err(ImageError::Decode(raw_error)) => raw_error,
                Err(other) => return Err(other),
            }
        } else {
            format!(
                "RAW decode skipped: {} bytes exceeds {RAW_MAX_INPUT_BYTES} bytes",
                image_bytes.len()
            )
        };

        return match decode_bytes_with_image_crate(image_bytes) {
            Ok(decoded) => Ok(orient_decoded_image_from_bytes(decoded, image_bytes)),
            Err(ImageError::Decode(fallback_error)) => Err(ImageError::Decode(format!(
                "{raw_failure}; image crate fallback also failed: {fallback_error}"
            ))),
            Err(other) => Err(other),
        };
    }

    match decode_bytes_with_image_crate(image_bytes) {
        Ok(decoded) => Ok(orient_decoded_image_from_bytes(decoded, image_bytes)),
        Err(primary_error) => {
            if !within_raw_size_limit {
                return Err(primary_error);
            }
            let raw_failure = match decode_raw_from_bytes(image_bytes) {
                Ok(RawDecodeOutcome::Decoded(decoded)) => return Ok(decoded),
                Ok(RawDecodeOutcome::ProbeRejected(probe_error)) => probe_error,
                Err(ImageError::Decode(raw_error)) => raw_error,
                Err(other) => return Err(other),
            };
            Err(ImageError::Decode(format!(
                "failed to decode image with image crate: {primary_error}; RAW fallback also failed: {raw_failure}"
            )))
        }
    }
}

fn decode_with_image_crate(image_path: &str) -> ImageResult<DynamicImage> {
    init_image_decoders();

    let reader = ImageReader::open(image_path)
        .map_err(|e| ImageError::Decode(format!("failed to open image file '{image_path}': {e}")))?
        .with_guessed_format()
        .map_err(|e| ImageError::Decode(format!("failed to guess image format: {e}")))?;
    let guessed_format = reader.format();

    match decode_reader_with_image_crate(reader) {
        Ok(decoded) => Ok(decoded.into_srgb()),
        Err(primary_error) if should_attempt_tiff_fallback(guessed_format) => {
            eprintln!(
                "[ml][decode] image crate TIFF decode failed for '{}': {}. Retrying with tiff crate fallback",
                image_path, primary_error
            );

            match decode_with_tiff_crate(image_path) {
                Ok(decoded) => Ok(decoded.into_srgb()),
                Err(ImageError::Decode(fallback_error)) => Err(ImageError::Decode(format!(
                    "failed to decode TIFF with image crate: {primary_error}; fallback with tiff crate also failed: {fallback_error}"
                ))),
                Err(other) => Err(other),
            }
        }
        Err(other) => Err(other.into()),
    }
}

fn decode_bytes_with_image_crate(image_bytes: &[u8]) -> ImageResult<DynamicImage> {
    init_image_decoders();

    let reader = ImageReader::new(Cursor::new(image_bytes))
        .with_guessed_format()
        .map_err(|e| ImageError::Decode(format!("failed to guess image format: {e}")))?;
    let guessed_format = reader.format();

    match decode_reader_with_image_crate(reader) {
        Ok(decoded) => Ok(decoded.into_srgb()),
        Err(primary_error) if should_attempt_tiff_fallback(guessed_format) => {
            match decode_tiff_from_bytes(image_bytes) {
                Ok(decoded) => Ok(decoded.into_srgb()),
                Err(ImageError::Decode(fallback_error)) => Err(ImageError::Decode(format!(
                    "failed to decode TIFF with image crate: {primary_error}; fallback with tiff crate also failed: {fallback_error}"
                ))),
                Err(other) => Err(other),
            }
        }
        Err(other) => Err(other.into()),
    }
}

fn decode_reader_with_image_crate<R>(
    reader: ImageReader<R>,
) -> image::ImageResult<DecodedDynamicImage>
where
    R: BufRead + Seek,
{
    let mut decoder = reader.into_decoder()?;
    let icc_profile = match decoder.icc_profile() {
        Ok(icc_profile) => icc_profile,
        Err(err) => {
            eprintln!("[ml][decode] failed to read embedded ICC profile: {err}");
            None
        }
    };

    let mut limits = Limits::default();
    limits.reserve(decoder.total_bytes())?;
    decoder.set_limits(limits)?;

    Ok(DecodedDynamicImage {
        image: DynamicImage::from_decoder(decoder)?,
        icc_profile,
    })
}

fn should_attempt_tiff_fallback(format: Option<ImageFormat>) -> bool {
    matches!(format, Some(ImageFormat::Tiff))
}

/// Outcome of routing an input through the RAW pipeline.
///
/// `ProbeRejected` is separated from hard errors so that callers can apply
/// their fallback policy (see [`decode_dynamic_from_path`]): in the committed
/// domain (extension and magic both say RAW) a rejection is a hard error,
/// while opportunistic callers treat rejections and decode failures alike and
/// fall back to the image crate. Size guardrails are enforced by the callers
/// before the `RawSource` is constructed, because construction materializes
/// the entire input.
enum RawDecodeOutcome {
    /// Successfully decoded, developed, and oriented.
    Decoded(DynamicImage),
    /// rawler does not recognize the input as a supported camera RAW.
    ProbeRejected(String),
}

fn decode_raw_from_path(image_path: &str) -> ImageResult<RawDecodeOutcome> {
    catch_raw_decode_panic(image_path, || {
        let source = RawSource::new(Path::new(image_path)).map_err(|e| {
            ImageError::Decode(format!("failed to open RAW image file '{image_path}': {e}"))
        })?;
        decode_raw_source_to_dynamic_image(&source, image_path)
    })
}

fn decode_raw_from_bytes(image_bytes: &[u8]) -> ImageResult<RawDecodeOutcome> {
    catch_raw_decode_panic("<bytes>", || {
        let source = RawSource::new_from_slice(image_bytes);
        decode_raw_source_to_dynamic_image(&source, "<bytes>")
    })
}

/// Decode and develop a RAW image. The returned image is already oriented:
/// EXIF orientation must come from the RAW metadata because the kamadak-exif
/// pass in [`orient_decoded_image`] cannot read most RAW containers
/// (CR3/RAF/RW2/ORF have non-TIFF magic or store EXIF in proprietary boxes).
fn decode_raw_source_to_dynamic_image(
    source: &RawSource,
    source_name: &str,
) -> ImageResult<RawDecodeOutcome> {
    let decode_params = RawDecodeParams::default();
    let decoder = match rawler::get_decoder(source) {
        Ok(decoder) => decoder,
        Err(probe_error) => {
            return Ok(RawDecodeOutcome::ProbeRejected(format!(
                "input not recognized as a supported camera RAW: {probe_error}"
            )));
        }
    };

    validate_raw_dimensions_before_decode(decoder.as_ref(), source, source_name)?;

    let raw_image = decoder
        .raw_image(source, &decode_params, false)
        .map_err(|e| ImageError::Decode(format!("failed to decode RAW image: {e}")))?;
    validate_raw_dimensions(raw_image.width, raw_image.height, source_name)?;
    // `RawImage::orientation` is only populated by rawler 0.7.2's DNG and QTK
    // decoders; every other decoder leaves it hardcoded to `Normal` (upstream
    // rawimage.rs "TODO fixme"). It is therefore only usable as a fallback —
    // the `raw_metadata` pass below is the authoritative orientation source
    // and must not be "simplified" away in favor of this field.
    let raw_image_orientation = raw_orientation_to_exif(raw_image.orientation);

    let developed = RawDevelop::default()
        .develop_intermediate(&raw_image)
        .map_err(|e| ImageError::Decode(format!("failed to develop RAW image: {e}")))?;
    let image = developed.to_dynamic_image().ok_or_else(|| {
        ImageError::Decode(format!(
            "failed to materialize developed RAW image for '{source_name}'"
        ))
    })?;
    validate_raw_dimensions(image.width() as usize, image.height() as usize, source_name)?;

    // Orientation is best effort: a metadata read failure should not discard
    // an otherwise successfully developed image.
    let metadata_orientation = match decoder.raw_metadata(source, &decode_params) {
        Ok(metadata) => metadata
            .exif
            .orientation
            .and_then(|value| u8::try_from(value).ok())
            .filter(|value| (1..=8).contains(value)),
        Err(err) => {
            eprintln!(
                "[ml][decode] failed to read RAW metadata for '{source_name}': {err}; falling back to decoded RAW orientation"
            );
            None
        }
    };
    let orientation = metadata_orientation.or(raw_image_orientation);

    Ok(RawDecodeOutcome::Decoded(match orientation {
        Some(orientation) => apply_exif_orientation_dynamic(image, orientation),
        None => image,
    }))
}

/// Best-effort dimension preflight before any pixel decode allocates.
/// Coverage: DNG exposes its raw IFD via `Decoder::ifd` (the only rawler
/// 0.7.2 decoder that implements it), CR3/CRM dimensions come from the CMP1
/// box, and other TIFF-based RAWs (NEF/ARW/CR2/PEF/SRW/...) are covered by
/// the TIFF IFD walk. Formats not covered here (RW2/RAF/CRW/MRW/..., and
/// buffers sized from embedded codec headers rather than container tags)
/// are bounded by rawler's internal `alloc_image!` caps (500MP, 50k px per
/// side), whose panics [`catch_raw_decode_panic`] converts to errors. Known
/// residual gap: IIQ's proprietary block parser allocates from an
/// unvalidated entry count upstream.
fn validate_raw_dimensions_before_decode(
    decoder: &dyn RawDecoder,
    source: &RawSource,
    source_name: &str,
) -> ImageResult<()> {
    if let Some(raw_ifd) = decoder
        .ifd(WellKnownIFD::Raw)
        .map_err(|e| ImageError::Decode(format!("failed to inspect RAW dimensions: {e}")))?
        && let Some((width, height)) = raw_dimensions_from_ifd(&raw_ifd)
    {
        validate_raw_dimensions(width, height, source_name)?;
        validate_dng_raw_ifd_allocation(&raw_ifd, source_name)?;
        return Ok(());
    }

    validate_raw_candidate_dimensions_for_format(decoder.format_hint(), source, source_name)
}

fn validate_raw_candidate_dimensions_for_format(
    format_hint: RawFormatHint,
    source: &RawSource,
    source_name: &str,
) -> ImageResult<()> {
    match format_hint {
        RawFormatHint::CR3 => validate_cr3_raw_candidate_dimensions(source, source_name),
        _ => validate_tiff_raw_candidate_dimensions(source, source_name),
    }
}

/// Validate the allocation dimensions used by rawler 0.7.2's
/// `plain_image_from_ifd` DNG path. The decoded buffer includes every sample
/// and is padded out to complete tile boundaries before rawler crops it back
/// to the nominal image dimensions.
fn validate_dng_raw_ifd_allocation(raw_ifd: &IFD, source_name: &str) -> ImageResult<()> {
    let (width, height) = raw_dimensions_from_ifd(raw_ifd).ok_or_else(|| {
        ImageError::Decode(format!(
            "failed to inspect DNG allocation dimensions for '{source_name}'"
        ))
    })?;
    let samples_per_pixel = raw_ifd
        .get_entry(RawTiffCommonTag::SamplesPerPixel)
        .map(|entry| entry.force_usize(0))
        .ok_or_else(|| {
            ImageError::Decode(format!(
                "DNG image '{source_name}' has no SamplesPerPixel value"
            ))
        })?;
    if samples_per_pixel == 0 {
        return Err(ImageError::Decode(format!(
            "DNG image '{source_name}' has invalid SamplesPerPixel value 0"
        )));
    }

    let (decode_width, decode_height) = match raw_ifd.data_mode().map_err(|e| {
        ImageError::Decode(format!(
            "failed to inspect DNG storage layout for '{source_name}': {e}"
        ))
    })? {
        DataMode::Strips => (width, height),
        DataMode::Tiles => {
            let tile_width = raw_ifd
                .get_entry(RawTiffCommonTag::TileWidth)
                .map(|entry| entry.force_usize(0))
                .ok_or_else(|| {
                    ImageError::Decode(format!(
                        "tiled DNG image '{source_name}' has no TileWidth value"
                    ))
                })?;
            let tile_height = raw_ifd
                .get_entry(RawTiffCommonTag::TileLength)
                .map(|entry| entry.force_usize(0))
                .ok_or_else(|| {
                    ImageError::Decode(format!(
                        "tiled DNG image '{source_name}' has no TileLength value"
                    ))
                })?;
            (
                padded_dng_dimension(width, tile_width, "width", source_name)?,
                padded_dng_dimension(height, tile_height, "height", source_name)?,
            )
        }
    };

    let sample_width = decode_width.checked_mul(samples_per_pixel).ok_or_else(|| {
        ImageError::Decode(format!(
            "DNG image '{source_name}' decoded sample width overflows: {decode_width} * {samples_per_pixel}"
        ))
    })?;
    validate_raw_sample_allocation(sample_width, decode_height, source_name)
}

fn padded_dng_dimension(
    dimension: usize,
    tile_dimension: usize,
    axis: &str,
    source_name: &str,
) -> ImageResult<usize> {
    if tile_dimension == 0 {
        return Err(ImageError::Decode(format!(
            "DNG image '{source_name}' has invalid tile {axis} 0"
        )));
    }

    let tile_count = (dimension / tile_dimension)
        .checked_add(usize::from(!dimension.is_multiple_of(tile_dimension)))
        .ok_or_else(|| {
            ImageError::Decode(format!("DNG image '{source_name}' padded {axis} overflows"))
        })?;
    tile_count.checked_mul(tile_dimension).ok_or_else(|| {
        ImageError::Decode(format!("DNG image '{source_name}' padded {axis} overflows"))
    })
}

fn validate_raw_sample_allocation(
    sample_width: usize,
    sample_height: usize,
    source_name: &str,
) -> ImageResult<()> {
    if sample_width == 0 || sample_height == 0 {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' has invalid decoded sample dimensions {sample_width}x{sample_height}"
        )));
    }
    validate_raw_side_limit(
        sample_width,
        sample_height,
        source_name,
        "decoded sample dimensions",
    )?;

    let samples = (sample_width as u128) * (sample_height as u128);
    if samples > RAW_MAX_PIXELS {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' is too large to decode safely: decoded sample allocation {sample_width}x{sample_height} exceeds {RAW_MAX_PIXELS} samples"
        )));
    }

    Ok(())
}

/// CR3/CRM preflight. rawler's crx decompressor sizes its output and line
/// buffers straight from the CMP1 box's `f_width`/`f_height` with no
/// internal cap (unlike the `alloc_image!` guards in most other decode
/// paths), so a crafted CMP1 can request an arbitrarily large allocation —
/// and an allocation failure aborts the process, which `catch_unwind`
/// cannot intercept. Parse the same box tree rawler's Cr3Decoder navigates
/// and validate every CMP1 before any pixel decode. The decoder format is
/// already known by the time this runs, so a second parse failure is treated
/// as a validation failure rather than allowing the decode to proceed.
fn validate_cr3_raw_candidate_dimensions(source: &RawSource, source_name: &str) -> ImageResult<()> {
    let bmff = Bmff::new(&mut source.reader()).map_err(|e| {
        ImageError::Decode(format!(
            "failed to inspect CR3 dimensions for '{source_name}': {e}"
        ))
    })?;

    for trak in &bmff.filebox.moov.traks {
        if let Some(craw) = &trak.mdia.minf.stbl.stsd.craw
            && let Some(cmp1) = &craw.cmp1
        {
            validate_raw_dimensions(cmp1.f_width as usize, cmp1.f_height as usize, source_name)?;
        }
    }

    Ok(())
}

fn validate_tiff_raw_candidate_dimensions(
    source: &RawSource,
    source_name: &str,
) -> ImageResult<()> {
    let mut reader = source.reader();
    let tiff = match GenericTiffReader::new(&mut reader, 0, 0, None, &[]) {
        Ok(tiff) => tiff,
        Err(_) => return Ok(()),
    };

    for ifd in tiff.find_ifds_with_filter(|ifd| {
        raw_dimensions_from_ifd(ifd).is_some()
            && (ifd.has_entry(RawTiffCommonTag::StripOffsets)
                || ifd.has_entry(RawTiffCommonTag::TileOffsets))
    }) {
        if let Some((width, height)) = raw_dimensions_from_ifd(ifd) {
            validate_raw_dimensions(width, height, source_name)?;
        }
    }

    Ok(())
}

fn raw_dimensions_from_ifd(ifd: &IFD) -> Option<(usize, usize)> {
    let width = ifd
        .get_entry(RawTiffCommonTag::ImageWidth)
        .map(|entry| entry.force_usize(0))?;
    let height = ifd
        .get_entry(RawTiffCommonTag::ImageLength)
        .map(|entry| entry.force_usize(0))?;
    Some((width, height))
}

fn raw_orientation_to_exif(orientation: RawOrientation) -> Option<u8> {
    match orientation {
        RawOrientation::Normal => Some(1),
        RawOrientation::HorizontalFlip => Some(2),
        RawOrientation::Rotate180 => Some(3),
        RawOrientation::VerticalFlip => Some(4),
        RawOrientation::Transpose => Some(5),
        RawOrientation::Rotate90 => Some(6),
        RawOrientation::Transverse => Some(7),
        RawOrientation::Rotate270 => Some(8),
        RawOrientation::Unknown => None,
    }
}

fn catch_raw_decode_panic<T, F>(source_name: &str, decode: F) -> ImageResult<T>
where
    F: FnOnce() -> ImageResult<T>,
{
    match panic::catch_unwind(AssertUnwindSafe(decode)) {
        Ok(result) => result,
        Err(payload) => Err(ImageError::Decode(format!(
            "RAW decoder panicked while decoding '{source_name}': {}",
            panic_payload_message(payload)
        ))),
    }
}

fn validate_raw_input_size(input_bytes: u64, source_name: &str) -> ImageResult<()> {
    if input_bytes > RAW_MAX_INPUT_BYTES {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' is too large to decode safely: {input_bytes} bytes exceeds {RAW_MAX_INPUT_BYTES} bytes"
        )));
    }
    Ok(())
}

fn validate_raw_dimensions(width: usize, height: usize, source_name: &str) -> ImageResult<()> {
    if width == 0 || height == 0 {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' decoded to invalid dimensions {width}x{height}"
        )));
    }
    validate_raw_side_limit(width, height, source_name, "dimensions")?;

    let pixels = (width as u128) * (height as u128);
    if pixels > RAW_MAX_PIXELS {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' is too large to decode safely: {width}x{height} exceeds {RAW_MAX_PIXELS} pixels"
        )));
    }

    Ok(())
}

fn validate_raw_side_limit(
    width: usize,
    height: usize,
    source_name: &str,
    dimension_kind: &str,
) -> ImageResult<()> {
    if width > RAW_MAX_DIMENSION || height > RAW_MAX_DIMENSION {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' is too large to decode safely: {dimension_kind} {width}x{height} exceeds maximum side length {RAW_MAX_DIMENSION}"
        )));
    }

    Ok(())
}

fn panic_payload_message(payload: Box<dyn Any + Send>) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        return (*message).to_string();
    }
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    "unknown panic payload".to_string()
}

fn decode_with_tiff_crate(image_path: &str) -> ImageResult<DecodedDynamicImage> {
    let file = File::open(image_path)
        .map_err(|e| ImageError::Decode(format!("failed to open TIFF file '{image_path}': {e}")))?;
    let mut decoder = TiffDecoder::new(BufReader::new(file))
        .map_err(|e| ImageError::Decode(format!("failed to initialize TIFF decoder: {e}")))?;
    let (width, height) = decoder
        .dimensions()
        .map_err(|e| ImageError::Decode(format!("failed to read TIFF dimensions: {e}")))?;
    let color_type = decoder
        .colortype()
        .map_err(|e| ImageError::Decode(format!("failed to read TIFF color type: {e}")))?;
    let icc_profile = decoder.get_tag_u8_vec(TiffTag::IccProfile).ok();
    let decoded = decoder
        .read_image()
        .map_err(|e| ImageError::Decode(format!("failed to decode TIFF image data: {e}")))?;

    Ok(DecodedDynamicImage {
        image: dynamic_image_from_tiff(image_path, width, height, color_type, decoded)?,
        icc_profile,
    })
}

fn decode_tiff_from_bytes(image_bytes: &[u8]) -> ImageResult<DecodedDynamicImage> {
    let mut decoder = TiffDecoder::new(Cursor::new(image_bytes))
        .map_err(|e| ImageError::Decode(format!("failed to initialize TIFF decoder: {e}")))?;
    let (width, height) = decoder
        .dimensions()
        .map_err(|e| ImageError::Decode(format!("failed to read TIFF dimensions: {e}")))?;
    let color_type = decoder
        .colortype()
        .map_err(|e| ImageError::Decode(format!("failed to read TIFF color type: {e}")))?;
    let icc_profile = decoder.get_tag_u8_vec(TiffTag::IccProfile).ok();
    let decoded = decoder
        .read_image()
        .map_err(|e| ImageError::Decode(format!("failed to decode TIFF image data: {e}")))?;

    Ok(DecodedDynamicImage {
        image: dynamic_image_from_tiff("<bytes>", width, height, color_type, decoded)?,
        icc_profile,
    })
}

fn dynamic_image_from_tiff(
    image_path: &str,
    width: u32,
    height: u32,
    color_type: TiffColorType,
    decoded: TiffDecodingResult,
) -> ImageResult<DynamicImage> {
    match (color_type, decoded) {
        (TiffColorType::Gray(8), TiffDecodingResult::U8(data)) => {
            let image = image::GrayImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(image_path, width, height, "Gray(8)"))?;
            Ok(DynamicImage::ImageLuma8(image))
        }
        (TiffColorType::GrayA(8), TiffDecodingResult::U8(data)) => {
            let image = image::GrayAlphaImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(image_path, width, height, "GrayA(8)"))?;
            Ok(DynamicImage::ImageLumaA8(image))
        }
        (TiffColorType::RGB(8), TiffDecodingResult::U8(data)) => {
            let image = image::RgbImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(image_path, width, height, "RGB(8)"))?;
            Ok(DynamicImage::ImageRgb8(image))
        }
        (TiffColorType::RGBA(8), TiffDecodingResult::U8(data)) => {
            let image = image::RgbaImage::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(image_path, width, height, "RGBA(8)"))?;
            Ok(DynamicImage::ImageRgba8(image))
        }
        (TiffColorType::Gray(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(image_path, width, height, "Gray(16)"))?;
            Ok(DynamicImage::ImageLuma16(image))
        }
        (TiffColorType::GrayA(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data).ok_or_else(|| {
                tiff_buffer_mismatch_error(image_path, width, height, "GrayA(16)")
            })?;
            Ok(DynamicImage::ImageLumaA16(image))
        }
        (TiffColorType::RGB(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(image_path, width, height, "RGB(16)"))?;
            Ok(DynamicImage::ImageRgb16(image))
        }
        (TiffColorType::RGBA(16), TiffDecodingResult::U16(data)) => {
            let image = image::ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| tiff_buffer_mismatch_error(image_path, width, height, "RGBA(16)"))?;
            Ok(DynamicImage::ImageRgba16(image))
        }
        (observed_color_type, observed_result_type) => Err(ImageError::Decode(format!(
            "unsupported TIFF pixel format for '{image_path}': color_type={observed_color_type:?}, sample_type={}",
            tiff_result_type_name(&observed_result_type)
        ))),
    }
}

fn tiff_buffer_mismatch_error(
    image_path: &str,
    width: u32,
    height: u32,
    color_type: &str,
) -> ImageError {
    ImageError::Decode(format!(
        "decoded TIFF buffer length does not match dimensions for '{image_path}': {width}x{height}, color_type={color_type}"
    ))
}

fn tiff_result_type_name(result: &TiffDecodingResult) -> &'static str {
    match result {
        TiffDecodingResult::U8(_) => "u8",
        TiffDecodingResult::U16(_) => "u16",
        _ => "unsupported",
    }
}

fn init_image_decoders() {
    IMAGE_DECODER_HOOKS_INIT.call_once(|| {
        let registration = register_image_decoder_hooks_with_guardrails(DecodeGuardrails {
            max_input_bytes: Some(128 * 1024 * 1024),
            max_pixels: Some(256_000_000),
            max_temp_spool_bytes: Some(256 * 1024 * 1024),
            temp_spool_directory: None,
        });

        let heic_hook_active = decoding_hook_registered(OsStr::new("heic"));
        let heif_hook_active = decoding_hook_registered(OsStr::new("heif"));
        let avif_hook_active = decoding_hook_registered(OsStr::new("avif"));
        let jxl_registered_now = register_jxl_decoding_hook();
        let jxl_hook_active = decoding_hook_registered(OsStr::new("jxl"));
        let has_heif_family_support = heic_hook_active || heif_hook_active;

        if !has_heif_family_support {
            eprintln!(
                "[ml][decode] failed to activate HEIF/HEIC decoder hooks; registration_result=(heic:{}, heif:{}, avif:{}), active_hooks=(heic:{}, heif:{}, avif:{})",
                registration.heic_decoder_hook_registered,
                registration.heif_decoder_hook_registered,
                registration.avif_decoder_hook_registered,
                heic_hook_active,
                heif_hook_active,
                avif_hook_active,
            );
        } else if !registration.all_decoder_hooks_registered() {
            eprintln!(
                "[ml][decode] ente_heic decoder hooks only partially registered (usually because another initializer registered first); registration_result=(heic:{}, heif:{}, avif:{}), active_hooks=(heic:{}, heif:{}, avif:{})",
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
            eprintln!(
                "[ml][decode] failed to activate JPEG XL decoder hook; registered_now={jxl_registered_now}, active_hook={jxl_hook_active}"
            );
        }

        debug_assert!(jxl_hook_active, "JPEG XL image decoder hook is not active");
    });
}

fn orient_decoded_image(image: DynamicImage, image_path: &str) -> DynamicImage {
    let path = Path::new(image_path);
    if path_extension_is_heif(path) {
        return apply_heif_exif_orientation_hint(image, path);
    }

    apply_standard_exif_orientation(image, image_path)
}

fn orient_decoded_image_from_bytes(image: DynamicImage, image_bytes: &[u8]) -> DynamicImage {
    if bytes_look_like_heif(image_bytes) {
        return apply_heif_exif_orientation_hint_from_bytes(image, image_bytes);
    }

    apply_standard_exif_orientation_from_bytes(image, image_bytes)
}

fn apply_heif_exif_orientation_hint(image: DynamicImage, image_path: &Path) -> DynamicImage {
    let hint = match exif_orientation_hint_from_path(image_path) {
        Ok(hint) => hint,
        Err(err) => {
            eprintln!(
                "[ml][decode] failed to inspect HEIF EXIF orientation for '{}': {}",
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

fn path_extension_is_raw(path: &Path) -> bool {
    path.extension()
        .and_then(OsStr::to_str)
        .is_some_and(|extension| {
            RAW_EXTENSIONS
                .iter()
                .any(|raw_extension| extension.eq_ignore_ascii_case(raw_extension))
        })
}

fn bytes_look_like_raw(image_bytes: &[u8]) -> bool {
    if image_bytes.len() >= 12 && &image_bytes[4..8] == b"ftyp" {
        // Canon CR3 is an ISO-BMFF container with the "crx " brand.
        return &image_bytes[8..12] == b"crx ";
    }

    if bytes_have_tiff_magic(image_bytes) {
        return tiff_looks_like_camera_raw(&mut Cursor::new(image_bytes));
    }

    RAW_MAGIC_PREFIXES
        .iter()
        .any(|prefix| image_bytes.starts_with(prefix))
}

fn bytes_have_tiff_magic(image_bytes: &[u8]) -> bool {
    image_bytes.starts_with(TIFF_MAGIC_LITTLE_ENDIAN)
        || image_bytes.starts_with(TIFF_MAGIC_BIG_ENDIAN)
}

fn file_magic_looks_like_raw(image_path: &str) -> bool {
    let Ok(file) = File::open(image_path) else {
        return false;
    };
    let mut reader = BufReader::new(file);

    let mut magic = Vec::with_capacity(16);
    if reader.by_ref().take(16).read_to_end(&mut magic).is_err() {
        return false;
    }

    if bytes_have_tiff_magic(&magic) {
        // The pre-screen seeks back to the start of the file itself.
        return tiff_looks_like_camera_raw(&mut reader);
    }

    bytes_look_like_raw(&magic)
}

/// Pre-screen for TIFF-magic inputs: reports whether the TIFF carries any of
/// the camera markers rawler's probe dispatches on ([`TIFF_TAG_MAKE`] and
/// friends), scanning exactly the scope rawler 0.7.2 consults — the direct
/// entries of each IFD in the root chain, no sub-IFDs. A TIFF without any
/// marker cannot match rawler's TIFF dispatch, so it is treated as a plain
/// TIFF and skips the RAW pipeline entirely. This matters because a failed
/// rawler probe is expensive: constructing the `RawSource` materializes the
/// whole input, and the probe's final naked-RAW lookup copies it a second
/// time.
///
/// Marker checks are presence-based — strictly more conservative than
/// rawler's value dispatch — except `Software`, where plain editor-written
/// TIFFs are so common that only the Leaf [`LEAF_MOS_SOFTWARE`] value counts.
/// Any parse trouble routes to the RAW pipeline (`true`): the pre-screen can
/// only skip work, never change an outcome rawler would have produced.
fn tiff_looks_like_camera_raw<R: Read + Seek>(reader: &mut R) -> bool {
    tiff_contains_camera_raw_markers(reader).unwrap_or(true)
}

fn tiff_contains_camera_raw_markers<R: Read + Seek>(reader: &mut R) -> std::io::Result<bool> {
    let invalid =
        |message: &str| std::io::Error::new(std::io::ErrorKind::InvalidData, message.to_string());

    let mut header = [0u8; 8];
    reader.seek(SeekFrom::Start(0))?;
    reader.read_exact(&mut header)?;
    let little_endian = if header.starts_with(TIFF_MAGIC_LITTLE_ENDIAN) {
        true
    } else if header.starts_with(TIFF_MAGIC_BIG_ENDIAN) {
        false
    } else {
        return Err(invalid("not a TIFF header"));
    };
    let read_u16 = |bytes: &[u8]| {
        let bytes: [u8; 2] = bytes.try_into().expect("exactly 2 bytes");
        if little_endian {
            u16::from_le_bytes(bytes)
        } else {
            u16::from_be_bytes(bytes)
        }
    };
    let read_u32 = |bytes: &[u8]| {
        let bytes: [u8; 4] = bytes.try_into().expect("exactly 4 bytes");
        if little_endian {
            u32::from_le_bytes(bytes)
        } else {
            u32::from_be_bytes(bytes)
        }
    };

    let mut ifd_offset = read_u32(&header[4..8]);
    let mut visited_ifds = 0usize;

    while ifd_offset != 0 {
        visited_ifds += 1;
        if visited_ifds > TIFF_PRESCREEN_MAX_IFDS {
            return Err(invalid("IFD chain too long"));
        }

        reader.seek(SeekFrom::Start(ifd_offset.into()))?;
        let mut entry_count_bytes = [0u8; 2];
        reader.read_exact(&mut entry_count_bytes)?;
        let entry_count = read_u16(&entry_count_bytes);
        if entry_count == 0 || entry_count > TIFF_PRESCREEN_MAX_ENTRIES_PER_IFD {
            return Err(invalid("implausible IFD entry count"));
        }

        let mut entries = vec![0u8; usize::from(entry_count) * 12];
        reader.read_exact(&mut entries)?;
        let mut next_offset_bytes = [0u8; 4];
        reader.read_exact(&mut next_offset_bytes)?;
        ifd_offset = read_u32(&next_offset_bytes);

        let mut software_entry: Option<[u8; 12]> = None;
        for entry in entries.chunks_exact(12) {
            match read_u16(&entry[0..2]) {
                TIFF_TAG_MAKE | TIFF_TAG_MODEL | TIFF_TAG_DNG_VERSION => return Ok(true),
                TIFF_TAG_SOFTWARE => {
                    software_entry = Some(entry.try_into().expect("exactly 12 bytes"));
                }
                _ => {}
            }
        }

        // Resolved after the IFD is fully read because the value may live
        // anywhere in the file and reading it moves the cursor.
        let Some(entry) = software_entry else {
            continue;
        };
        let value_count = read_u32(&entry[4..8]);
        if read_u16(&entry[2..4]) != TIFF_ASCII_TYPE
            || value_count == 0
            || value_count > TIFF_PRESCREEN_MAX_SOFTWARE_BYTES
        {
            continue;
        }
        let mut value = vec![0u8; value_count as usize];
        if value_count <= 4 {
            value.copy_from_slice(&entry[8..8 + value_count as usize]);
        } else {
            reader.seek(SeekFrom::Start(read_u32(&entry[8..12]).into()))?;
            reader.read_exact(&mut value)?;
        }
        let text = &value[..value
            .iter()
            .position(|byte| *byte == 0)
            .unwrap_or(value.len())];
        if std::str::from_utf8(text).is_ok_and(|text| text.trim() == LEAF_MOS_SOFTWARE) {
            return Ok(true);
        }
    }

    Ok(false)
}

#[cfg(test)]
mod tests {
    use std::{ffi::OsStr, io::Cursor, panic, path::Path};

    use image::hooks::decoding_hook_registered;
    use image::{
        ColorType, ImageEncoder, ImageFormat,
        codecs::{png::PngEncoder, tiff::TiffEncoder},
    };
    use moxcms::ColorProfile;
    use rawler::{
        decoders::{FormatHint as RawFormatHint, Orientation as RawOrientation},
        formats::tiff::{GenericTiffReader, reader::TiffReader},
        rawsource::RawSource,
    };

    use super::{
        ImageResult, bytes_look_like_heif, bytes_look_like_raw, catch_raw_decode_panic,
        decode_image_from_bytes, decode_image_from_path, init_image_decoders,
        path_extension_is_raw, raw_orientation_to_exif, should_attempt_tiff_fallback,
        validate_cr3_raw_candidate_dimensions, validate_dng_raw_ifd_allocation,
        validate_raw_candidate_dimensions_for_format, validate_raw_dimensions,
        validate_tiff_raw_candidate_dimensions,
    };

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
    fn detects_heif_brand_in_bytes() {
        let bytes = b"\0\0\0\x18ftypheic\0\0\0\0";

        assert!(bytes_look_like_heif(bytes));
    }

    #[test]
    fn skips_non_heif_bytes() {
        assert!(!bytes_look_like_heif(b"not an image"));
    }

    #[test]
    fn detects_raw_file_extensions_case_insensitively() {
        assert!(path_extension_is_raw(Path::new("photo.CR3")));
        assert!(path_extension_is_raw(Path::new("photo.dng")));
        assert!(path_extension_is_raw(Path::new("photo.3FR")));
        assert!(!path_extension_is_raw(Path::new("photo.jpg")));
        assert!(!path_extension_is_raw(Path::new("photo")));
    }

    #[test]
    fn detects_raw_magic_bytes() {
        assert!(bytes_look_like_raw(b"IIU\0rest")); // Panasonic RW2
        assert!(bytes_look_like_raw(b"IIRO rest")); // Olympus ORF
        assert!(bytes_look_like_raw(b"FUJIFILMCCD-RAW")); // Fujifilm RAF
        assert!(bytes_look_like_raw(b"\0\0\0\x18ftypcrx \0\0\0\0")); // Canon CR3

        assert!(!bytes_look_like_raw(b"\0\0\0\x18ftypheic\0\0\0\0")); // HEIC
        assert!(!bytes_look_like_raw(b"\x89PNG\r\n\x1a\n"));
        assert!(!bytes_look_like_raw(b"\xff\xd8\xff\xe0")); // JPEG
        assert!(!bytes_look_like_raw(b""));
    }

    #[test]
    fn tiff_magic_is_raw_candidate_only_with_camera_markers() {
        // Marker-less TIFFs are pre-screened out of the RAW pipeline; any of
        // the markers rawler's probe dispatches on keeps a TIFF a candidate.
        let mut plain = Vec::new();
        TiffEncoder::new(Cursor::new(&mut plain))
            .write_image(&[1u8, 2, 3], 1, 1, ColorType::Rgb8.into())
            .unwrap();
        assert!(!bytes_look_like_raw(&plain));

        let with_make = encode_rgb8_tiff_with_camera_exif(&[1, 2, 3], "SONY", "ILCE-7M3");
        assert!(bytes_look_like_raw(&with_make));

        let model_only = encode_rgb8_tiff_with_string_tag(tiff::tags::Tag::Model, "DCS560C");
        assert!(bytes_look_like_raw(&model_only));

        let leaf = encode_rgb8_tiff_with_string_tag(tiff::tags::Tag::Software, "Camera Library");
        assert!(bytes_look_like_raw(&leaf));
        let edited =
            encode_rgb8_tiff_with_string_tag(tiff::tags::Tag::Software, "Adobe Photoshop 27.1");
        assert!(!bytes_look_like_raw(&edited));

        // DNGVersion alone marks a DNG even without Make (hand-rolled: one
        // IFD whose only entry is DNGVersion).
        let mut dng = Vec::new();
        dng.extend_from_slice(b"II*\0");
        dng.extend_from_slice(&8u32.to_le_bytes());
        dng.extend_from_slice(&1u16.to_le_bytes());
        append_tiff_long(&mut dng, 0xC612, 0x0104);
        dng.extend_from_slice(&0u32.to_le_bytes());
        assert!(bytes_look_like_raw(&dng));

        // Big-endian TIFF whose single IFD entry is Make ("SONY\0" at 26).
        let big_endian_make =
            b"MM\0*\x00\x00\x00\x08\x00\x01\x01\x0F\x00\x02\x00\x00\x00\x05\x00\x00\x00\x1A\x00\x00\x00\x00SONY\0";
        assert!(bytes_look_like_raw(big_endian_make));

        // Parse trouble stays conservative: truncated TIFFs remain RAW
        // candidates and keep the pre-pre-screen routing.
        assert!(bytes_look_like_raw(b"II*\0rest"));
        assert!(bytes_look_like_raw(b"MM\0*rest"));
    }

    fn encode_rgb8_tiff_with_string_tag(tag: tiff::tags::Tag, value: &str) -> Vec<u8> {
        use tiff::encoder::{TiffEncoder as TiffCrateEncoder, colortype::RGB8};

        let mut encoded = Cursor::new(Vec::new());
        let mut tiff_encoder = TiffCrateEncoder::new(&mut encoded).unwrap();
        let mut image = tiff_encoder.new_image::<RGB8>(1, 1).unwrap();
        image.encoder().write_tag(tag, value).unwrap();
        image.write_data(&[1u8, 2, 3]).unwrap();
        encoded.into_inner()
    }

    #[test]
    fn rejects_oversized_tiff_raw_candidate_from_header_dimensions() {
        let encoded = minimal_tiff_with_raw_candidate_dimensions(50_000, 4_001);
        let source = RawSource::new_from_slice(&encoded);

        let error = validate_tiff_raw_candidate_dimensions(&source, "huge.dng")
            .expect_err("oversized TIFF RAW candidate should fail before decode");

        assert!(error.to_string().contains("50000x4001"));
        assert!(error.to_string().contains("exceeds 200000000 pixels"));
    }

    #[test]
    fn rejects_dng_sample_allocation_larger_than_nominal_dimensions() {
        let encoded = minimal_tiff_with_long_entries(&[
            (0x0100, 20_000), // ImageWidth
            (0x0101, 10_000), // ImageLength
            (0x0111, 0),      // StripOffsets
            (0x0115, 2),      // SamplesPerPixel
        ]);
        let tiff = parse_tiff(&encoded);

        let error = validate_dng_raw_ifd_allocation(tiff.root_ifd(), "wide-samples.dng")
            .expect_err("decoded samples should be bounded before allocation");

        assert!(error.to_string().contains("40000x10000"));
        assert!(error.to_string().contains("exceeds 200000000 samples"));
    }

    #[test]
    fn rejects_dng_tile_padding_larger_than_nominal_dimensions() {
        let encoded = minimal_tiff_with_long_entries(&[
            (0x0100, 1),      // ImageWidth
            (0x0101, 1),      // ImageLength
            (0x0115, 1),      // SamplesPerPixel
            (0x0142, 50_000), // TileWidth
            (0x0143, 10_000), // TileLength
            (0x0144, 0),      // TileOffsets
        ]);
        let tiff = parse_tiff(&encoded);

        let error = validate_dng_raw_ifd_allocation(tiff.root_ifd(), "padded.dng")
            .expect_err("padded decoded samples should be bounded before allocation");

        assert!(error.to_string().contains("50000x10000"));
        assert!(error.to_string().contains("exceeds 200000000 samples"));
    }

    fn minimal_tiff_with_raw_candidate_dimensions(width: u32, height: u32) -> Vec<u8> {
        minimal_tiff_with_long_entries(&[(0x0100, width), (0x0101, height), (0x0111, 0)])
    }

    fn minimal_tiff_with_long_entries(entries: &[(u16, u32)]) -> Vec<u8> {
        let mut encoded = Vec::new();
        encoded.extend_from_slice(b"II*\0");
        encoded.extend_from_slice(&8u32.to_le_bytes());
        encoded.extend_from_slice(&(entries.len() as u16).to_le_bytes());
        for &(tag, value) in entries {
            append_tiff_long(&mut encoded, tag, value);
        }
        encoded.extend_from_slice(&0u32.to_le_bytes());
        encoded
    }

    fn parse_tiff(encoded: &[u8]) -> GenericTiffReader {
        GenericTiffReader::new(&mut Cursor::new(encoded), 0, 0, None, &[])
            .expect("synthetic TIFF should parse")
    }

    fn append_tiff_long(encoded: &mut Vec<u8>, tag: u16, value: u32) {
        encoded.extend_from_slice(&tag.to_le_bytes());
        encoded.extend_from_slice(&4u16.to_le_bytes());
        encoded.extend_from_slice(&1u32.to_le_bytes());
        encoded.extend_from_slice(&value.to_le_bytes());
    }

    #[test]
    fn rejects_oversized_cr3_candidate_from_cmp1_dimensions() {
        let encoded = synthetic_cr3_with_cmp1_dimensions(50_000, 5_000);
        let source = RawSource::new_from_slice(&encoded);

        let error = validate_cr3_raw_candidate_dimensions(&source, "huge.cr3")
            .expect_err("oversized CR3 CMP1 dimensions should fail before decode");

        assert!(error.to_string().contains("50000x5000"));
        assert!(error.to_string().contains("exceeds 200000000 pixels"));
    }

    #[test]
    fn rejects_cr3_extreme_aspect_ratio_before_line_buffer_allocation() {
        let encoded = synthetic_cr3_with_cmp1_dimensions(100_000_000, 2);
        let source = RawSource::new_from_slice(&encoded);

        let error = validate_cr3_raw_candidate_dimensions(&source, "extreme-width.cr3")
            .expect_err("extreme CR3 sides should fail before line-buffer allocation");

        assert!(error.to_string().contains("100000000x2"));
        assert!(
            error
                .to_string()
                .contains("exceeds maximum side length 50000")
        );
    }

    #[test]
    fn accepts_raw_dimensions_at_maximum_side_length() {
        validate_raw_dimensions(50_000, 4_000, "boundary.raw")
            .expect("the rawler-compatible side limit should be inclusive");
    }

    #[test]
    fn accepts_cr3_candidate_with_sane_cmp1_dimensions() {
        let encoded = synthetic_cr3_with_cmp1_dimensions(6000, 4000);
        let source = RawSource::new_from_slice(&encoded);

        validate_cr3_raw_candidate_dimensions(&source, "ok.cr3")
            .expect("sane CMP1 dimensions should pass the preflight");
    }

    #[test]
    fn cr3_dimension_guard_rejects_unparseable_bmff() {
        let source = RawSource::new_from_slice(b"\0\0\0\x18ftypcrx garbage");

        let error = validate_cr3_raw_candidate_dimensions(&source, "junk.cr3")
            .expect_err("recognized CR3 inputs should fail closed when reparsing fails");

        assert!(
            error
                .to_string()
                .contains("failed to inspect CR3 dimensions")
        );
    }

    #[test]
    fn rejects_oversized_cr3_with_box_before_ftyp() {
        let mut encoded = bmff_box(b"free", &[]);
        encoded.extend_from_slice(&synthetic_cr3_with_cmp1_dimensions(50_000, 5_000));
        assert_eq!(&encoded[4..8], b"free");
        let source = RawSource::new_from_slice(&encoded);

        let error = validate_raw_candidate_dimensions_for_format(
            RawFormatHint::CR3,
            &source,
            "leading-box.cr3",
        )
        .expect_err("CR3 preflight should not require ftyp to be the first box");

        assert!(error.to_string().contains("50000x5000"));
        assert!(error.to_string().contains("exceeds 200000000 pixels"));
    }

    /// Minimal BMFF tree that rawler's parser accepts: every box rawler
    /// requires along the path to the CMP1 box, with zeroed filler for the
    /// fields the parsers read but this test doesn't care about.
    fn synthetic_cr3_with_cmp1_dimensions(width: u32, height: u32) -> Vec<u8> {
        // CMP1 payload (36 bytes); ext_header stays 0 so the CRM movie
        // branch in rawler's parser is skipped.
        let mut cmp1 = Vec::new();
        cmp1.extend_from_slice(&0i16.to_be_bytes()); // unknown1
        cmp1.extend_from_slice(&0u16.to_be_bytes()); // header_size
        cmp1.extend_from_slice(&0u16.to_be_bytes()); // version
        cmp1.extend_from_slice(&0u16.to_be_bytes()); // version_sub
        cmp1.extend_from_slice(&width.to_be_bytes()); // f_width
        cmp1.extend_from_slice(&height.to_be_bytes()); // f_height
        cmp1.extend_from_slice(&width.to_be_bytes()); // tile_width
        cmp1.extend_from_slice(&height.to_be_bytes()); // tile_height
        cmp1.push(14); // n_bits
        cmp1.push(0x40); // n_planes = 4, cfa_layout = 0
        cmp1.push(0x03); // enc_type = 0, image_levels = 3
        cmp1.push(0); // tile flags
        cmp1.extend_from_slice(&0u32.to_be_bytes()); // mdat_hdr_size
        cmp1.extend_from_slice(&0u32.to_be_bytes()); // ext_header

        // CRAW sample entry: 82 bytes of fixed fields, then child boxes.
        let mut craw = vec![0u8; 82];
        craw.extend_from_slice(&bmff_box(b"CMP1", &cmp1));

        let mut stsd = Vec::new();
        stsd.extend_from_slice(&0u32.to_be_bytes()); // version + flags
        stsd.extend_from_slice(&1u32.to_be_bytes()); // entry_count
        stsd.extend_from_slice(&bmff_box(b"CRAW", &craw));

        let mut stbl = Vec::new();
        stbl.extend_from_slice(&bmff_box(b"stsd", &stsd));
        stbl.extend_from_slice(&bmff_box(b"stts", &[0u8; 8]));
        stbl.extend_from_slice(&bmff_box(b"stsc", &[0u8; 8]));
        stbl.extend_from_slice(&bmff_box(b"stsz", &[0u8; 12]));

        let mut minf = Vec::new();
        minf.extend_from_slice(&bmff_box(b"dinf", &[]));
        minf.extend_from_slice(&bmff_box(b"stbl", &stbl));

        let mut mdia = Vec::new();
        mdia.extend_from_slice(&bmff_box(b"mdhd", &[0u8; 24]));
        mdia.extend_from_slice(&bmff_box(b"hdlr", &[0u8; 4]));
        mdia.extend_from_slice(&bmff_box(b"minf", &minf));

        let mut trak = Vec::new();
        trak.extend_from_slice(&bmff_box(b"tkhd", &[0u8; 4]));
        trak.extend_from_slice(&bmff_box(b"mdia", &mdia));

        let mut moov = Vec::new();
        moov.extend_from_slice(&bmff_box(b"mvhd", &[0u8; 20]));
        moov.extend_from_slice(&bmff_box(b"trak", &trak));

        let mut ftyp = Vec::new();
        ftyp.extend_from_slice(b"crx "); // major brand
        ftyp.extend_from_slice(&0u32.to_be_bytes()); // minor version

        let mut file = Vec::new();
        file.extend_from_slice(&bmff_box(b"ftyp", &ftyp));
        file.extend_from_slice(&bmff_box(b"moov", &moov));
        file.extend_from_slice(&bmff_box(b"mdat", &[]));
        file
    }

    fn bmff_box(fourcc: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut encoded = Vec::with_capacity(8 + payload.len());
        encoded.extend_from_slice(&(8 + payload.len() as u32).to_be_bytes());
        encoded.extend_from_slice(fourcc);
        encoded.extend_from_slice(payload);
        encoded
    }

    #[test]
    fn maps_raw_orientation_to_exif_orientation() {
        assert_eq!(raw_orientation_to_exif(RawOrientation::Normal), Some(1));
        assert_eq!(
            raw_orientation_to_exif(RawOrientation::HorizontalFlip),
            Some(2)
        );
        assert_eq!(raw_orientation_to_exif(RawOrientation::Rotate180), Some(3));
        assert_eq!(
            raw_orientation_to_exif(RawOrientation::VerticalFlip),
            Some(4)
        );
        assert_eq!(raw_orientation_to_exif(RawOrientation::Transpose), Some(5));
        assert_eq!(raw_orientation_to_exif(RawOrientation::Rotate90), Some(6));
        assert_eq!(raw_orientation_to_exif(RawOrientation::Transverse), Some(7));
        assert_eq!(raw_orientation_to_exif(RawOrientation::Rotate270), Some(8));
        assert_eq!(raw_orientation_to_exif(RawOrientation::Unknown), None);
    }

    #[test]
    fn plain_tiff_bytes_decode_via_image_crate() {
        // A marker-less TIFF is pre-screened out of the RAW pipeline (no
        // rawler probe, no full-input copies) and decodes via the image crate.
        let mut encoded = Vec::new();
        TiffEncoder::new(Cursor::new(&mut encoded))
            .write_image(&[10u8, 20, 30], 1, 1, ColorType::Rgb8.into())
            .unwrap();
        assert!(!bytes_look_like_raw(&encoded));

        let decoded = decode_image_from_bytes(&encoded).unwrap();

        assert_eq!(decoded.dimensions.width, 1);
        assert_eq!(decoded.dimensions.height, 1);
        assert_eq!(decoded.rgb, vec![10, 20, 30]);
    }

    #[test]
    fn plain_tiff_file_decodes_via_image_crate() {
        // Exercises the path-based pre-screen: TIFF magic without camera
        // markers or a RAW extension must not route into the RAW pipeline.
        let mut tiff = Vec::new();
        TiffEncoder::new(Cursor::new(&mut tiff))
            .write_image(&[11u8, 22, 33], 1, 1, ColorType::Rgb8.into())
            .unwrap();
        let path = std::env::temp_dir().join(format!(
            "ente_image_plain_{}_{:?}.tif",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::write(&path, &tiff).unwrap();

        let decoded = decode_image_from_path(path.to_str().unwrap());
        std::fs::remove_file(&path).ok();

        let decoded = decoded.expect("plain TIFF should decode via image crate");
        assert_eq!(decoded.dimensions.width, 1);
        assert_eq!(decoded.dimensions.height, 1);
        assert_eq!(decoded.rgb, vec![11, 22, 33]);
    }

    #[test]
    fn misnamed_raw_extension_falls_back_to_image_crate() {
        let mut png = Vec::new();
        PngEncoder::new(&mut png)
            .write_image(&[9u8, 8, 7], 1, 1, ColorType::Rgb8.into())
            .unwrap();
        let path = std::env::temp_dir().join(format!(
            "ente_image_misnamed_{}_{:?}.dng",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::write(&path, &png).unwrap();

        let decoded = decode_image_from_path(path.to_str().unwrap());
        std::fs::remove_file(&path).ok();

        let decoded = decoded.expect("misnamed PNG with RAW extension should fall back");
        assert_eq!(decoded.dimensions.width, 1);
        assert_eq!(decoded.dimensions.height, 1);
        assert_eq!(decoded.rgb, vec![9, 8, 7]);
    }

    #[test]
    fn camera_exif_tiff_bytes_still_decode_as_tiff() {
        // A plain TIFF exported from a camera photo keeps the camera's EXIF
        // Make/Model tags, so the pre-screen keeps it a RAW candidate.
        // rawler's probe dispatches TIFF containers on the Make tag alone, so
        // it may accept this file as a Sony ARW and only fail once actual RAW
        // data is requested. The RAW attempt from bytes is opportunistic, so
        // the file must still decode via the image crate.
        let tiff_bytes = encode_rgb8_tiff_with_camera_exif(&[40, 50, 60], "SONY", "ILCE-7M3");
        assert!(bytes_look_like_raw(&tiff_bytes));

        let decoded = decode_image_from_bytes(&tiff_bytes).unwrap();

        assert_eq!(decoded.dimensions.width, 1);
        assert_eq!(decoded.dimensions.height, 1);
        assert_eq!(decoded.rgb, vec![40, 50, 60]);
    }

    fn encode_rgb8_tiff_with_camera_exif(pixel: &[u8; 3], make: &str, model: &str) -> Vec<u8> {
        use tiff::{
            encoder::{TiffEncoder as TiffCrateEncoder, colortype::RGB8},
            tags::Tag,
        };

        let mut encoded = Cursor::new(Vec::new());
        let mut tiff_encoder = TiffCrateEncoder::new(&mut encoded).unwrap();
        let mut image = tiff_encoder.new_image::<RGB8>(1, 1).unwrap();
        image.encoder().write_tag(Tag::Make, make).unwrap();
        image.encoder().write_tag(Tag::Model, model).unwrap();
        image.write_data(pixel).unwrap();
        encoded.into_inner()
    }

    #[test]
    fn unrecognized_raw_with_raw_extension_and_magic_errors_instead_of_thumbnail() {
        // A TIFF with an unknown camera Make named .nef models a RAW from a
        // camera model missing in rawler's database: the extension and the
        // camera-marker magic both say RAW, but the probe finds no decoder
        // for the make. This must be a hard error, not an image crate
        // fallback that could decode an embedded preview.
        let tiff = encode_rgb8_tiff_with_camera_exif(&[10, 20, 30], "ENTE TESTCAM", "MODEL-1");
        let path = std::env::temp_dir().join(format!(
            "ente_image_unknown_camera_{}_{:?}.nef",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::write(&path, &tiff).unwrap();

        let result = decode_image_from_path(path.to_str().unwrap());
        std::fs::remove_file(&path).ok();

        let error = result.expect_err("unrecognized RAW-claiming file should not decode");
        assert!(error.to_string().contains("refusing thumbnail fallback"));
    }

    #[test]
    fn raw_decode_panics_are_returned_as_decode_errors() {
        let previous_hook = panic::take_hook();
        panic::set_hook(Box::new(|_| {}));
        let result: ImageResult<()> =
            catch_raw_decode_panic("panic.raw", || panic!("synthetic panic"));
        panic::set_hook(previous_hook);

        let error = result.expect_err("panic should be converted to an error");
        assert!(error.to_string().contains("RAW decoder panicked"));
        assert!(error.to_string().contains("synthetic panic"));
    }

    #[test]
    fn registers_jxl_decoder_hook() {
        init_image_decoders();

        assert!(decoding_hook_registered(OsStr::new("jxl")));
    }

    #[test]
    fn decode_applies_embedded_png_display_p3_profile() {
        let display_p3_icc = ColorProfile::new_display_p3().encode().unwrap();
        let png = encode_rgb8_png_with_icc(&[128, 0, 0], display_p3_icc);

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
        let png = encode_rgb8_png_with_icc(&[128, 64, 32], srgb_icc);

        let decoded = decode_image_from_bytes(&png).unwrap();

        assert_eq!(decoded.rgb, vec![128, 64, 32]);
    }

    fn encode_rgb8_png_with_icc(pixel: &[u8; 3], icc_profile: Vec<u8>) -> Vec<u8> {
        let mut encoded = Vec::new();
        let mut encoder = PngEncoder::new(&mut encoded);
        encoder.set_icc_profile(icc_profile).unwrap();
        encoder
            .write_image(pixel, 1, 1, ColorType::Rgb8.into())
            .unwrap();
        encoded
    }
}
