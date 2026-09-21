use super::{OpResult, image::ImageU8};
use rayon::prelude::*;

#[derive(Debug, Clone, Copy)]
pub(crate) struct ProjectiveMap {
    pub coefficients: [f64; 9],
}

impl ProjectiveMap {
    pub fn from_unit_quad(p: [(f64, f64); 4]) -> OpResult<Self> {
        if p.iter().any(|(x, y)| !x.is_finite() || !y.is_finite()) {
            return Err("non-finite projective coordinates".to_owned());
        }
        let origin = p[0];
        let scale = p
            .iter()
            .map(|p| (p.0 - origin.0).hypot(p.1 - origin.1))
            .fold(0.0, f64::max);
        if scale <= f64::MIN_POSITIVE {
            return Err("collapsed projective coordinates".to_owned());
        }
        let q = p.map(|p| ((p.0 - origin.0) / scale, (p.1 - origin.1) / scale));
        let dx1 = q[1].0 - q[2].0;
        let dx2 = q[3].0 - q[2].0;
        let dy1 = q[1].1 - q[2].1;
        let dy2 = q[3].1 - q[2].1;
        let dx = q[0].0 - q[1].0 + q[2].0 - q[3].0;
        let dy = q[0].1 - q[1].1 + q[2].1 - q[3].1;
        let determinant = dx1 * dy2 - dx2 * dy1;
        if determinant.abs() < 1e-12 {
            return Err("ill-conditioned projective coordinates".to_owned());
        }
        let g = (dx * dy2 - dx2 * dy) / determinant;
        let h = (dx1 * dy - dx * dy1) / determinant;
        let denominators = [1.0, 1.0 + g, 1.0 + g + h, 1.0 + h];
        let largest = denominators.iter().copied().fold(0.0, f64::max);
        if denominators
            .iter()
            .any(|d| !d.is_finite() || *d < largest * 1e-6)
        {
            return Err("projective pole crosses or approaches the page".to_owned());
        }
        let coefficients = [
            p[1].0 * (1.0 + g) - p[0].0,
            p[3].0 * (1.0 + h) - p[0].0,
            p[0].0,
            p[1].1 * (1.0 + g) - p[0].1,
            p[3].1 * (1.0 + h) - p[0].1,
            p[0].1,
            g,
            h,
            1.0,
        ];
        Ok(Self { coefficients })
    }

    pub fn at(self, u: f64, v: f64) -> (f64, f64) {
        let h = self.coefficients;
        let d = h[6] * u + h[7] * v + 1.0;
        (
            (h[0] * u + h[1] * v + h[2]) / d,
            (h[3] * u + h[4] * v + h[5]) / d,
        )
    }

    fn footprint(self, u: f64, v: f64, width: i32, height: i32) -> (f64, f64) {
        let h = self.coefficients;
        let (x, y) = self.at(u, v);
        let d = h[6] * u + h[7] * v + 1.0;
        (
            ((h[0] - h[6] * x).hypot(h[3] - h[6] * y) / d / width as f64).abs(),
            ((h[1] - h[7] * x).hypot(h[4] - h[7] * y) / d / height as f64).abs(),
        )
    }
}

pub(crate) struct WarpedImage {
    pub image: ImageU8,
    pub valid: Option<Vec<u8>>,
}

fn buffer(length: usize, value: u8) -> OpResult<Vec<u8>> {
    let mut data = Vec::new();
    data.try_reserve_exact(length)
        .map_err(|error| format!("image allocation failed: {error}"))?;
    data.resize(length, value);
    Ok(data)
}

fn reduce(source: &ImageU8) -> OpResult<ImageU8> {
    let width = (source.width / 2).max(1);
    let height = (source.height / 2).max(1);
    super::resize_u8(source, width, height, super::Interp::Area)
}

