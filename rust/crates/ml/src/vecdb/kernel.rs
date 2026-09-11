use super::{StorageKind, VecDbError};

pub(crate) const LANE_WIDTH: usize = 8;
pub(crate) const LANE_WIDTH_I8: usize = 32;
const I8_LIMIT: f32 = 127.0;
pub(crate) const MAX_DIMS_I8: usize =
    (i32::MAX / ((I8_LIMIT as i32) * (I8_LIMIT as i32))) as usize / LANE_WIDTH_I8 * LANE_WIDTH_I8;

pub(crate) fn is_within_quantized_range(value: i8) -> bool {
    i32::from(value).abs() <= I8_LIMIT as i32
}

#[repr(C, align(32))]
#[derive(Clone, Copy)]
pub(crate) struct Lane([f32; LANE_WIDTH]);

impl Lane {
    pub(crate) const ZERO: Self = Self([0.0; LANE_WIDTH]);

    pub(crate) fn to_array(self) -> [f32; LANE_WIDTH] {
        self.0
    }
}

impl From<[f32; LANE_WIDTH]> for Lane {
    fn from(values: [f32; LANE_WIDTH]) -> Self {
        Self(values)
    }
}

#[repr(C, align(32))]
#[derive(Clone, Copy)]
pub(crate) struct LaneI8([i8; LANE_WIDTH_I8]);

impl LaneI8 {
    pub(crate) const ZERO: Self = Self([0; LANE_WIDTH_I8]);

    pub(crate) fn to_array(self) -> [i8; LANE_WIDTH_I8] {
        self.0
    }
}

