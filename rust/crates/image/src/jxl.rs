use std::{
    borrow::Cow,
    fmt,
    io::{self, BufReader, Read, Seek, SeekFrom},
    sync::atomic::{AtomicUsize, Ordering},
    time::{Duration, Instant},
};

use ::jxl::api::{
    Endianness, Event, ExtraChannel, JxlBitDepth, JxlColorEncoding, JxlColorProfile, JxlColorType,
    JxlDataFormat, JxlDecoder, JxlDecoderOptions, JxlOutputBuffer, JxlParallelRunner,
    JxlParallelRunnerFun, JxlPixelFormat, JxlTransferFunction,
};
use ente_heic::DecodeGuardrails;
use image::{
    ColorType, ExtendedColorType, ImageDecoder, ImageError, ImageResult,
    error::{
        DecodingError, ImageFormatHint, LimitError, LimitErrorKind, UnsupportedError,
        UnsupportedErrorKind,
    },
};
use rayon::iter::{IntoParallelIterator, ParallelIterator};

use crate::memory_budget::MemoryBudget;

pub(crate) const CODESTREAM_SIGNATURE: [u8; 2] = [0xFF, 0x0A];
pub(crate) const CONTAINER_SIGNATURE: [u8; 12] = [
    0x00, 0x00, 0x00, 0x0C, b'J', b'X', b'L', b' ', 0x0D, 0x0A, 0x87, 0x0A,
];
const MAX_DECODE_DURATION: Duration = Duration::from_secs(60);
const MAX_DECODE_MEMORY_BYTES: usize = 512 * 1024 * 1024;
const MAX_DECODE_THREADS: usize = 8;
const MAX_SAMPLES_PER_PIXEL: u64 = 4;
const MIN_8_BIT_OUTPUT_GAMMA: f32 = 0.3;
const MAX_8_BIT_OUTPUT_GAMMA: f32 = 0.6;

#[cfg(test)]
pub(crate) const RGB_2X2_CODESTREAM: [u8; 27] = [
    0xFF, 0x0A, 0x08, 0x10, 0x10, 0x09, 0x08, 0x00, 0x01, 0x00, 0x3C, 0x00, 0x4B, 0x18, 0x8B, 0x15,
    0xC2, 0x41, 0x19, 0x5E, 0x20, 0x00, 0x80, 0x08, 0x20, 0x08, 0x06,
];

#[cfg(test)]
pub(crate) const RGB16_SRGB_2X1_CODESTREAM: [u8; 34] = [
    0xFF, 0x0A, 0x00, 0x70, 0xFC, 0x40, 0x02, 0x08, 0x00, 0x01, 0x00, 0x54, 0x00, 0x4B, 0x18, 0x8B,
    0x15, 0x42, 0x8A, 0x06, 0xE9, 0x45, 0x07, 0x50, 0xF6, 0xFF, 0x7F, 0xBB, 0x5B, 0x01, 0x03, 0xC8,
    0xCC, 0x04,
];

#[cfg(test)]
pub(crate) const RGB_F32_LINEAR_2X1_CODESTREAM: [u8; 35] = [
    0xFF, 0x0A, 0x00, 0x70, 0x72, 0x00, 0x45, 0x8B, 0x08, 0x00, 0x01, 0x00, 0x54, 0x00, 0x4B, 0x18,
    0x8B, 0x15, 0x01, 0x12, 0x5E, 0xB8, 0x01, 0x34, 0x3E, 0xC2, 0x4D, 0x00, 0x01, 0x00, 0xB3, 0xCC,
    0xFF, 0xA3, 0x07,
];

#[cfg(test)]
pub(crate) const RGB_F8_LINEAR_2X1_CODESTREAM: [u8; 32] = [
    0xFF, 0x0A, 0x00, 0x70, 0x7E, 0x50, 0x40, 0xD1, 0x22, 0x08, 0x00, 0x01, 0x00, 0x44, 0x00, 0x4B,
    0x18, 0x8B, 0x15, 0x42, 0x09, 0x6E, 0x4C, 0xFC, 0x05, 0x42, 0x00, 0x38, 0x0E, 0x0D, 0x89, 0x00,
];

