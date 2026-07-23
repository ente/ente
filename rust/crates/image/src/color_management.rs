use image::{DynamicImage, ImageBuffer, Pixel};
use moxcms::{
    ColorProfile, DataColorSpace, InPlaceTransformExecutor, Layout, ToneReprCurve,
    TransferCharacteristics, TransformOptions, Xyzd,
};
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex, OnceLock},
};

static SRGB_PROFILE: OnceLock<ColorProfile> = OnceLock::new();
static SRGB_GRAY_PROFILE: OnceLock<ColorProfile> = OnceLock::new();
static ICC_PROFILE_CACHE: OnceLock<Mutex<VecDeque<CachedIccProfile>>> = OnceLock::new();

const ICC_PROFILE_CACHE_CAPACITY: usize = 8;
const MAX_CACHEABLE_ICC_PROFILE_BYTES: usize = 4 * 1024 * 1024;

type U8Transform = Arc<dyn InPlaceTransformExecutor<u8> + Send + Sync>;

struct CachedIccProfile {
    encoded: Arc<[u8]>,
    profile: Arc<ColorProfile>,
    u8_transforms: Vec<(Layout, U8Transform)>,
}

pub(crate) fn apply_icc_profile_to_srgb(
    image: DynamicImage,
    icc_profile: Option<&[u8]>,
) -> DynamicImage {
    let Some(icc_profile) = icc_profile.filter(|profile| !profile.is_empty()) else {
        return image;
    };

    let source_profile = match cached_color_profile(icc_profile) {
        Ok(profile) => profile,
        Err(err) => {
            eprintln!("[ml][decode] failed to parse embedded ICC profile: {err}");
            return image;
        }
    };

    if profile_is_effectively_srgb(&source_profile) {
        return image;
    }

    if profile_uses_hdr_transfer(&source_profile) {
        eprintln!(
            "[ml][decode] embedded ICC profile uses PQ/HLG transfer; skipping ICC transform because tone mapping is not implemented"
        );
        return image;
    }

    match apply_profile_to_image(image, &source_profile, icc_profile) {
        Ok(image) => image,
        Err((image, err)) => {
            eprintln!("[ml][decode] failed to convert embedded ICC profile to sRGB: {err}");
            image
        }
    }
}

fn apply_profile_to_image(
    image: DynamicImage,
    source_profile: &ColorProfile,
    encoded_profile: &[u8],
) -> Result<DynamicImage, (DynamicImage, String)> {
    use DynamicImage::*;
    use Layout::{Gray, GrayAlpha, Rgb, Rgba};

    match image {
        ImageLuma8(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Gray, ImageLuma8)
        }
        ImageLumaA8(buffer) => transform_buffer(
            buffer,
            source_profile,
            encoded_profile,
            GrayAlpha,
            ImageLumaA8,
        ),
        ImageRgb8(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Rgb, ImageRgb8)
        }
        ImageRgba8(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Rgba, ImageRgba8)
        }
        ImageLuma16(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Gray, ImageLuma16)
        }
        ImageLumaA16(buffer) => transform_buffer(
            buffer,
            source_profile,
            encoded_profile,
            GrayAlpha,
            ImageLumaA16,
        ),
        ImageRgb16(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Rgb, ImageRgb16)
        }
        ImageRgba16(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Rgba, ImageRgba16)
        }
        ImageRgb32F(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Rgb, ImageRgb32F)
        }
        ImageRgba32F(buffer) => {
            transform_buffer(buffer, source_profile, encoded_profile, Rgba, ImageRgba32F)
        }
        other => Ok(other),
    }
}

fn transform_buffer<P>(
    mut buffer: ImageBuffer<P, Vec<P::Subpixel>>,
    source_profile: &ColorProfile,
    encoded_profile: &[u8],
    layout: Layout,
    into_dynamic: fn(ImageBuffer<P, Vec<P::Subpixel>>) -> DynamicImage,
) -> Result<DynamicImage, (DynamicImage, String)>
where
    P: Pixel,
    P::Subpixel: TransformSubpixel,
{
    let (width, height) = buffer.dimensions();
    match P::Subpixel::transform_to_srgb(buffer.as_mut(), source_profile, encoded_profile, layout) {
        Ok(Some(transformed)) => Ok(into_dynamic(
            ImageBuffer::from_raw(width, height, transformed)
                .expect("transformed buffer length should match source dimensions"),
        )),
        Ok(None) => Ok(into_dynamic(buffer)),
        Err(err) => Err((into_dynamic(buffer), err)),
    }
}