impl From<[i8; LANE_WIDTH_I8]> for LaneI8 {
    fn from(values: [i8; LANE_WIDTH_I8]) -> Self {
        Self(values)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum VectorPayload<'a> {
    F32(&'a [f32]),
    I8 { scale: f32, values: &'a [i8] },
}

impl VectorPayload<'_> {
    pub(crate) fn storage(&self) -> StorageKind {
        match self {
            Self::F32(_) => StorageKind::F32,
            Self::I8 { .. } => StorageKind::I8,
        }
    }

    pub(crate) fn dims(&self) -> usize {
        match self {
            Self::F32(values) => values.len(),
            Self::I8 { values, .. } => values.len(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum StoredVector {
    F32(Vec<f32>),
    I8 { scale: f32, values: Vec<i8> },
}

impl StoredVector {
    pub(crate) fn quantize(values: &[f32]) -> Self {
        let finite = values.iter().all(|value| value.is_finite());
        let max_abs = values
            .iter()
            .fold(0.0f32, |acc, value| acc.max(value.abs()));
        let scale = if finite { max_abs / I8_LIMIT } else { f32::NAN };
        let quantized = if scale > 0.0 {
            values
                .iter()
                .map(|value| (value / scale).round().clamp(-I8_LIMIT, I8_LIMIT) as i8)
                .collect()
        } else {
            vec![0; values.len()]
        };
        Self::I8 {
            scale,
            values: quantized,
        }
    }

    pub(crate) fn as_payload(&self) -> VectorPayload<'_> {
        match self {
            Self::F32(values) => VectorPayload::F32(values),
            Self::I8 { scale, values } => VectorPayload::I8 {
                scale: *scale,
                values,
            },
        }
    }
}

pub(crate) fn quantize_for(storage: StorageKind, values: &[f32]) -> Option<StoredVector> {
    match storage {
        StorageKind::F32 => None,
        StorageKind::I8 => Some(StoredVector::quantize(values)),
    }
}

pub(crate) fn dequantize(scale: f32, values: &[i8]) -> Vec<f32> {
    values
        .iter()
        .map(|&value| f32::from(value) * scale)
        .collect()
}

pub(crate) fn validate_dims(dims: usize, storage: StorageKind) -> Result<(), VecDbError> {
    if dims == 0
        || !dims.is_multiple_of(storage.lane_width())
        || u32::try_from(dims).is_err()
        || dims > storage.max_dims()
    {
        return Err(VecDbError::InvalidDimensions { dims, storage });
    }
    Ok(())
}

pub(crate) fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut mixed = *state;
    mixed = (mixed ^ (mixed >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    mixed = (mixed ^ (mixed >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    mixed ^ (mixed >> 31)
}

pub(crate) trait VectorKernel {
    type Lane;

    fn dot(a: &[Self::Lane], b: &[Self::Lane]) -> f32;

    fn distance(a: &[Self::Lane], b: &[Self::Lane]) -> f32 {
        1.0 - Self::dot(a, b)
    }
}

pub(crate) struct F32Kernel;

impl VectorKernel for F32Kernel {
    type Lane = Lane;

    fn dot(a: &[Lane], b: &[Lane]) -> f32 {
        debug_assert_eq!(a.len(), b.len());
        let mut partials = [0.0f32; LANE_WIDTH];
        for (x, y) in a.iter().zip(b.iter()) {
            for (partial, (left, right)) in partials.iter_mut().zip(x.0.iter().zip(&y.0)) {
                *partial += left * right;
            }
        }
        partials.iter().sum()
    }
}

pub(crate) struct I8Kernel;

impl I8Kernel {
    pub(crate) fn dot(a: &[LaneI8], b: &[LaneI8]) -> i32 {
        debug_assert_eq!(a.len(), b.len());
        let mut total = 0i32;
        for (x, y) in a.iter().zip(b) {
            let mut lane = 0i32;
            for (left, right) in x.0.iter().zip(&y.0) {
                lane += i32::from(*left) * i32::from(*right);
            }
            total += lane;
        }
        total
    }

    pub(crate) fn distance(a: &[LaneI8], scale_a: f32, b: &[LaneI8], scale_b: f32) -> f32 {
        1.0 - Self::dot(a, b) as f32 * scale_a * scale_b
    }
}

pub(crate) fn pack_lanes_i8(values: &[i8]) -> Vec<LaneI8> {
    debug_assert_eq!(values.len() % LANE_WIDTH_I8, 0);
    let mut lanes = vec![LaneI8::ZERO; values.len() / LANE_WIDTH_I8];
    pack_lanes_i8_into(values, &mut lanes);
    lanes
}

pub(crate) fn pack_lanes_i8_into(values: &[i8], lanes: &mut [LaneI8]) {
    debug_assert_eq!(values.len(), lanes.len() * LANE_WIDTH_I8);
    let (groups, remainder) = values.as_chunks::<LANE_WIDTH_I8>();
    debug_assert!(remainder.is_empty());
    for (lane, group) in lanes.iter_mut().zip(groups) {
        *lane = LaneI8::from(*group);
    }
}

pub(crate) fn unpack_lanes_i8(lanes: &[LaneI8]) -> Vec<i8> {
    let mut values = Vec::with_capacity(lanes.len() * LANE_WIDTH_I8);
    for lane in lanes {
        values.extend_from_slice(&lane.to_array());
    }
    values
}

pub(crate) fn pack_lanes(values: &[f32]) -> Vec<Lane> {
    debug_assert_eq!(values.len() % LANE_WIDTH, 0);
    let mut lanes = vec![Lane::ZERO; values.len() / LANE_WIDTH];
    pack_lanes_into(values, &mut lanes);
    lanes
}

pub(crate) fn pack_lanes_into(values: &[f32], lanes: &mut [Lane]) {
    debug_assert_eq!(values.len(), lanes.len() * LANE_WIDTH);
    let (groups, remainder) = values.as_chunks::<LANE_WIDTH>();
    debug_assert!(remainder.is_empty());
    for (lane, group) in lanes.iter_mut().zip(groups) {
        *lane = Lane::from(*group);
    }
}

pub(crate) fn unpack_lanes(lanes: &[Lane]) -> Vec<f32> {
    let mut values = Vec::with_capacity(lanes.len() * LANE_WIDTH);
    for lane in lanes {
        values.extend_from_slice(&lane.to_array());
    }
    values
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seeded_values(seed: u64, count: usize) -> Vec<f32> {
        let mut state = seed;
        (0..count)
            .map(|index| {
                let unit = (splitmix64(&mut state) >> 40) as f32 / (1u64 << 24) as f32;
                let signed = unit * 2.0 - 1.0;
                match index % 5 {
                    0 => signed * 1.0e6,
                    1 => signed * 1.0e-6,
                    _ => signed,
                }
            })
            .collect()
    }

    fn reference_dot(a: &[f32], b: &[f32]) -> f32 {
        let mut partials = [0.0f32; LANE_WIDTH];
        for (index, (x, y)) in a.iter().zip(b).enumerate() {
            partials[index % LANE_WIDTH] += x * y;
        }
        partials.iter().sum()
    }

    fn basis_vector(dims: usize, axis: usize) -> Vec<f32> {
        let mut values = vec![0.0; dims];
        values[axis] = 1.0;
        values
    }

    #[test]
    fn the_quantized_range_excludes_only_the_int8_minimum() {
        assert!(is_within_quantized_range(I8_LIMIT as i8));
        assert!(is_within_quantized_range(-(I8_LIMIT as i8)));
        assert!(is_within_quantized_range(0));
        assert!(!is_within_quantized_range(i8::MIN));
    }

    #[test]
    fn dot_matches_scalar_reference_bit_exactly() {
        for (dims, seed) in [(128, 11), (192, 22), (512, 33)] {
            let a = seeded_values(seed, dims);
            let b = seeded_values(seed.wrapping_mul(977), dims);
            let simd = F32Kernel::dot(&pack_lanes(&a), &pack_lanes(&b));
            let reference = reference_dot(&a, &b);
            assert!(reference.is_finite());
            assert_ne!(reference, 0.0);
            assert_eq!(simd.to_bits(), reference.to_bits());
        }
    }

    #[test]
    fn distance_of_basis_vectors_is_exact() {
        let e0 = pack_lanes(&basis_vector(128, 0));
        let e1 = pack_lanes(&basis_vector(128, 100));
        assert_eq!(F32Kernel::distance(&e0, &e0), 0.0);
        assert_eq!(F32Kernel::distance(&e0, &e1), 1.0);
    }

    #[test]
    fn pack_unpack_round_trips() {
        let values = seeded_values(99, 512);
        let lanes = pack_lanes(&values);
        assert_eq!(lanes.len(), 64);
        assert_eq!(unpack_lanes(&lanes), values);
    }

    #[test]
    fn packed_lanes_are_32_byte_aligned() {
        assert_eq!(align_of::<Lane>(), 32);
        for dims in [128, 192, 512] {
            let lanes = pack_lanes(&seeded_values(5, dims));
            assert_eq!(lanes.as_ptr() as usize % 32, 0);
        }
    }

    fn seeded_unit_values(seed: u64, count: usize) -> Vec<f32> {
        let mut state = seed;
        let mut values: Vec<f32> = (0..count)
            .map(|_| {
                let unit = (splitmix64(&mut state) >> 40) as f32 / (1u64 << 24) as f32;
                unit * 2.0 - 1.0
            })
            .collect();
        let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
        for value in &mut values {
            *value /= norm;
        }
        values
    }

    fn seeded_i8_values(seed: u64, count: usize) -> Vec<i8> {
        let mut state = seed;
        (0..count)
            .map(|_| ((splitmix64(&mut state) % 255) as i64 - 127) as i8)
            .collect()
    }

    fn quantized_parts(values: &[f32]) -> (f32, Vec<i8>) {
        match StoredVector::quantize(values) {
            StoredVector::I8 { scale, values } => (scale, values),
            StoredVector::F32(_) => panic!("quantize must produce i8 storage"),
        }
    }

    #[test]
    fn i8_dot_matches_the_scalar_reference_bit_exactly() {
        for (dims, seed) in [(32, 11), (64, 22), (512, 33)] {
            let a = seeded_i8_values(seed, dims);
            let b = seeded_i8_values(seed.wrapping_mul(977), dims);
            let simd = I8Kernel::dot(&pack_lanes_i8(&a), &pack_lanes_i8(&b));
            let mut partials = [0i32; LANE_WIDTH_I8];
            for (index, (x, y)) in a.iter().zip(&b).enumerate() {
                partials[index % LANE_WIDTH_I8] += i32::from(*x) * i32::from(*y);
            }
            let reference: i32 = partials.iter().sum();
            assert_ne!(reference, 0);
            assert_eq!(simd, reference);
            let saturated = vec![127i8; dims];
            let negated = vec![-127i8; dims];
            assert_eq!(
                I8Kernel::dot(&pack_lanes_i8(&saturated), &pack_lanes_i8(&negated)),
                -(dims as i32) * 127 * 127
            );
        }
    }

    #[test]
    fn i8_dims_are_capped_where_a_saturated_dot_still_fits_i32() {
        assert!(validate_dims(MAX_DIMS_I8, StorageKind::I8).is_ok());
        assert!(validate_dims(MAX_DIMS_I8 + LANE_WIDTH_I8, StorageKind::F32).is_ok());
        assert!(matches!(
            validate_dims(MAX_DIMS_I8 + LANE_WIDTH_I8, StorageKind::I8),
            Err(VecDbError::InvalidDimensions {
                dims,
                storage: StorageKind::I8
            }) if dims == MAX_DIMS_I8 + LANE_WIDTH_I8
        ));
        let saturated_product = i64::from(I8_LIMIT as i32) * i64::from(I8_LIMIT as i32);
        assert!(MAX_DIMS_I8 as i64 * saturated_product <= i64::from(i32::MAX));
        assert!((MAX_DIMS_I8 + LANE_WIDTH_I8) as i64 * saturated_product > i64::from(i32::MAX));
        let saturated = vec![127i8; MAX_DIMS_I8];
        let packed = pack_lanes_i8(&saturated);
        assert_eq!(
            i64::from(I8Kernel::dot(&packed, &packed)),
            MAX_DIMS_I8 as i64 * saturated_product
        );
    }

    #[test]
    fn i8_distance_pins_the_evaluation_order() {
        let a = pack_lanes_i8(&seeded_i8_values(5, 64));
        let b = pack_lanes_i8(&seeded_i8_values(6, 64));
        let scale_a = 0.012_345_6f32;
        let scale_b = 0.045_678_9f32;
        let dot = I8Kernel::dot(&a, &b);
        let scaled_once = dot as f32 * scale_a;
        let expected = 1.0 - scaled_once * scale_b;
        assert_eq!(
            I8Kernel::distance(&a, scale_a, &b, scale_b).to_bits(),
            expected.to_bits()
        );
        assert_eq!(
            I8Kernel::distance(&b, scale_b, &a, scale_a).to_bits(),
            (1.0 - (dot as f32 * scale_b) * scale_a).to_bits()
        );
    }

    #[test]
    fn i8_distance_of_basis_vectors_is_orthogonal_exactly_and_self_within_rounding() {
        let (scale_0, values_0) = quantized_parts(&basis_vector(32, 0));
        let (scale_5, values_5) = quantized_parts(&basis_vector(32, 5));
        assert_eq!(scale_0, 1.0 / 127.0);
        assert_eq!(values_0[0], 127);
        assert!(values_0[1..].iter().all(|&value| value == 0));
        let e0 = pack_lanes_i8(&values_0);
        let e5 = pack_lanes_i8(&values_5);
        assert_eq!(I8Kernel::distance(&e0, scale_0, &e5, scale_5), 1.0);
        assert!(I8Kernel::distance(&e0, scale_0, &e0, scale_0).abs() < 1.0e-6);
    }

    #[test]
    fn quantize_bounds_every_value_and_maps_the_extreme_component_to_127() {
        for seed in 0..40u64 {
            let values = seeded_values(seed, 128);
            let max_abs = values
                .iter()
                .fold(0.0f32, |acc, value| acc.max(value.abs()));
            let (scale, quantized) = quantized_parts(&values);
            assert_eq!(scale.to_bits(), (max_abs / 127.0).to_bits());
            assert!(quantized.iter().all(|&value| (-127..=127).contains(&value)));
            let extreme = values
                .iter()
                .position(|value| value.abs() == max_abs)
                .unwrap();
            assert_eq!(
                quantized[extreme],
                if values[extreme] > 0.0 { 127 } else { -127 }
            );
            for (value, &q) in values.iter().zip(&quantized) {
                if value.abs() >= scale {
                    assert_eq!(q.signum(), value.signum() as i8);
                }
            }
        }
    }

    #[test]
    fn quantize_is_bit_stable_and_handles_zero_and_non_finite_inputs() {
        let values = seeded_unit_values(7, 512);
        let first = StoredVector::quantize(&values);
        for _ in 0..5 {
            let again = StoredVector::quantize(&values);
            let (
                StoredVector::I8 { scale, values: q },
                StoredVector::I8 {
                    scale: s2,
                    values: q2,
                },
            ) = (&first, &again)
            else {
                panic!("quantize must produce i8 storage");
            };
            assert_eq!(scale.to_bits(), s2.to_bits());
            assert_eq!(q, q2);
        }
        let (zero_scale, zeros) = quantized_parts(&[0.0; 64]);
        assert_eq!(zero_scale.to_bits(), 0.0f32.to_bits());
        assert!(zeros.iter().all(|&value| value == 0));
        let (negative_zero_scale, _) = quantized_parts(&[-0.0; 64]);
        assert_eq!(negative_zero_scale.to_bits(), 0.0f32.to_bits());
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let mut poisoned = values.clone();
            poisoned[100] = bad;
            let (scale, q) = quantized_parts(&poisoned);
            assert!(scale.is_nan());
            assert!(q.iter().all(|&value| value == 0));
        }
        assert_eq!(quantize_for(StorageKind::F32, &values), None);
        assert_eq!(quantize_for(StorageKind::I8, &values), Some(first));
    }

    #[test]
    fn quantize_pins_half_way_ties_signed_zeros_and_denormals() {
        let mut values = [0.0f32; 32];
        values[..14].copy_from_slice(&[
            127.0,
            2.5,
            -2.5,
            0.5,
            -0.5,
            1.5,
            -1.5,
            126.5,
            -126.5,
            0.0,
            -0.0,
            1.0e-40,
            -1.0e-40,
            f32::MIN_POSITIVE,
        ]);
        let (scale, quantized) = quantized_parts(&values);
        assert_eq!(scale.to_bits(), 1.0f32.to_bits());
        let mut expected = [0i8; 32];
        expected[..9].copy_from_slice(&[127, 3, -3, 1, -1, 2, -2, 127, -127]);
        assert_eq!(quantized, expected);
        let mut tiny = [0.0f32; 32];
        tiny[0] = 1.0e-40;
        tiny[1] = -1.0e-40;
        tiny[2] = f32::from_bits(1);
        let (tiny_scale, tiny_quantized) = quantized_parts(&tiny);
        assert_eq!(tiny_scale.to_bits(), (1.0e-40f32 / 127.0).to_bits());
        assert!(tiny_scale > 0.0);
        assert_eq!(tiny_quantized[0], 127);
        assert_eq!(tiny_quantized[1], -127);
        assert_eq!(tiny_quantized[2], 0);
        assert!(tiny_quantized[3..].iter().all(|&value| value == 0));
        let (min_scale, min_quantized) = quantized_parts(&[f32::from_bits(1); 32]);
        assert_eq!(min_scale.to_bits(), 0.0f32.to_bits());
        assert!(min_quantized.iter().all(|&value| value == 0));
        for _ in 0..3 {
            assert_eq!(quantized_parts(&values), (scale, quantized.clone()));
            assert_eq!(quantized_parts(&tiny), (tiny_scale, tiny_quantized.clone()));
        }
    }

    #[test]
    fn dequantize_stays_within_half_a_step_of_the_input() {
        for (dims, seed) in [(64usize, 1u64), (512, 2), (32, 3)] {
            let values = seeded_unit_values(seed, dims);
            let (scale, quantized) = quantized_parts(&values);
            let restored = dequantize(scale, &quantized);
            assert_eq!(restored.len(), dims);
            for (original, restored) in values.iter().zip(&restored) {
                assert!((original - restored).abs() <= scale / 2.0 + scale * 1.0e-6);
            }
        }
    }

    #[test]
    fn i8_distance_tracks_f32_distance_on_unit_vectors_within_the_bound() {
        let mut max_delta = 0.0f32;
        for (dims, pairs, seed) in [(512usize, 300u64, 0x1000u64), (64, 300, 0x2000)] {
            for pair in 0..pairs {
                let a = seeded_unit_values(seed + pair * 2, dims);
                let b = seeded_unit_values(seed + pair * 2 + 1, dims);
                let f32_distance = F32Kernel::distance(&pack_lanes(&a), &pack_lanes(&b));
                let (scale_a, qa) = quantized_parts(&a);
                let (scale_b, qb) = quantized_parts(&b);
                let i8_distance =
                    I8Kernel::distance(&pack_lanes_i8(&qa), scale_a, &pack_lanes_i8(&qb), scale_b);
                let delta = (i8_distance - f32_distance).abs();
                assert!(delta <= 0.01, "dims {dims} pair {pair}: delta {delta}");
                max_delta = max_delta.max(delta);
            }
        }
        assert!(max_delta > 0.0);
        assert!(max_delta <= 0.005, "max delta {max_delta}");
    }

    #[test]
    fn packed_i8_lanes_are_32_byte_aligned_and_round_trip() {
        assert_eq!(align_of::<LaneI8>(), 32);
        assert_eq!(size_of::<LaneI8>(), 32);
        for dims in [32, 64, 512] {
            let values = seeded_i8_values(9, dims);
            let lanes = pack_lanes_i8(&values);
            assert_eq!(lanes.len(), dims / LANE_WIDTH_I8);
            assert_eq!(lanes.as_ptr() as usize % 32, 0);
            assert_eq!(unpack_lanes_i8(&lanes), values);
        }
    }
}