pub(crate) fn register_decoding_hook(guardrails: DecodeGuardrails) -> bool {
    let registered = image::hooks::register_decoding_hook(
        "jxl".into(),
        Box::new(move |reader| {
            decoder_from_reader(reader, &guardrails, Instant::now() + MAX_DECODE_DURATION)
        }),
    );

    if registered {
        image::hooks::register_format_detection_hook("jxl".into(), &CODESTREAM_SIGNATURE, None);
        image::hooks::register_format_detection_hook("jxl".into(), &CONTAINER_SIGNATURE, None);
    }

    registered
}

fn decoder_from_reader<'a, R>(
    mut reader: R,
    guardrails: &DecodeGuardrails,
    deadline: Instant,
) -> ImageResult<Box<dyn ImageDecoder + 'a>>
where
    R: Read + Seek + 'a,
{
    if let Some(max_input_bytes) = guardrails.max_input_bytes {
        let input_len = reader.seek(SeekFrom::End(0)).map_err(ImageError::IoError)?;
        if input_len > max_input_bytes {
            return Err(too_large());
        }
        reader.rewind().map_err(ImageError::IoError)?;
    }

    let input = BoundedReader {
        inner: reader,
        position: 0,
        max_position: guardrails.max_input_bytes.unwrap_or(u64::MAX),
        deadline,
    };
    let sample_limit = guardrails.max_pixels.map(|max_pixels| {
        usize::try_from(max_pixels.saturating_mul(MAX_SAMPLES_PER_PIXEL)).unwrap_or(usize::MAX)
    });
    let decoder = JxlImageDecoder::new(input, sample_limit, MAX_DECODE_MEMORY_BYTES)?;

    if let Some(max_pixels) = guardrails.max_pixels {
        let (width, height) = decoder.dimensions();
        if u64::from(width) * u64::from(height) > max_pixels {
            return Err(too_large());
        }
    }

    Ok(Box::new(decoder))
}

struct JxlImageDecoder<R: Read + Seek> {
    input: BufReader<BoundedReader<R>>,
    decoder: JxlDecoder,
    budget: MemoryBudget,
    dimensions: (u32, u32),
    color_type: ColorType,
}

impl<R: Read + Seek> JxlImageDecoder<R> {
    fn new(
        reader: BoundedReader<R>,
        sample_limit: Option<usize>,
        memory_limit: usize,
    ) -> ImageResult<Self> {
        let mut input = BufReader::new(reader);
        let mut options = JxlDecoderOptions::default();
        options.sample_limit = sample_limit;
        let mut decoder = JxlDecoder::new(options);
        let budget = MemoryBudget::new(memory_limit);
        if process(&mut decoder, &mut input, None, &budget)? != Event::BasicInfo {
            return Err(truncated());
        }

        let info = decoder.basic_info().ok_or_else(truncated)?;
        if info
            .extra_channels
            .iter()
            .any(|channel| channel.ec_type == ExtraChannel::Black)
        {
            return Err(ImageError::Unsupported(
                UnsupportedError::from_format_and_kind(
                    format_hint(),
                    UnsupportedErrorKind::Color(ExtendedColorType::Cmyk8),
                ),
            ));
        }
        let width = u32::try_from(info.size.0).map_err(|_| dimension_error())?;
        let height = u32::try_from(info.size.1).map_err(|_| dimension_error())?;
        let alpha = info
            .extra_channels
            .iter()
            .any(|channel| channel.ec_type == ExtraChannel::Alpha);
        let num_extra_channels = info.extra_channels.len();
        let finer_than_u8 = matches!(info.bit_depth, JxlBitDepth::Float { .. })
            || info.bit_depth.bits_per_sample() > 8;
        let grayscale = decoder
            .current_pixel_format()
            .ok_or_else(truncated)?
            .color_type
            .is_grayscale();

        let pixel_format = |sixteen_bit| JxlPixelFormat {
            color_type: jxl_color_type(grayscale, alpha),
            color_data_format: Some(output_data_format(sixteen_bit)),
            extra_channel_format: vec![None; num_extra_channels],
        };
        within_budget(&budget, || decoder.set_pixel_format(pixel_format(false)))?
            .map_err(jxl_error)?;
        let sixteen_bit = finer_than_u8
            && decoder
                .output_color_profile()
                .is_none_or(needs_sixteen_bit_output);
        if sixteen_bit {
            within_budget(&budget, || decoder.set_pixel_format(pixel_format(true)))?
                .map_err(jxl_error)?;
        }
        let color_type = output_color_type(sixteen_bit, grayscale, alpha);

        Ok(Self {
            input,
            decoder,
            budget,
            dimensions: (width, height),
            color_type,
        })
    }

