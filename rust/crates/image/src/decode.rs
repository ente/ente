use std::{
    any::Any,
    ffi::OsStr,
    fs::File,
    io::{BufRead, BufReader, Cursor, Read, Seek, SeekFrom},
    panic::{self, AssertUnwindSafe},
    path::Path,
    sync::{Arc, Once},
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
    DynamicImage, ImageDecoder, ImageFormat, ImageReader, Limits, RgbImage,
    hooks::decoding_hook_registered,
};
use jxl_bitstream::{BitstreamKind, ContainerParser, ParseEvent};
use jxl_oxide::{
    AllocTracker, InitializeResult, JxlImage, JxlThreadPool, UninitializedJxlImage,
    integration::register_image_decoding_hook as register_jxl_decoding_hook,
};
use rawler::{
    decoders::{
        Decoder as RawDecoder, Orientation as RawOrientation, RawDecodeParams, WellKnownIFD,
    },
    decompressors::ljpeg::LjpegDecompressor,
    formats::tiff::{GenericTiffReader, IFD, ifd::DataMode, reader::TiffReader},
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
/// The local rawler fork's owned RGB8 path tracks a 16 B/source-pixel peak for
/// ordinary non-rotated Bayer and X-Trans, 18 B/px for integer Linear RGB,
/// 20 B/px for a four-color CFA, and 24 B/px for integer four-channel Linear
/// RAW. Legacy Fuji rotation can be higher but occurs on much smaller sensors.
/// Keep a conservative universal 54MP ceiling until device RSS validation
/// supports a higher limit; larger RAWs may use an embedded JPEG.
const RAW_MAX_DEVELOPMENT_PIXELS: u128 = 54_000_000;
/// Separate sample-allocation ceiling for compressed/tiled DNG preflight.
/// Multi-channel RAWs contain more than one sample per image pixel.
const RAW_MAX_DECODED_SAMPLES: u128 = RAW_MAX_DEVELOPMENT_PIXELS * 4;
const RAW_PREVIEW_MIN_SHORT_EDGE: u32 = 1080;
const RAW_PREVIEW_MAX_PIXELS: u64 = 200_000_000;
/// A separate side limit bounds decoder line and wavelet buffers for extreme
/// aspect ratios; total pixels alone is not a sufficient allocation bound.
const RAW_MAX_DIMENSION: usize = 50_000;
const RAW_EXTENSIONS: &[&str] = &[
    "3fr", "ari", "arw", "cr2", "cr3", "crm", "crw", "dcr", "dcs", "dng", "erf", "fff", "iiq",
    "kdc", "mef", "mos", "mrw", "nef", "nrw", "orf", "ori", "pef", "qtk", "raf", "raw", "rw2",
    "rwl", "sr2", "srf", "srw", "x3f",
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
const DNG_COMPRESSION_MODERN_JPEG: u16 = 7;
const DNG_COMPRESSION_JPEG_XL: u16 = 52_546;
/// Bound the codestream data inspected while locating the first displayed
/// keyframe. Progressive-DC streams can place complete LF dependency frames
/// before that header, so this is deliberately larger than an ordinary image
/// header. Container metadata does not count toward this budget.
const JPEG_XL_PREFLIGHT_MAX_CODESTREAM_BYTES: usize = 16 * 1024 * 1024;
const JPEG_XL_PREFLIGHT_CHUNK_BYTES: usize = 64 * 1024;
/// jxl-oxide tracks header and compressed frame-data allocations, but not the
/// rendered framebuffers. Those are bounded separately from frame dimensions
/// before rawler calls `render_frame`.
const JPEG_XL_PREFLIGHT_MAX_TRACKED_ALLOC_BYTES: usize = 32 * 1024 * 1024;
/// Allow the two full-canvas LF frames emitted by libjxl's most progressive DC
/// mode, plus one further canvas worth of referenced data. This bounds hidden
/// render allocations without excluding ordinary progressive still images.
const JPEG_XL_PREFLIGHT_MAX_DEPENDENCY_SAMPLE_MULTIPLIER: u128 = 3;

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
///   pipeline. RAWs at or below 54MP are developed; larger RAWs may return the
///   largest eligible embedded JPEG preview. Other failures — oversized
///   input, unmatched camera model, decode/develop error, or no sufficiently
///   large preview — are hard errors. There is no generic image-crate
///   fallback that could silently return a thumbnail-sized image.
/// - Only one signal says RAW (a camera-marker TIFF without a RAW extension —
///   typically a `.tif` export that kept its camera EXIF — or a misnamed file
///   whose magic disagrees): the RAW attempt is opportunistic and any RAW
///   failure falls back to the image crate. This matters because rawler's
///   probe dispatches TIFF containers on the EXIF `Make` tag alone, so a
///   plain TIFF exported from a camera photo can pass the probe and only
///   fail later in `raw_image()` — such files must keep decoding as TIFFs.
///
/// The size guardrail runs before the RAW source is constructed because
/// constructing it materializes the entire input ([`decode_raw_from_path`]
/// reads the file into memory, `RawSource::new_from_slice` copies, and a
/// failed probe copies the buffer again for the naked-RAW lookup).
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
        // Hard-error domain: RAWs from camera models newer than rawler's model
        // database land on the ProbeRejected arm by design. The controlled
        // embedded-preview fallback requires a matched decoder; probe
        // rejections carry no decoder and must not fall through to the image
        // crate's potentially thumbnail-sized TIFF decode.
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
    decode_reader_with_image_crate_and_limits(reader, Limits::default())
}

fn decode_reader_with_image_crate_and_limits<R>(
    reader: ImageReader<R>,
    mut limits: Limits,
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RawDecodePlan {
    Develop,
    UseEmbeddedPreview,
}

fn decode_raw_from_path(image_path: &str) -> ImageResult<RawDecodeOutcome> {
    catch_raw_decode_panic(image_path, || {
        // Read the file into memory instead of mmapping it (`RawSource::new`):
        // a file that shrinks or is rewritten while mmapped (cache eviction,
        // removable storage) turns page faults into SIGBUS, which kills the
        // process and cannot be caught. The callers check the size guardrail
        // before routing here, but the file may have changed since, so the
        // read itself is capped at one byte past [`RAW_MAX_INPUT_BYTES`] —
        // enough for the post-read validation to reject an overgrown file
        // without ever buffering more than the limit. `new_from_shared_vec`
        // takes ownership without copying, so memory use matches the mmap
        // path, which pre-populated all pages anyway. The path is re-attached
        // only so rawler's internal error messages keep naming the file.
        let read_failed = |e: std::io::Error| {
            ImageError::Decode(format!("failed to read RAW image file '{image_path}': {e}"))
        };
        let file = File::open(image_path).map_err(read_failed)?;
        let size_hint = file
            .metadata()
            .map(|metadata| metadata.len())
            .unwrap_or(0)
            .min(RAW_MAX_INPUT_BYTES + 1);
        let mut bytes = Vec::with_capacity(size_hint as usize);
        file.take(RAW_MAX_INPUT_BYTES + 1)
            .read_to_end(&mut bytes)
            .map_err(read_failed)?;
        validate_raw_input_size(bytes.len() as u64, image_path)?;
        let source = RawSource::new_from_shared_vec(Arc::new(bytes)).with_path(image_path);
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

    if validate_raw_dimensions_before_decode(decoder.as_ref(), source, &decode_params, source_name)?
        == RawDecodePlan::UseEmbeddedPreview
    {
        let preview =
            decode_best_raw_preview(decoder.as_ref(), source, &decode_params, source_name)?;
        return Ok(RawDecodeOutcome::Decoded(preview));
    }

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

    let (developed, memory_report) = RawDevelop::default()
        .develop_rgb8_with_report(raw_image)
        .map_err(|e| ImageError::Decode(format!("failed to develop RAW image: {e}")))?;
    validate_raw_dimensions(developed.width, developed.height, source_name)?;
    eprintln!(
        "[ml][decode] RAW development for '{source_name}' tracked a peak of {} bytes ({:.2} B/source-pixel) at {:?}; decoder and process memory are not included",
        memory_report.peak_tracked_bytes,
        memory_report.peak_bytes_per_source_pixel(),
        memory_report.peak_stage,
    );
    let width = u32::try_from(developed.width).map_err(|_| {
        ImageError::Decode(format!(
            "developed RAW width {} does not fit in u32 for '{source_name}'",
            developed.width
        ))
    })?;
    let height = u32::try_from(developed.height).map_err(|_| {
        ImageError::Decode(format!(
            "developed RAW height {} does not fit in u32 for '{source_name}'",
            developed.height
        ))
    })?;
    let image = RgbImage::from_raw(width, height, developed.data).ok_or_else(|| {
        ImageError::Decode(format!(
            "failed to materialize developed RGB8 RAW image for '{source_name}'"
        ))
    })?;
    let image = DynamicImage::ImageRgb8(image);

    // Orientation is best effort: a metadata read failure should not discard
    // an otherwise successfully developed image.
    let metadata_orientation =
        raw_metadata_orientation(decoder.as_ref(), source, &decode_params, source_name);
    let orientation = metadata_orientation.or(raw_image_orientation);

    Ok(RawDecodeOutcome::Decoded(match orientation {
        Some(orientation) => apply_exif_orientation_dynamic(image, orientation),
        None => image,
    }))
}

fn raw_metadata_orientation(
    decoder: &dyn RawDecoder,
    source: &RawSource,
    decode_params: &RawDecodeParams,
    source_name: &str,
) -> Option<u8> {
    match decoder.raw_metadata(source, decode_params) {
        Ok(metadata) => metadata
            .exif
            .orientation
            .and_then(|value| u8::try_from(value).ok())
            .filter(|value| (1..=8).contains(value)),
        Err(err) => {
            eprintln!(
                "[ml][decode] failed to read RAW metadata for '{source_name}': {err}; leaving the decoded image's orientation unchanged when no pixel orientation is available"
            );
            None
        }
    }
}

fn decode_best_raw_preview(
    decoder: &dyn RawDecoder,
    source: &RawSource,
    decode_params: &RawDecodeParams,
    source_name: &str,
) -> ImageResult<DynamicImage> {
    let previews = decoder
        .embedded_previews(source, decode_params)
        .map_err(|e| {
            ImageError::Decode(format!(
                "failed to inspect embedded RAW previews for '{source_name}': {e}"
            ))
        })?;
    let preview = previews
        .iter()
        .filter(|preview| {
            preview.format == ImageFormat::Jpeg
                && raw_preview_dimensions_are_eligible(preview.width, preview.height)
        })
        .max_by_key(|preview| preview.pixel_count());
    let Some(preview) = preview else {
        let available = if previews.is_empty() {
            "none".to_string()
        } else {
            previews
                .iter()
                .map(|preview| format!("{}x{}", preview.width, preview.height))
                .collect::<Vec<_>>()
                .join(", ")
        };
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' exceeds {RAW_MAX_DEVELOPMENT_PIXELS} pixels and has no usable embedded JPEG preview (requires short edge >= {RAW_PREVIEW_MIN_SHORT_EDGE}px and <= {RAW_PREVIEW_MAX_PIXELS} pixels; found: {available})"
        )));
    };

    let encoded_preview = preview.encoded_data(source).map_err(|e| {
        ImageError::Decode(format!(
            "failed to read embedded RAW preview {}x{} for '{source_name}': {e}",
            preview.width, preview.height
        ))
    })?;
    let mut limits = Limits::default();
    limits.max_image_width = Some(preview.width);
    limits.max_image_height = Some(preview.height);
    // Match rawler's preview decode budget. The decoded RGB8 buffer uses
    // three bytes per pixel; one further byte per pixel plus 16 MiB gives the
    // JPEG decoder bounded working space without reinstating the default
    // 512 MiB ceiling for eligible large previews.
    limits.max_alloc = Some(
        preview
            .pixel_count()
            .saturating_mul(4)
            .saturating_add(16 * 1024 * 1024),
    );
    let reader = ImageReader::with_format(Cursor::new(encoded_preview), preview.format);
    let image = decode_reader_with_image_crate_and_limits(reader, limits)
        .map(DecodedDynamicImage::into_srgb)
        .map_err(|e| {
            ImageError::Decode(format!(
                "failed to decode embedded RAW preview {}x{} for '{source_name}': {e}",
                preview.width, preview.height
            ))
        })?;
    if !raw_preview_dimensions_are_eligible(image.width(), image.height()) {
        return Err(ImageError::Decode(format!(
            "embedded RAW preview for '{source_name}' decoded to ineligible dimensions {}x{}",
            image.width(),
            image.height()
        )));
    }

    let orientation = raw_metadata_orientation(decoder, source, decode_params, source_name);

    Ok(match orientation {
        Some(orientation) => apply_exif_orientation_dynamic(image, orientation),
        None => image,
    })
}

fn raw_preview_dimensions_are_eligible(width: u32, height: u32) -> bool {
    width.min(height) >= RAW_PREVIEW_MIN_SHORT_EDGE
        && u64::from(width) * u64::from(height) <= RAW_PREVIEW_MAX_PIXELS
}

/// Best-effort dimension preflight before any pixel decode allocates.
/// The fork's `Decoder::raw_dimensions` hook covers formats whose sensor
/// dimensions do not live in ordinary TIFF image tags. DNG exposes its raw
/// IFD via `Decoder::ifd`, allowing checks for tile padding and dimensions
/// hidden in lossless-JPEG/JPEG-XL payloads. Remaining TIFF-based RAWs are
/// covered by the TIFF IFD walk.
fn validate_raw_dimensions_before_decode(
    decoder: &dyn RawDecoder,
    source: &RawSource,
    decode_params: &RawDecodeParams,
    source_name: &str,
) -> ImageResult<RawDecodePlan> {
    let dimension_plan = decoder
        .raw_dimensions(source, decode_params)
        .map_err(|e| ImageError::Decode(format!("failed to inspect RAW dimensions: {e}")))?
        .map(|(width, height)| raw_decode_plan_for_dimensions(width, height, source_name))
        .transpose()?;
    if dimension_plan == Some(RawDecodePlan::UseEmbeddedPreview) {
        return Ok(RawDecodePlan::UseEmbeddedPreview);
    }

    // The dimension hook bounds the final image, not necessarily temporary
    // codec allocations. Keep the DNG-specific payload checks when an IFD is
    // available, even if a decoder also reports authoritative dimensions.
    if let Some(raw_ifd) = decoder
        .ifd(WellKnownIFD::Raw)
        .map_err(|e| ImageError::Decode(format!("failed to inspect RAW dimensions: {e}")))?
        && let Some((width, height)) = raw_dimensions_from_ifd(&raw_ifd)
    {
        let plan = raw_decode_plan_for_dimensions(width, height, source_name)?;
        if plan == RawDecodePlan::Develop {
            validate_dng_raw_ifd_allocation(&raw_ifd, source_name)?;
            validate_dng_embedded_codec_dimensions(&raw_ifd, source, source_name)?;
        }
        return Ok(plan);
    }

    if let Some(plan) = dimension_plan {
        return Ok(plan);
    }

    for (width, height) in tiff_raw_candidate_dimensions(source) {
        if raw_decode_plan_for_dimensions(width, height, source_name)?
            == RawDecodePlan::UseEmbeddedPreview
        {
            return Ok(RawDecodePlan::UseEmbeddedPreview);
        }
    }
    Ok(RawDecodePlan::Develop)
}

fn raw_decode_plan_for_dimensions(
    width: usize,
    height: usize,
    source_name: &str,
) -> ImageResult<RawDecodePlan> {
    if raw_dimensions_require_preview(width, height, source_name)? {
        Ok(RawDecodePlan::UseEmbeddedPreview)
    } else {
        Ok(RawDecodePlan::Develop)
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

/// Validate dimensions declared inside compressed DNG strip/tile payloads.
///
/// rawler 0.7.2 validates and allocates the IFD-sized destination first, but
/// its lossless-JPEG wrapper then creates a second `PixU16` from the JPEG SOF
/// dimensions. JPEG-XL similarly renders the codestream dimensions before it
/// copies into the destination. A small IFD can therefore hide an arbitrarily
/// larger codec allocation. Inspect every payload before `raw_image` and
/// require its allocation to be compatible with the storage block it will
/// populate.
fn validate_dng_embedded_codec_dimensions(
    raw_ifd: &IFD,
    source: &RawSource,
    source_name: &str,
) -> ImageResult<()> {
    let compression = raw_ifd
        .get_entry(RawTiffCommonTag::Compression)
        .map(|entry| entry.force_u16(0))
        .unwrap_or(1);
    if !matches!(
        compression,
        DNG_COMPRESSION_MODERN_JPEG | DNG_COMPRESSION_JPEG_XL
    ) {
        return Ok(());
    }

    let width = dng_required_usize_tag(raw_ifd, RawTiffCommonTag::ImageWidth, source_name)?;
    let height = dng_required_usize_tag(raw_ifd, RawTiffCommonTag::ImageLength, source_name)?;
    let samples_per_pixel =
        dng_required_usize_tag(raw_ifd, RawTiffCommonTag::SamplesPerPixel, source_name)?;
    if samples_per_pixel == 0 {
        return Err(ImageError::Decode(format!(
            "DNG image '{source_name}' has invalid SamplesPerPixel value 0"
        )));
    }

    let mut total_codec_samples = 0u128;
    match raw_ifd.data_mode().map_err(|e| {
        ImageError::Decode(format!(
            "failed to inspect compressed DNG storage for '{source_name}': {e}"
        ))
    })? {
        DataMode::Strips => {
            let rows_per_strip = raw_ifd
                .get_entry(RawTiffCommonTag::RowsPerStrip)
                .map(|entry| entry.force_usize(0))
                .unwrap_or(height);
            if rows_per_strip == 0 {
                return Err(ImageError::Decode(format!(
                    "compressed DNG image '{source_name}' has invalid RowsPerStrip value 0"
                )));
            }

            let expected_strip_count = height.div_ceil(rows_per_strip);
            let (strips, _) = raw_ifd.strip_data(source).map_err(|e| {
                ImageError::Decode(format!(
                    "failed to inspect compressed DNG strips for '{source_name}': {e}"
                ))
            })?;
            if strips.len() != expected_strip_count {
                return Err(ImageError::Decode(format!(
                    "compressed DNG image '{source_name}' declares {} strips but dimensions require {expected_strip_count}",
                    strips.len()
                )));
            }

            let expected_sample_width = width.checked_mul(samples_per_pixel).ok_or_else(|| {
                ImageError::Decode(format!(
                    "compressed DNG image '{source_name}' sample width overflows"
                ))
            })?;
            for (index, payload) in strips.into_iter().enumerate() {
                let first_row = index.checked_mul(rows_per_strip).ok_or_else(|| {
                    ImageError::Decode(format!(
                        "compressed DNG image '{source_name}' strip row offset overflows"
                    ))
                })?;
                let required_rows = height.saturating_sub(first_row).min(rows_per_strip);
                // A final strip may be encoded to the full RowsPerStrip size.
                // Do not grant that padding to a single strip whose declared
                // RowsPerStrip is itself larger than the image.
                let maximum_rows = if expected_strip_count > 1 {
                    rows_per_strip
                } else {
                    required_rows
                };
                total_codec_samples = total_codec_samples
                    .checked_add(validate_dng_codec_payload_dimensions(
                        payload,
                        compression,
                        width,
                        expected_sample_width,
                        required_rows,
                        maximum_rows,
                        samples_per_pixel,
                        DngBlockContext::new("strip", index, source_name),
                    )?)
                    .ok_or_else(|| {
                        ImageError::Decode(format!(
                            "compressed DNG image '{source_name}' payload sample count overflows"
                        ))
                    })?;
            }
        }
        DataMode::Tiles => {
            let tile_width =
                dng_required_usize_tag(raw_ifd, RawTiffCommonTag::TileWidth, source_name)?;
            let tile_height =
                dng_required_usize_tag(raw_ifd, RawTiffCommonTag::TileLength, source_name)?;
            if tile_width == 0 || tile_height == 0 {
                return Err(ImageError::Decode(format!(
                    "compressed DNG image '{source_name}' has invalid tile dimensions {tile_width}x{tile_height}"
                )));
            }

            let expected_tile_count = width
                .div_ceil(tile_width)
                .checked_mul(height.div_ceil(tile_height))
                .ok_or_else(|| {
                    ImageError::Decode(format!(
                        "compressed DNG image '{source_name}' tile count overflows"
                    ))
                })?;
            let tiles = raw_ifd.tile_data(source).map_err(|e| {
                ImageError::Decode(format!(
                    "failed to inspect compressed DNG tiles for '{source_name}': {e}"
                ))
            })?;
            if tiles.len() != expected_tile_count {
                return Err(ImageError::Decode(format!(
                    "compressed DNG image '{source_name}' declares {} tiles but dimensions require {expected_tile_count}",
                    tiles.len()
                )));
            }

            let expected_sample_width =
                tile_width.checked_mul(samples_per_pixel).ok_or_else(|| {
                    ImageError::Decode(format!(
                        "compressed DNG image '{source_name}' tile sample width overflows"
                    ))
                })?;
            for (index, payload) in tiles.into_iter().enumerate() {
                total_codec_samples = total_codec_samples
                    .checked_add(validate_dng_codec_payload_dimensions(
                        payload,
                        compression,
                        tile_width,
                        expected_sample_width,
                        tile_height,
                        tile_height,
                        samples_per_pixel,
                        DngBlockContext::new("tile", index, source_name),
                    )?)
                    .ok_or_else(|| {
                        ImageError::Decode(format!(
                            "compressed DNG image '{source_name}' payload sample count overflows"
                        ))
                    })?;
            }
        }
    }

    if total_codec_samples > RAW_MAX_DECODED_SAMPLES {
        return Err(ImageError::Decode(format!(
            "compressed DNG image '{source_name}' is too large to decode safely: embedded codec payloads declare {total_codec_samples} samples, exceeding {RAW_MAX_DECODED_SAMPLES}"
        )));
    }

    Ok(())
}

#[derive(Clone, Copy)]
struct DngBlockContext<'a> {
    kind: &'static str,
    index: usize,
    source_name: &'a str,
}

impl<'a> DngBlockContext<'a> {
    fn new(kind: &'static str, index: usize, source_name: &'a str) -> Self {
        Self {
            kind,
            index,
            source_name,
        }
    }
}

impl std::fmt::Display for DngBlockContext<'_> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "DNG {} {} for '{}'",
            self.kind, self.index, self.source_name
        )
    }
}

