//! DDIM scheduler for the Moebius latent-diffusion inpainting pipeline.
//!
//! Mirrors the reference `onnx_pipeline.py` (`simonw/moebius-web`): a
//! scaled-linear beta schedule over `NUM_TRAIN_TIMESTEPS`, with a deterministic
//! DDIM update (eta = 0, no sample clipping).

/// Number of timesteps the model was trained with.
pub const NUM_TRAIN_TIMESTEPS: usize = 1000;
/// Scaled-linear schedule endpoints.
pub const BETA_START: f64 = 0.00085;
pub const BETA_END: f64 = 0.012;

/// Precomputed DDIM schedule for a given number of inference steps.
pub struct DdimSchedule {
    /// Cumulative product of alphas, indexed by training timestep `[0, 1000)`.
    alphas_cumprod: Vec<f64>,
    /// Inference timesteps in descending order (first entry already dropped to
    /// emulate strength ~0.99, matching the reference pipeline).
    pub timesteps: Vec<i64>,
}

impl DdimSchedule {
    pub fn new(num_steps: usize) -> Self {
        // betas = linspace(sqrt(beta_start), sqrt(beta_end), N) ** 2
        let sqrt_start = BETA_START.sqrt();
        let sqrt_end = BETA_END.sqrt();
        let n = NUM_TRAIN_TIMESTEPS;
        let mut alphas_cumprod = Vec::with_capacity(n);
        let mut running = 1.0f64;
        for i in 0..n {
            let frac = if n > 1 {
                i as f64 / (n as f64 - 1.0)
            } else {
                0.0
            };
            let sqrt_beta = sqrt_start + (sqrt_end - sqrt_start) * frac;
            let beta = sqrt_beta * sqrt_beta;
            let alpha = 1.0 - beta;
            running *= alpha;
            alphas_cumprod.push(running);
        }

        // The reference recipe at 20 steps is `(arange(20) * 50)[::-1][1:]`
        // = [900, 850, ..., 0]: the first timestep is dropped to emulate
        // strength ~0.99, leaving a start at t=900. Naively reusing that
        // formula at lower step counts also lowers the start (e.g. 12 steps
        // -> t=830), which mismatches the pure-noise init latent and degrades
        // output badly. Instead, pin the start at T_START and spread the
        // effective steps evenly down to 0 — identical to the reference
        // schedule at 20 steps, and correct at lower counts.
        const T_START: i64 = 900;
        let effective = num_steps.saturating_sub(1).max(1);
        let timesteps: Vec<i64> = if effective == 1 {
            vec![T_START]
        } else {
            (0..effective)
                .map(|i| {
                    let remaining = (effective - 1 - i) as f64;
                    (T_START as f64 * remaining / (effective - 1) as f64).round() as i64
                })
                .collect()
        };

        Self {
            alphas_cumprod,
            timesteps,
        }
    }

    fn alpha_cumprod(&self, t: i64) -> f64 {
        if t < 0 {
            1.0
        } else {
            self.alphas_cumprod[t as usize]
        }
    }

    /// Single DDIM update (eta = 0, clip_sample = false).
    ///
    /// `latents` and `noise_pred` are flat `(4 * 64 * 64)` buffers; `latents` is
    /// updated in place.
    pub fn step(&self, latents: &mut [f32], noise_pred: &[f32], t: i64, prev_t: i64) {
        let ac_t = self.alpha_cumprod(t);
        let ac_prev = self.alpha_cumprod(prev_t);

        let sqrt_ac_t = ac_t.sqrt();
        let sqrt_one_minus_ac_t = (1.0 - ac_t).sqrt();
        let sqrt_ac_prev = ac_prev.sqrt();
        let sqrt_one_minus_ac_prev = (1.0 - ac_prev).sqrt();

        for (latent, &pred) in latents.iter_mut().zip(noise_pred.iter()) {
            let sample = *latent as f64;
            let pred = pred as f64;
            let pred_x0 = (sample - sqrt_one_minus_ac_t * pred) / sqrt_ac_t;
            let pred_dir = sqrt_one_minus_ac_prev * pred;
            *latent = (sqrt_ac_prev * pred_x0 + pred_dir) as f32;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schedule_matches_reference_at_20_steps() {
        let schedule = DdimSchedule::new(20);
        // Must be bit-identical to the reference recipe: [900, 850, ..., 0].
        let expected: Vec<i64> = (0..19).map(|i| 900 - i * 50).collect();
        assert_eq!(schedule.timesteps, expected);
    }

    #[test]
    fn schedule_keeps_high_start_at_low_step_counts() {
        let schedule = DdimSchedule::new(12);
        // 12 steps, first dropped => 11 timesteps, still starting at t=900.
        assert_eq!(schedule.timesteps.len(), 11);
        assert_eq!(schedule.timesteps[0], 900);
        assert_eq!(*schedule.timesteps.last().unwrap(), 0);
        for pair in schedule.timesteps.windows(2) {
            assert!(pair[0] > pair[1]);
        }
    }

    #[test]
    fn alphas_cumprod_is_monotonic_decreasing() {
        let schedule = DdimSchedule::new(20);
        assert!(schedule.alpha_cumprod(0) > schedule.alpha_cumprod(999));
        assert!(schedule.alpha_cumprod(-1) == 1.0);
    }
}