    fn decode_into(mut self, buf: &mut [u8]) -> ImageResult<()> {
        assert_eq!(buf.len() as u64, self.total_bytes());
        let bytes_per_sample =
            usize::from(self.color_type.bytes_per_pixel() / self.color_type.channel_count());
        if buf.as_ptr().align_offset(bytes_per_sample) != 0 {
            return Err(decoding_error(
                "output buffer is not aligned to its sample size",
            ));
        }

        let rows = self.dimensions.1 as usize;
        let bytes_per_row = buf.len() / rows;
        let mut output = JxlOutputBuffer::new(buf, rows, bytes_per_row);
        loop {
            match process(
                &mut self.decoder,
                &mut self.input,
                Some(std::slice::from_mut(&mut output)),
                &self.budget,
            )? {
                Event::FrameHeader => {}
                Event::FrameComplete { .. } => return Ok(()),
                _ => return Err(truncated()),
            }
        }
    }
}

impl<R: Read + Seek> ImageDecoder for JxlImageDecoder<R> {
    fn dimensions(&self) -> (u32, u32) {
        self.dimensions
    }

    fn color_type(&self) -> ColorType {
        self.color_type
    }

    fn icc_profile(&mut self) -> ImageResult<Option<Vec<u8>>> {
        within_budget(&self.budget, || {
            self.decoder
                .output_color_profile()
                .filter(|profile| !uses_hdr_transfer(profile))
                .map(with_dci_as_pure_gamma)
                .and_then(|profile| profile.try_as_icc().map(Cow::into_owned))
        })
    }

    fn read_image(self, buf: &mut [u8]) -> ImageResult<()> {
        self.decode_into(buf)
    }

    fn read_image_boxed(self: Box<Self>, buf: &mut [u8]) -> ImageResult<()> {
        (*self).decode_into(buf)
    }
}

fn process<R: Read + Seek>(
    decoder: &mut JxlDecoder,
    input: &mut BufReader<BoundedReader<R>>,
    output: Option<&mut [JxlOutputBuffer]>,
    budget: &MemoryBudget,
) -> ImageResult<Event> {
    within_budget(budget, || {
        decoder.process(input, output, Some(&mut RayonRunner { budget }))
    })?
    .map_err(jxl_error)
}

fn within_budget<T>(budget: &MemoryBudget, work: impl FnOnce() -> T) -> ImageResult<T> {
    let result = budget.enter(work);
    if budget.is_exceeded() {
        return Err(too_large());
    }
    Ok(result)
}

fn output_data_format(sixteen_bit: bool) -> JxlDataFormat {
    if sixteen_bit {
        JxlDataFormat::U16 {
            endianness: Endianness::native(),
            bit_depth: 16,
        }
    } else {
        JxlDataFormat::U8 { bit_depth: 8 }
    }
}

fn output_color_type(sixteen_bit: bool, grayscale: bool, alpha: bool) -> ColorType {
    match (sixteen_bit, grayscale, alpha) {
        (false, true, false) => ColorType::L8,
        (false, true, true) => ColorType::La8,
        (false, false, false) => ColorType::Rgb8,
        (false, false, true) => ColorType::Rgba8,
        (true, true, false) => ColorType::L16,
        (true, true, true) => ColorType::La16,
        (true, false, false) => ColorType::Rgb16,
        (true, false, true) => ColorType::Rgba16,
    }
}