/// Subpixel types for which moxcms can transform pixel buffers to sRGB.
trait TransformSubpixel: Copy {
    fn transform_to_srgb(
        pixels: &mut [Self],
        source_profile: &ColorProfile,
        encoded_profile: &[u8],
        layout: Layout,
    ) -> Result<Option<Vec<Self>>, String>;
}

impl TransformSubpixel for u8 {
    fn transform_to_srgb(
        pixels: &mut [Self],
        source_profile: &ColorProfile,
        encoded_profile: &[u8],
        layout: Layout,
    ) -> Result<Option<Vec<Self>>, String> {
        // A2B LUTs take ICC precedence over matrix/TRC, and the in-place
        // executor only implements matrix math, so LUT-carrying profiles go
        // out-of-place; the matrix path is the fallback when the LUT does
        // not cover the default intent (moxcms has no cross-intent fallback).
        if profile_has_device_to_pcs_lut(source_profile)
            && let Ok(transformed) = transform_u8_out_of_place(pixels, source_profile, layout)
        {
            return Ok(Some(transformed));
        }

        if let Ok(transform) = cached_u8_transform(encoded_profile, source_profile, layout) {
            transform.transform(pixels).map_err(|err| err.to_string())?;
            return Ok(None);
        }

        transform_u8_out_of_place(pixels, source_profile, layout).map(Some)
    }
}

impl TransformSubpixel for u16 {
    fn transform_to_srgb(
        pixels: &mut [Self],
        source_profile: &ColorProfile,
        _encoded_profile: &[u8],
        layout: Layout,
    ) -> Result<Option<Vec<Self>>, String> {
        let target_profile = target_profile_for_layout(layout);
        let transform = source_profile
            .create_transform_16bit(layout, target_profile, layout, transform_options())
            .map_err(|err| err.to_string())?;
        let mut transformed = vec![0; pixels.len()];
        transform
            .transform(pixels, &mut transformed)
            .map_err(|err| err.to_string())?;
        Ok(Some(transformed))
    }
}

impl TransformSubpixel for f32 {
    fn transform_to_srgb(
        pixels: &mut [Self],
        source_profile: &ColorProfile,
        _encoded_profile: &[u8],
        layout: Layout,
    ) -> Result<Option<Vec<Self>>, String> {
        let target_profile = target_profile_for_layout(layout);
        let transform = source_profile
            .create_transform_f32(layout, target_profile, layout, transform_options())
            .map_err(|err| err.to_string())?;
        let mut transformed = vec![0.0; pixels.len()];
        transform
            .transform(pixels, &mut transformed)
            .map_err(|err| err.to_string())?;
        Ok(Some(transformed))
    }
}

fn cached_color_profile(encoded: &[u8]) -> Result<Arc<ColorProfile>, String> {
    if !profile_is_cacheable(encoded) {
        return ColorProfile::new_from_slice(encoded)
            .map(Arc::new)
            .map_err(|err| err.to_string());
    }

    {
        let mut cache = lock_profile_cache();
        if let Some(index) = cache
            .iter()
            .position(|entry| entry.encoded.as_ref() == encoded)
        {
            let entry = cache
                .remove(index)
                .expect("cache index came from iteration");
            let profile = Arc::clone(&entry.profile);
            cache.push_back(entry);
            return Ok(profile);
        }
    }

    let profile = Arc::new(ColorProfile::new_from_slice(encoded).map_err(|err| err.to_string())?);
    let mut cache = lock_profile_cache();
    if let Some(entry) = cache.iter().find(|entry| entry.encoded.as_ref() == encoded) {
        return Ok(Arc::clone(&entry.profile));
    }
    if cache.len() == ICC_PROFILE_CACHE_CAPACITY {
        cache.pop_front();
    }
    cache.push_back(CachedIccProfile {
        encoded: Arc::from(encoded),
        profile: Arc::clone(&profile),
        u8_transforms: Vec::new(),
    });
    Ok(profile)
}

