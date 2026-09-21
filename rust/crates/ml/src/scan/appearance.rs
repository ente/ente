use std::sync::OnceLock;

use crate::cv::OpResult;
use crate::cv::image::ImageU8;

use super::ColorMode;

const ANALYSIS_LONG_EDGE: usize = 384;
const CELL_EDGE: usize = 16;
const CHROMA_BIN_COUNT: usize = 48;
const PAPER_CHROMA_RADIUS: f32 = 0.032;
const NEUTRAL_CHROMA_SPREAD: f32 = 0.067;
const MIN_PAPER_LUMINANCE: f32 = 0.12;
const MAX_CELL_LOG_STEP: f32 = 0.14;
const MAX_PAPER_CURVATURE: f32 = 16.0;
const ENCODE_TABLE_SIZE: usize = 8192;

#[derive(Clone, Copy, Default)]
struct Sample {
    rgb: [f32; 3],
    luminance: f32,
    coverage: f32,
    unclipped: f32,
    smoothness: f32,
}

struct Analysis {
    width: usize,
    height: usize,
    samples: Vec<Sample>,
}

#[derive(Clone, Copy, Default)]
struct PaperCell {
    log_luminance: f32,
    weight: f32,
}

#[derive(Clone, Copy)]
enum PaperScale {
    Coarse,
    Detailed,
}

struct PaperField {
    width: usize,
    height: usize,
    gain: Vec<f32>,
}

struct TransferTables {
    decode: [f32; 256],
    encode: Vec<f32>,
}

fn transfer_tables() -> &'static TransferTables {
    static TABLES: OnceLock<TransferTables> = OnceLock::new();
    TABLES.get_or_init(|| TransferTables {
        decode: std::array::from_fn(|value| {
            let encoded = value as f32 / 255.0;
            if encoded <= 0.04045 {
                encoded / 12.92
            } else {
                ((encoded + 0.055) / 1.055).powf(2.4)
            }
        }),
        encode: (0..=ENCODE_TABLE_SIZE)
            .map(|index| {
                let linear = index as f32 / ENCODE_TABLE_SIZE as f32;
                255.0
                    * if linear <= 0.0031308 {
                        linear * 12.92
                    } else {
                        1.055 * linear.powf(1.0 / 2.4) - 0.055
                    }
            })
            .collect(),
    })
}

fn luminance(rgb: [f32; 3]) -> f32 {
    0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
}

fn chromaticity(rgb: [f32; 3]) -> [f32; 3] {
    let total = (rgb[0] + rgb[1] + rgb[2]).max(f32::MIN_POSITIVE);
    rgb.map(|value| value / total)
}

fn chroma_distance(a: [f32; 3], b: [f32; 3]) -> f32 {
    a.into_iter()
        .zip(b)
        .map(|(left, right)| (left - right).abs())
        .fold(0.0, f32::max)
}