fn needs_sixteen_bit_output(profile: &JxlColorProfile) -> bool {
    match profile {
        JxlColorProfile::Simple(
            JxlColorEncoding::RgbColorSpace {
                transfer_function, ..
            }
            | JxlColorEncoding::GrayscaleColorSpace {
                transfer_function, ..
            },
        ) => match transfer_function {
            JxlTransferFunction::Linear | JxlTransferFunction::BT709 => true,
            JxlTransferFunction::Gamma(gamma) => {
                !(MIN_8_BIT_OUTPUT_GAMMA..=MAX_8_BIT_OUTPUT_GAMMA).contains(gamma)
            }
            _ => false,
        },
        _ => true,
    }
}

fn uses_hdr_transfer(profile: &JxlColorProfile) -> bool {
    matches!(
        profile,
        JxlColorProfile::Simple(
            JxlColorEncoding::RgbColorSpace {
                transfer_function: JxlTransferFunction::PQ | JxlTransferFunction::HLG,
                ..
            } | JxlColorEncoding::GrayscaleColorSpace {
                transfer_function: JxlTransferFunction::PQ | JxlTransferFunction::HLG,
                ..
            }
        )
    )
}

fn with_dci_as_pure_gamma(profile: &JxlColorProfile) -> Cow<'_, JxlColorProfile> {
    let JxlColorProfile::Simple(encoding) = profile else {
        return Cow::Borrowed(profile);
    };
    let mut encoding = encoding.clone();
    match &mut encoding {
        JxlColorEncoding::RgbColorSpace {
            transfer_function, ..
        }
        | JxlColorEncoding::GrayscaleColorSpace {
            transfer_function, ..
        } if *transfer_function == JxlTransferFunction::DCI => {
            *transfer_function = JxlTransferFunction::Gamma(1.0 / 2.6);
            Cow::Owned(JxlColorProfile::Simple(encoding))
        }
        _ => Cow::Borrowed(profile),
    }
}

fn jxl_color_type(grayscale: bool, alpha: bool) -> JxlColorType {
    match (grayscale, alpha) {
        (true, false) => JxlColorType::Grayscale,
        (true, true) => JxlColorType::GrayscaleAlpha,
        (false, false) => JxlColorType::Rgb,
        (false, true) => JxlColorType::Rgba,
    }
}

struct RayonRunner<'a> {
    budget: &'a MemoryBudget,
}

impl JxlParallelRunner for RayonRunner<'_> {
    fn run(&mut self, num: usize, fun: &JxlParallelRunnerFun<'_>) -> ::jxl::error::Result<()> {
        self.run_ordered(num, None, fun)
    }

    fn num_threads(&self) -> usize {
        rayon::current_num_threads().min(MAX_DECODE_THREADS)
    }

    fn run_ordered(
        &mut self,
        num: usize,
        max_threads: Option<usize>,
        fun: &JxlParallelRunnerFun<'_>,
    ) -> ::jxl::error::Result<()> {
        let budget = self.budget;
        let workers = max_threads
            .unwrap_or(usize::MAX)
            .min(self.num_threads())
            .min(num);
        let next_index = AtomicUsize::new(0);
        let work = || {
            loop {
                if budget.is_exceeded() {
                    return Err(io::Error::from(io::ErrorKind::OutOfMemory).into());
                }
                let index = next_index.fetch_add(1, Ordering::Relaxed);
                if index >= num {
                    return Ok(());
                }
                fun(index)?;
            }
        };
        if workers <= 1 {
            return work();
        }
        MemoryBudget::suspend(|| {
            (0..workers)
                .into_par_iter()
                .try_for_each(|_| budget.enter(work))
        })
    }
}

#[derive(Debug)]
enum InputLimitExceeded {
    Bytes,
    Duration,
}

impl fmt::Display for InputLimitExceeded {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Bytes => f.write_str("JPEG XL input exceeds configured max_input_bytes"),
            Self::Duration => f.write_str("JPEG XL decode exceeded its time budget"),
        }
    }
}