#[allow(clippy::too_many_arguments)]
fn validate_dng_codec_payload_dimensions(
    payload: &[u8],
    compression: u16,
    expected_pixel_width: usize,
    expected_sample_width: usize,
    minimum_height: usize,
    maximum_height: usize,
    samples_per_pixel: usize,
    context: DngBlockContext<'_>,
) -> ImageResult<u128> {
    match compression {
        DNG_COMPRESSION_MODERN_JPEG => {
            let decoder = LjpegDecompressor::new(payload).map_err(|e| {
                ImageError::Decode(format!("failed to inspect lossless-JPEG {context}: {e}"))
            })?;
            validate_dng_lossless_jpeg_sample_count(
                decoder.width(),
                decoder.height(),
                expected_sample_width,
                minimum_height,
                maximum_height,
                context,
            )
        }
        DNG_COMPRESSION_JPEG_XL => {
            let header = inspect_jpeg_xl_header(payload, context)?;
            if header.width != expected_pixel_width
                || !(minimum_height..=maximum_height).contains(&header.height)
            {
                return Err(ImageError::Decode(format!(
                    "compressed {context} has incompatible JPEG-XL pixel dimensions {}x{}; expected width {expected_pixel_width} and height {minimum_height}..={maximum_height}",
                    header.width, header.height
                )));
            }
            if header.output_channels != samples_per_pixel {
                return Err(ImageError::Decode(format!(
                    "JPEG-XL {context} declares {} output channels, expected {samples_per_pixel}",
                    header.output_channels
                )));
            }
            validate_raw_side_limit(
                header
                    .width
                    .checked_mul(header.output_channels)
                    .ok_or_else(|| {
                        ImageError::Decode(format!("JPEG-XL {context} sample width overflows"))
                    })?,
                header.height,
                context.source_name,
                "embedded JPEG-XL sample dimensions",
            )?;

            let expected_block_samples = (expected_sample_width as u128)
                .checked_mul(maximum_height as u128)
                .ok_or_else(|| {
                    ImageError::Decode(format!("compressed {context} sample count overflows"))
                })?;
            if header.rendered_samples > expected_block_samples {
                return Err(ImageError::Decode(format!(
                    "JPEG-XL {context} declares {} rendered samples, exceeding the expected block allocation {expected_block_samples}",
                    header.rendered_samples
                )));
            }
            Ok(header.rendered_samples)
        }
        _ => Ok(0),
    }
}