fn transition(value: f32, low: f32, high: f32) -> f32 {
    let t = ((value - low) / (high - low)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn validate(image: &ImageU8, valid: Option<&[u8]>) -> OpResult<(usize, usize)> {
    if image.width <= 0 || image.height <= 0 || image.channels != 3 {
        return Err("document appearance requires a nonempty three-channel image".into());
    }
    let width = image.width as usize;
    let height = image.height as usize;
    let pixels = width
        .checked_mul(height)
        .ok_or_else(|| "document image dimensions overflow".to_string())?;
    let bytes = pixels
        .checked_mul(3)
        .ok_or_else(|| "document image byte count overflows".to_string())?;
    if image.data.len() != bytes {
        return Err("document image buffer does not match its dimensions".into());
    }
    if valid.is_some_and(|mask| mask.len() != pixels) {
        return Err("document validity mask does not match its image".into());
    }
    Ok((width, height))
}

fn analyze(image: &ImageU8, valid: Option<&[u8]>, long_edge: usize) -> Analysis {
    let source_width = image.width as usize;
    let source_height = image.height as usize;
    let ratio = (long_edge as f64 / source_width.max(source_height) as f64).min(1.0);
    let width = (source_width as f64 * ratio).round().max(1.0) as usize;
    let height = (source_height as f64 * ratio).round().max(1.0) as usize;
    let mut samples = vec![Sample::default(); width * height];
    let decode = &transfer_tables().decode;
    for y in 0..height {
        let top = y * source_height / height;
        let bottom = (y + 1) * source_height / height;
        for x in 0..width {
            let left = x * source_width / width;
            let right = (x + 1) * source_width / width;
            let mut rgb = [0.0; 3];
            let mut count = 0;
            let mut unclipped = 0;
            for source_y in top..bottom {
                for source_x in left..right {
                    let index = source_y * source_width + source_x;
                    if valid.is_some_and(|mask| mask[index] == 0) {
                        continue;
                    }
                    let pixel = &image.data[index * 3..index * 3 + 3];
                    unclipped += usize::from(pixel.iter().all(|&value| value < 254));
                    rgb[0] += decode[pixel[2] as usize];
                    rgb[1] += decode[pixel[1] as usize];
                    rgb[2] += decode[pixel[0] as usize];
                    count += 1;
                }
            }
            if count != 0 {
                rgb.iter_mut().for_each(|value| *value /= count as f32);
                samples[y * width + x] = Sample {
                    rgb,
                    luminance: luminance(rgb),
                    coverage: count as f32 / ((right - left) * (bottom - top)) as f32,
                    unclipped: unclipped as f32 / count as f32,
                    smoothness: 0.0,
                };
            }
        }
    }
    for y in 0..height {
        for x in 0..width {
            let index = y * width + x;
            let center = samples[index];
            if center.coverage < 0.6
                || center.unclipped < 0.9
                || center.luminance < MIN_PAPER_LUMINANCE
            {
                continue;
            }
            let mut low = center.luminance;
            let mut high = center.luminance;
            let mut chroma_range: f32 = 0.0;
            let center_chroma = chromaticity(center.rgb);
            for nearby_y in y.saturating_sub(1)..=(y + 1).min(height - 1) {
                for nearby_x in x.saturating_sub(1)..=(x + 1).min(width - 1) {
                    let neighbor = samples[nearby_y * width + nearby_x];
                    if neighbor.coverage >= 0.6 {
                        low = low.min(neighbor.luminance);
                        high = high.max(neighbor.luminance);
                        chroma_range = chroma_range
                            .max(chroma_distance(center_chroma, chromaticity(neighbor.rgb)));
                    }
                }
            }
            let local_range = (high - low) / center.luminance.max(MIN_PAPER_LUMINANCE);
            samples[index].smoothness = (1.0 - transition(local_range, 0.07, 0.25))
                * (1.0 - transition(chroma_range, 0.012, 0.055));
        }
    }
    Analysis {
        width,
        height,
        samples,
    }
}

fn paper_chromaticity(analysis: &Analysis) -> Option<[f32; 3]> {
    let mut histogram = vec![0.0f32; CHROMA_BIN_COUNT * CHROMA_BIN_COUNT];
    for sample in &analysis.samples {
        if sample.smoothness <= 0.0 {
            continue;
        }
        let chroma = chromaticity(sample.rgb);
        let x = (chroma[0] * CHROMA_BIN_COUNT as f32) as usize;
        let y = (chroma[2] * CHROMA_BIN_COUNT as f32) as usize;
        let x = x.min(CHROMA_BIN_COUNT - 1);
        let y = y.min(CHROMA_BIN_COUNT - 1);
        histogram[y * CHROMA_BIN_COUNT + x] +=
            sample.smoothness * sample.coverage * sample.luminance.sqrt();
    }
    let mut peak = (0, 0);
    let mut peak_weight = 0.0;
    for y in 0..CHROMA_BIN_COUNT {
        for x in 0..CHROMA_BIN_COUNT {
            let mut weight = 0.0;
            for near_y in y.saturating_sub(1)..=(y + 1).min(CHROMA_BIN_COUNT - 1) {
                for near_x in x.saturating_sub(1)..=(x + 1).min(CHROMA_BIN_COUNT - 1) {
                    let horizontal = if near_x == x { 2.0 } else { 1.0 };
                    let vertical = if near_y == y { 2.0 } else { 1.0 };
                    weight += histogram[near_y * CHROMA_BIN_COUNT + near_x] * horizontal * vertical;
                }
            }
            if weight > peak_weight {
                peak = (x, y);
                peak_weight = weight;
            }
        }
    }
    if peak_weight == 0.0 {
        return None;
    }
    let red = (peak.0 as f32 + 0.5) / CHROMA_BIN_COUNT as f32;
    let blue = (peak.1 as f32 + 0.5) / CHROMA_BIN_COUNT as f32;
    let mut center = [red, 1.0 - red - blue, blue];
    for _ in 0..3 {
        let mut sum = [0.0; 3];
        let mut weight = 0.0;
        for sample in &analysis.samples {
            let chroma = chromaticity(sample.rgb);
            if sample.smoothness > 0.0 && chroma_distance(center, chroma) < PAPER_CHROMA_RADIUS {
                let w = sample.smoothness * sample.coverage;
                for channel in 0..3 {
                    sum[channel] += chroma[channel] * w;
                }
                weight += w;
            }
        }
        if weight == 0.0 {
            return None;
        }
        center = chromaticity(sum);
    }
    Some(center)
}

fn estimate_field(analysis: &Analysis) -> Option<PaperField> {
    let chroma = paper_chromaticity(analysis)?;
    let width = analysis.width.div_ceil(CELL_EDGE);
    let height = analysis.height.div_ceil(CELL_EDGE);
    let mut cells = vec![PaperCell::default(); width * height];
    let mut eligible = Vec::with_capacity(CELL_EDGE * CELL_EDGE);
    let mut valid_weight = 0.0;
    let mut paper_weight = 0.0;
    for y in 0..height {
        for x in 0..width {
            eligible.clear();
            let left = x * analysis.width / width;
            let right = (x + 1) * analysis.width / width;
            let top = y * analysis.height / height;
            let bottom = (y + 1) * analysis.height / height;
            let mut supported = 0.0;
            let mut available = 0.0;
            for sample_y in top..bottom {
                for sample_x in left..right {
                    let sample = analysis.samples[sample_y * analysis.width + sample_x];
                    available += sample.coverage;
                    if sample.smoothness > 0.5
                        && chroma_distance(chromaticity(sample.rgb), chroma) < PAPER_CHROMA_RADIUS
                    {
                        eligible.push(sample.luminance);
                        supported += sample.coverage;
                    }
                }
            }
            valid_weight += available;
            paper_weight += supported;
            if supported >= available * 0.18 && eligible.len() >= 3 {
                eligible.sort_unstable_by(f32::total_cmp);
                let bright = eligible[eligible.len() * 3 / 4];
                let median = eligible[eligible.len() / 2];
                let spread = (bright / median).ln();
                cells[y * width + x] = PaperCell {
                    log_luminance: bright.ln(),
                    weight: (supported / available.max(1.0))
                        * (1.0 - transition(spread, 0.06, 0.22)),
                };
            }
        }
    }
    if valid_weight < 12.0 || paper_weight / valid_weight < 0.38 {
        return None;
    }
    retain_paper_components(&mut cells, width, height, PaperScale::Coarse);
    if paper_curvature(&cells, width, height) > MAX_PAPER_CURVATURE {
        return None;
    }
    let supported_cells = cells.iter().filter(|cell| cell.weight > 0.0).count();
    if supported_cells < 2 || supported_cells as f32 / cells.len() as f32 <= 0.32 {
        return None;
    }
    let mut regions = [false; 9];
    for y in 0..height {
        for x in 0..width {
            if cells[y * width + x].weight > 0.0 {
                regions[(y * 3 / height).min(2) * 3 + (x * 3 / width).min(2)] = true;
            }
        }
    }
    if width >= 3 && height >= 3 && regions.iter().filter(|&&value| value).count() < 7 {
        return None;
    }
    let mut measured: Vec<f32> = cells
        .iter()
        .filter(|cell| cell.weight > 0.0)
        .map(|cell| cell.log_luminance)
        .collect();
    measured.sort_unstable_by(f32::total_cmp);
    let initial = measured[measured.len() / 2];
    let bright = measured[measured.len() * 9 / 10];
    let neutral = chroma.iter().copied().fold(f32::NEG_INFINITY, f32::max)
        - chroma.iter().copied().fold(f32::INFINITY, f32::min)
        < NEUTRAL_CHROMA_SPREAD;
    let target_log_luminance = if neutral {
        bright.max(0.965f32.ln())
    } else {
        bright
    };
    let mut field = vec![initial; width * height];
    let mut scratch = field.clone();
    let mut distance = vec![width + height; width * height];
    for (index, cell) in cells.iter().enumerate() {
        if cell.weight > 0.0 {
            field[index] = cell.log_luminance;
            distance[index] = 0;
        }
    }
    for _ in 0..(width + height) {
        let mut changed = false;
        for y in 0..height {
            for x in 0..width {
                let index = y * width + x;
                let old = distance[index];
                for neighbor in neighbors(x, y, width, height).into_iter().flatten() {
                    distance[index] = distance[index].min(distance[neighbor] + 1);
                }
                changed |= old != distance[index];
            }
        }
        if !changed {
            break;
        }
    }
    for _ in 0..(width.max(height) * 6) {
        for y in 0..height {
            for x in 0..width {
                let index = y * width + x;
                let evidence = cells[index].weight * 7.0;
                let mut sum = cells[index].log_luminance * evidence;
                let mut total = evidence;
                for neighbor in neighbors(x, y, width, height).into_iter().flatten() {
                    sum += field[neighbor];
                    total += 1.0;
                }
                scratch[index] = if total > 0.0 { sum / total } else { initial };
            }
        }
        std::mem::swap(&mut field, &mut scratch);
    }
    let confidence_start = (width.min(height) as f32 * 0.3).max(2.0);
    let confidence_end = (width.max(height) as f32 * 0.75).max(confidence_start + 1.0);
    let confidence: Vec<f32> = distance
        .into_iter()
        .map(|value| 1.0 - transition(value as f32, confidence_start, confidence_end))
        .collect();
    Some(refine_field(
        analysis,
        &cells,
        width,
        height,
        &field,
        &confidence,
        target_log_luminance,
    ))
}

fn refine_field(
    analysis: &Analysis,
    cells: &[PaperCell],
    width: usize,
    height: usize,
    field: &[f32],
    confidence: &[f32],
    target: f32,
) -> PaperField {
    let support: Vec<f32> = cells
        .iter()
        .map(|cell| f32::from(cell.weight > 0.0))
        .collect();
    let support = close_background(&support, width, height, 1);
    let background: Vec<f32> = analysis
        .samples
        .iter()
        .map(|sample| sample.luminance.max(MIN_PAPER_LUMINANCE).ln())
        .collect();
    let background = close_background(&background, analysis.width, analysis.height, 3);
    let mut detailed_cells: Vec<PaperCell> = background
        .iter()
        .zip(&analysis.samples)
        .map(|(&log_luminance, sample)| PaperCell {
            log_luminance,
            weight: sample.coverage,
        })
        .collect();
    retain_paper_components(
        &mut detailed_cells,
        analysis.width,
        analysis.height,
        PaperScale::Detailed,
    );
    let gain = analysis
        .samples
        .iter()
        .enumerate()
        .map(|(index, sample)| {
            let x = (index % analysis.width) as f32 / analysis.width as f32
                + 0.5 / analysis.width as f32;
            let y = (index / analysis.width) as f32 / analysis.height as f32
                + 0.5 / analysis.height as f32;
            let coarse = interpolate(field, width, height, x, y);
            let confidence = interpolate(confidence, width, height, x, y);
            let support = interpolate(&support, width, height, x, y);
            let difference = background[index] - coarse;
            let weight = transition(support, 0.5, 1.0)
                * (1.0 - transition(difference.abs(), 0.65, 0.85))
                * sample.coverage
                * f32::from(detailed_cells[index].weight > 0.0);
            let paper = coarse + difference * weight;
            ((target - paper).clamp(-0.08, 4.0f32.ln()) * confidence).exp()
        })
        .collect();
    PaperField {
        width: analysis.width,
        height: analysis.height,
        gain,
    }
}

fn close_background(values: &[f32], width: usize, height: usize, radius: usize) -> Vec<f32> {
    let mut source = values.to_vec();
    let mut target = source.clone();
    for maximum in [true, false] {
        for horizontal in [true, false] {
            for y in 0..height {
                for x in 0..width {
                    let position = if horizontal { x } else { y };
                    let length = if horizontal { width } else { height };
                    let mut value = source[y * width + x];
                    for nearby in
                        position.saturating_sub(radius)..=(position + radius).min(length - 1)
                    {
                        let index = if horizontal {
                            y * width + nearby
                        } else {
                            nearby * width + x
                        };
                        value = if maximum {
                            value.max(source[index])
                        } else {
                            value.min(source[index])
                        };
                    }
                    target[y * width + x] = value;
                }
            }
            std::mem::swap(&mut source, &mut target);
        }
    }
    source
}

fn paper_adaptation(analysis: &Analysis) -> [f32; 3] {
    let Some(chroma) = paper_chromaticity(analysis) else {
        return [1.0; 3];
    };
    let spread = chroma.iter().copied().fold(f32::NEG_INFINITY, f32::max)
        - chroma.iter().copied().fold(f32::INFINITY, f32::min);
    if spread >= NEUTRAL_CHROMA_SPREAD {
        return [1.0; 3];
    }
    let mut supported = [0.0; 9];
    let mut available = [0.0; 9];
    for (index, sample) in analysis.samples.iter().enumerate() {
        let x = index % analysis.width;
        let y = index / analysis.width;
        let region = (y * 3 / analysis.height) * 3 + x * 3 / analysis.width;
        available[region] += sample.coverage;
        if sample.smoothness > 0.5
            && chroma_distance(chromaticity(sample.rgb), chroma) < PAPER_CHROMA_RADIUS
        {
            supported[region] += sample.coverage;
        }
    }
    let broad_support = supported.iter().sum::<f32>() >= available.iter().sum::<f32>() * 0.2;
    let regions = supported
        .iter()
        .zip(available)
        .filter(|(support, available)| available > &0.0 && **support >= available * 0.05)
        .count();
    if !broad_support || regions < 7 {
        return [1.0; 3];
    }
    let paper_luminance = luminance(chroma);
    chroma.map(|channel| (paper_luminance / channel.max(0.001)).clamp(0.88, 1.12))
}

fn neighbors(x: usize, y: usize, width: usize, height: usize) -> [Option<usize>; 4] {
    [
        (x > 0).then(|| y * width + x - 1),
        (x + 1 < width).then_some(y * width + x + 1),
        (y > 0).then(|| (y - 1) * width + x),
        (y + 1 < height).then_some((y + 1) * width + x),
    ]
}

fn paper_curvature(cells: &[PaperCell], width: usize, height: usize) -> f32 {
    let mut smoothed = cells.to_vec();
    for y in 0..height {
        for x in 0..width {
            let mut sum = 0.0;
            let mut weight = 0.0;
            for near_y in y.saturating_sub(1)..=(y + 1).min(height - 1) {
                for near_x in x.saturating_sub(1)..=(x + 1).min(width - 1) {
                    let cell = cells[near_y * width + near_x];
                    sum += cell.log_luminance * cell.weight;
                    weight += cell.weight;
                }
            }
            if weight > 0.0 {
                smoothed[y * width + x].log_luminance = sum / weight;
            }
        }
    }
    let cells = &smoothed;
    let mut curvature = Vec::new();
    for y in 0..height {
        for x in 0..width {
            let center = cells[y * width + x];
            if center.weight == 0.0 {
                continue;
            }
            if x > 0 && x + 1 < width {
                let before = cells[y * width + x - 1];
                let after = cells[y * width + x + 1];
                if before.weight > 0.0 && after.weight > 0.0 {
                    curvature.push(
                        (before.log_luminance + after.log_luminance - 2.0 * center.log_luminance)
                            .abs()
                            * (width * width) as f32,
                    );
                }
            }
            if y > 0 && y + 1 < height {
                let before = cells[(y - 1) * width + x];
                let after = cells[(y + 1) * width + x];
                if before.weight > 0.0 && after.weight > 0.0 {
                    curvature.push(
                        (before.log_luminance + after.log_luminance - 2.0 * center.log_luminance)
                            .abs()
                            * (height * height) as f32,
                    );
                }
            }
        }
    }
    curvature.sort_unstable_by(f32::total_cmp);
    if curvature.is_empty() {
        0.0
    } else {
        curvature[curvature.len() * 3 / 4]
    }
}

fn retain_paper_components(
    cells: &mut [PaperCell],
    width: usize,
    height: usize,
    scale: PaperScale,
) {
    let mut labels = vec![usize::MAX; cells.len()];
    let mut queue = Vec::with_capacity(cells.len());
    let mut best_label = 0;
    let mut best_weight = 0.0;
    let mut label = 0;
    let mut components = Vec::new();
    for start in 0..cells.len() {
        if cells[start].weight <= 0.0 || labels[start] != usize::MAX {
            continue;
        }
        queue.clear();
        queue.push(start);
        labels[start] = label;
        let mut index = 0;
        let mut weight = 0.0;
        let mut edges = 0u8;
        while index < queue.len() {
            let current = queue[index];
            let x = current % width;
            let y = current / width;
            edges |= u8::from(x == 0)
                | (u8::from(x + 1 == width) << 1)
                | (u8::from(y == 0) << 2)
                | (u8::from(y + 1 == height) << 3);
            weight += cells[current].weight * (0.3 * cells[current].log_luminance).exp();
            for neighbor in neighbors(current % width, current / width, width, height)
                .into_iter()
                .flatten()
            {
                if cells[neighbor].weight > 0.0
                    && labels[neighbor] == usize::MAX
                    && paper_cells_agree(cells, current, neighbor, width, height, scale)
                {
                    labels[neighbor] = label;
                    queue.push(neighbor);
                }
            }
            index += 1;
        }
        if weight > best_weight {
            best_weight = weight;
            best_label = label;
        }
        components.push((weight, edges));
        label += 1;
    }
    let (minimum_edges, minimum_weight) = match scale {
        PaperScale::Coarse => (2, best_weight * 0.1),
        PaperScale::Detailed => (1, 0.0),
    };
    for (cell, label) in cells.iter_mut().zip(labels) {
        let border_paper = components.get(label).is_some_and(|&(weight, edges)| {
            edges.count_ones() >= minimum_edges && weight >= minimum_weight
        });
        if label != best_label && !border_paper {
            cell.weight = 0.0;
        }
    }
}

fn paper_cells_agree(
    cells: &[PaperCell],
    current: usize,
    neighbor: usize,
    width: usize,
    height: usize,
    scale: PaperScale,
) -> bool {
    let step = (cells[neighbor].log_luminance - cells[current].log_luminance).abs();
    if matches!(scale, PaperScale::Detailed) {
        return step <= 0.025;
    }
    if step > MAX_CELL_LOG_STEP {
        return false;
    }
    let current_x = (current % width) as isize;
    let current_y = (current / width) as isize;
    let neighbor_x = (neighbor % width) as isize;
    let neighbor_y = (neighbor / width) as isize;
    let dx = neighbor_x - current_x;
    let dy = neighbor_y - current_y;
    let before = (current_x - dx, current_y - dy);
    let after = (neighbor_x + dx, neighbor_y + dy);
    let at = |(x, y): (isize, isize)| {
        (x >= 0 && y >= 0 && x < width as isize && y < height as isize)
            .then(|| cells[y as usize * width + x as usize])
            .filter(|cell| cell.weight > 0.0)
    };
    if let (Some(before), Some(after)) = (at(before), at(after)) {
        let before_slope = cells[current].log_luminance - before.log_luminance;
        let after_slope = after.log_luminance - cells[neighbor].log_luminance;
        let slope = cells[neighbor].log_luminance - cells[current].log_luminance;
        (slope - (before_slope + after_slope) * 0.5).abs()
            <= (after_slope - before_slope).abs() + 0.035
    } else {
        true
    }
}

fn interpolate(values: &[f32], width: usize, height: usize, x: f32, y: f32) -> f32 {
    let x = (x * width as f32 - 0.5).clamp(0.0, (width - 1) as f32);
    let y = (y * height as f32 - 0.5).clamp(0.0, (height - 1) as f32);
    let left = x as usize;
    let top = y as usize;
    let right = (left + 1).min(width - 1);
    let bottom = (top + 1).min(height - 1);
    let fx = x - left as f32;
    let fy = y - top as f32;
    let upper = values[top * width + left] * (1.0 - fx) + values[top * width + right] * fx;
    let lower = values[bottom * width + left] * (1.0 - fx) + values[bottom * width + right] * fx;
    upper * (1.0 - fy) + lower * fy
}

fn encode(value: f32, table: &[f32]) -> u8 {
    let index = value.clamp(0.0, 1.0) * ENCODE_TABLE_SIZE as f32;
    let low = index as usize;
    let high = (low + 1).min(ENCODE_TABLE_SIZE);
    let fraction = index - low as f32;
    (table[low] * (1.0 - fraction) + table[high] * fraction).round() as u8
}

fn render(
    image: &mut ImageU8,
    valid: Option<&[u8]>,
    field: Option<&PaperField>,
    adaptation: [f32; 3],
    grayscale: bool,
) {
    let width = image.width as usize;
    let height = image.height as usize;
    let tables = transfer_tables();
    for (index, pixel) in image.data.as_chunks_mut::<3>().0.iter_mut().enumerate() {
        if valid.is_some_and(|mask| mask[index] == 0) {
            pixel.fill(255);
            continue;
        }
        if field.is_none() && adaptation == [1.0; 3] && !grayscale {
            continue;
        }
        let mut rgb = [
            tables.decode[pixel[2] as usize],
            tables.decode[pixel[1] as usize],
            tables.decode[pixel[0] as usize],
        ];
        if let Some(field) = field {
            let x = (index % width) as f32 / width as f32 + 0.5 / width as f32;
            let y = (index / width) as f32 / height as f32 + 0.5 / height as f32;
            let gain = interpolate(&field.gain, field.width, field.height, x, y);
            for value in &mut rgb {
                *value *= gain;
            }
        }
        for (value, adaptation) in rgb.iter_mut().zip(adaptation) {
            *value *= adaptation;
        }
        let maximum = rgb.iter().copied().fold(1.0, f32::max);
        rgb.iter_mut().for_each(|value| *value /= maximum);
        if grayscale {
            pixel.fill(encode(luminance(rgb), &tables.encode));
        } else {
            pixel[0] = encode(rgb[2], &tables.encode);
            pixel[1] = encode(rgb[1], &tables.encode);
            pixel[2] = encode(rgb[0], &tables.encode);
        }
    }
}

fn stroke_contrast(image: &ImageU8, valid: Option<&[u8]>) -> Vec<f32> {
    let width = image.width as usize;
    let height = image.height as usize;
    let tables = transfer_tables();
    let background: Vec<f32> = image
        .data
        .as_chunks::<3>()
        .0
        .iter()
        .enumerate()
        .map(|(index, pixel)| {
            if valid.is_some_and(|mask| mask[index] == 0) {
                return 0.0;
            }
            luminance([
                tables.decode[pixel[2] as usize],
                tables.decode[pixel[1] as usize],
                tables.decode[pixel[0] as usize],
            ])
        })
        .collect();
    let radius = width.max(height).div_ceil(192).max(2);
    let mut contrasts = vec![0.0; width * height];
    for (index, &level) in background.iter().enumerate() {
        if valid.is_some_and(|mask| mask[index] == 0) {
            continue;
        }
        let x = index % width;
        let y = index / width;
        let mut paper = level;
        for distance in [radius, radius * 2] {
            let horizontal = background[y * width + x.saturating_sub(distance)]
                .min(background[y * width + (x + distance).min(width - 1)]);
            let vertical = background[y.saturating_sub(distance) * width + x]
                .min(background[(y + distance).min(height - 1) * width + x]);
            paper = paper.max(horizontal).max(vertical);
        }
        let contrast = (1.0 - level / paper.max(0.01)).max(0.0);
        contrasts[index] = contrast;
    }
    contrasts
}

fn enhance_neutral_strokes(image: &mut ImageU8, contrasts: &[f32]) {
    let tables = transfer_tables();
    for (pixel, &contrast) in image.data.as_chunks_mut::<3>().0.iter_mut().zip(contrasts) {
        if contrast <= 0.02 {
            continue;
        }
        let rgb = [
            tables.decode[pixel[2] as usize],
            tables.decode[pixel[1] as usize],
            tables.decode[pixel[0] as usize],
        ];
        let low = rgb.into_iter().fold(f32::INFINITY, f32::min);
        let high = rgb.into_iter().fold(0.0, f32::max);
        let neutrality = 1.0 - transition((high - low) / high.max(0.01), 0.04, 0.12);
        let paper = luminance(rgb) / (1.0 - contrast).max(f32::EPSILON);
        let weight = neutrality * transition(paper, 0.75, 0.9) * transition(contrast, 0.02, 0.07);
        if weight == 0.0 {
            continue;
        }
        let gain = 1.0 / (1.0 + 2.0 * weight * contrast);
        pixel[0] = encode(rgb[2] * gain, &tables.encode);
        pixel[1] = encode(rgb[1] * gain, &tables.encode);
        pixel[2] = encode(rgb[0] * gain, &tables.encode);
    }
}

fn dark_stock_support(analysis: &Analysis) -> f32 {
    let mut supported = [0.0; 9];
    let mut available = [0.0; 9];
    for y in 0..analysis.height {
        for x in 0..analysis.width {
            let sample = analysis.samples[y * analysis.width + x];
            let region = (y * 3 / analysis.height) * 3 + x * 3 / analysis.width;
            available[region] += sample.coverage;
            if sample.coverage < 0.6 || sample.luminance >= 0.08 {
                continue;
            }
            let mut low = sample.luminance;
            let mut high = sample.luminance;
            for nearby_y in y.saturating_sub(1)..=(y + 1).min(analysis.height - 1) {
                for nearby_x in x.saturating_sub(1)..=(x + 1).min(analysis.width - 1) {
                    let neighbor = analysis.samples[nearby_y * analysis.width + nearby_x];
                    if neighbor.coverage >= 0.6 {
                        low = low.min(neighbor.luminance);
                        high = high.max(neighbor.luminance);
                    }
                }
            }
            supported[region] += sample.coverage * (1.0 - transition(high - low, 0.006, 0.025));
        }
    }
    let total = supported.iter().sum::<f32>() / available.iter().sum::<f32>().max(1.0);
    let mut regions = std::array::from_fn::<_, 9, _>(|i| supported[i] / available[i].max(1.0));
    regions.sort_unstable_by(f32::total_cmp);
    transition(total, 0.55, 0.75) * transition(regions[2], 0.35, 0.6)
}

fn light_stroke_contrast(image: &ImageU8, valid: Option<&[u8]>) -> Vec<f32> {
    let width = image.width as usize;
    let height = image.height as usize;
    let tables = transfer_tables();
    let background: Vec<f32> = image
        .data
        .as_chunks::<3>()
        .0
        .iter()
        .enumerate()
        .map(|(index, pixel)| {
            if valid.is_some_and(|mask| mask[index] == 0) {
                return 1.0;
            }
            luminance([
                tables.decode[pixel[2] as usize],
                tables.decode[pixel[1] as usize],
                tables.decode[pixel[0] as usize],
            ])
        })
        .collect();
    let radius = width.max(height).div_ceil(192).max(2);
    let mut contrasts = vec![0.0; width * height];
    for (index, &level) in background.iter().enumerate() {
        if valid.is_some_and(|mask| mask[index] == 0) {
            continue;
        }
        let x = index % width;
        let y = index / width;
        let mut contrast = 0.0f32;
        for distance in [radius, radius * 2, radius * 3] {
            for (a, b) in [
                (
                    background[y * width + x.saturating_sub(distance)],
                    background[y * width + (x + distance).min(width - 1)],
                ),
                (
                    background[y.saturating_sub(distance) * width + x],
                    background[(y + distance).min(height - 1) * width + x],
                ),
            ] {
                let difference = (level - a.max(b)).max(0.0);
                let agreement = 1.0 - transition((a - b).abs() / difference.max(0.005), 0.25, 0.75);
                let darkness = 1.0 - transition(a.max(b), 0.04, 0.08);
                contrast = contrast.max(difference * agreement * darkness);
            }
        }
        contrasts[index] = contrast;
    }
    contrasts
}

fn enhance_light_strokes(image: &mut ImageU8, contrasts: &[f32], support: f32) {
    let tables = transfer_tables();
    for (pixel, &contrast) in image.data.as_chunks_mut::<3>().0.iter_mut().zip(contrasts) {
        let weight = support * transition(contrast, 0.005, 0.025);
        if weight == 0.0 {
            continue;
        }
        let rgb = [
            tables.decode[pixel[2] as usize],
            tables.decode[pixel[1] as usize],
            tables.decode[pixel[0] as usize],
        ];
        let level = luminance(rgb);
        let paper = (level - contrast).max(0.0);
        let lift = 2.0 * contrast * (1.0 - level) / (1.0 - paper + 2.0 * contrast);
        let gain = (level + weight * lift) / level.max(f32::EPSILON);
        let maximum = rgb.iter().copied().fold(0.0, f32::max);
        let gain = gain.min(1.0 / maximum.max(f32::EPSILON));
        pixel[0] = encode(rgb[2] * gain, &tables.encode);
        pixel[1] = encode(rgb[1] * gain, &tables.encode);
        pixel[2] = encode(rgb[0] * gain, &tables.encode);
    }
}

fn meaningful_color(image: &ImageU8, valid: Option<&[u8]>, adaptation: [f32; 3]) -> bool {
    let width = image.width as usize;
    let height = image.height as usize;
    let decode = &transfer_tables().decode;
    let corrected = |pixel: &[u8]| {
        std::array::from_fn::<_, 3, _>(|channel| {
            decode[pixel[2 - channel] as usize] * adaptation[channel]
        })
    };
    let radius = (width.max(height) / 192).max(2);
    let mut saturated = 0.0;
    let mut colored_content = 0.0;
    let mut content = 0.0;
    let mut available = 0;
    for y in 0..height {
        for x in 0..width {
            let index = y * width + x;
            if valid.is_some_and(|mask| mask[index] == 0) {
                continue;
            }
            let pixel = &image.data[index * 3..index * 3 + 3];
            let rgb = corrected(pixel);
            let low = rgb.into_iter().fold(f32::INFINITY, f32::min);
            let high = rgb.into_iter().fold(0.0, f32::max);
            let brightness = |x: usize, y: usize| {
                let neighbor = y * width + x;
                if valid.is_some_and(|mask| mask[neighbor] == 0) {
                    luminance(rgb)
                } else {
                    luminance(corrected(&image.data[neighbor * 3..neighbor * 3 + 3]))
                }
            };
            let horizontal = brightness(x.saturating_sub(radius), y)
                .min(brightness((x + radius).min(width - 1), y));
            let vertical = brightness(x, y.saturating_sub(radius))
                .min(brightness(x, (y + radius).min(height - 1)));
            let local = horizontal.max(vertical);
            let contrast = (1.0 - luminance(rgb) / local.max(0.01)).max(0.0);
            let ink = contrast * transition(contrast, 0.08, 0.3);
            available += 1;
            content += ink;
            let strength = transition((high - low) / high.sqrt().max(0.01), 0.045, 0.12);
            if strength == 0.0 {
                continue;
            }
            let differences = [rgb[0] - rgb[1], rgb[2] - rgb[1]];
            let mut matched = width * height < 36;
            for neighbor in [
                (x + 1 < width).then_some(index + 1),
                (y + 1 < height).then_some(index + width),
                (x > 0 && y + 1 < height).then(|| index + width - 1),
                (x + 1 < width && y + 1 < height).then_some(index + width + 1),
            ]
            .into_iter()
            .flatten()
            {
                if valid.is_some_and(|mask| mask[neighbor] == 0) {
                    continue;
                }
                let other = corrected(&image.data[neighbor * 3..neighbor * 3 + 3]);
                let other_differences = [other[0] - other[1], other[2] - other[1]];
                let dot =
                    differences[0] * other_differences[0] + differences[1] * other_differences[1];
                let length = differences[0].powi(2) + differences[1].powi(2);
                matched |= dot > length * 0.5;
            }
            if matched {
                saturated += strength * transition((high - low) / high.max(0.01), 0.12, 0.3);
                colored_content += ink * strength;
            }
        }
    }
    saturated / available.max(1) as f32 >= 0.02
        || (colored_content > 0.0 && colored_content >= content * 0.4)
}

pub(super) fn render_document(
    image: &mut ImageU8,
    valid: Option<&[u8]>,
    requested_mode: Option<ColorMode>,
) -> OpResult<ColorMode> {
    validate(image, valid)?;
    let analysis = analyze(image, valid, ANALYSIS_LONG_EDGE);
    let field = estimate_field(&analysis);
    let adaptation = paper_adaptation(&analysis);
    let mode = requested_mode.unwrap_or_else(|| {
        if meaningful_color(image, valid, adaptation) {
            ColorMode::Color
        } else {
            ColorMode::Grayscale
        }
    });
    let contrasts = field.as_ref().map(|_| stroke_contrast(image, valid));
    let dark_support = if field.is_none() {
        dark_stock_support(&analysis)
    } else {
        0.0
    };
    let light_contrasts = (dark_support > 0.0).then(|| light_stroke_contrast(image, valid));
    render(
        image,
        valid,
        field.as_ref(),
        adaptation,
        matches!(mode, ColorMode::Grayscale),
    );
    if let Some(contrasts) = contrasts {
        enhance_neutral_strokes(image, &contrasts);
    }
    if let Some(contrasts) = light_contrasts {
        enhance_light_strokes(image, &contrasts, dark_support);
    }
    Ok(mode)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn light_text_on_dark_stock_gains_contrast_without_lifting_the_stock() {
        for mode in [ColorMode::Color, ColorMode::Grayscale] {
            let mut page = image(384, 512, [24; 3]);
            for y in 80..420 {
                for x in 40..344 {
                    if y % 29 < 3 && x % 17 < 11 {
                        page.data[(y * 384 + x) * 3..(y * 384 + x + 1) * 3].fill(120);
                    }
                }
            }
            let original = page.clone();
            process(&mut page, None, Some(mode));
            let mut ink = 0.0;
            let mut count = 0;
            for (pixel, before) in page
                .data
                .as_chunks::<3>()
                .0
                .iter()
                .zip(original.data.as_chunks::<3>().0)
            {
                if before[0] == 120 {
                    ink += pixel[0] as f32;
                    count += 1;
                } else {
                    assert!(pixel[0].abs_diff(24) <= 1);
                }
            }
            assert!(ink / count as f32 - 24.0 >= 96.0 * 1.3);
        }
    }

    #[test]
    fn dark_stock_keeps_noise_panels_and_continuous_tones() {
        for stock in [[24; 3], [55; 3], [18, 29, 62]] {
            let mut page = image(384, 512, stock);
            for y in 0..512 {
                for x in 0..384 {
                    let noise = ((x * 17 + y * 11) % 5) as i16 - 2;
                    let mut rgb = stock.map(|value| (value as i16 + noise) as u8);
                    if (40..344).contains(&x) && (100..156).contains(&y) {
                        rgb = [((x - 40) * 255 / 303) as u8; 3];
                    }
                    for (i, gray) in [45, 96, 150, 208].into_iter().enumerate() {
                        if (32 + i * 84..96 + i * 84).contains(&x) && (300..364).contains(&y) {
                            rgb = [gray; 3];
                        }
                    }
                    page.data[(y * 384 + x) * 3..(y * 384 + x + 1) * 3]
                        .copy_from_slice(&[rgb[2], rgb[1], rgb[0]]);
                }
            }
            let original = page.clone();
            process(&mut page, None, Some(ColorMode::Color));
            for (index, (&actual, &expected)) in page.data.iter().zip(&original.data).enumerate() {
                assert_eq!(actual, expected, "stock {stock:?} at byte {index}");
            }
        }
    }

    #[test]
    fn light_stroke_tones_and_antialiasing_remain_monotonic() {
        for stock in [8u8, 24, 48] {
            let mut previous = [stock; 5];
            for ink in stock + 1..=255 {
                let mut page = image(192, 256, [stock; 3]);
                for y in 0..5 {
                    let coverage = [0.2, 0.5, 1.0, 0.7, 0.3][y];
                    let value = (stock as f32 + (ink - stock) as f32 * coverage).round() as u8;
                    for x in 50..142 {
                        page.data[((80 + y) * 192 + x) * 3..((80 + y) * 192 + x + 1) * 3]
                            .fill(value);
                    }
                }
                process(&mut page, None, Some(ColorMode::Grayscale));
                let profile: [u8; 5] =
                    std::array::from_fn(|y| page.data[((80 + y) * 192 + 96) * 3]);
                assert!(profile[0] <= profile[1] && profile[1] <= profile[2]);
                assert!(profile[2] >= profile[3] && profile[3] >= profile[4]);
                for (y, previous) in previous.iter_mut().enumerate() {
                    let actual = page.data[((80 + y) * 192 + 96) * 3];
                    assert!(
                        actual >= *previous,
                        "{stock}/{ink}/{y}: {actual} < {previous}"
                    );
                    *previous = actual;
                }
            }
        }
    }

    #[test]
    fn shaded_dark_colored_stock_keeps_hue_while_light_strokes_brighten() {
        let tables = transfer_tables();
        for stock in [[24; 3], [56; 3], [18, 28, 58]] {
            for ink in [[104; 3], [145, 107, 73], [80, 134, 175]] {
                let mut page = image(384, 512, stock);
                let mut strokes = vec![false; 384 * 512];
                for y in 0..512 {
                    for x in 0..384 {
                        let index = y * 384 + x;
                        let stroke = (40..344).contains(&x)
                            && (70..440).contains(&y)
                            && y % 29 < 3
                            && x % 17 < 11;
                        let rgb = if stroke { ink } else { stock };
                        let illumination = 0.55 + 0.4 * x as f32 / 384.0;
                        for (channel, value) in rgb.into_iter().enumerate() {
                            page.data[index * 3 + 2 - channel] = encode(
                                tables.decode[value as usize] * illumination,
                                &tables.encode,
                            );
                        }
                        strokes[index] = stroke;
                    }
                }
                let original = page.clone();
                process(&mut page, None, Some(ColorMode::Color));
                let mut before_sum = 0.0;
                let mut after_sum = 0.0;
                for ((pixel, before), stroke) in page
                    .data
                    .as_chunks::<3>()
                    .0
                    .iter()
                    .zip(original.data.as_chunks::<3>().0)
                    .zip(strokes)
                {
                    if stroke {
                        let rgb = pixel.map(|v| tables.decode[v as usize]);
                        let old_rgb = before.map(|v| tables.decode[v as usize]);
                        assert!(chroma_distance(chromaticity(rgb), chromaticity(old_rgb)) < 0.015);
                        before_sum += pixel_luma(*before);
                        after_sum += pixel_luma(*pixel);
                    } else {
                        assert_eq!(pixel, before);
                    }
                }
                assert!(after_sum > before_sum * 1.25);
            }
        }
    }

    fn pixel_luma(pixel: [u8; 3]) -> f32 {
        luminance([pixel[2] as f32, pixel[1] as f32, pixel[0] as f32])
    }

    #[test]
    fn dark_continuous_tone_images_retain_highlights_and_noise() {
        let mut page = image(384, 512, [0; 3]);
        for y in 0..512 {
            for x in 0..384 {
                let a = (-((x as f32 - 132.0).powi(2) + (y as f32 - 180.0).powi(2)) / 1800.0).exp();
                let b = (-((x as f32 - 260.0).powi(2) + (y as f32 - 330.0).powi(2)) / 3200.0).exp();
                let noise = ((x * 37 + y * 19) % 5) as f32 - 2.0;
                let rgb = [
                    22.0 + 116.0 * a + 32.0 * b + noise,
                    25.0 + 76.0 * a + 80.0 * b + noise,
                    31.0 + 60.0 * a + 126.0 * b + noise,
                ];
                for (channel, value) in rgb.into_iter().enumerate() {
                    page.data[(y * 384 + x) * 3 + 2 - channel] = value.round() as u8;
                }
            }
        }
        let original = page.clone();
        process(&mut page, None, Some(ColorMode::Color));
        let mut difference = 0u64;
        for (&actual, &expected) in page.data.iter().zip(&original.data) {
            let error = actual.abs_diff(expected);
            assert!(error <= 3, "{actual} versus {expected}");
            difference += error as u64;
        }
        assert!(difference as f64 / (page.data.len() as f64) < 0.1);
    }

    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Region {
        Paper,
        Ink,
        Faint,
        Color,
        Illustration,
    }

    struct Fixture {
        clean: ImageU8,
        shaded: ImageU8,
        regions: Vec<Region>,
    }

    fn process(image: &mut ImageU8, valid: Option<&[u8]>, mode: Option<ColorMode>) -> ColorMode {
        match render_document(image, valid, mode) {
            Ok(mode) => mode,
            Err(error) => panic!("{error}"),
        }
    }

    fn has_color(image: &ImageU8, valid: Option<&[u8]>) -> bool {
        meaningful_color(
            image,
            valid,
            paper_adaptation(&analyze(image, valid, ANALYSIS_LONG_EDGE)),
        )
    }

    fn image(width: usize, height: usize, rgb: [u8; 3]) -> ImageU8 {
        ImageU8 {
            width: width as i32,
            height: height as i32,
            channels: 3,
            data: [rgb[2], rgb[1], rgb[0]].repeat(width * height),
        }
    }

    fn document(width: usize, height: usize, stock: [u8; 3], color: bool) -> Fixture {
        let mut clean = image(width, height, stock);
        let mut shaded = clean.clone();
        let mut regions = vec![Region::Paper; width * height];
        let transfer = transfer_tables();
        for y in 0..height {
            for x in 0..width {
                let index = y * width + x;
                let mut rgb = stock;
                let nx = x as f32 / width as f32;
                let ny = y as f32 / height as f32;
                if (0.09..0.84).contains(&nx)
                    && (0.10..0.66).contains(&ny)
                    && y % 29 < 3
                    && x % 17 < 11
                {
                    rgb = [38; 3];
                    regions[index] = Region::Ink;
                }
                if (0.11..0.83).contains(&nx) && y == height * 7 / 10 {
                    rgb = stock.map(|value| value.saturating_sub(15));
                    regions[index] = Region::Faint;
                }
                if color && (0.77..0.87).contains(&ny) && (0.08..0.89).contains(&nx) {
                    let patch = ((nx - 0.08) / 0.21) as usize;
                    rgb = [[185, 33, 58], [21, 103, 206], [30, 163, 88], [239, 180, 38]]
                        [patch.min(3)];
                    regions[index] = Region::Color;
                }
                if color
                    && (0.34..0.37).contains(&ny)
                    && (0.08..0.89).contains(&nx)
                    && regions[index] == Region::Paper
                {
                    rgb = [244, 235, 120];
                    regions[index] = Region::Color;
                }
                let illumination = 0.37 + 0.55 * nx + 0.045 * (ny * 5.0).sin();
                for (channel, value) in rgb.into_iter().enumerate() {
                    clean.data[index * 3 + 2 - channel] = value;
                    shaded.data[index * 3 + 2 - channel] = encode(
                        transfer.decode[value as usize] * illumination,
                        &transfer.encode,
                    );
                }
            }
        }
        Fixture {
            clean,
            shaded,
            regions,
        }
    }

    fn region_mean(image: &ImageU8, regions: &[Region], region: Region) -> f32 {
        let mut sum = 0.0;
        let mut count = 0;
        for (pixel, &kind) in image.data.as_chunks::<3>().0.iter().zip(regions) {
            if kind == region {
                sum += pixel.iter().map(|&value| value as f32).sum::<f32>() / 3.0;
                count += 1;
            }
        }
        sum / count as f32
    }

    fn region_error(
        image: &ImageU8,
        reference: &ImageU8,
        regions: &[Region],
        region: Region,
    ) -> f32 {
        let mut sum = 0.0;
        let mut count = 0;
        for ((pixel, expected), &kind) in image
            .data
            .as_chunks::<3>()
            .0
            .iter()
            .zip(reference.data.as_chunks::<3>().0.iter())
            .zip(regions)
        {
            if kind == region {
                for channel in 0..3 {
                    sum += (pixel[channel] as f32 - expected[channel] as f32).abs();
                    count += 1;
                }
            }
        }
        sum / count as f32
    }

    fn paper_deviation(image: &ImageU8, regions: &[Region]) -> f32 {
        let mean = region_mean(image, regions, Region::Paper);
        let mut squared = 0.0;
        let mut count = 0;
        for (pixel, &kind) in image.data.as_chunks::<3>().0.iter().zip(regions) {
            if kind == Region::Paper {
                let value = pixel.iter().map(|&value| value as f32).sum::<f32>() / 3.0;
                squared += (value - mean).powi(2);
                count += 1;
            }
        }
        (squared / count as f32).sqrt()
    }

    #[test]
    fn restores_shaded_color_paper_without_erasing_faint_strokes() {
        let fixture = document(512, 704, [248; 3], true);
        let mut rendered = fixture.shaded.clone();
        let mode = process(&mut rendered, None, None);
        let paper_error = region_error(&rendered, &fixture.clean, &fixture.regions, Region::Paper);
        let color_error = region_error(&rendered, &fixture.clean, &fixture.regions, Region::Color);
        let deviation = paper_deviation(&rendered, &fixture.regions);
        let faint_contrast = region_mean(&rendered, &fixture.regions, Region::Paper)
            - region_mean(&rendered, &fixture.regions, Region::Faint);
        eprintln!(
            "neutral page: paper MAE {paper_error:.3}, color MAE {color_error:.3}, paper SD {deviation:.3}, faint contrast {faint_contrast:.3}"
        );
        assert!(matches!(mode, ColorMode::Color));
        assert!(paper_error < 7.0);
        assert!(color_error < 8.0);
        assert!(deviation < paper_deviation(&fixture.shaded, &fixture.regions) * 0.2);
        assert!(faint_contrast > 11.0);
        assert!(region_mean(&rendered, &fixture.regions, Region::Ink) < 48.0);
    }

    #[test]
    fn color_and_grayscale_share_the_same_paper_correction() {
        let fixture = document(384, 512, [248; 3], false);
        let mut color = fixture.shaded.clone();
        let mut gray = fixture.shaded;
        assert!(matches!(
            process(&mut color, None, Some(ColorMode::Color)),
            ColorMode::Color
        ));
        assert!(matches!(
            process(&mut gray, None, Some(ColorMode::Grayscale)),
            ColorMode::Grayscale
        ));
        assert_eq!(color.data, gray.data);
        assert!(paper_deviation(&gray, &fixture.regions) < 4.0);
    }

    #[test]
    fn shaded_colored_stock_preserves_its_tint_and_flattens_light() {
        let fixture = document(416, 608, [235, 211, 159], true);
        let mut rendered = fixture.shaded.clone();
        assert!(matches!(
            process(&mut rendered, None, None),
            ColorMode::Color
        ));
        let deviation = paper_deviation(&rendered, &fixture.regions);
        eprintln!("colored stock: paper SD {deviation:.3}");
        assert!(deviation < paper_deviation(&fixture.shaded, &fixture.regions) * 0.25);
        let pixel = &rendered.data[3 * (40 * 416 + 40)..][..3];
        assert!(pixel[2] > pixel[1] + 17);
        assert!(pixel[1] > pixel[0] + 38);
        let decode = &transfer_tables().decode;
        let expected = chromaticity([decode[235], decode[211], decode[159]]);
        let actual = chromaticity([
            decode[pixel[2] as usize],
            decode[pixel[1] as usize],
            decode[pixel[0] as usize],
        ]);
        assert!(chroma_distance(expected, actual) < 0.005);
    }

    #[test]
    fn small_stamp_on_monochrome_print_chooses_grayscale() {
        for stamp in [false, true] {
            let mut printed = document(160, 220, [244; 3], false).clean;
            if stamp {
                for y in 180..184 {
                    for x in 40..44 {
                        let offset = (y * 160 + x) * 3;
                        printed.data[offset..offset + 3].copy_from_slice(&[194, 32, 61]);
                    }
                }
            }
            assert!(matches!(
                process(&mut printed, None, None),
                ColorMode::Grayscale
            ));
        }
    }

    #[test]
    fn sparse_colored_writing_as_main_content_stays_color() {
        let mut signature = image(700, 1000, [244; 3]);
        for x in 230..249 {
            let offset = (720 * 700 + x) * 3;
            signature.data[offset..offset + 3].copy_from_slice(&[120, 60, 44]);
        }
        assert!(matches!(
            process(&mut signature, None, None),
            ColorMode::Color
        ));
    }

    #[test]
    fn stamp_decisions_follow_content_proportions_across_resolutions() {
        for (width, height) in [(192, 264), (576, 792), (1152, 1584)] {
            for stamp_width in [width / 50, width / 20, width / 10] {
                let mut printed = document(width, height, [244; 3], false).clean;
                for y in height * 4 / 5..height * 4 / 5 + stamp_width {
                    for x in width / 3..width / 3 + stamp_width {
                        printed.data[(y * width + x) * 3..][..3].copy_from_slice(&[173, 93, 66]);
                    }
                }
                let mut explicit = printed.clone();
                assert!(
                    matches!(process(&mut printed, None, None), ColorMode::Grayscale),
                    "{width}x{height}, stamp {stamp_width}"
                );
                assert!(
                    printed
                        .data
                        .as_chunks::<3>()
                        .0
                        .iter()
                        .all(|p| p[0] == p[1] && p[1] == p[2])
                );
                assert!(matches!(
                    process(&mut explicit, None, Some(ColorMode::Color)),
                    ColorMode::Color
                ));
                let pixel = &explicit.data[((height * 4 / 5) * width + width / 3) * 3..][..3];
                assert!(pixel[0] > pixel[2] + 60);
            }
        }
    }

    #[test]
    fn faint_colored_handwriting_is_distinct_from_an_accent_on_black_print() {
        for (width, height) in [(224, 320), (672, 960)] {
            for rgb in [[63, 82, 153], [191, 203, 227]] {
                let mut writing = image(width, height, [244; 3]);
                let mut printed = document(width, height, [244; 3], false).clean;
                let mut previous_y = (height * 4 / 5) as isize;
                for x in width / 4..width * 3 / 4 {
                    let y = (height * 4 / 5) as isize
                        + ((x as f32 / width as f32 * 80.0).sin() * 8.0) as isize;
                    for stroke_y in previous_y.min(y)..=previous_y.max(y) {
                        let index = stroke_y as usize * width + x;
                        writing.data[index * 3..][..3].copy_from_slice(&[rgb[2], rgb[1], rgb[0]]);
                        printed.data[index * 3..][..3].copy_from_slice(&[rgb[2], rgb[1], rgb[0]]);
                    }
                    previous_y = y;
                }
                for shadow in [false, true] {
                    let mut writing = writing.clone();
                    let mut printed = printed.clone();
                    if shadow {
                        for image in [&mut writing, &mut printed] {
                            for (index, pixel) in
                                image.data.as_chunks_mut::<3>().0.iter_mut().enumerate()
                            {
                                let illumination = if index % width < width / 2 {
                                    0.42
                                } else {
                                    0.91
                                };
                                for value in pixel {
                                    *value = encode(
                                        transfer_tables().decode[*value as usize] * illumination,
                                        &transfer_tables().encode,
                                    );
                                }
                            }
                        }
                    }
                    assert!(
                        matches!(process(&mut writing, None, None), ColorMode::Color),
                        "writing {width} {rgb:?} shadow {shadow}"
                    );
                    assert!(
                        matches!(process(&mut printed, None, None), ColorMode::Grayscale),
                        "accent {width} {rgb:?} shadow {shadow}"
                    );
                }
            }
        }
    }

    #[test]
    fn highlighted_monochrome_print_stays_color() {
        let mut page = document(384, 544, [244; 3], false).clean;
        for y in 181..197 {
            for x in 35..323 {
                let pixel = &mut page.data[(y * 384 + x) * 3..][..3];
                if pixel[0] > 220 {
                    pixel.copy_from_slice(&[103, 230, 242]);
                }
            }
        }
        assert!(matches!(process(&mut page, None, None), ColorMode::Color));
        let pixel = &page.data[(195 * 384 + 40) * 3..][..3];
        assert!(pixel[2] > pixel[0] + 100);
    }

    #[test]
    fn neutral_paper_cast_is_corrected_without_an_illumination_field() {
        let mut fixture = document(384, 544, [248; 3], true);
        let tables = transfer_tables();
        for (index, pixel) in fixture
            .shaded
            .data
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .enumerate()
        {
            let illumination = if index % 384 < 192 { 0.45 } else { 0.9 };
            for (channel, value) in pixel.iter_mut().enumerate() {
                *value = encode(
                    tables.decode[fixture.clean.data[index * 3 + channel] as usize]
                        * illumination
                        * [0.94, 1.01, 1.06][channel],
                    &tables.encode,
                );
            }
        }
        let analysis = analyze(&fixture.shaded, None, ANALYSIS_LONG_EDGE);
        let mut output = fixture.shaded;
        render(&mut output, None, None, paper_adaptation(&analysis), false);
        for x in [40, 340] {
            let paper = &output.data[(40 * 384 + x) * 3..][..3];
            assert!(
                paper.iter().max().expect("channel") - paper.iter().min().expect("channel") <= 2
            );
        }
        assert!(
            region_mean(&output, &fixture.regions, Region::Paper)
                - region_mean(&output, &fixture.regions, Region::Faint)
                > 10.0
        );
        for (actual, expected) in output
            .data
            .as_chunks::<3>()
            .0
            .iter()
            .zip(fixture.clean.data.as_chunks::<3>().0.iter())
        {
            if expected[0] as i16 - expected[2] as i16 > 100 {
                assert!(actual[0] as i16 - actual[2] as i16 > 75);
            }
        }
    }

    #[test]
    fn photograph_without_broad_paper_support_is_unchanged() {
        let mut photo = image(384, 512, [0; 3]);
        for y in 0..512 {
            for x in 0..384 {
                let index = (y * 384 + x) * 3;
                let noise = ((x * 37 + y * 73 + x * y * 7) % 25) as u8;
                let rgb = if y < 200 {
                    [65 + noise, 130 + noise, 190 + noise]
                } else {
                    [45 + noise, 68 + noise, 29 + noise]
                };
                photo.data[index..index + 3].copy_from_slice(&[rgb[2], rgb[1], rgb[0]]);
            }
        }
        let original = photo.data.clone();
        assert!(matches!(process(&mut photo, None, None), ColorMode::Color));
        assert_eq!(photo.data, original);
    }

    #[test]
    fn large_neutral_graphics_are_not_used_as_dark_paper() {
        let mut fixture = document(512, 704, [248; 3], false);
        let transfer = transfer_tables();
        for y in 300..530 {
            for x in 150..380 {
                let index = y * 512 + x;
                let illumination =
                    0.37 + 0.55 * x as f32 / 512.0 + 0.045 * (y as f32 / 704.0 * 5.0).sin();
                fixture.clean.data[index * 3..index * 3 + 3].fill(119);
                fixture.shaded.data[index * 3..index * 3 + 3].fill(encode(
                    transfer.decode[119] * illumination,
                    &transfer.encode,
                ));
                fixture.regions[index] = Region::Illustration;
            }
        }
        let mut rendered = fixture.shaded;
        process(&mut rendered, None, Some(ColorMode::Color));
        let error = region_error(
            &rendered,
            &fixture.clean,
            &fixture.regions,
            Region::Illustration,
        );
        eprintln!("neutral illustration MAE {error:.3}");
        assert!(region_mean(&rendered, &fixture.regions, Region::Illustration) < 132.0);
        assert!(error < 16.0);
    }

    #[test]
    fn missing_pixels_do_not_contribute_to_analysis_and_finish_neutral() {
        let fixture = document(256, 352, [248; 3], false);
        let mut first = fixture.shaded;
        let mut second = first.clone();
        let mut mask = vec![1; 256 * 352];
        for y in 0..352 {
            for x in 0..32 {
                let index = y * 256 + x;
                mask[index] = 0;
                first.data[index * 3..index * 3 + 3].copy_from_slice(&[255, 0, 128]);
                second.data[index * 3..index * 3 + 3].fill(0);
            }
        }
        process(&mut first, Some(&mask), None);
        process(&mut second, Some(&mask), None);
        assert_eq!(first.data, second.data);
        for (pixel, valid) in first.data.as_chunks::<3>().0.iter().zip(mask) {
            if valid == 0 {
                assert_eq!(*pixel, [255; 3]);
            }
        }
    }

    #[test]
    fn invalid_inputs_are_rejected_before_mutation() {
        let mut invalid = image(20, 20, [130; 3]);
        let original = invalid.clone();
        assert!(render_document(&mut invalid, Some(&[1; 7]), None).is_err());
        assert_eq!(invalid, original);
        invalid.width = i32::MAX;
        invalid.height = i32::MAX;
        let original = invalid.clone();
        assert!(render_document(&mut invalid, None, None).is_err());
        assert_eq!(invalid, original);
        invalid.width = 0;
        assert!(render_document(&mut invalid, None, None).is_err());
    }

    #[test]
    fn blank_degenerate_and_fully_masked_pages_are_safe() {
        for (width, height) in [(1, 1), (1, 400), (400, 1), (64, 96)] {
            for value in [0, 71, 176, 245, 255] {
                let mut blank = image(width, height, [value; 3]);
                assert!(matches!(
                    process(&mut blank, None, None),
                    ColorMode::Grayscale
                ));
                assert!(
                    blank
                        .data
                        .as_chunks::<3>()
                        .0
                        .iter()
                        .all(|pixel| pixel[0] == pixel[1] && pixel[1] == pixel[2])
                );
            }
        }
        let mut missing = image(32, 48, [97, 124, 48]);
        assert!(matches!(
            process(&mut missing, Some(&[0; 32 * 48]), None),
            ColorMode::Grayscale
        ));
        assert!(missing.data.iter().all(|&value| value == 255));
        for (width, height) in [(1, 1), (1, 2), (2, 1), (4, 4)] {
            let mut tiny = image(width, height, [184, 38, 91]);
            assert!(matches!(process(&mut tiny, None, None), ColorMode::Color));
        }
    }

    #[test]
    fn noise_does_not_erase_faint_paper_marks() {
        let mut fixture = document(384, 544, [248; 3], false);
        for (index, pixel) in fixture
            .shaded
            .data
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .enumerate()
        {
            let noise = ((index * 37 + index / 384 * 19) % 5) as i16 - 2;
            pixel
                .iter_mut()
                .for_each(|value| *value = (*value as i16 + noise).clamp(0, 255) as u8);
        }
        let mut output = fixture.shaded;
        process(&mut output, None, None);
        let faint_contrast = region_mean(&output, &fixture.regions, Region::Paper)
            - region_mean(&output, &fixture.regions, Region::Faint);
        assert!(faint_contrast > 10.0);
        assert!(paper_deviation(&output, &fixture.regions) < 5.0);
    }

    #[test]
    fn color_conversion_is_identity_without_a_field() {
        let mut pixels = image(256, 1, [0; 3]);
        for value in 0..256 {
            pixels.data[value * 3..value * 3 + 3].fill(value as u8);
        }
        let expected = pixels.data.clone();
        render(&mut pixels, None, None, [1.0; 3], true);
        assert_eq!(pixels.data, expected);
    }

    #[test]
    fn broad_faint_graphics_keep_their_contrast() {
        for value in [226, 236, 242] {
            let mut page = image(512, 704, [248; 3]);
            for y in 290..490 {
                for x in 140..350 {
                    page.data[(y * 512 + x) * 3..][..3].fill(value);
                }
            }
            process(&mut page, None, None);
            let paper = page.data[(250 * 512 + 245) * 3];
            let graphic = page.data[(390 * 512 + 245) * 3];
            eprintln!("faint graphic {value}: paper {paper}, graphic {graphic}");
            assert!(paper as i16 - graphic as i16 >= (248 - value as i16) * 3 / 4);
        }
    }

    #[test]
    fn embedded_photograph_receives_the_surrounding_paper_correction() {
        let mut fixture = document(448, 640, [248; 3], true);
        let transfer = transfer_tables();
        for y in 130..510 {
            for x in 90..360 {
                let index = y * 448 + x;
                let nx = x as f32 / 448.0;
                let ny = y as f32 / 640.0;
                let wave = (x as f32 * 0.073).sin() * (y as f32 * 0.052).cos();
                let rgb = [0.15 + 0.05 * wave, 0.35 + 0.13 * wave, 0.48 - 0.07 * wave];
                let illumination = 0.37 + 0.55 * nx + 0.045 * (ny * 5.0).sin();
                for (channel, value) in rgb.into_iter().enumerate() {
                    fixture.clean.data[index * 3 + 2 - channel] = encode(value, &transfer.encode);
                    fixture.shaded.data[index * 3 + 2 - channel] =
                        encode(value * illumination, &transfer.encode);
                }
                fixture.regions[index] = Region::Illustration;
            }
        }
        let mut output = fixture.shaded;
        process(&mut output, None, None);
        let error = region_error(
            &output,
            &fixture.clean,
            &fixture.regions,
            Region::Illustration,
        );
        eprintln!("embedded photograph MAE {error:.3}");
        assert!(error < 8.0);
    }

    #[test]
    fn held_out_illumination_shapes_and_neutral_casts_recover_the_reference() {
        let transfer = transfer_tables();
        for scenario in 0..3 {
            let mut fixture = document(480, 688, [248; 3], true);
            for (index, pixel) in fixture
                .shaded
                .data
                .as_chunks_mut::<3>()
                .0
                .iter_mut()
                .enumerate()
            {
                let x = (index % 480) as f32 / 480.0;
                let y = (index / 480) as f32 / 688.0;
                let illumination = match scenario {
                    0 => 0.65 + 0.24 * (y * 5.1 + 0.8).cos(),
                    1 => 0.91 - 0.47 * (-((x - 0.32).powi(2) + (y - 0.62).powi(2)) / 0.09).exp(),
                    _ => 0.36 + 0.55 * (0.3 * x + 0.7 * y),
                };
                for (channel, value) in pixel.iter_mut().enumerate() {
                    let cast = if scenario == 2 {
                        [0.975, 1.0, 1.025][channel]
                    } else {
                        1.0
                    };
                    *value = encode(
                        transfer.decode[fixture.clean.data[index * 3 + channel] as usize]
                            * illumination
                            * cast,
                        &transfer.encode,
                    );
                }
            }
            let mut output = fixture.shaded;
            process(&mut output, None, None);
            let paper = region_error(&output, &fixture.clean, &fixture.regions, Region::Paper);
            let color = region_error(&output, &fixture.clean, &fixture.regions, Region::Color);
            let deviation = paper_deviation(&output, &fixture.regions);
            eprintln!(
                "held-out lighting {scenario}: paper MAE {paper:.3}, color MAE {color:.3}, paper SD {deviation:.3}"
            );
            assert!(paper < 7.0);
            assert!(color < 10.0);
            assert!(deviation < 5.0);
        }
    }

    #[test]
    fn hard_shadow_boundaries_are_not_erased_as_paper() {
        let mut fixture = document(400, 560, [248; 3], true);
        let transfer = transfer_tables();
        for (index, pixel) in fixture
            .shaded
            .data
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .enumerate()
        {
            let illumination = if index % 400 < 170 { 0.42 } else { 0.91 };
            for (channel, value) in pixel.iter_mut().enumerate() {
                *value = encode(
                    transfer.decode[fixture.clean.data[index * 3 + channel] as usize]
                        * illumination,
                    &transfer.encode,
                );
            }
        }
        let mut output = fixture.shaded;
        process(&mut output, None, None);
        let faint_contrast = region_mean(&output, &fixture.regions, Region::Paper)
            - region_mean(&output, &fixture.regions, Region::Faint);
        assert!(faint_contrast > 10.0);
        assert!(region_mean(&output, &fixture.regions, Region::Ink) < 42.0);
        assert!(has_color(&output, None));
        assert!(region_error(&output, &fixture.clean, &fixture.regions, Region::Paper) < 7.0);
        assert!(paper_deviation(&output, &fixture.regions) < 5.0);
    }

    #[test]
    fn directional_shadow_edges_preserve_faint_ink_and_solid_bars() {
        let transfer = transfer_tables();
        for (width, height) in [(320, 448), (640, 896), (1280, 1792)] {
            for diagonal in [false, true] {
                let mut fixture = document(width, height, [248; 3], false);
                for y in height / 3..height * 2 / 5 {
                    for x in width / 8..width * 7 / 8 {
                        let index = y * width + x;
                        fixture.clean.data[index * 3..][..3].fill(30);
                        fixture.regions[index] = Region::Ink;
                    }
                }
                for (index, pixel) in fixture
                    .shaded
                    .data
                    .as_chunks_mut::<3>()
                    .0
                    .iter_mut()
                    .enumerate()
                {
                    let x = (index % width) as f32 / width as f32;
                    let y = (index / width) as f32 / height as f32;
                    let boundary = if diagonal { 0.2 + y * 0.55 } else { 0.43 };
                    let illumination = 0.33 + 0.56 * transition(x, boundary, boundary + 0.008);
                    for (channel, value) in pixel.iter_mut().enumerate() {
                        *value = encode(
                            transfer.decode[fixture.clean.data[index * 3 + channel] as usize]
                                * illumination,
                            &transfer.encode,
                        );
                    }
                }
                let mut output = fixture.shaded;
                process(&mut output, None, None);
                let paper_error =
                    region_error(&output, &fixture.clean, &fixture.regions, Region::Paper);
                let faint_contrast = region_mean(&output, &fixture.regions, Region::Paper)
                    - region_mean(&output, &fixture.regions, Region::Faint);
                let mut edge_error = 0.0;
                let mut count = 0;
                for (index, &region) in fixture.regions.iter().enumerate() {
                    let x = (index % width) as f32 / width as f32;
                    let y = (index / width) as f32 / height as f32;
                    let boundary = if diagonal { 0.2 + y * 0.55 } else { 0.43 };
                    if region == Region::Paper && (x - boundary).abs() < 0.025 {
                        edge_error += output.data[index * 3].abs_diff(248) as f32;
                        count += 1;
                    }
                }
                let edge_error = edge_error / count as f32;
                assert!(
                    paper_error < 7.0,
                    "{width} diagonal {diagonal}: {paper_error}"
                );
                assert!(
                    edge_error < 7.0,
                    "{width} diagonal {diagonal}: {edge_error}"
                );
                assert!(faint_contrast > 10.0, "{width}: {faint_contrast}");
                assert!(region_mean(&output, &fixture.regions, Region::Ink) < 44.0);
            }
        }
    }

    #[test]
    fn printed_gray_gradients_are_not_illumination_measurements() {
        let transfer = transfer_tables();
        for (low, high) in [(140.0, 210.0), (200.0, 232.0), (226.0, 242.0)] {
            let mut fixture = document(480, 688, [248; 3], false);
            for y in 220..490 {
                for x in 100..380 {
                    let index = y * 480 + x;
                    let value = (low + (high - low) * (x - 100) as f32 / 280.0) as u8;
                    let illumination =
                        0.37 + 0.55 * x as f32 / 480.0 + 0.045 * (y as f32 / 688.0 * 5.0).sin();
                    fixture.clean.data[index * 3..][..3].fill(value);
                    fixture.shaded.data[index * 3..][..3].fill(encode(
                        transfer.decode[value as usize] * illumination,
                        &transfer.encode,
                    ));
                    fixture.regions[index] = Region::Illustration;
                }
            }
            let mut output = fixture.shaded;
            process(&mut output, None, None);
            let error = region_error(
                &output,
                &fixture.clean,
                &fixture.regions,
                Region::Illustration,
            );
            assert!(error < 8.0, "gradient {low}..{high}: {error}");
        }
    }

    #[test]
    fn small_neutral_panels_preserve_contrast() {
        let transfer = transfer_tables();
        for edge in [16, 24, 32, 48, 64, 96] {
            for value in [128, 160, 192, 216, 232] {
                let mut fixture = document(512, 704, [248; 3], false);
                for y in 560..560 + edge {
                    for x in 200..200 + edge {
                        let index = y * 512 + x;
                        let illumination =
                            0.37 + 0.55 * x as f32 / 512.0 + 0.045 * (y as f32 / 704.0 * 5.0).sin();
                        fixture.clean.data[index * 3..][..3].fill(value);
                        fixture.shaded.data[index * 3..][..3].fill(encode(
                            transfer.decode[value as usize] * illumination,
                            &transfer.encode,
                        ));
                        fixture.regions[index] = Region::Illustration;
                    }
                }
                let mut output = fixture.shaded;
                process(&mut output, None, None);
                let contrast = region_mean(&output, &fixture.regions, Region::Paper)
                    - region_mean(&output, &fixture.regions, Region::Illustration);
                assert!(
                    contrast >= (248 - value) as f32 * 0.75,
                    "{edge}px panel {value}: contrast {contrast}"
                );
            }
        }
    }

    #[test]
    fn hard_shadows_on_colored_stock_preserve_chromaticity() {
        let mut fixture = document(400, 560, [235, 211, 159], true);
        let transfer = transfer_tables();
        for (index, pixel) in fixture
            .shaded
            .data
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .enumerate()
        {
            let illumination = if index % 400 < 180 { 0.4 } else { 0.91 };
            for (channel, value) in pixel.iter_mut().enumerate() {
                *value = encode(
                    transfer.decode[fixture.clean.data[index * 3 + channel] as usize]
                        * illumination,
                    &transfer.encode,
                );
            }
        }
        let mut output = fixture.shaded;
        assert!(matches!(process(&mut output, None, None), ColorMode::Color));
        assert!(paper_deviation(&output, &fixture.regions) < 4.0);
        let expected = chromaticity([
            transfer.decode[235],
            transfer.decode[211],
            transfer.decode[159],
        ]);
        for x in [40, 340] {
            let pixel = &output.data[(40 * 400 + x) * 3..][..3];
            let actual = chromaticity([
                transfer.decode[pixel[2] as usize],
                transfer.decode[pixel[1] as usize],
                transfer.decode[pixel[0] as usize],
            ]);
            assert!(chroma_distance(expected, actual) < 0.005);
        }
    }

    #[test]
    fn ambiguous_strong_illumination_and_colored_stock_keep_their_tint() {
        for tint in [[248, 214, 171], [188, 221, 248], [243, 220, 238]] {
            let mut page = image(320, 448, tint);
            process(&mut page, None, None);
            let original = [tint[2], tint[1], tint[0]];
            assert!(
                page.data
                    .as_chunks::<3>()
                    .0
                    .iter()
                    .all(|pixel| pixel.iter().zip(original).all(|(&a, b)| a.abs_diff(b) <= 1))
            );
            assert!(has_color(&page, None));
        }
    }

    #[test]
    fn monochrome_photographic_tones_do_not_become_white_paper() {
        let mut photo = image(384, 512, [0; 3]);
        let transfer = transfer_tables();
        for (index, pixel) in photo.data.as_chunks_mut::<3>().0.iter_mut().enumerate() {
            let x = (index % 384) as f32 / 384.0;
            let y = (index / 384) as f32 / 512.0;
            let tone = 0.27
                + 0.16 * (x * 8.0 + y * 3.0).sin() * (y * 7.0).cos()
                + 0.06 * (x * 18.0 - y * 14.0).cos();
            pixel.fill(encode(tone, &transfer.encode));
        }
        for caption in [false, true] {
            let mut photo = photo.clone();
            if caption {
                for y in 425..485 {
                    for x in 30..345 {
                        if y % 12 < 3 && x % 17 < 11 {
                            photo.data[(y * 384 + x) * 3..][..3].fill(25);
                        }
                    }
                }
            }
            let before = photo.data.clone();
            process(&mut photo, None, None);
            let change = photo
                .data
                .iter()
                .zip(before)
                .map(|(&a, b)| a.abs_diff(b) as f32)
                .sum::<f32>()
                / photo.data.len() as f32;
            assert!(change < 3.0, "caption {caption}: {change}");
        }
    }

    #[test]
    fn clipped_reflections_do_not_set_the_paper_level() {
        let mut page = image(320, 448, [235; 3]);
        for y in 150..300 {
            for x in 130..260 {
                page.data[(y * 320 + x) * 3..][..3].fill(255);
            }
        }
        let analysis = analyze(&page, None, ANALYSIS_LONG_EDGE);
        assert!(
            analysis
                .samples
                .iter()
                .filter(|sample| sample.unclipped == 0.0)
                .all(|sample| sample.smoothness == 0.0)
        );
        process(&mut page, None, None);
        let paper = page.data[(30 * 320 + 30) * 3];
        assert!((250..=252).contains(&paper));
        assert_eq!(page.data[(200 * 320 + 200) * 3], 255);
    }

    #[test]
    fn equally_supported_ink_preserves_tonal_order() {
        let mut previous = [0; 5];
        for ink in 0..248 {
            let mut page = image(192, 256, [248; 3]);
            for y in 50..220 {
                for x in 32..160 {
                    if y % 16 < 5 && x % 11 < 7 {
                        let coverage = [0.25, 0.75, 1.0, 0.75, 0.25][y % 16];
                        let value = (248.0 - (248 - ink) as f32 * coverage).round() as u8;
                        page.data[(y * 192 + x) * 3..][..3].fill(value);
                    }
                }
            }
            process(&mut page, None, Some(ColorMode::Grayscale));
            let profile =
                std::array::from_fn::<_, 5, _>(|offset| page.data[((64 + offset) * 192 + 48) * 3]);
            for (actual, before) in profile.into_iter().zip(previous) {
                assert!(actual >= before, "ink {ink}: {before} -> {actual}");
            }
            assert!(profile[0] >= profile[1] && profile[1] >= profile[2]);
            assert!(profile[2] <= profile[3] && profile[3] <= profile[4]);
            previous = profile;
        }
    }

    #[test]
    fn faint_neutral_strokes_gain_contrast_without_amplifying_paper_noise() {
        for scale in [1, 2, 4] {
            let width = 160 * scale;
            let height = 224 * scale;
            for ink in [224u8, 232, 240] {
                let mut page = image(width, height, [248; 3]);
                let mut strokes = vec![false; width * height];
                for y in 0..height {
                    for x in 0..width {
                        let index = y * width + x;
                        let noise = ((x / scale * 13 + y / scale * 7) % 3) as i16 - 1;
                        let stroke = (30 * scale..190 * scale).contains(&y)
                            && (20 * scale..140 * scale).contains(&x)
                            && y % (16 * scale) < 2 * scale
                            && x % (9 * scale) < 6 * scale;
                        let value = if stroke { ink } else { 248 };
                        page.data[index * 3..][..3].fill((value as i16 + noise) as u8);
                        strokes[index] = stroke;
                    }
                }
                process(&mut page, None, Some(ColorMode::Grayscale));
                let mut paper = Vec::new();
                let mut marked = Vec::new();
                for (pixel, stroke) in page.data.as_chunks::<3>().0.iter().zip(strokes) {
                    if stroke {
                        marked.push(pixel[0] as f32);
                    } else {
                        paper.push(pixel[0] as f32);
                    }
                }
                let paper_mean = paper.iter().sum::<f32>() / paper.len() as f32;
                let ink_mean = marked.iter().sum::<f32>() / marked.len() as f32;
                let deviation = (paper
                    .iter()
                    .map(|value| (value - paper_mean).powi(2))
                    .sum::<f32>()
                    / paper.len() as f32)
                    .sqrt();
                assert!(
                    paper_mean - ink_mean >= (248 - ink) as f32 * 1.6,
                    "scale {scale}, ink {ink}: {}",
                    paper_mean - ink_mean
                );
                assert!(deviation < 3.0, "scale {scale}, ink {ink}: {deviation}");
            }
        }
    }

    #[test]
    #[ignore = "appearance calibration and timing report"]
    fn analysis_resolution_calibration() {
        for (width, height) in [(836, 1196), (1180, 1694), (1668, 2396)] {
            let fixture = document(width, height, [248; 3], true);
            for long_edge in [192, 288, 384, 512] {
                let mut elapsed = Vec::new();
                let mut output = fixture.shaded.clone();
                let mut samples = 0;
                for _ in 0..11 {
                    output.data.copy_from_slice(&fixture.shaded.data);
                    let start = std::time::Instant::now();
                    let analysis = analyze(&output, None, long_edge);
                    samples = analysis.samples.len();
                    let field = estimate_field(&analysis);
                    render(
                        &mut output,
                        None,
                        field.as_ref(),
                        paper_adaptation(&analysis),
                        false,
                    );
                    assert!(has_color(&output, None));
                    elapsed.push(start.elapsed().as_secs_f64() * 1000.0);
                }
                elapsed.sort_unstable_by(f64::total_cmp);
                let paper = region_error(&output, &fixture.clean, &fixture.regions, Region::Paper);
                let color = region_error(&output, &fixture.clean, &fixture.regions, Region::Color);
                let deviation = paper_deviation(&output, &fixture.regions);
                eprintln!(
                    "{} pixels, analysis {long_edge}, sample bytes {}, median {:.3} ms, p95 {:.3} ms, paper MAE {paper:.3}, color MAE {color:.3}, paper SD {deviation:.3}",
                    width * height,
                    samples * std::mem::size_of::<Sample>(),
                    elapsed[5],
                    elapsed[10]
                );
            }
        }
    }
}
