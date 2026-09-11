use image::RgbImage;
use imageproc::geometric_transformations::Projection;
use wide::f32x4;

pub(super) fn warp(source: &RgbImage, projection: Projection, width: u32, height: u32) -> RgbImage {
    let inverse = projection.invert();
    let mut output = RgbImage::new(width, height);
    let pixels = source.as_raw();
    let stride = source.width() as usize * 3;
    let load = |offset: usize| {
        f32x4::from([
            f32::from(pixels[offset]),
            f32::from(pixels[offset + 1]),
            f32::from(pixels[offset + 2]),
            0.0,
        ])
    };
    for (y, row) in output
        .as_mut()
        .chunks_exact_mut(width as usize * 3)
        .enumerate()
    {
        for (x, pixel) in row.as_chunks_mut::<3>().0.iter_mut().enumerate() {
            let (px, py) = inverse * (x as f32, y as f32);
            let left = px.floor();
            let top = py.floor();
            if !(left >= 0.0
                && left + 1.0 < source.width() as f32
                && top >= 0.0
                && top + 1.0 < source.height() as f32)
            {
                continue;
            }
            let right_weight = px - left;
            let bottom_weight = py - top;
            let offset = top as usize * stride + left as usize * 3;
            let right = f32x4::splat(right_weight);
            let left = f32x4::splat(1.0 - right_weight);
            let upper =
                f32x4::from_i32x4((left * load(offset) + right * load(offset + 3)).trunc_int());
            let lower = f32x4::from_i32x4(
                (left * load(offset + stride) + right * load(offset + stride + 3)).trunc_int(),
            );
            let blended = (f32x4::splat(1.0 - bottom_weight) * upper
                + f32x4::splat(bottom_weight) * lower)
                .trunc_int()
                .to_array();
            for channel in 0..3 {
                pixel[channel] = blended[channel] as u8;
            }
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use image::Rgb;
    use imageproc::geometric_transformations::{Interpolation, warp_into};

    use super::*;

    #[test]
    fn matches_reference_pixels_for_projective_and_border_cases() {
        let source = RgbImage::from_fn(83, 71, |x, y| {
            Rgb([
                (x * 17 + y * 3) as u8,
                (x * 11 + y * 31) as u8,
                (x * 7 + y * 19) as u8,
            ])
        });
        for index in 0..200 {
            let shift = index as f32 * 0.173 - 13.0;
            let projection = Projection::from_matrix([
                0.78,
                0.13,
                shift,
                -0.07,
                1.14,
                shift / 2.0,
                index as f32 * 0.00001,
                -0.0004,
                1.0,
            ])
            .expect("valid projection");
            let actual = warp(&source, projection, 113, 97);
            let mut expected = RgbImage::new(113, 97);
            warp_into(
                &source,
                &projection,
                Interpolation::Bilinear,
                Rgb([0, 0, 0]),
                &mut expected,
            );
            assert_eq!(actual, expected, "case {index}");
        }
    }
}