fn validate_dng_lossless_jpeg_sample_count(
    jpeg_sample_width: usize,
    jpeg_height: usize,
    expected_sample_width: usize,
    minimum_height: usize,
    maximum_height: usize,
    context: DngBlockContext<'_>,
) -> ImageResult<u128> {
    let declared_samples = (jpeg_sample_width as u128)
        .checked_mul(jpeg_height as u128)
        .ok_or_else(|| {
            ImageError::Decode(format!("lossless-JPEG {context} sample count overflows"))
        })?;
    let expected_sample_width = expected_sample_width as u128;
    let minimum_samples = expected_sample_width
        .checked_mul(minimum_height as u128)
        .ok_or_else(|| {
            ImageError::Decode(format!(
                "compressed {context} minimum sample count overflows"
            ))
        })?;
    let maximum_samples = expected_sample_width
        .checked_mul(maximum_height as u128)
        .ok_or_else(|| {
            ImageError::Decode(format!(
                "compressed {context} maximum sample count overflows"
            ))
        })?;
    let contains_complete_destination_rows =
        expected_sample_width != 0 && declared_samples.is_multiple_of(expected_sample_width);

    if !(minimum_samples..=maximum_samples).contains(&declared_samples)
        || !contains_complete_destination_rows
    {
        return Err(ImageError::Decode(format!(
            "lossless-JPEG {context} declares {declared_samples} samples ({jpeg_sample_width}x{jpeg_height}); expected {minimum_samples}..={maximum_samples} samples in complete destination rows of {expected_sample_width}"
        )));
    }

    Ok(declared_samples)
}

