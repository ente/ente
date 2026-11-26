use crate::{Dimensions, ImageResult, bounded::too_large};

pub(crate) struct Downsampler {
    source: Dimensions,
    target: Dimensions,
    rgb: Vec<u8>,
    column_sums: Vec<u32>,
    taps: Taps,
    mean: AreaMean,
    completed_rows: u32,
}

#[derive(Default)]
struct BufferLengths {
    rgb: u64,
    column_sums: u64,
    taps: TapLayout,
}

impl BufferLengths {
    fn new(source: &Dimensions, target: &Dimensions) -> Self {
        let rgb = u64::from(target.width) * u64::from(target.height) * 3;
        if source == target {
            return Self {
                rgb,
                ..Self::default()
            };
        }
        Self {
            rgb,
            column_sums: u64::from(source.width) * 3 * 2,
            taps: TapLayout::new(source.width, target.width),
        }
    }
}

#[derive(Default)]
struct TapLayout {
    target_width: u64,
    taps_per_column: u64,
}

impl TapLayout {
    fn new(source_width: u32, target_width: u32) -> Self {
        Self {
            target_width: u64::from(target_width),
            taps_per_column: u64::from(source_width.div_ceil(target_width) + 1)
                .min(u64::from(source_width)),
        }
    }

    fn weight_count(&self) -> u64 {
        self.target_width * self.taps_per_column
    }
}

#[derive(Default)]
struct Taps {
    count: usize,
    starts: Vec<u32>,
    weights: Vec<u32>,
}

impl Taps {
    fn new(source_width: u32, layout: TapLayout) -> ImageResult<Self> {
        let mut starts = reserved(layout.target_width)?;
        let mut weights = reserved(layout.weight_count())?;
        let source_width = u64::from(source_width);
        let target_width = layout.target_width;
        let count = layout.taps_per_column;
        for target_x in 0..target_width {
            let begin = target_x * source_width;
            let end = begin + source_width;
            let start = (begin / target_width).min(source_width - count);
            starts.push(start as u32);
            weights.extend((start..start + count).map(|x| {
                let pixel_begin = x * target_width;
                let pixel_end = pixel_begin + target_width;
                end.min(pixel_end).saturating_sub(begin.max(pixel_begin)) as u32
            }));
        }
        Ok(Self {
            count: count as usize,
            starts,
            weights,
        })
    }

    fn write_means(&self, columns: &[[u32; 3]], mean: &AreaMean, output: &mut [[u8; 3]]) {
        match self.count {
            2 => self.write_means_with(2, columns, mean, output),
            3 => self.write_means_with(3, columns, mean, output),
            4 => self.write_means_with(4, columns, mean, output),
            count => self.write_means_with(count, columns, mean, output),
        }
    }

    #[inline(always)]
    fn write_means_with(
        &self,
        count: usize,
        columns: &[[u32; 3]],
        mean: &AreaMean,
        output: &mut [[u8; 3]],
    ) {
        let weights = self.weights.chunks_exact(count);
        for ((&start, weights), pixel) in self.starts.iter().zip(weights).zip(output) {
            let mut sum = [0u64; 3];
            for (column, &weight) in columns[start as usize..][..count].iter().zip(weights) {
                for (total, &value) in sum.iter_mut().zip(column) {
                    *total += u64::from(value) * u64::from(weight);
                }
            }
            *pixel = sum.map(|channel| mean.of(channel));
        }
    }
}

struct AreaMean {
    area: u64,
    multiplier: u64,
    shift: u32,
}

impl AreaMean {
    fn new(source: &Dimensions) -> Self {
        let area = u64::from(source.width) * u64::from(source.height);
        let divisor = 2 * area;
        let divisor_bits = u64::BITS - (divisor - 1).leading_zeros();
        let shift = (2 * divisor_bits + 8).saturating_sub(64);
        Self {
            area,
            multiplier: ((1u128 << (64 + shift)) / u128::from(divisor) + 1) as u64,
            shift,
        }
    }

    fn of(&self, sum: u64) -> u8 {
        let numerator = u128::from(2 * sum + self.area);
        (((numerator * u128::from(self.multiplier)) >> 64) as u64 >> self.shift) as u8
    }
}

