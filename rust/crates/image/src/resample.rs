use crate::{Dimensions, ImageResult, bounded::too_large};

pub(crate) struct Downsampler {
    source: Dimensions,
    target: Dimensions,
    rgb: Vec<u8>,
    sums: Vec<[f64; 3]>,
    interlaced_sums: Vec<[f32; 3]>,
    row_sums: Vec<[f64; 3]>,
    interlaced: bool,
    completed_rows: u32,
}

struct BufferLengths {
    rgb: u64,
    sums: u64,
    interlaced_sums: u64,
    row_sums: u64,
}

impl BufferLengths {
    fn new(source: &Dimensions, target: &Dimensions, interlaced: bool) -> Self {
        let pixels = u64::from(target.width) * u64::from(target.height);
        let sum_rows = if source == target {
            0
        } else {
            target.height.min(2)
        };
        Self {
            rgb: pixels.saturating_mul(3),
            sums: u64::from(target.width) * u64::from(sum_rows),
            interlaced_sums: if interlaced && sum_rows > 0 {
                pixels
            } else {
                0
            },
            row_sums: if sum_rows == 0 {
                0
            } else {
                u64::from(target.width)
            },
        }
    }
}

impl Downsampler {
    pub(crate) fn bytes(source: &Dimensions, target: &Dimensions, interlaced: bool) -> u64 {
        let lengths = BufferLengths::new(source, target, interlaced);
        lengths
            .rgb
            .saturating_add(lengths.sums.saturating_mul(24))
            .saturating_add(lengths.interlaced_sums.saturating_mul(12))
            .saturating_add(lengths.row_sums.saturating_mul(24))
    }

    pub(crate) fn new(
        source: Dimensions,
        target: Dimensions,
        interlaced: bool,
    ) -> ImageResult<Self> {
        let lengths = BufferLengths::new(&source, &target, interlaced);
        Ok(Self {
            rgb: zeroed(lengths.rgb)?,
            sums: zeroed(lengths.sums)?,
            interlaced_sums: zeroed(lengths.interlaced_sums)?,
            row_sums: zeroed(lengths.row_sums)?,
            source,
            target,
            interlaced,
            completed_rows: 0,
        })
    }

    pub(crate) fn push_row(&mut self, rgb: &[u8], left: u32, y: u32, step_x: u32) {
        if self.sums.is_empty() {
            for (index, pixel) in rgb.as_chunks::<3>().0.iter().enumerate() {
                let x = left as usize + index * step_x as usize;
                let offset = (y as usize * self.target.width as usize + x) * 3;
                self.rgb[offset..offset + 3].copy_from_slice(pixel);
            }
            return;
        }
        self.finish_rows(
            (u64::from(y) * u64::from(self.target.height) / u64::from(self.source.height)) as u32,
        );
        let ys = contributions(y, self.source.height, self.target.height);
        self.row_sums.fill([0.0; 3]);
        for (index, pixel) in rgb.as_chunks::<3>().0.iter().enumerate() {
            let x = left + index as u32 * step_x;
            for (dest_x, weight_x) in contributions(x, self.source.width, self.target.width) {
                if weight_x == 0.0 {
                    continue;
                }
                for (channel, &value) in pixel.iter().enumerate() {
                    self.row_sums[dest_x as usize][channel] += f64::from(value) * weight_x;
                }
            }
        }
        for (dest_y, weight_y) in ys {
            if weight_y == 0.0 {
                continue;
            }
            let row = dest_y % 2;
            for dest_x in 0..self.target.width {
                let sum = &mut self.sums[(row * self.target.width + dest_x) as usize];
                for (channel, value) in sum.iter_mut().enumerate() {
                    *value += self.row_sums[dest_x as usize][channel] * weight_y;
                }
            }
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
        let row = y % 2;
        for x in 0..self.target.width {
            let sum = &mut self.sums[(row * self.target.width + x) as usize];
            let index = (y * self.target.width + x) as usize;
            for (channel, &value) in sum.iter().enumerate() {
                if self.interlaced {
                    self.interlaced_sums[index][channel] += value as f32;
                } else {
                    self.rgb[index * 3 + channel] = value.round().clamp(0.0, 255.0) as u8;
                }
            }
            *sum = [0.0; 3];
        }
    }

    pub(crate) fn finish_pass(&mut self) {
        if !self.sums.is_empty() {
            self.finish_rows(self.target.height);
            self.completed_rows = 0;
        }
    }

    pub(crate) fn finish(mut self) -> Vec<u8> {
        for (pixel, sum) in self
            .rgb
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .zip(self.interlaced_sums)
        {
            for (channel, value) in sum.into_iter().enumerate() {
                pixel[channel] = value.round().clamp(0.0, 255.0) as u8;
            }
        }
        self.rgb
    }
}

fn contributions(position: u32, source: u32, target: u32) -> [(u32, f64); 2] {
    let start = u64::from(position) * u64::from(target);
    let end = start + u64::from(target);
    let first = start / u64::from(source);
    let boundary = (first + 1) * u64::from(source);
    let first_weight = (end.min(boundary) - start) as f64 / source as f64;
    let second_weight = end.saturating_sub(boundary) as f64 / source as f64;
    [
        (first as u32, first_weight),
        (first as u32 + 1, second_weight),
    ]
}

fn zeroed<T: Default + Clone>(length: u64) -> ImageResult<Vec<T>> {
    let length = usize::try_from(length).map_err(|_| too_large())?;
    let mut buffer = Vec::new();
    buffer.try_reserve_exact(length).map_err(|_| too_large())?;
    buffer.resize(length, T::default());
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

    #[test]
    fn extreme_downsampling_preserves_constant_colors() {
        let source = Dimensions {
            width: 1,
            height: 1_000_000,
        };
        for interlaced in [false, true] {
            let mut output = Downsampler::new(
                source.clone(),
                Dimensions {
                    width: 1,
                    height: 1,
                },
                interlaced,
            )
            .unwrap();
            let plain = [(0, 0, 1, 1)];
            let passes = if interlaced {
                &crate::png::ADAM7[..]
            } else {
                &plain[..]
            };
            for &(left, top, step_x, step_y) in passes {
                if left >= source.width {
                    continue;
                }
                for y in (top..source.height).step_by(step_y as usize) {
                    output.push_row(&[128, 127, 254], left, y, step_x);
                }
                output.finish_pass();
            }
            assert_eq!(output.finish(), [128, 127, 254]);
        }
    }
}
