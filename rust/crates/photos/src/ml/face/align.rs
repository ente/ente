use image::{ImageBuffer, Rgb, RgbImage};
use imageproc::geometric_transformations::{Interpolation, Projection, warp_into};
use nalgebra::{Matrix2, Matrix3, Vector2};

use crate::ml::{
    error::{MlError, MlResult},
    types::{AlignmentResult, DecodedImage, FaceDetection, FaceResult, to_face_id},
};

use super::FACE_INPUT_SIZE;

const LAPLACIAN_HARD_THRESHOLD: f32 = 10.0;
const REMOVE_SIDE_COLUMNS: usize = 56;
const MOBILEFACENET_NORMALIZATION_SCALE: f32 = 1.0 / 127.5;

const MOBILEFACENET_IDEAL_5_LANDMARKS: [[f32; 2]; 5] = [
    [38.2946 / 112.0, 51.6963 / 112.0],
    [73.5318 / 112.0, 51.5014 / 112.0],
    [56.0252 / 112.0, 71.7366 / 112.0],
    [41.5493 / 112.0, 92.3655 / 112.0],
    [70.7299 / 112.0, 92.2041 / 112.0],
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FaceDirection {
    Left,
    Right,
    Straight,
}

#[derive(Clone, Debug)]
struct FaceDetectionAbsolute {
    keypoints: [[f32; 2]; 5],
}

pub(crate) fn run_face_alignment(
    file_id: i64,
    decoded: &mut DecodedImage,
    detections: Vec<FaceDetection>,
) -> MlResult<(Vec<Vec<f32>>, Vec<FaceResult>)> {
    let image_width = decoded.dimensions.width;
    let image_height = decoded.dimensions.height;
    let source = take_rgb_image(decoded)?;
    let mut aligned_face_inputs = Vec::with_capacity(detections.len());
    let mut face_results = Vec::with_capacity(detections.len());

    let result = (|| {
        for detection in detections {
            let absolute_detection = to_absolute_detection(&detection, image_width, image_height);
            let alignment = estimate_similarity_transform(&absolute_detection.keypoints)?;
            let aligned = warp_face_image(&source, &alignment.affine_matrix)?;
            let normalized = normalize_face_rgb_for_mobilefacenet(&aligned);
            let blur_value = compute_blur_value(&aligned, face_direction(&absolute_detection));
            let face_id = to_face_id(file_id, detection.box_xyxy);

            aligned_face_inputs.push(normalized);
            face_results.push(FaceResult {
                detection,
                blur_value,
                alignment,
                embedding: Vec::new(),
                face_id,
            });
        }

        Ok((aligned_face_inputs, face_results))
    })();

    // `imageproc::warp_into` requires an owned `RgbImage`. Put its allocation
    // back so later indexing stages continue to borrow the decoded pixels.
    decoded.rgb = source.into_raw();
    result
}

fn take_rgb_image(decoded: &mut DecodedImage) -> MlResult<RgbImage> {
    let expected_len = (decoded.dimensions.width as usize)
        .checked_mul(decoded.dimensions.height as usize)
        .and_then(|pixels| pixels.checked_mul(3))
        .ok_or_else(|| MlError::Preprocess("RGB source dimensions overflow".to_string()))?;
    if decoded.rgb.len() != expected_len {
        return Err(MlError::Preprocess(format!(
            "invalid RGB source length: expected {expected_len}, got {}",
            decoded.rgb.len()
        )));
    }

    let rgb = std::mem::take(&mut decoded.rgb);
    Ok(ImageBuffer::<Rgb<u8>, _>::from_raw(
        decoded.dimensions.width,
        decoded.dimensions.height,
        rgb,
    )
    .expect("validated RGB source dimensions and length"))
}

fn to_absolute_detection(
    detection: &FaceDetection,
    image_width: u32,
    image_height: u32,
) -> FaceDetectionAbsolute {
    let width = image_width as f32;
    let height = image_height as f32;
    let mut keypoints = [[0.0f32; 2]; 5];
    for (i, point) in detection.keypoints.iter().enumerate() {
        keypoints[i] = [point[0] * width, point[1] * height];
    }

    FaceDetectionAbsolute { keypoints }
}

fn estimate_similarity_transform(src_points: &[[f32; 2]; 5]) -> MlResult<AlignmentResult> {
    let src_mean = mean_2d(src_points);
    let dst_mean = mean_2d(&MOBILEFACENET_IDEAL_5_LANDMARKS);
    let n = src_points.len() as f32;

    let mut a = Matrix2::<f32>::zeros();
    let mut src_var_sum = 0.0f32;
    for (src, dst) in src_points
        .iter()
        .zip(MOBILEFACENET_IDEAL_5_LANDMARKS.iter())
    {
        let src_d = Vector2::new(src[0] - src_mean.x, src[1] - src_mean.y);
        let dst_d = Vector2::new(dst[0] - dst_mean.x, dst[1] - dst_mean.y);
        a += dst_d * src_d.transpose();
        src_var_sum += src_d.dot(&src_d);
    }
    a /= n;
    src_var_sum /= n;

    let mut d = Vector2::new(1.0f32, 1.0f32);
    if a.determinant() < 0.0 {
        d[1] = -1.0;
    }

    let svd = a.svd(true, true);
    let u = svd
        .u
        .ok_or_else(|| MlError::Postprocess("SVD failed to produce U".to_string()))?;
    let v_t = svd
        .v_t
        .ok_or_else(|| MlError::Postprocess("SVD failed to produce V^T".to_string()))?;
    let singular = svd.singular_values;

    let rank = singular.iter().filter(|v| **v > 1e-6).count();
    if rank == 0 {
        return Err(MlError::Postprocess(
            "failed to estimate similarity transform (rank=0)".to_string(),
        ));
    }

    let r;
    if rank == 1 {
        if u.determinant() * v_t.transpose().determinant() > 0.0 {
            r = u * v_t;
        } else {
            let mut d_local = d;
            let last = d_local[1];
            d_local[1] = -1.0;
            r = u * Matrix2::new(d_local[0], 0.0, 0.0, d_local[1]) * v_t;
            d[1] = last;
        }
    } else {
        r = u * Matrix2::new(d[0], 0.0, 0.0, d[1]) * v_t;
    }

    let scale = if src_var_sum <= f32::EPSILON {
        1.0
    } else {
        (singular[0] * d[0] + singular[1] * d[1]) / src_var_sum
    };

    let src_mean_v = Vector2::new(src_mean.x, src_mean.y);
    let dst_mean_v = Vector2::new(dst_mean.x, dst_mean.y);
    let translation = dst_mean_v - (r * src_mean_v) * scale;

    let mut t = Matrix3::<f32>::identity();
    let r_scaled = r * scale;
    t[(0, 0)] = r_scaled[(0, 0)];
    t[(0, 1)] = r_scaled[(0, 1)];
    t[(1, 0)] = r_scaled[(1, 0)];
    t[(1, 1)] = r_scaled[(1, 1)];
    t[(0, 2)] = translation[0];
    t[(1, 2)] = translation[1];

    let size = if scale.abs() < f32::EPSILON {
        1.0
    } else {
        1.0 / scale
    };
    let rotation = r[(1, 0)].atan2(r[(0, 0)]);
    let mean_translation = (dst_mean_v - Vector2::new(0.5, 0.5)) * size;
    let center = src_mean_v - mean_translation;

    Ok(AlignmentResult {
        affine_matrix: [
            [t[(0, 0)], t[(0, 1)], t[(0, 2)]],
            [t[(1, 0)], t[(1, 1)], t[(1, 2)]],
            [t[(2, 0)], t[(2, 1)], t[(2, 2)]],
        ],
        center: [center[0], center[1]],
        size,
        rotation,
    })
}

fn mean_2d(points: &[[f32; 2]]) -> Vector2<f32> {
    let mut sum = Vector2::new(0.0f32, 0.0f32);
    for point in points {
        sum[0] += point[0];
        sum[1] += point[1];
    }
    sum / points.len() as f32
}

fn warp_face_image(source: &RgbImage, affine_matrix: &[[f32; 3]; 3]) -> MlResult<RgbImage> {
    let mut transform = [[0.0f32; 3]; 3];
    for row in 0..3 {
        for col in 0..3 {
            let value = affine_matrix[row][col];
            transform[row][col] = if (value - 1.0).abs() <= f32::EPSILON {
                1.0
            } else {
                value * FACE_INPUT_SIZE as f32
            };
        }
    }

    let projection = Projection::from_matrix([
        transform[0][0],
        transform[0][1],
        transform[0][2],
        transform[1][0],
        transform[1][1],
        transform[1][2],
        transform[2][0],
        transform[2][1],
        transform[2][2],
    ])
    .ok_or_else(|| MlError::Postprocess("invalid affine matrix projection".to_string()))?;

    let mut output = RgbImage::from_pixel(FACE_INPUT_SIZE, FACE_INPUT_SIZE, Rgb([114, 114, 114]));
    warp_into(
        source,
        &projection,
        Interpolation::Bicubic,
        Rgb([114, 114, 114]),
        &mut output,
    );
    Ok(output)
}

fn normalize_face_rgb_for_mobilefacenet(face_image: &RgbImage) -> Vec<f32> {
    let mut output = Vec::with_capacity((FACE_INPUT_SIZE * FACE_INPUT_SIZE * 3) as usize);
    for y in 0..FACE_INPUT_SIZE {
        for x in 0..FACE_INPUT_SIZE {
            let px = face_image.get_pixel(x, y).0;
            output.push(px[0] as f32 * MOBILEFACENET_NORMALIZATION_SCALE - 1.0);
            output.push(px[1] as f32 * MOBILEFACENET_NORMALIZATION_SCALE - 1.0);
            output.push(px[2] as f32 * MOBILEFACENET_NORMALIZATION_SCALE - 1.0);
        }
    }
    output
}

fn face_direction(detection: &FaceDetectionAbsolute) -> FaceDirection {
    let left_eye = detection.keypoints[0];
    let right_eye = detection.keypoints[1];
    let nose = detection.keypoints[2];
    let left_mouth = detection.keypoints[3];
    let right_mouth = detection.keypoints[4];

    let eye_distance_x = (right_eye[0] - left_eye[0]).abs();
    let eye_distance_y = (right_eye[1] - left_eye[1]).abs();
    let mouth_distance_y = (right_mouth[1] - left_mouth[1]).abs();

    let face_is_upright = left_eye[1].max(right_eye[1]) + 0.5 * eye_distance_y < nose[1]
        && nose[1] + 0.5 * mouth_distance_y < left_mouth[1].min(right_mouth[1]);

    let nose_sticking_out_left =
        nose[0] < left_eye[0].min(right_eye[0]) && nose[0] < left_mouth[0].min(right_mouth[0]);
    let nose_sticking_out_right =
        nose[0] > left_eye[0].max(right_eye[0]) && nose[0] > left_mouth[0].max(right_mouth[0]);

    let nose_close_to_left_eye = (nose[0] - left_eye[0]).abs() < 0.2 * eye_distance_x;
    let nose_close_to_right_eye = (nose[0] - right_eye[0]).abs() < 0.2 * eye_distance_x;

    if nose_sticking_out_left || (face_is_upright && nose_close_to_left_eye) {
        FaceDirection::Left
    } else if nose_sticking_out_right || (face_is_upright && nose_close_to_right_eye) {
        FaceDirection::Right
    } else {
        FaceDirection::Straight
    }
}

fn compute_blur_value(face_image: &RgbImage, direction: FaceDirection) -> f32 {
    let (gray, gray_rows, gray_cols) = to_grayscale_buffer(face_image);
    let (padded, padded_rows, padded_cols) =
        pad_image_for_direction(&gray, gray_rows, gray_cols, direction);
    let (laplacian, lap_rows, lap_cols) = apply_laplacian(&padded, padded_rows, padded_cols);
    let variance = variance_2d(&laplacian, lap_rows, lap_cols);
    if variance.is_finite() {
        variance
    } else {
        LAPLACIAN_HARD_THRESHOLD + 1.0
    }
}

fn to_grayscale_buffer(face_image: &RgbImage) -> (Vec<i32>, usize, usize) {
    let w = face_image.width() as usize;
    let h = face_image.height() as usize;
    let mut gray = vec![0i32; w * h];
    for y in 0..h {
        for x in 0..w {
            let px = face_image.get_pixel(x as u32, y as u32).0;
            gray[y * w + x] = (0.299 * px[0] as f32 + 0.587 * px[1] as f32 + 0.114 * px[2] as f32)
                .round()
                .clamp(0.0, 255.0) as i32;
        }
    }
    (gray, h, w)
}

fn apply_laplacian(
    padded: &[i32],
    padded_rows: usize,
    padded_cols: usize,
) -> (Vec<i32>, usize, usize) {
    let rows = padded_rows.saturating_sub(2);
    let cols = padded_cols.saturating_sub(2);
    let mut out = vec![0i32; rows * cols];
    for i in 0..rows {
        for j in 0..cols {
            let top = padded[i * padded_cols + (j + 1)];
            let left = padded[(i + 1) * padded_cols + j];
            let center = padded[(i + 1) * padded_cols + (j + 1)];
            let right = padded[(i + 1) * padded_cols + (j + 2)];
            let bottom = padded[(i + 2) * padded_cols + (j + 1)];
            out[i * cols + j] = top + left - (4 * center) + right + bottom;
        }
    }
    (out, rows, cols)
}

fn pad_image_for_direction(
    image: &[i32],
    rows: usize,
    cols: usize,
    direction: FaceDirection,
) -> (Vec<i32>, usize, usize) {
    let padded_cols = cols + 2 - REMOVE_SIDE_COLUMNS;
    let padded_rows = rows + 2;
    let mut padded = vec![0i32; padded_rows * padded_cols];

    let start_col = match direction {
        FaceDirection::Straight => REMOVE_SIDE_COLUMNS / 2,
        FaceDirection::Left => REMOVE_SIDE_COLUMNS,
        FaceDirection::Right => 0,
    };
    let copy_cols = padded_cols.saturating_sub(2);

    for i in 0..rows {
        for j in 0..copy_cols {
            padded[(i + 1) * padded_cols + (j + 1)] = image[i * cols + (j + start_col)];
        }
    }

    if copy_cols > 0 {
        for col in 0..copy_cols {
            padded[1 + col] = padded[2 * padded_cols + 1 + col];
            padded[(rows + 1) * padded_cols + 1 + col] = padded[(rows - 1) * padded_cols + 1 + col];
        }
    }

    for row in 0..(rows + 2) {
        let row_start = row * padded_cols;
        padded[row_start] = padded[row_start + 2];
        padded[row_start + padded_cols - 1] = padded[row_start + padded_cols - 3];
    }

    (padded, padded_rows, padded_cols)
}

fn variance_2d(matrix: &[i32], rows: usize, cols: usize) -> f32 {
    if rows == 0 || cols == 0 {
        return 0.0;
    }

    let total = (rows * cols) as f32;

    let mut mean = 0.0f32;
    for value in matrix {
        mean += *value as f32;
    }
    mean /= total;

    let mut variance = 0.0f32;
    for value in matrix {
        let diff = *value as f32 - mean;
        variance += diff * diff;
    }
    variance / total
}

#[cfg(test)]
mod tests {
    use super::run_face_alignment;
    use crate::ml::types::{DecodedImage, Dimensions};

    #[test]
    fn face_alignment_restores_the_decoded_rgb_allocation() {
        let mut decoded = DecodedImage {
            dimensions: Dimensions {
                width: 2,
                height: 2,
            },
            rgb: (0..12).collect(),
        };
        let allocation = decoded.rgb.as_ptr();

        let (aligned, results) = run_face_alignment(1, &mut decoded, Vec::new()).unwrap();

        assert!(aligned.is_empty());
        assert!(results.is_empty());
        assert_eq!(decoded.rgb, (0..12).collect::<Vec<_>>());
        assert_eq!(decoded.rgb.as_ptr(), allocation);
    }
}