fn sample(source: &ImageU8, x: f64, y: f64, original: &ImageU8) -> [f64; 3] {
    let x = (x * source.width as f64 / original.width as f64 - 0.5)
        .clamp(0.0, source.width as f64 - 1.0);
    let y = (y * source.height as f64 / original.height as f64 - 0.5)
        .clamp(0.0, source.height as f64 - 1.0);
    let x0 = x.floor() as usize;
    let y0 = y.floor() as usize;
    let x1 = (x0 + 1).min(source.width as usize - 1);
    let y1 = (y0 + 1).min(source.height as usize - 1);
    let fx = x - x0 as f64;
    let fy = y - y0 as f64;
    std::array::from_fn(|c| {
        let a = source.data[(y0 * source.width as usize + x0) * 3 + c] as f64;
        let b = source.data[(y0 * source.width as usize + x1) * 3 + c] as f64;
        let d = source.data[(y1 * source.width as usize + x0) * 3 + c] as f64;
        let e = source.data[(y1 * source.width as usize + x1) * 3 + c] as f64;
        (a + (b - a) * fx) * (1.0 - fy) + (d + (e - d) * fx) * fy
    })
}

pub(crate) fn warp_document(
    source: &ImageU8,
    map: ProjectiveMap,
    width: i32,
    height: i32,
) -> OpResult<WarpedImage> {
    if source.width <= 0 || source.height <= 0 || source.channels != 3 || width <= 0 || height <= 0
    {
        return Err("invalid document warp geometry".to_owned());
    }
    let source_len = (source.width as usize)
        .checked_mul(source.height as usize)
        .and_then(|n| n.checked_mul(3));
    if source_len != Some(source.data.len()) {
        return Err("invalid document warp source buffer".to_owned());
    }
    let pixels = (width as usize)
        .checked_mul(height as usize)
        .ok_or("document size overflow")?;
    let length = pixels.checked_mul(3).ok_or("document size overflow")?;
    let mut data = buffer(length, 255)?;
    let outside = |(x, y): (f64, f64)| {
        x < 0.0 || y < 0.0 || x > source.width as f64 || y > source.height as f64
    };
    let has_missing = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        .iter()
        .any(|&(u, v)| outside(map.at(u, v)));
    let mut validity = if has_missing {
        Some(buffer(pixels, 255)?)
    } else {
        None
    };
    let mut max_footprint = 1.0f64;
    for y in 0..=4 {
        for x in 0..=4 {
            let (a, b) = map.footprint(x as f64 / 4.0, y as f64 / 4.0, width, height);
            max_footprint = max_footprint.max(a).max(b);
        }
    }
    if !max_footprint.is_finite() {
        return Err("non-finite projective footprint".to_owned());
    }
    let mut levels = Vec::new();
    let mut factor = 1.0;
    while factor * 4.0 < max_footprint {
        let previous = levels.last().unwrap_or(source);
        if previous.width == 1 && previous.height == 1 {
            break;
        }
        levels.push(reduce(previous)?);
        factor *= 2.0;
    }
    let render_row = |row: usize, output: &mut [u8], mut valid: Option<&mut [u8]>| {
        for (column, pixel) in output.as_chunks_mut::<3>().0.iter_mut().enumerate() {
            let u = (column as f64 + 0.5) / width as f64;
            let v = (row as f64 + 0.5) / height as f64;
            let (a, b) = map.footprint(u, v, width, height);
            let level_index = ((a.max(b) / 2.0).log2().floor().max(0.0) as usize).min(levels.len());
            let selected = if level_index == 0 {
                source
            } else {
                &levels[level_index - 1]
            };
            let scale = (source.width as f64 / selected.width as f64)
                .max(source.height as f64 / selected.height as f64);
            let nx = (a / scale - 1e-9).ceil().clamp(1.0, 4.0) as usize;
            let ny = (b / scale - 1e-9).ceil().clamp(1.0, 4.0) as usize;
            let mut sum = [0.0; 3];
            let mut complete = true;
            for iy in 0..ny {
                for ix in 0..nx {
                    let p = map.at(
                        (column as f64 + (ix as f64 + 0.5) / nx as f64) / width as f64,
                        (row as f64 + (iy as f64 + 0.5) / ny as f64) / height as f64,
                    );
                    let value = if outside(p) {
                        complete = false;
                        [255.0; 3]
                    } else {
                        sample(selected, p.0, p.1, source)
                    };
                    for c in 0..3 {
                        sum[c] += value[c];
                    }
                }
            }
            for c in 0..3 {
                pixel[c] = (sum[c] / (nx * ny) as f64).round().clamp(0.0, 255.0) as u8;
            }
            if let Some(valid) = valid.as_deref_mut() {
                valid[column] = if complete { 255 } else { 0 };
            }
        }
    };
    let stride = width as usize * 3;
    if pixels >= 262_144 {
        if let Some(valid) = validity.as_mut() {
            data.par_chunks_mut(stride)
                .zip(valid.par_chunks_mut(width as usize))
                .enumerate()
                .for_each(|(row, (dst, valid))| render_row(row, dst, Some(valid)));
        } else {
            data.par_chunks_mut(stride)
                .enumerate()
                .for_each(|(row, dst)| render_row(row, dst, None));
        }
    } else {
        for (row, dst) in data.chunks_mut(stride).enumerate() {
            let valid = validity
                .as_mut()
                .map(|v| &mut v[row * width as usize..(row + 1) * width as usize]);
            render_row(row, dst, valid);
        }
    }
    Ok(WarpedImage {
        image: ImageU8::new(width, height, 3, data)?,
        valid: validity,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checkerboard_reduction_is_filtered() -> OpResult<()> {
        let pixels = (0..64 * 64)
            .flat_map(|i| [if (i / 64 + i % 64) % 2 == 0 { 0 } else { 255 }; 3])
            .collect();
        let source = ImageU8::new(64, 64, 3, pixels)?;
        let map =
            ProjectiveMap::from_unit_quad([(0.0, 0.0), (64.0, 0.0), (64.0, 64.0), (0.0, 64.0)])?;
        let output = warp_document(&source, map, 7, 9)?;
        assert!(output.image.data.iter().all(|v| (125..=130).contains(v)));
        Ok(())
    }

    #[test]
    fn unavailable_source_is_white_and_excluded_from_statistics() -> OpResult<()> {
        let source = ImageU8::new(20, 20, 3, vec![50; 1200])?;
        let map =
            ProjectiveMap::from_unit_quad([(-2.0, 0.0), (20.0, 0.0), (20.0, 20.0), (-2.0, 20.0)])?;
        let output = warp_document(&source, map, 22, 20)?;
        assert_eq!(&output.image.data[0..6], &[255; 6]);
        let valid = output.valid.ok_or("missing validity")?;
        assert_eq!(&valid[..3], &[0, 0, 255]);
        assert_eq!(&output.image.data[6..9], &[50; 3]);
        Ok(())
    }

    #[test]
    fn independently_projected_landmarks_match_mapping() -> OpResult<()> {
        let project = |u: f64, v: f64| {
            (
                (120.0 * u + 24.0 * v + 17.0) / (0.3 * u + 0.2 * v + 1.0),
                (13.0 * u + 180.0 * v + 29.0) / (0.3 * u + 0.2 * v + 1.0),
            )
        };
        let map = ProjectiveMap::from_unit_quad([
            project(0.0, 0.0),
            project(1.0, 0.0),
            project(1.0, 1.0),
            project(0.0, 1.0),
        ])?;
        for (u, v) in [(0.0, 0.0), (0.17, 0.82), (0.5, 0.5), (1.0, 1.0)] {
            let expected = project(u, v);
            let actual = map.at(u, v);
            assert!((actual.0 - expected.0).hypot(actual.1 - expected.1) < 1e-10);
        }
        Ok(())
    }
}
