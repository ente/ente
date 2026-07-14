use image::{DynamicImage, ImageBuffer, Pixel};
use moxcms::{
    ColorProfile, DataColorSpace, Layout, ToneReprCurve, TransferCharacteristics, TransformOptions,
    Xyzd,
};

pub(crate) fn apply_icc_profile_to_srgb(
    image: DynamicImage,
    icc_profile: Option<&[u8]>,
) -> DynamicImage {
    let Some(icc_profile) = icc_profile.filter(|profile| !profile.is_empty()) else {
        return image;
    };

    let source_profile = match ColorProfile::new_from_slice(icc_profile) {
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

    match apply_profile_to_image(image, &source_profile) {
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
) -> Result<DynamicImage, (DynamicImage, String)> {
    use DynamicImage::*;
    use Layout::{Gray, GrayAlpha, Rgb, Rgba};

    match image {
        ImageLuma8(buffer) => transform_buffer(buffer, source_profile, Gray, ImageLuma8),
        ImageLumaA8(buffer) => transform_buffer(buffer, source_profile, GrayAlpha, ImageLumaA8),
        ImageRgb8(buffer) => transform_buffer(buffer, source_profile, Rgb, ImageRgb8),
        ImageRgba8(buffer) => transform_buffer(buffer, source_profile, Rgba, ImageRgba8),
        ImageLuma16(buffer) => transform_buffer(buffer, source_profile, Gray, ImageLuma16),
        ImageLumaA16(buffer) => transform_buffer(buffer, source_profile, GrayAlpha, ImageLumaA16),
        ImageRgb16(buffer) => transform_buffer(buffer, source_profile, Rgb, ImageRgb16),
        ImageRgba16(buffer) => transform_buffer(buffer, source_profile, Rgba, ImageRgba16),
        ImageRgb32F(buffer) => transform_buffer(buffer, source_profile, Rgb, ImageRgb32F),
        ImageRgba32F(buffer) => transform_buffer(buffer, source_profile, Rgba, ImageRgba32F),
        other => Ok(other),
    }
}

fn transform_buffer<P>(
    buffer: ImageBuffer<P, Vec<P::Subpixel>>,
    source_profile: &ColorProfile,
    layout: Layout,
    into_dynamic: fn(ImageBuffer<P, Vec<P::Subpixel>>) -> DynamicImage,
) -> Result<DynamicImage, (DynamicImage, String)>
where
    P: Pixel,
    P::Subpixel: TransformSubpixel,
{
    let (width, height) = buffer.dimensions();
    match P::Subpixel::transform_to_srgb(buffer.as_raw(), source_profile, layout) {
        Ok(data) => Ok(into_dynamic(
            ImageBuffer::from_raw(width, height, data)
                .expect("transformed buffer length should match source dimensions"),
        )),
        Err(err) => Err((into_dynamic(buffer), err)),
    }
}

/// Subpixel types for which moxcms can transform pixel buffers to sRGB.
trait TransformSubpixel: Copy {
    fn transform_to_srgb(
        pixels: &[Self],
        source_profile: &ColorProfile,
        layout: Layout,
    ) -> Result<Vec<Self>, String>;
}

impl TransformSubpixel for u8 {
    fn transform_to_srgb(
        pixels: &[Self],
        source_profile: &ColorProfile,
        layout: Layout,
    ) -> Result<Vec<Self>, String> {
        let target_profile = target_profile_for_layout(layout);
        let transform = source_profile
            .create_transform_8bit(layout, &target_profile, layout, transform_options())
            .map_err(|err| err.to_string())?;
        let mut transformed = vec![0; pixels.len()];
        transform
            .transform(pixels, &mut transformed)
            .map_err(|err| err.to_string())?;
        Ok(transformed)
    }
}

impl TransformSubpixel for u16 {
    fn transform_to_srgb(
        pixels: &[Self],
        source_profile: &ColorProfile,
        layout: Layout,
    ) -> Result<Vec<Self>, String> {
        let target_profile = target_profile_for_layout(layout);
        let transform = source_profile
            .create_transform_16bit(layout, &target_profile, layout, transform_options())
            .map_err(|err| err.to_string())?;
        let mut transformed = vec![0; pixels.len()];
        transform
            .transform(pixels, &mut transformed)
            .map_err(|err| err.to_string())?;
        Ok(transformed)
    }
}

impl TransformSubpixel for f32 {
    fn transform_to_srgb(
        pixels: &[Self],
        source_profile: &ColorProfile,
        layout: Layout,
    ) -> Result<Vec<Self>, String> {
        let target_profile = target_profile_for_layout(layout);
        let transform = source_profile
            .create_transform_f32(layout, &target_profile, layout, transform_options())
            .map_err(|err| err.to_string())?;
        let mut transformed = vec![0.0; pixels.len()];
        transform
            .transform(pixels, &mut transformed)
            .map_err(|err| err.to_string())?;
        Ok(transformed)
    }
}

fn transform_options() -> TransformOptions {
    TransformOptions::default()
}

fn target_profile_for_layout(layout: Layout) -> ColorProfile {
    if matches!(layout, Layout::Gray | Layout::GrayAlpha) {
        return srgb_gray_profile();
    }

    ColorProfile::new_srgb()
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
    let srgb = ColorProfile::new_srgb();

    profile_colorants_match(profile, &srgb)
        && tone_curve_matches_srgb(profile.red_trc.as_ref(), srgb.red_trc.as_ref())
        && tone_curve_matches_srgb(profile.green_trc.as_ref(), srgb.green_trc.as_ref())
        && tone_curve_matches_srgb(profile.blue_trc.as_ref(), srgb.blue_trc.as_ref())
}

fn gray_profile_is_effectively_srgb(profile: &ColorProfile) -> bool {
    let srgb = ColorProfile::new_srgb();
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
    use moxcms::ColorProfile;

    use super::{apply_icc_profile_to_srgb, profile_is_effectively_srgb};

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