/// Cache only exact profile bytes, bound both entry count and profile size,
/// and retain at most one u8 transform per pixel layout in each entry.
fn cached_u8_transform(
    encoded: &[u8],
    source_profile: &ColorProfile,
    layout: Layout,
) -> Result<U8Transform, String> {
    if profile_is_cacheable(encoded) {
        let cache = lock_profile_cache();
        if let Some(transform) = cache
            .iter()
            .find(|entry| entry.encoded.as_ref() == encoded)
            .and_then(|entry| {
                entry
                    .u8_transforms
                    .iter()
                    .find(|(cached_layout, _)| *cached_layout == layout)
                    .map(|(_, transform)| Arc::clone(transform))
            })
        {
            return Ok(transform);
        }
    }

    let transform = source_profile
        .create_in_place_transform_8bit(
            layout,
            target_profile_for_layout(layout),
            transform_options(),
        )
        .map_err(|err| err.to_string())?;
    Ok(cache_u8_transform(encoded, layout, transform))
}

fn cache_u8_transform(encoded: &[u8], layout: Layout, transform: U8Transform) -> U8Transform {
    if !profile_is_cacheable(encoded) {
        return transform;
    }
    let mut cache = lock_profile_cache();
    let Some(entry) = cache
        .iter_mut()
        .find(|entry| entry.encoded.as_ref() == encoded)
    else {
        return transform;
    };
    if let Some((_, cached)) = entry
        .u8_transforms
        .iter()
        .find(|(cached_layout, _)| *cached_layout == layout)
    {
        return Arc::clone(cached);
    }
    entry.u8_transforms.push((layout, Arc::clone(&transform)));
    transform
}

fn transform_u8_out_of_place(
    pixels: &[u8],
    source_profile: &ColorProfile,
    layout: Layout,
) -> Result<Vec<u8>, String> {
    let target_profile = target_profile_for_layout(layout);
    let transform = source_profile
        .create_transform_8bit(layout, target_profile, layout, transform_options())
        .map_err(|err| err.to_string())?;
    let mut transformed = vec![0; pixels.len()];
    transform
        .transform(pixels, &mut transformed)
        .map_err(|err| err.to_string())?;
    Ok(transformed)
}

/// Mirrors moxcms's crate-private `ColorProfile::has_device_to_pcs_lut`.
fn profile_has_device_to_pcs_lut(profile: &ColorProfile) -> bool {
    profile.lut_a_to_b_perceptual.is_some()
        || profile.lut_a_to_b_colorimetric.is_some()
        || profile.lut_a_to_b_saturation.is_some()
}

fn profile_is_cacheable(encoded: &[u8]) -> bool {
    !encoded.is_empty() && encoded.len() <= MAX_CACHEABLE_ICC_PROFILE_BYTES
}

fn lock_profile_cache() -> std::sync::MutexGuard<'static, VecDeque<CachedIccProfile>> {
    ICC_PROFILE_CACHE
        .get_or_init(|| Mutex::new(VecDeque::with_capacity(ICC_PROFILE_CACHE_CAPACITY)))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn transform_options() -> TransformOptions {
    TransformOptions::default()
}

fn target_profile_for_layout(layout: Layout) -> &'static ColorProfile {
    if matches!(layout, Layout::Gray | Layout::GrayAlpha) {
        return SRGB_GRAY_PROFILE.get_or_init(srgb_gray_profile);
    }

    SRGB_PROFILE.get_or_init(ColorProfile::new_srgb)
}

fn srgb_gray_profile() -> ColorProfile {
    let srgb = ColorProfile::new_srgb();
    let mut gray = ColorProfile::new_gray_with_gamma(2.2);
    gray.gray_trc = srgb.red_trc.clone();
    gray.media_white_point = srgb.media_white_point;
    gray
}

fn profile_is_effectively_srgb(profile: &ColorProfile) -> bool {
    match profile.color_space {
        DataColorSpace::Rgb => rgb_profile_is_effectively_srgb(profile),
        DataColorSpace::Gray => gray_profile_is_effectively_srgb(profile),
        _ => false,
    }
}

