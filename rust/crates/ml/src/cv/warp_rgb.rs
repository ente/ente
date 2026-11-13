use image::RgbImage;
use imageproc::geometric_transformations::Projection;
use rayon::prelude::*;

pub(super) fn warp(source: &RgbImage, projection: Projection, width: u32, height: u32) -> RgbImage {
    let inverse = projection.invert();
    let mut output = RgbImage::new(width, height);
    let pixels = source.as_raw();
    let stride = source.width() as usize * 3;
    output
        .as_mut()
        .par_chunks_mut(width as usize * 3)
        .enumerate()
        .for_each(|(y, row)| {
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
                let top = &pixels[offset..offset + 6];
                let bottom = &pixels[offset + stride..offset + stride + 6];
                let upper: [f32; 3] = std::array::from_fn(|c| {
                    ((1.0 - right_weight) * f32::from(top[c])
                        + right_weight * f32::from(top[c + 3]))
                    .trunc()
                });
                let lower: [f32; 3] = std::array::from_fn(|c| {
                    ((1.0 - right_weight) * f32::from(bottom[c])
                        + right_weight * f32::from(bottom[c + 3]))
                    .trunc()
                });
                let blended: [u8; 3] = std::array::from_fn(|c| {
                    ((1.0 - bottom_weight) * upper[c] + bottom_weight * lower[c]) as u8
                });
                *pixel = blended;
            }
        });
    output
}

#[cfg(test)]
mod tests {
    use image::Rgb;
    use imageproc::geometric_transformations::{Border, Interpolation, warp_into};

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
            let inverse = projection.invert();
            let actual = warp(&source, projection, 113, 97);
            let mut expected = RgbImage::new(113, 97);
            warp_into(
                &source,
                projection,
                Interpolation::Bilinear,
                Border::Constant(Rgb([0, 0, 0])),
                &mut expected,
            );
            // The older imageproc reference returned black when any of the
            // four bilinear source pixels fell outside the image.
            for (x, y, pixel) in expected.enumerate_pixels_mut() {
                let (source_x, source_y) = inverse * (x as f32, y as f32);
                let left = source_x.floor();
                let top = source_y.floor();
                if !(left >= 0.0
                    && left + 1.0 < source.width() as f32
                    && top >= 0.0
                    && top + 1.0 < source.height() as f32)
                {
                    *pixel = Rgb([0, 0, 0]);
                }
            }
            assert_eq!(actual, expected, "case {index}");
        }
    }
}
