use ort::session::{Session, SessionInputValue};
use ort::value::{Tensor, TensorRef};

use crate::onnx::{SessionRunError, SessionRunResult};

#[derive(Clone)]
pub(super) struct SharedValues(std::sync::Arc<Vec<f32>>);

impl std::ops::Deref for SharedValues {
    type Target = Vec<f32>;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl std::ops::DerefMut for SharedValues {
    fn deref_mut(&mut self) -> &mut Self::Target {
        std::sync::Arc::make_mut(&mut self.0)
    }
}

#[derive(Clone)]
pub(super) struct Input {
    pub name: String,
    pub shape: Vec<i64>,
    pub values: SharedValues,
}

impl Input {
    pub fn zeros(name: impl Into<String>, shape: &[usize]) -> Self {
        Self {
            name: name.into(),
            shape: shape.iter().map(|&v| v as i64).collect(),
            values: SharedValues(std::sync::Arc::new(vec![0.0; shape.iter().product()])),
        }
    }
}

pub(super) fn infer(
    session: &mut Session,
    inputs: &[Input],
) -> SessionRunResult<(Vec<i64>, Vec<f32>)> {
    let tensors: Result<Vec<_>, _> = inputs
        .iter()
        .map(|input| {
            if input.name.starts_with("path_") {
                return Tensor::from_array((input.shape.clone(), vec![input.values[0] != 0.0]))
                    .map(|tensor| (input.name.as_str(), SessionInputValue::from(tensor)));
            }
            TensorRef::from_array_view((input.shape.as_slice(), input.values.as_slice()))
                .map(|tensor| (input.name.as_str(), SessionInputValue::from(tensor)))
        })
        .collect();
    let tensors = tensors?;
    let result = session.run(tensors);
    let outputs = result.map_err(SessionRunError::from_inference_error)?;
    let (shape, values) = outputs[0].try_extract_tensor::<f32>()?;
    Ok((shape.to_vec(), values.to_vec()))
}

pub(super) fn detector(raw: &[f32], height: usize, width: usize) -> Vec<Input> {
    let side = 960;
    let mut image = Input::zeros("x", &[1, 3, side, side]);
    for channel in 0..3 {
        for y in 0..height {
            let source = (channel * height + y) * width;
            let target = (channel * side + y) * side;
            image.values[target..target + width].copy_from_slice(&raw[source..source + width]);
        }
    }
    detector_paths(image, height, width)
}

pub(super) struct Line {
    pub values: Vec<f32>,
    pub width: usize,
    pub content_width: i32,
}

pub(super) fn packed(lines: &[&Line], width: usize, slots: usize) -> (Vec<Input>, Vec<usize>) {
    let mut image = Input::zeros("x", &[1, 3, 48, width]);
    let mut positions = Vec::with_capacity(lines.len());
    let mut cursor = 0;
    for line in lines {
        for row in 0..3 * 48 {
            let source = row * line.width;
            let target = row * width + cursor;
            image.values[target..target + line.width]
                .copy_from_slice(&line.values[source..source + line.width]);
        }
        positions.push(cursor);
        cursor += line.width.div_ceil(8) * 8 + 16;
    }
    let mut inputs = vec![image];
    for (height, scale) in [(48, 1), (24, 2), (12, 2), (12, 4), (6, 4), (3, 4), (1, 8)] {
        let size = width / scale;
        let mut input = Input::zeros(format!("mask_{height}_{size}"), &[1, 1, 1, size]);
        for (line, &offset) in lines.iter().zip(&positions) {
            let count = if scale == 8 {
                line.width.div_ceil(4) / 2
            } else {
                line.width.div_ceil(scale)
            };
            input.values[offset / scale..offset / scale + count].fill(1.0);
        }
        inputs.push(input);
    }
    let size = width / 4;
    let mut pool = Input::zeros(format!("pool_weights_{size}"), &[1, size, slots]);
    let mut gate = Input::zeros(format!("gate_weights_{size}"), &[1, slots, size]);
    for (slot, (line, &offset)) in lines.iter().zip(&positions).enumerate() {
        let count = line.width.div_ceil(4);
        for x in offset / 4..offset / 4 + count {
            pool.values[x * slots + slot] = 1.0 / count as f32;
            gate.values[slot * size + x] = 1.0;
        }
    }
    inputs.extend([pool, gate]);
    let steps = width / 8;
    let mut attention = Input::zeros("attention_bias", &[1, 1, steps, steps]);
    attention.values.fill(-10000.0);
    for query in 0..steps {
        attention.values[query * steps] = 0.0;
    }
    for (line, &offset) in lines.iter().zip(&positions) {
        let count = line.width.div_ceil(4) / 2;
        let start = offset / 8;
        for query in start..start + count {
            let row = &mut attention.values[query * steps..(query + 1) * steps];
            row.fill(-10000.0);
            row[start..start + count].fill(0.0);
        }
    }
    inputs.push(attention);
    (inputs, positions)
}

fn detector_auxiliary(index: usize, height: usize, width: usize, h: usize, w: usize) -> Vec<Input> {
    let mut inputs = Vec::new();
    for scale in [1, 2, 4, 8, 16, 32] {
        let mh = h / scale;
        let mw = w / scale;
        let mut mask = Input::zeros(format!("p{index}_mask_{mh}_{mw}"), &[1, 1, mh, mw]);
        for y in 0..height / scale {
            mask.values[y * mw..y * mw + width / scale].fill(1.0);
        }
        inputs.push(mask);
        if scale >= 4 {
            let mut value = Input::zeros(format!("p{index}_pool_scale_{mh}_{mw}"), &[1, 1, 1, 1]);
            value.values[0] = if height > 0 && width > 0 {
                (h * w) as f32 / (height * width) as f32
            } else {
                1.0
            };
            inputs.push(value);
        }
    }
    inputs
}

fn detector_paths(image: Input, height: usize, width: usize) -> Vec<Input> {
    static UNUSED: std::sync::OnceLock<Vec<Vec<Input>>> = std::sync::OnceLock::new();
    let shapes = &[(960, 480), (480, 960), (960, 704), (704, 960), (960, 960)];
    let unused = UNUSED.get_or_init(|| {
        shapes
            .iter()
            .enumerate()
            .map(|(i, &(h, w))| detector_auxiliary(i, 0, 0, h, w))
            .collect()
    });
    let selected = shapes
        .iter()
        .position(|&(h, w)| height <= h && width <= w)
        .unwrap_or(shapes.len() - 1);
    let mut inputs = vec![image];
    for (index, &(h, w)) in shapes.iter().enumerate() {
        inputs.extend(if index == selected {
            detector_auxiliary(index, height, width, h, w)
        } else {
            unused[index].clone()
        });
        if index < shapes.len() - 1 {
            let mut flag = Input::zeros(format!("path_{index}"), &[]);
            flag.values[0] = if selected == index { 1.0 } else { 0.0 };
            inputs.push(flag);
        }
    }
    inputs
}

pub(super) fn branch_widths() -> &'static [usize] {
    &[2048, 7168]
}