fn profile_uses_hdr_transfer(profile: &ColorProfile) -> bool {
    if matches!(
        profile
            .cicp
            .as_ref()
            .map(|cicp| cicp.transfer_characteristics),
        Some(TransferCharacteristics::Smpte2084 | TransferCharacteristics::Hlg)
    ) {
        return true;
    }

    match profile.color_space {
        DataColorSpace::Rgb => [
            profile.red_trc.as_ref(),
            profile.green_trc.as_ref(),
            profile.blue_trc.as_ref(),
        ]
        .into_iter()
        .flatten()
        .any(tone_curve_is_hdr_transfer),
        DataColorSpace::Gray => profile
            .gray_trc
            .as_ref()
            .is_some_and(tone_curve_is_hdr_transfer),
        _ => false,
    }
}

fn tone_curve_is_hdr_transfer(candidate: &ToneReprCurve) -> bool {
    tone_curve_matches_transfer(candidate, TransferCharacteristics::Smpte2084)
        || tone_curve_matches_transfer(candidate, TransferCharacteristics::Hlg)
}

fn tone_curve_matches_transfer(
    candidate: &ToneReprCurve,
    transfer: TransferCharacteristics,
) -> bool {
    if let Ok(reference) = ToneReprCurve::try_from(transfer)
        && tone_curve_matches_reference(candidate, &reference, 0.01)
    {
        return true;
    }

    let profile_reference = match transfer {
        TransferCharacteristics::Smpte2084 => ColorProfile::new_bt2020_pq().red_trc,
        TransferCharacteristics::Hlg => ColorProfile::new_bt2020_hlg().red_trc,
        _ => None,
    };

    profile_reference
        .as_ref()
        .is_some_and(|reference| tone_curve_matches_reference(candidate, reference, 0.01))
}

fn rgb_profile_is_effectively_srgb(profile: &ColorProfile) -> bool {
    let srgb = SRGB_PROFILE.get_or_init(ColorProfile::new_srgb);

    profile_colorants_match(profile, srgb)
        && tone_curve_matches_srgb(profile.red_trc.as_ref(), srgb.red_trc.as_ref())
        && tone_curve_matches_srgb(profile.green_trc.as_ref(), srgb.green_trc.as_ref())
        && tone_curve_matches_srgb(profile.blue_trc.as_ref(), srgb.blue_trc.as_ref())
}

fn gray_profile_is_effectively_srgb(profile: &ColorProfile) -> bool {
    let srgb = SRGB_PROFILE.get_or_init(ColorProfile::new_srgb);
    tone_curve_matches_srgb(profile.gray_trc.as_ref(), srgb.red_trc.as_ref())
}

fn profile_colorants_match(profile: &ColorProfile, srgb: &ColorProfile) -> bool {
    xyz_matches(profile.red_colorant, srgb.red_colorant)
        && xyz_matches(profile.green_colorant, srgb.green_colorant)
        && xyz_matches(profile.blue_colorant, srgb.blue_colorant)
}

fn xyz_matches(a: Xyzd, b: Xyzd) -> bool {
    const COLORANT_TOLERANCE: f64 = 0.002;

    (a.x - b.x).abs() <= COLORANT_TOLERANCE
        && (a.y - b.y).abs() <= COLORANT_TOLERANCE
        && (a.z - b.z).abs() <= COLORANT_TOLERANCE
}

fn tone_curve_matches_srgb(
    candidate: Option<&ToneReprCurve>,
    srgb: Option<&ToneReprCurve>,
) -> bool {
    let (Some(candidate), Some(srgb)) = (candidate, srgb) else {
        return false;
    };

    tone_curve_matches_reference(candidate, srgb, 0.002)
}

fn tone_curve_matches_reference(
    candidate: &ToneReprCurve,
    reference: &ToneReprCurve,
    tolerance: f32,
) -> bool {
    if candidate == reference {
        return true;
    }

    let Ok(candidate_evaluator) = candidate.make_linear_evaluator() else {
        return false;
    };
    let Ok(reference_evaluator) = reference.make_linear_evaluator() else {
        return false;
    };

    const SAMPLES: [f32; 17] = [
        0.0, 0.003, 0.01, 0.02, 0.04, 0.06, 0.1, 0.18, 0.25, 0.33, 0.5, 0.66, 0.75, 0.85, 0.9,
        0.96, 1.0,
    ];

    SAMPLES.iter().copied().all(|value| {
        (candidate_evaluator.evaluate_value(value) - reference_evaluator.evaluate_value(value))
            .abs()
            <= tolerance
    })
}

