pub(crate) fn l2_normalize(embedding: &mut [f32], zero_threshold: f32) {
    let mut norm = 0.0f32;
    for value in embedding.iter() {
        norm += value * value;
    }
    let norm = norm.sqrt();
    if norm <= zero_threshold {
        return;
    }
    for value in embedding.iter_mut() {
        *value /= norm;
    }
}

#[cfg(test)]
mod tests {
    use super::l2_normalize;

    #[test]
    fn l2_normalization_preserves_the_existing_arithmetic() {
        let mut embedding = [3.0, 4.0];

        l2_normalize(&mut embedding, f32::EPSILON);

        assert_eq!(embedding, [0.6, 0.8]);
    }

    #[test]
    fn l2_normalization_honors_the_callers_zero_threshold() {
        let mut embedding = [1e-13];

        l2_normalize(&mut embedding, 1e-12);

        assert_eq!(embedding, [1e-13]);
    }
}