struct JpegXlHeaderDimensions {
    width: usize,
    height: usize,
    output_channels: usize,
    rendered_samples: u128,
}

#[derive(Clone, Copy)]
struct JpegXlFrameLayout {
    is_reference_only: bool,
    x0: i32,
    y0: i32,
    width: u32,
    height: u32,
}

struct JpegXlPreflightDecoder {
    uninitialized: Option<UninitializedJxlImage>,
    image: Option<JxlImage>,
}

impl JpegXlPreflightDecoder {
    fn new() -> Self {
        let uninitialized = JxlImage::builder()
            .pool(JxlThreadPool::none())
            .alloc_tracker(AllocTracker::with_limit(
                JPEG_XL_PREFLIGHT_MAX_TRACKED_ALLOC_BYTES,
            ))
            .build_uninit();
        Self {
            uninitialized: Some(uninitialized),
            image: None,
        }
    }

    fn feed_codestream(&mut self, bytes: &[u8]) -> jxl_oxide::Result<()> {
        if let Some(image) = self.image.as_mut() {
            image.feed_bytes(bytes)?;
            return Ok(());
        }

        let mut uninitialized = self
            .uninitialized
            .take()
            .expect("JPEG-XL preflight decoder must have one active state");
        uninitialized.feed_bytes(bytes)?;
        match uninitialized.try_init()? {
            InitializeResult::Initialized(image) => self.image = Some(image),
            InitializeResult::NeedMoreData(uninitialized) => {
                self.uninitialized = Some(uninitialized)
            }
        }
        Ok(())
    }

    fn has_first_keyframe_header(&self) -> bool {
        self.image
            .as_ref()
            .is_some_and(|image| image.frame_header(0).is_some())
    }

    fn into_image(self) -> Option<JxlImage> {
        self.image.filter(|image| image.frame_header(0).is_some())
    }
}

fn inspect_jpeg_xl_header(
    payload: &[u8],
    context: DngBlockContext<'_>,
) -> ImageResult<JpegXlHeaderDimensions> {
    let mut container = ContainerParser::new();
    let mut decoder = JpegXlPreflightDecoder::new();
    let mut inspected_codestream_bytes = 0usize;

    'container_events: for event in container.feed_bytes(payload) {
        let event = event
            .map_err(|e| ImageError::Decode(format!("failed to inspect JPEG-XL {context}: {e}")))?;
        match event {
            ParseEvent::BitstreamKind(BitstreamKind::Invalid) => {
                return Err(ImageError::Decode(format!(
                    "failed to inspect JPEG-XL {context}: invalid JPEG-XL signature"
                )));
            }
            ParseEvent::Codestream(mut codestream) => {
                while !codestream.is_empty() {
                    if inspected_codestream_bytes == JPEG_XL_PREFLIGHT_MAX_CODESTREAM_BYTES {
                        break 'container_events;
                    }
                    let remaining_budget =
                        JPEG_XL_PREFLIGHT_MAX_CODESTREAM_BYTES - inspected_codestream_bytes;
                    let chunk_len = codestream
                        .len()
                        .min(JPEG_XL_PREFLIGHT_CHUNK_BYTES)
                        .min(remaining_budget);
                    let (chunk, remaining) = codestream.split_at(chunk_len);
                    decoder.feed_codestream(chunk).map_err(|e| {
                        ImageError::Decode(format!("failed to inspect JPEG-XL {context}: {e}"))
                    })?;
                    inspected_codestream_bytes += chunk_len;
                    codestream = remaining;

                    if decoder.has_first_keyframe_header() {
                        break 'container_events;
                    }
                }
            }
            ParseEvent::BitstreamKind(_)
            | ParseEvent::NoMoreAuxBox
            | ParseEvent::AuxBoxStart { .. }
            | ParseEvent::AuxBoxData(..)
            | ParseEvent::AuxBoxEnd(..) => {}
        }
    }

    let image = decoder.into_image().ok_or_else(|| {
        ImageError::Decode(format!(
            "failed to inspect JPEG-XL {context}: first keyframe header exceeds the {JPEG_XL_PREFLIGHT_MAX_CODESTREAM_BYTES}-byte codestream inspection budget or is truncated"
        ))
    })?;

    let image_header = image.image_header();
    let width = image.width() as usize;
    let height = image.height() as usize;
    let color_channels = if image_header.metadata.grayscale() {
        1usize
    } else {
        3usize
    };
    // `stream_no_alpha`, which rawler uses, emits the base color channels and
    // one black channel for CMYK, but omits alpha and other auxiliary data.
    let output_channels = color_channels
        + usize::from(
            image_header
                .metadata
                .ec_info
                .iter()
                .any(|channel| channel.is_black()),
        );

    let raw_width = image_header.size.width as u128;
    let raw_height = image_header.size.height as u128;
    let mut rendered_samples = raw_width
        .checked_mul(raw_height)
        .and_then(|pixels| pixels.checked_mul(color_channels as u128))
        .ok_or_else(|| ImageError::Decode(format!("JPEG-XL {context} sample count overflows")))?;
    for channel in &image_header.metadata.ec_info {
        let divisor = 1u128.checked_shl(channel.dim_shift).ok_or_else(|| {
            ImageError::Decode(format!(
                "JPEG-XL {context} has invalid extra-channel dimension shift {}",
                channel.dim_shift
            ))
        })?;
        let channel_width = raw_width.div_ceil(divisor);
        let channel_height = raw_height.div_ceil(divisor);
        rendered_samples = rendered_samples
            .checked_add(channel_width.checked_mul(channel_height).ok_or_else(|| {
                ImageError::Decode(format!(
                    "JPEG-XL {context} extra-channel sample count overflows"
                ))
            })?)
            .ok_or_else(|| {
                ImageError::Decode(format!("JPEG-XL {context} total sample count overflows"))
            })?;
    }

    let first_keyframe_index = image
        .frame_by_keyframe(0)
        .expect("first keyframe header was checked above")
        .index();
    let dependency_frames = (0..first_keyframe_index)
        .map(|frame_index| {
            let header = image
                .frame(frame_index)
                .expect("frames preceding the first keyframe must be loaded")
                .header();
            JpegXlFrameLayout {
                is_reference_only: !header.frame_type.is_normal_frame()
                    && !header.frame_type.is_progressive_frame(),
                x0: header.x0,
                y0: header.y0,
                width: header.width,
                height: header.height,
            }
        })
        .collect::<Vec<_>>();
    validate_jpeg_xl_dependency_frame_layouts(
        &dependency_frames,
        image_header.size.width,
        image_header.size.height,
        color_channels + image_header.metadata.ec_info.len(),
        rendered_samples,
        context,
    )?;

    Ok(JpegXlHeaderDimensions {
        width,
        height,
        output_channels,
        rendered_samples,
    })
}