impl Downsampler {
    pub(crate) fn bytes(source: &Dimensions, target: &Dimensions) -> u64 {
        let lengths = BufferLengths::new(source, target);
        lengths.rgb.saturating_add(
            lengths
                .column_sums
                .saturating_add(lengths.taps.target_width)
                .saturating_add(lengths.taps.weight_count())
                .saturating_mul(size_of::<u32>() as u64),
        )
    }

    pub(crate) fn new(source: Dimensions, target: Dimensions) -> ImageResult<Self> {
        if u64::from(source.height) * u64::from(u8::MAX) > u64::from(u32::MAX) {
            return Err(too_large());
        }
        let lengths = BufferLengths::new(&source, &target);
        Ok(Self {
            rgb: reserved(lengths.rgb)?,
            column_sums: zeroed(lengths.column_sums)?,
            taps: if source == target {
                Taps::default()
            } else {
                Taps::new(source.width, lengths.taps)?
            },
            mean: AreaMean::new(&source),
            source,
            target,
            completed_rows: 0,
        })
    }

    pub(crate) fn push_row(&mut self, rgb: &[u8], y: u32) {
        if self.column_sums.is_empty() {
            self.rgb.extend_from_slice(rgb);
        } else {
            self.accumulate_row(rgb, y);
        }
    }

    #[inline(never)]
    fn accumulate_row(&mut self, rgb: &[u8], y: u32) {
        let (dest_y, first_weight, second_weight) =
            row_weights(y, self.source.height, self.target.height);
        let (even, odd) = self.column_sums.split_at_mut(rgb.len());
        let (first_row, second_row) = if dest_y % 2 == 0 {
            (even, odd)
        } else {
            (odd, even)
        };
        add_weighted(first_row, rgb, first_weight);
        if second_weight > 0 {
            add_weighted(second_row, rgb, second_weight);
        }
        let complete = ((u64::from(y) + 1) * u64::from(self.target.height)
            / u64::from(self.source.height)) as u32;
        self.finish_rows(complete);
    }

    fn finish_rows(&mut self, complete: u32) {
        while self.completed_rows < complete {
            self.finish_row(self.completed_rows);
            self.completed_rows += 1;
        }
    }

    fn finish_row(&mut self, y: u32) {
        let row_length = self.source.width as usize * 3;
        let sums = &mut self.column_sums[(y as usize % 2) * row_length..][..row_length];
        let row_start = self.rgb.len();
        self.rgb
            .resize(row_start + self.target.width as usize * 3, 0);
        self.taps.write_means(
            sums.as_chunks::<3>().0,
            &self.mean,
            self.rgb[row_start..].as_chunks_mut::<3>().0,
        );
        sums.fill(0);
    }

    pub(crate) fn finish(self) -> Vec<u8> {
        self.rgb
    }
}

fn add_weighted(sums: &mut [u32], values: &[u8], weight: u32) {
    for (sum, &value) in sums.iter_mut().zip(values) {
        *sum += u32::from(value) * weight;
    }
}

fn row_weights(y: u32, source_height: u32, target_height: u32) -> (u32, u32, u32) {
    let begin = u64::from(y) * u64::from(target_height);
    let end = begin + u64::from(target_height);
    let dest_y = begin / u64::from(source_height);
    let boundary = (dest_y + 1) * u64::from(source_height);
    (
        dest_y as u32,
        (end.min(boundary) - begin) as u32,
        end.saturating_sub(boundary) as u32,
    )
}

fn reserved<T>(length: u64) -> ImageResult<Vec<T>> {
    let mut buffer = Vec::new();
    buffer
        .try_reserve_exact(usize::try_from(length).map_err(|_| too_large())?)
        .map_err(|_| too_large())?;
    Ok(buffer)
}