impl std::error::Error for InputLimitExceeded {}

struct BoundedReader<R> {
    inner: R,
    position: u64,
    max_position: u64,
    deadline: Instant,
}

impl<R: Read> Read for BoundedReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        if Instant::now() >= self.deadline {
            return Err(std::io::Error::other(InputLimitExceeded::Duration));
        }
        let count = self.inner.read(buf)?;
        self.position = self.position.saturating_add(count as u64);
        if count > 0 && self.position > self.max_position {
            return Err(std::io::Error::other(InputLimitExceeded::Bytes));
        }
        Ok(count)
    }
}

impl<R: Seek> Seek for BoundedReader<R> {
    fn seek(&mut self, pos: SeekFrom) -> std::io::Result<u64> {
        self.position = self.inner.seek(pos)?;
        Ok(self.position)
    }
}

fn jxl_error(error: ::jxl::error::Error) -> ImageError {
    match error {
        ::jxl::error::Error::ImageSizeTooLarge(..)
        | ::jxl::error::Error::ImageDimensionTooLarge(_)
        | ::jxl::error::Error::ImageOutOfMemory(..)
        | ::jxl::error::Error::OutOfMemory(_) => too_large(),
        ::jxl::error::Error::IOError(ref io_error) if exceeds_input_limit(io_error) => too_large(),
        error => decoding_error(error),
    }
}

fn exceeds_input_limit(error: &std::io::Error) -> bool {
    matches!(error.get_ref(), Some(inner) if inner.is::<InputLimitExceeded>())
}

fn too_large() -> ImageError {
    ImageError::Limits(LimitError::from_kind(LimitErrorKind::InsufficientMemory))
}

fn dimension_error() -> ImageError {
    ImageError::Limits(LimitError::from_kind(LimitErrorKind::DimensionError))
}

fn truncated() -> ImageError {
    decoding_error("truncated JPEG XL image")
}

fn decoding_error(error: impl Into<Box<dyn std::error::Error + Send + Sync>>) -> ImageError {
    ImageError::Decoding(DecodingError::new(format_hint(), error))
}

fn format_hint() -> ImageFormatHint {
    ImageFormatHint::PathExtension("jxl".into())
}

#[cfg(test)]
mod tests {
    use std::{
        io::{BufReader, Cursor, Read, Seek, SeekFrom},
        sync::{
            Mutex,
            atomic::{AtomicUsize, Ordering},
        },
        time::{Duration, Instant},
    };

    use ::jxl::api::{JxlBitstreamInput, JxlParallelRunner};
    use ente_heic::DecodeGuardrails;
    use image::{ColorType, ImageDecoder, ImageError, ImageResult};

    use super::{
        BoundedReader, JxlImageDecoder, MAX_DECODE_MEMORY_BYTES, MAX_DECODE_THREADS,
        RGB_2X2_CODESTREAM, RGB_F8_LINEAR_2X1_CODESTREAM, RGB_F32_LINEAR_2X1_CODESTREAM,
        RGB16_SRGB_2X1_CODESTREAM, RayonRunner, decoder_from_reader,
    };
    use crate::memory_budget::MemoryBudget;

    fn guardrails(max_input_bytes: Option<u64>, max_pixels: Option<u64>) -> DecodeGuardrails {
        DecodeGuardrails {
            max_input_bytes,
            max_pixels,
            max_temp_spool_bytes: None,
            temp_spool_directory: None,
        }
    }

    fn later() -> Instant {
        Instant::now() + Duration::from_secs(60)
    }

    fn decode_rgb(decoder: Box<dyn ImageDecoder + '_>) -> Vec<u8> {
        image::DynamicImage::from_decoder(decoder)
            .unwrap()
            .into_rgb8()
            .into_raw()
    }

    #[test]
    fn decodes_lossless_codestream_to_exact_pixels() {
        let decoder = decoder_from_reader(
            Cursor::new(RGB_2X2_CODESTREAM),
            &guardrails(Some(1024), Some(64)),
            later(),
        )
        .unwrap();

        assert_eq!(decoder.dimensions(), (2, 2));
        assert_eq!(
            decode_rgb(decoder),
            [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]
        );
    }