pub(super) fn recognizer_paths(mut selected: Vec<Input>, width: usize) -> Vec<Input> {
    let mut original = selected.remove(0);
    let mut image = Input::zeros("x", &[1, 3, 48, 7168]);
    if width == 7168 {
        std::mem::swap(&mut image.values, &mut original.values);
    } else {
        for row in 0..3 * 48 {
            image.values[row * 7168..row * 7168 + width]
                .copy_from_slice(&original.values[row * width..(row + 1) * width]);
        }
    }
    static UNUSED: std::sync::OnceLock<Vec<Vec<Input>>> = std::sync::OnceLock::new();
    let widths = branch_widths();
    let unused = UNUSED.get_or_init(|| {
        widths
            .iter()
            .map(|&w| {
                let (mut values, _) = packed(&[], w, w / 336);
                values.remove(0);
                values
            })
            .collect()
    });
    let mut inputs = vec![image];
    for (index, &branch_width) in widths.iter().enumerate() {
        let mut values = if branch_width == width {
            std::mem::take(&mut selected)
        } else {
            unused[index].clone()
        };
        for input in &mut values {
            input.name = format!("p{index}_{}", input.name);
        }
        inputs.extend(values);
    }
    for (index, &w) in widths.iter().enumerate().take(widths.len() - 1) {
        let mut flag = Input::zeros(format!("path_{index}"), &[]);
        flag.values[0] = if width == w { 1.0 } else { 0.0 };
        inputs.push(flag);
    }
    inputs
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input<'a>(inputs: &'a [Input], name: &str) -> &'a Input {
        inputs.iter().find(|input| input.name == name).unwrap()
    }

    #[test]
    fn detector_masks_preserve_area_at_every_scale_and_choose_the_smallest_path() {
        for (height, width, path) in [
            (32, 32, 0),
            (960, 480, 0),
            (448, 960, 1),
            (960, 672, 2),
            (704, 960, 3),
            (960, 736, 4),
        ] {
            let raw = vec![0.5; 3 * height * width];
            let inputs = detector(&raw, height, width);
            let image = input(&inputs, "x");
            assert_eq!(image.shape, [1, 3, 960, 960]);
            for channel in 0..3 {
                for row in 0..960 {
                    let pixels =
                        &image.values[(channel * 960 + row) * 960..(channel * 960 + row + 1) * 960];
                    if row < height {
                        assert!(pixels[..width].iter().all(|&v| v == 0.5));
                        assert!(pixels[width..].iter().all(|&v| v == 0.0));
                    } else {
                        assert!(pixels.iter().all(|&v| v == 0.0));
                    }
                }
            }
            for index in 0..4 {
                assert_eq!(
                    input(&inputs, &format!("path_{index}")).values[0],
                    f32::from(index == path)
                );
            }
            let prefix = format!("p{path}_mask_");
            for mask in inputs
                .iter()
                .filter(|input| input.name.starts_with(&prefix))
            {
                let scale = match path {
                    1 => 480,
                    3 => 704,
                    _ => 960,
                } / mask.shape[2] as usize;
                assert_eq!(
                    mask.values.iter().filter(|&&v| v == 1.0).count(),
                    height * width / (scale * scale)
                );
                let scale_name = mask.name.replace("mask", "pool_scale");
                if let Some(pool_scale) = inputs.iter().find(|input| input.name == scale_name) {
                    let active = height * width / (scale * scale);
                    assert!(
                        (pool_scale.values[0] * active as f32 / mask.values.len() as f32 - 1.0)
                            .abs()
                            < 1e-6
                    );
                }
            }
        }
    }

    #[test]
    fn packing_isolates_odd_width_lines_in_pooling_and_attention() {
        let lines: Vec<_> = [321, 327]
            .into_iter()
            .map(|width| Line {
                values: vec![0.25; 3 * 48 * width],
                width,
                content_width: width as i32,
            })
            .collect();
        let (inputs, offsets) = packed(&[&lines[0], &lines[1]], 2048, 6);
        assert_eq!(offsets, [0, 344]);
        let mask = input(&inputs, "mask_1_256");
        assert_eq!(mask.values.iter().filter(|&&v| v == 1.0).count(), 81);
        let attention = input(&inputs, "attention_bias");
        for (line, &offset) in lines.iter().zip(&offsets) {
            let start = offset / 8;
            let count = line.width.div_ceil(4) / 2;
            for query in start..start + count {
                let row = &attention.values[query * 256..(query + 1) * 256];
                assert!(row[start..start + count].iter().all(|&v| v == 0.0));
                assert!(
                    row[..start]
                        .iter()
                        .chain(&row[start + count..])
                        .all(|&v| v == -10000.0)
                );
            }
        }
        let pool = input(&inputs, "pool_weights_512");
        for slot in 0..2 {
            let sum: f32 = pool.values.iter().skip(slot).step_by(6).sum();
            assert!((sum - 1.0).abs() < 1e-6);
        }
        let lifted = recognizer_paths(inputs, 2048);
        assert_eq!(input(&lifted, "x").shape, [1, 3, 48, 7168]);
        assert_eq!(input(&lifted, "path_0").values[0], 1.0);
        assert_eq!(input(&lifted, "p1_attention_bias").shape, [1, 1, 896, 896]);
    }

    #[test]
    fn packing_preserves_the_last_step_at_the_maximum_width() {
        for width in [7167, 7168] {
            let line = Line {
                values: vec![0.5; 3 * 48 * width],
                width,
                content_width: width as i32,
            };
            let (inputs, offsets) = packed(&[&line], 7168, 21);
            assert_eq!(offsets, [0]);
            assert_eq!(input(&inputs, "mask_1_896").values[895], 1.0);
            assert_eq!(
                input(&recognizer_paths(inputs, 7168), "path_0").values[0],
                0.0
            );
        }
    }
}