fn validate_jpeg_xl_dependency_frame_layouts(
    frames: &[JpegXlFrameLayout],
    canvas_width: u32,
    canvas_height: u32,
    allocation_channels: usize,
    rendered_samples: u128,
    context: DngBlockContext<'_>,
) -> ImageResult<()> {
    let maximum_dependency_samples = rendered_samples
        .checked_mul(JPEG_XL_PREFLIGHT_MAX_DEPENDENCY_SAMPLE_MULTIPLIER)
        .ok_or_else(|| {
            ImageError::Decode(format!(
                "JPEG-XL {context} dependency sample budget overflows"
            ))
        })?;
    let mut dependency_samples = 0u128;

    for (frame_index, frame) in frames.iter().enumerate() {
        let (allocation_width, allocation_height) = if frame.is_reference_only {
            (u128::from(frame.width), u128::from(frame.height))
        } else {
            (
                jpeg_xl_canvas_intersection(frame.x0, frame.width, canvas_width),
                jpeg_xl_canvas_intersection(frame.y0, frame.height, canvas_height),
            )
        };
        validate_raw_side_limit(
            allocation_width as usize,
            allocation_height as usize,
            context.source_name,
            "embedded JPEG-XL dependency frame dimensions",
        )?;
        let frame_samples = allocation_width
            .checked_mul(allocation_height)
            .and_then(|pixels| pixels.checked_mul(allocation_channels as u128))
            .ok_or_else(|| {
                ImageError::Decode(format!(
                    "JPEG-XL {context} dependency frame {frame_index} sample count overflows"
                ))
            })?;
        dependency_samples = dependency_samples
            .checked_add(frame_samples)
            .ok_or_else(|| {
                ImageError::Decode(format!(
                    "JPEG-XL {context} total dependency sample count overflows"
                ))
            })?;

        if dependency_samples > maximum_dependency_samples {
            return Err(ImageError::Decode(format!(
                "JPEG-XL {context} dependency frames require {dependency_samples} samples by frame {frame_index}, exceeding the bounded dependency allocation {maximum_dependency_samples}; frame {frame_index} reference-only={}, origin=({}, {}), dimensions={}x{} on a {}x{} canvas",
                frame.is_reference_only,
                frame.x0,
                frame.y0,
                frame.width,
                frame.height,
                canvas_width,
                canvas_height,
            )));
        }
    }

    Ok(())
}

fn jpeg_xl_canvas_intersection(origin: i32, length: u32, canvas_length: u32) -> u128 {
    let start = i64::from(origin).max(0).min(i64::from(canvas_length));
    let end = i64::from(origin)
        .saturating_add(i64::from(length))
        .max(0)
        .min(i64::from(canvas_length));
    end.saturating_sub(start) as u128
}

fn dng_required_usize_tag<T: rawler::tags::TiffTag>(
    raw_ifd: &IFD,
    tag: T,
    source_name: &str,
) -> ImageResult<usize> {
    raw_ifd
        .get_entry(tag)
        .map(|entry| entry.force_usize(0))
        .ok_or_else(|| {
            ImageError::Decode(format!(
                "compressed DNG image '{source_name}' is missing a required TIFF tag"
            ))
        })
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
    if samples > RAW_MAX_DECODED_SAMPLES {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' is too large to decode safely: decoded sample allocation {sample_width}x{sample_height} exceeds {RAW_MAX_DECODED_SAMPLES} samples"
        )));
    }

    Ok(())
}

#[cfg(test)]
fn validate_tiff_raw_candidate_dimensions(
    source: &RawSource,
    source_name: &str,
) -> ImageResult<()> {
    for (width, height) in tiff_raw_candidate_dimensions(source) {
        validate_raw_dimensions(width, height, source_name)?;
    }
    Ok(())
}

fn tiff_raw_candidate_dimensions(source: &RawSource) -> Vec<(usize, usize)> {
    let mut reader = source.reader();
    let tiff = match GenericTiffReader::new(&mut reader, 0, 0, None, &[]) {
        Ok(tiff) => tiff,
        Err(_) => return Vec::new(),
    };

    tiff.find_ifds_with_filter(|ifd| {
        raw_dimensions_from_ifd(ifd).is_some()
            && (ifd.has_entry(RawTiffCommonTag::StripOffsets)
                || ifd.has_entry(RawTiffCommonTag::TileOffsets))
    })
    .into_iter()
    .filter_map(raw_dimensions_from_ifd)
    .collect()
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
    if raw_dimensions_require_preview(width, height, source_name)? {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' is too large to develop safely: {width}x{height} exceeds {RAW_MAX_DEVELOPMENT_PIXELS} pixels"
        )));
    }
    Ok(())
}