#[cfg(test)]
mod tests {
    use image::{DynamicImage, ImageBuffer};
    use moxcms::{
        ColorProfile, Layout, LutMultidimensionalType, LutWarehouse, Matrix3d, ToneReprCurve,
        TransformOptions, Vector3d,
    };

    use super::{apply_icc_profile_to_srgb, profile_is_effectively_srgb};

    fn identity_a_to_b_lut() -> LutWarehouse {
        let identity_curve = || ToneReprCurve::Lut(vec![0, u16::MAX]);
        LutWarehouse::Multidimensional(LutMultidimensionalType {
            num_input_channels: 3,
            num_output_channels: 3,
            grid_points: [0; 16],
            clut: None,
            a_curves: Vec::new(),
            b_curves: vec![identity_curve(), identity_curve(), identity_curve()],
            m_curves: Vec::new(),
            matrix: Matrix3d::IDENTITY,
            bias: Vector3d::default(),
        })
    }

    /// An RGB profile that converts only through an A2B LUT (no TRC tags),
    /// like calibrated display/scanner profiles.
    fn lut_based_rgb_profile() -> ColorProfile {
        let mut profile = ColorProfile::new_display_p3();
        profile.red_trc = None;
        profile.green_trc = None;
        profile.blue_trc = None;
        profile.lut_a_to_b_perceptual = Some(identity_a_to_b_lut());
        profile
    }

    #[test]
    fn detects_generated_srgb_profile() {
        let srgb = ColorProfile::new_srgb();

        assert!(profile_is_effectively_srgb(&srgb));
    }

    #[test]
    fn leaves_srgb_pixels_unchanged() {
        let srgb_icc = ColorProfile::new_srgb().encode().unwrap();
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(1, 1, vec![128, 64, 32]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(&srgb_icc));

        assert_eq!(transformed.into_rgb8().into_raw(), vec![128, 64, 32]);
    }

    #[test]
    fn detects_quantized_srgb_colorants() {
        let mut srgb = ColorProfile::new_srgb();
        srgb.red_colorant.x += 0.0005;
        srgb.green_colorant.y -= 0.0005;
        srgb.blue_colorant.z += 0.0005;

        assert!(profile_is_effectively_srgb(&srgb));
    }

    #[test]
    fn skips_hdr_pq_profiles_without_tone_mapping() {
        let display_p3_pq_icc = ColorProfile::new_display_p3_pq().encode().unwrap();
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(1, 1, vec![200, 200, 200]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(&display_p3_pq_icc));

        assert_eq!(transformed.into_rgb8().into_raw(), vec![200, 200, 200]);
    }

    #[test]
    fn skips_hdr_pq_profiles_without_cicp_tag() {
        let mut display_p3_pq = ColorProfile::new_display_p3_pq();
        display_p3_pq.cicp = None;
        let display_p3_pq_icc = display_p3_pq.encode().unwrap();
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(1, 1, vec![200, 200, 200]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(&display_p3_pq_icc));

        assert_eq!(transformed.into_rgb8().into_raw(), vec![200, 200, 200]);
    }

    #[test]
    fn skips_hdr_hlg_profiles_without_cicp_tag() {
        let mut bt2020_hlg = ColorProfile::new_bt2020_hlg();
        bt2020_hlg.cicp = None;
        let bt2020_hlg_icc = bt2020_hlg.encode().unwrap();
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(1, 1, vec![200, 200, 200]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(&bt2020_hlg_icc));

        assert_eq!(transformed.into_rgb8().into_raw(), vec![200, 200, 200]);
    }

    #[test]
    fn falls_back_to_original_pixels_for_invalid_icc_profile() {
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(1, 1, vec![128, 64, 32]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(b"not an icc profile"));

        assert_eq!(transformed.into_rgb8().into_raw(), vec![128, 64, 32]);
    }