fn zeroed<T: Default + Clone>(length: u64) -> ImageResult<Vec<T>> {
    let mut buffer = reserved(length)?;
    buffer.resize(length as usize, T::default());
    Ok(buffer)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub(crate) fn area_reference(
        pixels: &[u8],
        width: u32,
        height: u32,
        target: &Dimensions,
    ) -> Vec<u8> {
        let mut result = Vec::new();
        for y in 0..target.height {
            for x in 0..target.width {
                let x0 = x as f64 * width as f64 / target.width as f64;
                let x1 = (x + 1) as f64 * width as f64 / target.width as f64;
                let y0 = y as f64 * height as f64 / target.height as f64;
                let y1 = (y + 1) as f64 * height as f64 / target.height as f64;
                let mut sums = [0.0f64; 3];
                for sy in y0.floor() as u32..y1.ceil() as u32 {
                    for sx in x0.floor() as u32..x1.ceil() as u32 {
                        let weight = (x1.min((sx + 1) as f64) - x0.max(sx as f64))
                            * (y1.min((sy + 1) as f64) - y0.max(sy as f64));
                        for channel in 0..3 {
                            sums[channel] +=
                                f64::from(pixels[((sy * width + sx) * 3) as usize + channel])
                                    * weight;
                        }
                    }
                }
                for sum in sums {
                    result.push((sum / ((x1 - x0) * (y1 - y0))).round() as u8);
                }
            }
        }
        result
    }

    fn exact_area_means(pixels: &[u8], source: &Dimensions, target: &Dimensions) -> Vec<u8> {
        let overlap = |source_position: u32, target_position: u32, source_len, target_len| {
            let begin = u64::from(source_position) * u64::from(target_len);
            let end = begin + u64::from(target_len);
            let target_begin = u64::from(target_position) * u64::from(source_len);
            let target_end = target_begin + u64::from(source_len);
            end.min(target_end).saturating_sub(begin.max(target_begin))
        };
        let area = u64::from(source.width) * u64::from(source.height);
        let mut result = Vec::new();
        for target_y in 0..target.height {
            for target_x in 0..target.width {
                for channel in 0..3 {
                    let mut sum = 0;
                    for y in 0..source.height {
                        for x in 0..source.width {
                            let value = pixels[((y * source.width + x) * 3) as usize + channel];
                            sum += u64::from(value)
                                * overlap(x, target_x, source.width, target.width)
                                * overlap(y, target_y, source.height, target.height);
                        }
                    }
                    result.push(((2 * sum + area) / (2 * area)) as u8);
                }
            }
        }
        result
    }

    #[test]
    fn area_means_match_integer_division_around_every_tie() {
        for (width, height) in [
            (1, 1),
            (2, 1),
            (3, 1),
            (7, 3),
            (8160, 6120),
            (16320, 12240),
            (22360, 22361),
            (65535, 65535),
            (1, u32::MAX / 255),
        ] {
            let mean = AreaMean::new(&Dimensions { width, height });
            let area = u64::from(width) * u64::from(height);
            for value in 0..=255u64 {
                let tie = value * area + area / 2;
                for sum in tie.saturating_sub(2)..=(tie + 2).min(255 * area) {
                    assert_eq!(
                        u64::from(mean.of(sum)),
                        (2 * sum + area) / (2 * area),
                        "{width}x{height}, sum {sum}"
                    );
                }
            }
        }
    }

    #[test]
    fn downsampling_rounds_exact_area_means_half_up() {
        for (source, target) in [
            ((4, 4), (2, 2)),
            ((2, 1), (1, 1)),
            ((13, 17), (5, 7)),
            ((31, 23), (7, 5)),
            ((31, 23), (30, 22)),
            ((1, 19), (1, 3)),
            ((19, 1), (4, 1)),
            ((9, 7), (9, 3)),
            ((7, 9), (3, 9)),
            ((40, 3), (1, 1)),
        ] {
            let source = Dimensions {
                width: source.0,
                height: source.1,
            };
            let target = Dimensions {
                width: target.0,
                height: target.1,
            };
            let length = (source.width * source.height * 3) as usize;
            for pixels in [
                (0..length).map(|i| ((i * 37 + 11) % 256) as u8).collect(),
                (0..length).map(|i| (i % 2) as u8).collect::<Vec<_>>(),
                (0..length).map(|i| 254 + (i / 3 % 2) as u8).collect(),
            ] {
                let mut output = Downsampler::new(source.clone(), target.clone()).unwrap();
                for (y, row) in pixels.chunks_exact(source.width as usize * 3).enumerate() {
                    output.push_row(row, y as u32);
                }
                assert_eq!(
                    output.finish(),
                    exact_area_means(&pixels, &source, &target),
                    "{source:?} -> {target:?}"
                );
            }
        }
    }

    #[test]
    fn extreme_downsampling_preserves_constant_colors() {
        let source = Dimensions {
            width: 1,
            height: 1_000_000,
        };
        let mut output = Downsampler::new(
            source.clone(),
            Dimensions {
                width: 1,
                height: 1,
            },
        )
        .unwrap();
        for y in 0..source.height {
            output.push_row(&[128, 127, 254], y);
        }
        assert_eq!(output.finish(), [128, 127, 254]);
    }
}