    #[test]
    fn decodes_high_bit_depth_images_to_8_bit_samples_only_for_perceptual_transfers() {
        const RGB16_GAMMA_0_556_2X1_CODESTREAM: [u8; 36] = [
            0xFF, 0x0A, 0x00, 0x70, 0xFC, 0x00, 0x54, 0xC8, 0x62, 0xAA, 0x08, 0x08, 0x00, 0x01,
            0x00, 0x4C, 0x00, 0x4B, 0x18, 0x8B, 0x15, 0x42, 0x19, 0x36, 0x2E, 0xCB, 0x5D, 0x20,
            0x04, 0x80, 0xB4, 0x9C, 0x0A, 0xA5, 0x6E, 0x18,
        ];
        const RGB16_XYB_ICC_2X1_CODESTREAM: [u8; 160] = [
            0xFF, 0x0A, 0x00, 0x70, 0xFC, 0xA4, 0x50, 0xDF, 0x01, 0x09, 0xF3, 0x00, 0xE8, 0x70,
            0x66, 0x1C, 0x4A, 0xB4, 0x95, 0xB8, 0xCB, 0x2B, 0x03, 0x8D, 0x2D, 0xC4, 0xBE, 0xBA,
            0x82, 0xA8, 0x42, 0xEB, 0x98, 0x7A, 0x4D, 0x38, 0x0E, 0xFD, 0x03, 0xFC, 0x34, 0xDA,
            0xB5, 0xF2, 0x38, 0x9C, 0xA6, 0xC1, 0xBE, 0x92, 0x20, 0x58, 0x3B, 0x54, 0x1F, 0xB0,
            0xA2, 0x16, 0xF0, 0xE6, 0x01, 0x06, 0xE5, 0x42, 0x88, 0x22, 0xE8, 0x3B, 0x00, 0x6D,
            0x3E, 0x2F, 0xE8, 0x03, 0x32, 0x82, 0xB6, 0x0E, 0xF4, 0xEF, 0x1F, 0x00, 0x13, 0x88,
            0x02, 0x00, 0x20, 0x01, 0xB5, 0x9F, 0x20, 0x00, 0x00, 0x15, 0x2A, 0xA3, 0x8C, 0x1B,
            0xBC, 0x9C, 0xEB, 0xF9, 0xF2, 0x43, 0x87, 0xC5, 0xB4, 0x8D, 0xEB, 0x0C, 0x6D, 0xB5,
            0x6D, 0x61, 0x09, 0x63, 0xB3, 0xBD, 0x30, 0x48, 0x48, 0x38, 0x82, 0x8D, 0x4B, 0x0E,
            0x6E, 0x0E, 0xCE, 0xC1, 0x40, 0xBA, 0x51, 0x49, 0x22, 0x25, 0x91, 0xB7, 0x63, 0xAF,
            0x8A, 0x88, 0x30, 0x8A, 0xC6, 0x27, 0xA0, 0x09, 0xC0, 0x33, 0xC6, 0x01, 0x16, 0x00,
            0x89, 0x7D, 0x81, 0x09, 0x40, 0x01,
        ];

        for (codestream, color_type) in [
            (&RGB16_SRGB_2X1_CODESTREAM[..], ColorType::Rgb8),
            (&RGB16_GAMMA_0_556_2X1_CODESTREAM[..], ColorType::Rgb8),
            (&RGB16_XYB_ICC_2X1_CODESTREAM[..], ColorType::Rgb8),
            (&RGB_F32_LINEAR_2X1_CODESTREAM[..], ColorType::Rgb16),
            (&RGB_F8_LINEAR_2X1_CODESTREAM[..], ColorType::Rgb16),
        ] {
            let decoder =
                decoder_from_reader(Cursor::new(codestream), &guardrails(None, None), later())
                    .unwrap();

            assert_eq!(decoder.color_type(), color_type);
        }
    }