    #[test]
    fn converts_gray_gamma_luma8_to_srgb() {
        let gray_icc = ColorProfile::new_gray_with_gamma(1.8).encode().unwrap();
        let image = DynamicImage::ImageLuma8(ImageBuffer::from_raw(1, 1, vec![128]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(&gray_icc));
        let DynamicImage::ImageLuma8(buffer) = transformed else {
            panic!("expected Luma8 output");
        };

        assert!(
            buffer.into_raw()[0] > 128,
            "expected gamma 1.8 gray to brighten when re-encoded as sRGB"
        );
    }

    #[test]
    fn converts_gray_gamma_luma16_to_srgb() {
        let gray_icc = ColorProfile::new_gray_with_gamma(1.8).encode().unwrap();
        let image = DynamicImage::ImageLuma16(ImageBuffer::from_raw(1, 1, vec![32768u16]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(&gray_icc));
        let DynamicImage::ImageLuma16(buffer) = transformed else {
            panic!("expected Luma16 output");
        };

        assert!(
            buffer.into_raw()[0] > 32768,
            "expected gamma 1.8 gray to brighten when re-encoded as sRGB"
        );
    }

    #[test]
    fn converts_display_p3_rgb8_to_srgb() {
        let display_p3_icc = ColorProfile::new_display_p3().encode().unwrap();
        let image = DynamicImage::ImageRgb8(ImageBuffer::from_raw(1, 1, vec![128, 0, 0]).unwrap());

        let transformed = apply_icc_profile_to_srgb(image, Some(&display_p3_icc));
        let raw = transformed.into_rgb8().into_raw();

        assert!(raw[0] > 128, "expected red channel to move into sRGB");
        assert_eq!(raw[1], 0);
        assert_eq!(raw[2], 0);
    }

    #[test]
    fn in_place_rgb8_transform_matches_previous_out_of_place_result() {
        let display_p3 = ColorProfile::new_display_p3();
        let display_p3_icc = display_p3.encode().unwrap();
        let parsed_display_p3 = ColorProfile::new_from_slice(&display_p3_icc).unwrap();
        let pixels = vec![0, 32, 64, 96, 128, 160, 192, 224, 255, 17, 91, 203];
        let mut expected = vec![0; pixels.len()];
        parsed_display_p3
            .create_transform_8bit(
                Layout::Rgb,
                &ColorProfile::new_srgb(),
                Layout::Rgb,
                TransformOptions::default(),
            )
            .unwrap()
            .transform(&pixels, &mut expected)
            .unwrap();
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(4, 1, pixels).expect("valid RGB image"));

        let actual = apply_icc_profile_to_srgb(image, Some(&display_p3_icc))
            .into_rgb8()
            .into_raw();

        assert_eq!(actual, expected);
    }

    /// A profile with matrix/TRC AND A2B LUT tags must be converted via the
    /// LUT (ICC precedence), even though the in-place constructor accepts it.
    #[test]
    fn profile_with_matrix_and_lut_tags_is_transformed_via_the_lut() {
        let mut profile = ColorProfile::new_display_p3();
        profile.lut_a_to_b_perceptual = Some(identity_a_to_b_lut());
        let icc = profile.encode().unwrap();
        let parsed = ColorProfile::new_from_slice(&icc).unwrap();
        let pixels = vec![0, 32, 64, 96, 128, 160, 192, 224, 255, 17, 91, 203];

        let in_place = parsed
            .create_in_place_transform_8bit(
                Layout::Rgb,
                &ColorProfile::new_srgb(),
                TransformOptions::default(),
            )
            .expect("the in-place constructor accepts matrix-shaper profiles with LUT tags");
        let mut matrix_result = pixels.clone();
        in_place.transform(&mut matrix_result).unwrap();

        let mut expected = vec![0; pixels.len()];
        parsed
            .create_transform_8bit(
                Layout::Rgb,
                &ColorProfile::new_srgb(),
                Layout::Rgb,
                TransformOptions::default(),
            )
            .unwrap()
            .transform(&pixels, &mut expected)
            .unwrap();
        assert_ne!(
            expected, matrix_result,
            "the LUT and matrix paths must disagree for this test to discriminate"
        );

        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(4, 1, pixels).expect("valid RGB image"));

        let actual = apply_icc_profile_to_srgb(image, Some(&icc))
            .into_rgb8()
            .into_raw();

        assert_eq!(actual, expected);
    }