fn raw_dimensions_require_preview(
    width: usize,
    height: usize,
    source_name: &str,
) -> ImageResult<bool> {
    if width == 0 || height == 0 {
        return Err(ImageError::Decode(format!(
            "RAW image '{source_name}' decoded to invalid dimensions {width}x{height}"
        )));
    }
    validate_raw_side_limit(width, height, source_name, "dimensions")?;

    let pixels = (width as u128) * (height as u128);
    Ok(pixels > RAW_MAX_DEVELOPMENT_PIXELS)
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
        codecs::{jpeg::JpegEncoder, png::PngEncoder, tiff::TiffEncoder},
    };
    use moxcms::ColorProfile;
    use rawler::{
        decoders::Orientation as RawOrientation,
        formats::tiff::{GenericTiffReader, reader::TiffReader},
        rawsource::RawSource,
    };

    use super::{
        DngBlockContext, ImageResult, JpegXlFrameLayout, RAW_MAX_DECODED_SAMPLES,
        bytes_look_like_heif, bytes_look_like_raw, catch_raw_decode_panic, decode_image_from_bytes,
        decode_image_from_path, init_image_decoders, path_extension_is_raw,
        raw_dimensions_require_preview, raw_orientation_to_exif,
        raw_preview_dimensions_are_eligible, should_attempt_tiff_fallback,
        validate_dng_embedded_codec_dimensions, validate_dng_lossless_jpeg_sample_count,
        validate_dng_raw_ifd_allocation, validate_jpeg_xl_dependency_frame_layouts,
        validate_raw_dimensions, validate_tiff_raw_candidate_dimensions,
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
        assert!(error.to_string().contains("exceeds 54000000 pixels"));
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
        assert!(
            error
                .to_string()
                .contains(&format!("exceeds {RAW_MAX_DECODED_SAMPLES} samples"))
        );
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
        assert!(
            error
                .to_string()
                .contains(&format!("exceeds {RAW_MAX_DECODED_SAMPLES} samples"))
        );
    }

    #[test]
    fn accepts_matching_lossless_jpeg_dng_strip_dimensions() {
        let jpeg = synthetic_lossless_jpeg_header(8, 4);
        let encoded = minimal_dng_with_single_strip_payload(8, 4, 4, 1, 7, &jpeg);
        let tiff = parse_tiff(&encoded);
        let source = RawSource::new_from_slice(&encoded);

        validate_dng_embedded_codec_dimensions(tiff.root_ifd(), &source, "matching.dng")
            .expect("matching embedded lossless-JPEG dimensions should pass preflight");
    }

    #[test]
    fn accepts_reshaped_lossless_jpeg_dng_tile_samples() {
        // DNG permits the JPEG axes to differ from the tile axes when their
        // total sample counts match. rawler flattens this 4x8 JPEG buffer and
        // rechunks its 32 samples into four destination rows of eight.
        let jpeg = synthetic_lossless_jpeg_header(4, 8);
        let encoded = minimal_dng_with_single_tile_payload(8, 4, 8, 4, 1, 7, &jpeg);
        let tiff = parse_tiff(&encoded);
        let source = RawSource::new_from_slice(&encoded);

        validate_dng_embedded_codec_dimensions(tiff.root_ifd(), &source, "reshaped.dng")
            .expect("reshaped lossless-JPEG samples should pass preflight");
    }

    #[test]
    fn rejects_lossless_jpeg_samples_not_aligned_to_destination_rows() {
        let context = DngBlockContext::new("strip", 1, "partial-row.dng");
        let error = validate_dng_lossless_jpeg_sample_count(5, 4, 8, 2, 4, context)
            .expect_err("partial destination rows should fail preflight");

        assert!(error.to_string().contains("declares 20 samples (5x4)"));
        assert!(error.to_string().contains("complete destination rows of 8"));
    }

    #[test]
    fn rejects_oversized_lossless_jpeg_dng_tile_dimensions_before_decode() {
        // The TIFF allocation is only 1x1, while the embedded SOF advertises
        // a multi-gigabyte 50,000x50,000 u16 image. Header inspection must
        // reject it without constructing rawler's payload-sized PixU16.
        let jpeg = synthetic_lossless_jpeg_header(50_000, 50_000);
        let encoded = minimal_dng_with_single_tile_payload(1, 1, 1, 1, 1, 7, &jpeg);
        let tiff = parse_tiff(&encoded);
        let source = RawSource::new_from_slice(&encoded);

        let error =
            validate_dng_embedded_codec_dimensions(tiff.root_ifd(), &source, "embedded-huge.dng")
                .expect_err("embedded lossless-JPEG dimensions should be checked before decode");

        assert!(
            error
                .to_string()
                .contains("declares 2500000000 samples (50000x50000)")
        );
        assert!(error.to_string().contains("expected 1..=1 samples"));
    }

    #[test]
    fn rejects_unparseable_jpeg_xl_dng_payload_before_decode() {
        let encoded = minimal_dng_with_single_tile_payload(
            1,
            1,
            1,
            1,
            1,
            52_546,
            b"not a JPEG-XL codestream",
        );
        let tiff = parse_tiff(&encoded);
        let source = RawSource::new_from_slice(&encoded);

        let error =
            validate_dng_embedded_codec_dimensions(tiff.root_ifd(), &source, "invalid-jxl.dng")
                .expect_err("invalid JPEG-XL headers should fail closed before decode");

        assert!(error.to_string().contains("failed to inspect JPEG-XL"));
    }

    #[test]
    fn accepts_matching_jpeg_xl_dng_tile_dimensions() {
        let encoded =
            minimal_dng_with_single_tile_payload(2, 2, 2, 2, 3, 52_546, tiny_rgb_jpeg_xl());
        let tiff = parse_tiff(&encoded);
        let source = RawSource::new_from_slice(&encoded);

        validate_dng_embedded_codec_dimensions(tiff.root_ifd(), &source, "matching-jxl.dng")
            .expect("matching embedded JPEG-XL dimensions should pass preflight");
    }

    #[test]
    fn accepts_jpeg_xl_container_with_large_leading_metadata() {
        let payload =
            jpeg_xl_container_with_leading_metadata(tiny_rgb_jpeg_xl(), 1024 * 1024 + 4096);
        jxl_oxide::JxlImage::builder()
            .read(Cursor::new(&payload))
            .expect("the underlying decoder should accept the metadata-bearing container");
        let encoded = minimal_dng_with_single_tile_payload(2, 2, 2, 2, 3, 52_546, &payload);
        let tiff = parse_tiff(&encoded);
        let source = RawSource::new_from_slice(&encoded);

        validate_dng_embedded_codec_dimensions(tiff.root_ifd(), &source, "container-metadata.dng")
            .expect("container metadata should not consume the codestream inspection budget");
    }

    #[test]
    fn accepts_progressive_dc_jpeg_xl_dependencies() {
        let payload = progressive_dc_jpeg_xl();
        let image = jxl_oxide::JxlImage::builder()
            .read(Cursor::new(&payload))
            .expect("progressive fixture should decode");
        assert!(
            !image
                .frame(0)
                .unwrap()
                .header()
                .frame_type
                .is_normal_frame()
        );
        assert_eq!(image.frame_by_keyframe(0).unwrap().index(), 2);

        let encoded = minimal_dng_with_single_tile_payload(32, 32, 32, 32, 3, 52_546, &payload);
        let tiff = parse_tiff(&encoded);
        let source = RawSource::new_from_slice(&encoded);

        validate_dng_embedded_codec_dimensions(tiff.root_ifd(), &source, "progressive-dc.dng")
            .expect("bounded LF dependency frames should pass JPEG-XL preflight");
    }

    #[test]
    fn rejects_oversized_reference_only_jpeg_xl_dependency_before_decode() {
        let error = validate_jpeg_xl_dependency_frame_layouts(
            &[JpegXlFrameLayout {
                is_reference_only: true,
                x0: 0,
                y0: 0,
                width: 50_000,
                height: 50_000,
            }],
            2,
            2,
            3,
            12,
            DngBlockContext::new("tile", 0, "referenced-frame.dng"),
        )
        .expect_err("a leading reference-only frame should fail preflight");

        assert!(error.to_string().contains("dependency frames require"));
        assert!(error.to_string().contains("reference-only=true"));
        assert!(error.to_string().contains("dimensions=50000x50000"));
    }

    #[test]
    fn bounds_cropped_jpeg_xl_dependencies_by_the_rendered_canvas_intersection() {
        validate_jpeg_xl_dependency_frame_layouts(
            &[JpegXlFrameLayout {
                is_reference_only: false,
                x0: -50_000,
                y0: 0,
                width: 50_002,
                height: 2,
            }],
            2,
            2,
            3,
            12,
            DngBlockContext::new("tile", 0, "cropped.dng"),
        )
        .expect("non-reference frames render only their intersection with the canvas");
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

    fn minimal_dng_with_single_strip_payload(
        width: u32,
        height: u32,
        rows_per_strip: u32,
        samples_per_pixel: u16,
        compression: u16,
        payload: &[u8],
    ) -> Vec<u8> {
        const ENTRY_COUNT: u16 = 7;
        let payload_offset = 8 + 2 + usize::from(ENTRY_COUNT) * 12 + 4;
        let mut encoded = Vec::new();
        encoded.extend_from_slice(b"II*\0");
        encoded.extend_from_slice(&8u32.to_le_bytes());
        encoded.extend_from_slice(&ENTRY_COUNT.to_le_bytes());
        append_tiff_long(&mut encoded, 0x0100, width); // ImageWidth
        append_tiff_long(&mut encoded, 0x0101, height); // ImageLength
        append_tiff_short(&mut encoded, 0x0103, compression); // Compression
        append_tiff_long(&mut encoded, 0x0111, payload_offset as u32); // StripOffsets
        append_tiff_short(&mut encoded, 0x0115, samples_per_pixel); // SamplesPerPixel
        append_tiff_long(&mut encoded, 0x0116, rows_per_strip); // RowsPerStrip
        append_tiff_long(&mut encoded, 0x0117, payload.len() as u32); // StripByteCounts
        encoded.extend_from_slice(&0u32.to_le_bytes());
        assert_eq!(encoded.len(), payload_offset);
        encoded.extend_from_slice(payload);
        encoded
    }

    #[allow(clippy::too_many_arguments)]
    fn minimal_dng_with_single_tile_payload(
        width: u32,
        height: u32,
        tile_width: u32,
        tile_height: u32,
        samples_per_pixel: u16,
        compression: u16,
        payload: &[u8],
    ) -> Vec<u8> {
        const ENTRY_COUNT: u16 = 8;
        let payload_offset = 8 + 2 + usize::from(ENTRY_COUNT) * 12 + 4;
        let mut encoded = Vec::new();
        encoded.extend_from_slice(b"II*\0");
        encoded.extend_from_slice(&8u32.to_le_bytes());
        encoded.extend_from_slice(&ENTRY_COUNT.to_le_bytes());
        append_tiff_long(&mut encoded, 0x0100, width); // ImageWidth
        append_tiff_long(&mut encoded, 0x0101, height); // ImageLength
        append_tiff_short(&mut encoded, 0x0103, compression); // Compression
        append_tiff_short(&mut encoded, 0x0115, samples_per_pixel); // SamplesPerPixel
        append_tiff_long(&mut encoded, 0x0142, tile_width); // TileWidth
        append_tiff_long(&mut encoded, 0x0143, tile_height); // TileLength
        append_tiff_long(&mut encoded, 0x0144, payload_offset as u32); // TileOffsets
        append_tiff_long(&mut encoded, 0x0145, payload.len() as u32); // TileByteCounts
        encoded.extend_from_slice(&0u32.to_le_bytes());
        assert_eq!(encoded.len(), payload_offset);
        encoded.extend_from_slice(payload);
        encoded
    }

    fn synthetic_lossless_jpeg_header(width: u16, height: u16) -> Vec<u8> {
        let mut jpeg = Vec::new();
        jpeg.extend_from_slice(&[0xFF, 0xD8]); // SOI
        jpeg.extend_from_slice(&[0xFF, 0xC3]); // SOF3
        jpeg.extend_from_slice(&11u16.to_be_bytes());
        jpeg.push(12); // precision
        jpeg.extend_from_slice(&height.to_be_bytes());
        jpeg.extend_from_slice(&width.to_be_bytes());
        jpeg.push(1); // component count
        jpeg.extend_from_slice(&[1, 0x11, 0]); // id, sampling, quantization table

        jpeg.extend_from_slice(&[0xFF, 0xC4]); // DHT
        jpeg.extend_from_slice(&20u16.to_be_bytes());
        jpeg.push(0); // DC table 0
        jpeg.push(1); // one one-bit code
        jpeg.extend_from_slice(&[0; 15]);
        jpeg.push(0); // Huffman value

        jpeg.extend_from_slice(&[0xFF, 0xDA]); // SOS
        jpeg.extend_from_slice(&8u16.to_be_bytes());
        jpeg.extend_from_slice(&[1, 1, 0]); // component count, id, table
        jpeg.extend_from_slice(&[1, 0, 0]); // predictor, Se/Ah, point transform
        jpeg
    }

    fn tiny_rgb_jpeg_xl() -> &'static [u8] {
        // A lossless 2x2 black RGB codestream generated by cjxl 0.11.1.
        &[
            0xff, 0x0a, 0x08, 0x10, 0x10, 0x09, 0x08, 0x02, 0x01, 0x00, 0x8c, 0x02, 0x4b, 0x18,
            0x9b, 0x9c, 0x71, 0x84, 0x03, 0x38, 0x80, 0x03, 0x38, 0x20, 0x4a, 0xc0, 0x39, 0x05,
            0x01, 0x00, 0x20, 0x44, 0x80, 0x08, 0x10, 0x01, 0x22, 0x40, 0x84, 0xff, 0xf7, 0xef,
            0xf9, 0xef, 0xa1, 0x31, 0xe7, 0x9c, 0x6b, 0xed, 0x73, 0x6f, 0x92, 0x24, 0x09, 0x01,
            0x55, 0x55, 0x55, 0x55, 0x55, 0xd5, 0xff, 0xff, 0xff, 0x73, 0xef, 0xeb, 0xee, 0xee,
            0xee, 0x86, 0xff, 0xf7, 0xef, 0xf9, 0xef, 0xa1, 0x31, 0xe7, 0x9c, 0x6b, 0xed, 0x73,
            0x6f, 0x92, 0x24, 0x09, 0x01, 0x55, 0x55, 0x55, 0x55, 0x55, 0xd5, 0xff, 0xff, 0xff,
            0x73, 0xef, 0xeb, 0xee, 0xee, 0xee, 0x86, 0xff, 0xf7, 0xef, 0xf9, 0xef, 0xa1, 0x31,
            0xe7, 0x9c, 0x6b, 0xed, 0x73, 0x6f, 0x92, 0x24, 0x09, 0x01, 0x55, 0x55, 0x55, 0x55,
            0x55, 0xd5, 0xff, 0xff, 0xff, 0x73, 0xef, 0xeb, 0xee, 0xee, 0xee, 0x86, 0xff, 0xf7,
            0xef, 0xf9, 0xef, 0xa1, 0x31, 0xe7, 0x9c, 0x6b, 0xed, 0x73, 0x6f, 0x92, 0x24, 0x09,
            0x01, 0x55, 0x55, 0x55, 0x55, 0x55, 0xd5, 0xff, 0xff, 0xff, 0x73, 0xef, 0xeb, 0xee,
            0xee, 0xee, 0x3e, 0x00, 0x00, 0x00, 0x00,
        ]
    }

    fn progressive_dc_jpeg_xl() -> Vec<u8> {
        // A 32x32 RGB gradient encoded by cjxl 0.11.1 with
        // --progressive_dc=2 --progressive_ac --container=0. It contains two
        // LF dependency frames before the first displayed keyframe.
        decode_hex(concat!(
            "ff0a47060a2a1805005c00000000000000000030005000504a2834226e3a",
            "0040249ca6619fac3b193de2c3a460040000acc000504204704032104c10",
            "64106cfeffea030050a132cab8c1cbb99e2f3f74584cdbb8ced056db1696",
            "24422924b146030834024333280c4d554d494d4586a6aaa6a4a622435355",
            "53525391a1a9aa29a9a9c8d054d594d4546468aa6a4a6a2a323455352535",
            "15199aaa9a929a8a0c4d554d494d4586a6aaa6a4a62243535553525391a1",
            "a9aa29a9a9c8d054d594d4546468aa6a4a6a2a32345535253515199aaa9a",
            "929a8a0c4d554d494d454a120b83736c604a46cb5f3c5c4962558276def2",
            "cb46197c921fa428a4701bfac66c6e98553a643430e44931d9449804c18d",
            "d68f926a7462b19f82bbb0e7929cac33e626a883d263685da269d7720600",
            "3e60a7016a00089bdeb5033f3914b5a8790ae23bd8dede0e286ad7cafe1c",
            "ef4d7ddb2fa32dc77eb66399c58870d74f9dadf439f0df04d8f8dc59c175",
            "e1927752c5be808c0ff2afe2b1abef0329000c94a1f2d83d0397049a8911",
            "ec22e87e91e8f38f52df1edf9c74939ce48ac705e3d2e9e2660e3f1afb56",
            "ac1218807c3452b61e936bfa0586e97723d04ac4b64aa88beb74f0e4d9be",
            "e72ad03ff3070ce79b47c4472e9f7605db9062cf534060ccdfa7025e7140",
            "4981ab54782e97312d06eab15681943200e0c3a460842800904001640006",
            "2c0002b59f200000152aa38c1bbc9cebf9f24387c5b48deb0c6db56d6149",
            "22944212891a10450330fe050000952492d0f327bbf7d7a8084d49e200f1",
            "363f45210566ab1809879fe369cf77aff67e9f2ab345d57399a91106e892",
            "b100400f00000bd8036800a4000ca250ea5bdb238062",
        ))
    }

    fn decode_hex(hex: &str) -> Vec<u8> {
        assert!(hex.len().is_multiple_of(2));
        (0..hex.len())
            .step_by(2)
            .map(|offset| u8::from_str_radix(&hex[offset..offset + 2], 16).unwrap())
            .collect()
    }

    fn jpeg_xl_container_with_leading_metadata(
        codestream: &[u8],
        metadata_bytes: usize,
    ) -> Vec<u8> {
        let mut container = Vec::new();
        container.extend_from_slice(b"\0\0\0\x0cJXL \r\n\x87\n");
        append_jpeg_xl_box(&mut container, b"ftyp", b"jxl \0\0\0\0jxl ");
        append_jpeg_xl_box(&mut container, b"Exif", &vec![0; metadata_bytes]);
        append_jpeg_xl_box(&mut container, b"jxlc", codestream);
        container
    }

    fn append_jpeg_xl_box(container: &mut Vec<u8>, box_type: &[u8; 4], payload: &[u8]) {
        let box_size = u32::try_from(8 + payload.len()).expect("test box must fit in u32");
        container.extend_from_slice(&box_size.to_be_bytes());
        container.extend_from_slice(box_type);
        container.extend_from_slice(payload);
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

    fn append_tiff_short(encoded: &mut Vec<u8>, tag: u16, value: u16) {
        encoded.extend_from_slice(&tag.to_le_bytes());
        encoded.extend_from_slice(&3u16.to_le_bytes());
        encoded.extend_from_slice(&1u32.to_le_bytes());
        encoded.extend_from_slice(&value.to_le_bytes());
        encoded.extend_from_slice(&0u16.to_le_bytes());
    }

    #[test]
    fn accepts_raw_dimensions_at_maximum_side_length() {
        validate_raw_dimensions(50_000, 1080, "boundary.raw")
            .expect("the side and 54MP limits should both be inclusive");
    }

    #[test]
    fn raw_development_limit_is_exactly_54_megapixels() {
        assert!(!raw_dimensions_require_preview(6000, 9000, "boundary.raw").unwrap());
        assert!(raw_dimensions_require_preview(6001, 9000, "oversized.raw").unwrap());
    }

    #[test]
    fn raw_preview_requires_full_hd_short_edge() {
        assert!(raw_preview_dimensions_are_eligible(1920, 1080));
        assert!(raw_preview_dimensions_are_eligible(1080, 1920));
        assert!(!raw_preview_dimensions_are_eligible(1920, 1079));
    }

    #[test]
    fn raw_preview_limit_is_exactly_200_megapixels() {
        assert!(raw_preview_dimensions_are_eligible(20_000, 10_000));
        assert!(!raw_preview_dimensions_are_eligible(20_001, 10_000));
    }

    #[test]
    fn oversized_dng_applies_embedded_preview_icc_profile_without_raw_decode() {
        let preview_width = 1920;
        let preview_height = 1080;
        let display_p3_icc = ColorProfile::new_display_p3().encode().unwrap();
        let preview_pixel = [128, 0, 0];
        let preview_pixels = preview_pixel
            .into_iter()
            .cycle()
            .take((preview_width * preview_height * 3) as usize)
            .collect::<Vec<_>>();
        let mut jpeg = Vec::new();
        let mut jpeg_encoder = JpegEncoder::new_with_quality(&mut jpeg, 100);
        jpeg_encoder.set_icc_profile(display_p3_icc).unwrap();
        jpeg_encoder
            .write_image(
                &preview_pixels,
                preview_width,
                preview_height,
                ColorType::Rgb8.into(),
            )
            .unwrap();
        let expected_preview = decode_image_from_bytes(&jpeg).unwrap();
        assert!(
            expected_preview.rgb[0] > preview_pixel[0],
            "test profile should visibly move the red channel into sRGB"
        );

        let root_entry_count = 7_u16;
        let preview_entry_count = 6_u16;
        let preview_ifd_offset = 8 + 2 + u32::from(root_entry_count) * 12 + 4;
        let jpeg_offset = preview_ifd_offset + 2 + u32::from(preview_entry_count) * 12 + 4;
        let mut dng = Vec::new();
        dng.extend_from_slice(b"II*\0");
        dng.extend_from_slice(&8_u32.to_le_bytes());
        dng.extend_from_slice(&root_entry_count.to_le_bytes());
        append_tiff_long(&mut dng, 0x0100, 6001); // ImageWidth
        append_tiff_long(&mut dng, 0x0101, 9000); // ImageLength: 54,009,000 px
        append_tiff_short(&mut dng, 0x0102, 16); // BitsPerSample
        append_tiff_short(&mut dng, 0x0103, 1); // Compression
        append_tiff_short(&mut dng, 0x0106, 32_803); // CFA photometric
        append_tiff_long(&mut dng, 0x014a, preview_ifd_offset); // SubIFDs
        dng.extend_from_slice(&0xc612_u16.to_le_bytes()); // DNGVersion
        dng.extend_from_slice(&1_u16.to_le_bytes()); // BYTE
        dng.extend_from_slice(&4_u32.to_le_bytes());
        dng.extend_from_slice(&[1, 4, 0, 0]);
        dng.extend_from_slice(&0_u32.to_le_bytes());
        assert_eq!(dng.len(), preview_ifd_offset as usize);

        dng.extend_from_slice(&preview_entry_count.to_le_bytes());
        append_tiff_long(&mut dng, 0x00fe, 1); // reduced-resolution image
        append_tiff_long(&mut dng, 0x0100, preview_width);
        append_tiff_long(&mut dng, 0x0101, preview_height);
        append_tiff_short(&mut dng, 0x0103, 7); // JPEG compression
        append_tiff_long(&mut dng, 0x0201, jpeg_offset);
        append_tiff_long(&mut dng, 0x0202, jpeg.len() as u32);
        dng.extend_from_slice(&0_u32.to_le_bytes());
        assert_eq!(dng.len(), jpeg_offset as usize);
        dng.extend_from_slice(&jpeg);

        let decoded = decode_image_from_bytes(&dng).expect("eligible preview should be returned");
        assert_eq!(
            (decoded.dimensions.width, decoded.dimensions.height),
            (1920, 1080)
        );
        assert_eq!(&decoded.rgb[..3], &expected_preview.rgb[..3]);
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