    #[test]
    fn rejects_inputs_exceeding_the_input_cap() {
        let decoder =
            decoder_from_reader(Cursor::new([0u8; 16]), &guardrails(Some(4), None), later());

        assert!(matches!(decoder.err(), Some(ImageError::Limits(_))));
    }

    struct UnderreportingReader {
        bytes: Cursor<[u8; 27]>,
    }

    impl Read for UnderreportingReader {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            self.bytes.read(buf)
        }
    }

    impl Seek for UnderreportingReader {
        fn seek(&mut self, pos: SeekFrom) -> std::io::Result<u64> {
            match pos {
                SeekFrom::End(0) => Ok(4),
                pos => self.bytes.seek(pos),
            }
        }
    }

    #[test]
    fn rejects_inputs_exceeding_the_input_cap_when_the_source_underreports_its_length() {
        let decoder = decoder_from_reader(
            UnderreportingReader {
                bytes: Cursor::new(RGB_2X2_CODESTREAM),
            },
            &guardrails(Some(4), None),
            later(),
        );

        assert!(matches!(decoder.err(), Some(ImageError::Limits(_))));
    }

    const RGB_16X16_CODESTREAM: [u8; 45] = [
        0xFF, 0x0A, 0x43, 0x40, 0x24, 0x08, 0x00, 0x01, 0x00, 0x88, 0x00, 0x4B, 0x18, 0x8B, 0x15,
        0x00, 0xD4, 0x88, 0x31, 0x66, 0x9C, 0x89, 0x13, 0x42, 0x04, 0x8C, 0x2B, 0x9A, 0x79, 0x03,
        0xA8, 0x83, 0x43, 0x17, 0x03, 0xDD, 0x04, 0xD0, 0xF6, 0xFF, 0x00, 0xD1, 0x7B, 0x80, 0x00,
    ];

    #[test]
    fn rejects_images_exceeding_the_pixel_cap() {
        let decoder = decoder_from_reader(
            Cursor::new(RGB_16X16_CODESTREAM),
            &guardrails(None, Some(255)),
            later(),
        );

        assert!(matches!(decoder.err(), Some(ImageError::Limits(_))));
    }

    #[test]
    fn rejects_images_exceeding_the_sample_limit_while_reading_the_header() {
        let reader = BoundedReader {
            inner: Cursor::new(RGB_2X2_CODESTREAM),
            position: 0,
            max_position: u64::MAX,
            deadline: later(),
        };

        assert!(matches!(
            JxlImageDecoder::new(reader, Some(12), MAX_DECODE_MEMORY_BYTES).err(),
            Some(ImageError::Limits(_))
        ));
    }

    const SOLID_256X256_CODESTREAM: [u8; 84] = [
        0xFF, 0x0A, 0x7F, 0x40, 0x40, 0x71, 0x21, 0x08, 0x02, 0x01, 0x00, 0x1C, 0x01, 0x4B, 0x18,
        0x8B, 0x15, 0x00, 0xD4, 0x88, 0x31, 0xEE, 0xEE, 0xC6, 0x3D, 0x80, 0x03, 0x38, 0xC3, 0x99,
        0x00, 0x9A, 0x0F, 0xBD, 0x15, 0x5E, 0xCC, 0xFB, 0x36, 0xA1, 0xD4, 0x48, 0x74, 0x04, 0x47,
        0x60, 0x22, 0x00, 0x88, 0x6E, 0xD6, 0x89, 0xD2, 0x5B, 0xE1, 0xC5, 0xBC, 0x6F, 0x13, 0x4A,
        0x8D, 0x44, 0x47, 0x70, 0x84, 0x0A, 0x69, 0x5A, 0x3A, 0xD0, 0xC7, 0x0B, 0x06, 0x18, 0x51,
        0x69, 0x92, 0xC5, 0x4F, 0xAF, 0x7D, 0x25, 0xC9, 0x3C,
    ];

    fn decode_solid_rgb(memory_limit: usize) -> ImageResult<Vec<u8>> {
        let reader = BoundedReader {
            inner: Cursor::new(SOLID_256X256_CODESTREAM),
            position: 0,
            max_position: u64::MAX,
            deadline: later(),
        };
        let decoder = JxlImageDecoder::new(reader, None, memory_limit)?;
        Ok(image::DynamicImage::from_decoder(decoder)?
            .into_rgb8()
            .into_raw())
    }

    #[test]
    fn decodes_images_within_the_memory_budget() {
        assert_eq!(
            decode_solid_rgb(MAX_DECODE_MEMORY_BYTES).unwrap(),
            [40, 90, 200].repeat(256 * 256)
        );
    }

    #[test]
    fn rejects_decodes_exceeding_the_memory_budget() {
        assert!(matches!(decode_solid_rgb(0), Err(ImageError::Limits(_))));
    }

    #[test]
    fn stops_parallel_tasks_once_their_allocations_exceed_the_budget() {
        let budget = MemoryBudget::new(4 << 20);
        let held = Mutex::new(Vec::new());
        let started = AtomicUsize::new(0);
        let result = budget.enter(|| {
            RayonRunner { budget: &budget }.run_ordered(64, Some(2), &|_| {
                started.fetch_add(1, Ordering::Relaxed);
                held.lock().unwrap().push(vec![0u8; 1 << 20]);
                Ok(())
            })
        });

        assert!(result.is_err());
        assert!((4..=5).contains(&started.into_inner()));
    }

    #[test]
    fn rejects_icc_profile_copies_exceeding_the_memory_budget() {
        let reader = BoundedReader {
            inner: Cursor::new(RGB_2X2_CODESTREAM),
            position: 0,
            max_position: u64::MAX,
            deadline: later(),
        };
        let mut decoder = JxlImageDecoder::new(reader, None, MAX_DECODE_MEMORY_BYTES).unwrap();
        assert!(decoder.icc_profile().unwrap().is_some());

        decoder.budget = MemoryBudget::new(0);

        assert!(matches!(decoder.icc_profile(), Err(ImageError::Limits(_))));
    }

    #[test]
    fn caps_parallel_decoding_at_the_thread_limit() {
        let budget = MemoryBudget::new(MAX_DECODE_MEMORY_BYTES);
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(2 * MAX_DECODE_THREADS)
            .build()
            .unwrap();

        assert_eq!(
            pool.install(|| RayonRunner { budget: &budget }.num_threads()),
            MAX_DECODE_THREADS
        );
    }

    #[test]
    fn rejects_decodes_that_pass_their_deadline() {
        let decoder = decoder_from_reader(
            Cursor::new(RGB_2X2_CODESTREAM),
            &guardrails(None, None),
            Instant::now(),
        );

        assert!(matches!(decoder.err(), Some(ImageError::Limits(_))));
    }

    #[test]
    fn bounded_reader_errors_once_the_input_cap_is_exceeded() {
        let mut reader = BoundedReader {
            inner: Cursor::new([7u8; 16]),
            position: 0,
            max_position: 8,
            deadline: later(),
        };
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

    #[test]
    fn bounded_reader_counts_bytes_reread_after_a_seek_once() {
        let mut input = BufReader::with_capacity(
            8,
            BoundedReader {
                inner: Cursor::new([7u8; 16]),
                position: 0,
                max_position: 16,
                deadline: later(),
            },
        );
        let mut head = [0u8; 4];
        input.read_exact(&mut head).unwrap();
        JxlBitstreamInput::available_bytes(&mut input).unwrap();
        let mut rest = Vec::new();
        input.read_to_end(&mut rest).unwrap();

        assert_eq!(rest.len(), 12);
    }

    #[test]
    fn bounded_reader_reports_end_of_input_after_seeking_past_the_cap() {
        let mut reader = BoundedReader {
            inner: Cursor::new([7u8; 8]),
            position: 0,
            max_position: 8,
            deadline: later(),
        };
        let mut buf = [0u8; 4];
        reader.seek(SeekFrom::Start(100)).unwrap();

        assert_eq!(reader.read(&mut buf).unwrap(), 0);
    }
}