    /// A colorimetric-only A2B LUT (no A2B0) is unusable under moxcms's
    /// default Perceptual intent; the matrix path must still convert.
    #[test]
    fn profile_with_unusable_lut_intent_falls_back_to_the_matrix_transform() {
        let mut profile = ColorProfile::new_display_p3();
        profile.lut_a_to_b_colorimetric = Some(identity_a_to_b_lut());
        let icc = profile.encode().unwrap();
        let parsed = ColorProfile::new_from_slice(&icc).unwrap();
        let pixels = vec![0, 32, 64, 96, 128, 160, 192, 224, 255, 17, 91, 203];
        assert!(
            parsed
                .create_transform_8bit(
                    Layout::Rgb,
                    &ColorProfile::new_srgb(),
                    Layout::Rgb,
                    TransformOptions::default(),
                )
                .is_err(),
            "the out-of-place transform must fail for this test to cover the fallback"
        );
        let mut expected = pixels.clone();
        parsed
            .create_in_place_transform_8bit(
                Layout::Rgb,
                &ColorProfile::new_srgb(),
                TransformOptions::default(),
            )
            .unwrap()
            .transform(&mut expected)
            .unwrap();
        assert_ne!(expected, pixels);
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(4, 1, pixels).expect("valid RGB image"));

        let actual = apply_icc_profile_to_srgb(image, Some(&icc))
            .into_rgb8()
            .into_raw();

        assert_eq!(actual, expected);
    }

    #[test]
    fn lut_profile_rgb8_falls_back_to_out_of_place_transform() {
        let lut_icc = lut_based_rgb_profile().encode().unwrap();
        let parsed = ColorProfile::new_from_slice(&lut_icc).unwrap();
        assert!(
            parsed
                .create_in_place_transform_8bit(
                    Layout::Rgb,
                    &ColorProfile::new_srgb(),
                    TransformOptions::default(),
                )
                .is_err(),
            "profile must be rejected by the in-place executor for this test to cover the fallback"
        );
        let pixels = vec![0, 32, 64, 96, 128, 160, 192, 224, 255, 17, 91, 203];
        let mut expected = vec![0; pixels.len()];
        parsed
            .create_transform_8bit(
                Layout::Rgb,
                &ColorProfile::new_srgb(),
                Layout::Rgb,
                TransformOptions::default(),
            )
            .unwrap()
            .transform(&pixels, &mut expected)
            .unwrap();
        assert_ne!(
            expected, pixels,
            "the LUT transform must actually change pixel values"
        );
        let image =
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(4, 1, pixels).expect("valid RGB image"));

        let actual = apply_icc_profile_to_srgb(image, Some(&lut_icc))
            .into_rgb8()
            .into_raw();

        assert_eq!(actual, expected);
    }

    #[test]
    fn rgba16_transform_matches_previous_out_of_place_result() {
        let display_p3 = ColorProfile::new_display_p3();
        let display_p3_icc = display_p3.encode().unwrap();
        let parsed_display_p3 = ColorProfile::new_from_slice(&display_p3_icc).unwrap();
        let pixels = vec![0, 8192, 32768, 1111, 49152, 65535, 12345, 54321];
        let mut expected = vec![0; pixels.len()];
        parsed_display_p3
            .create_transform_16bit(
                Layout::Rgba,
                &ColorProfile::new_srgb(),
                Layout::Rgba,
                TransformOptions::default(),
            )
            .unwrap()
            .transform(&pixels, &mut expected)
            .unwrap();
        let image = DynamicImage::ImageRgba16(
            ImageBuffer::from_raw(2, 1, pixels).expect("valid RGBA image"),
        );

        let actual = apply_icc_profile_to_srgb(image, Some(&display_p3_icc));
        let DynamicImage::ImageRgba16(actual) = actual else {
            panic!("expected RGBA16 image");
        };

        assert_eq!(actual.into_raw(), expected);
    }

    #[test]
    fn converts_display_p3_rgba16_and_preserves_alpha() {
        let display_p3_icc = ColorProfile::new_display_p3().encode().unwrap();
        let image = DynamicImage::ImageRgba16(
            ImageBuffer::from_raw(1, 1, vec![32768, 0, 0, 12345]).unwrap(),
        );

        let transformed = apply_icc_profile_to_srgb(image, Some(&display_p3_icc));
        let DynamicImage::ImageRgba16(buffer) = transformed else {
            panic!("expected Rgba16 output");
        };
        let raw = buffer.into_raw();

        assert!(raw[0] > 32768, "expected red channel to move into sRGB");
        assert_eq!(raw[1], 0);
        assert_eq!(raw[2], 0);
        assert_eq!(raw[3], 12345);
    }
}
