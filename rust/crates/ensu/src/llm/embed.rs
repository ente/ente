use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::AddBos;

use super::{Context, Error};

impl Context {
    pub fn embed(&self, text: &str) -> Result<Vec<f32>, Error> {
        let params = self.embedding_params().ok_or(Error::Unsupported(
            "Context is not configured for embeddings",
        ))?;
        if text.trim().is_empty() {
            return Err(Error::InvalidInput(
                "embedding query must not be empty".to_string(),
            ));
        }

        let prompt = params.query_prompt.replacen("{query}", text, 1);
        let (batch_size, source_dim, dim) = (params.batch_size, params.source_dim, params.dim);
        self.with_context_and_cache_mut(|context, cached_tokens| {
            let tokens = context
                .model
                .str_to_token(&prompt, AddBos::Always)
                .map_err(|err| Error::Llama {
                    op: "Embedding tokenization failed",
                    message: err.to_string(),
                })?;
            if tokens.is_empty() {
                return Err(Error::InvalidInput(
                    "embedding prompt produced no tokens".to_string(),
                ));
            }
            let token_count = u32::try_from(tokens.len()).map_err(|_| {
                Error::InvalidInput("embedding prompt has too many tokens".to_string())
            })?;
            if token_count > context.n_ctx() || token_count > batch_size {
                return Err(Error::PromptTooLong {
                    tokens: tokens.len(),
                    context_size: context.n_ctx(),
                });
            }

            context.clear_kv_cache();
            cached_tokens.clear();
            let mut batch = LlamaBatch::new(tokens.len(), 1);
            for (index, token) in tokens.into_iter().enumerate() {
                let position = i32::try_from(index).map_err(|_| {
                    Error::InvalidInput("embedding token position is too large".to_string())
                })?;
                batch
                    .add(token, position, &[0], true)
                    .map_err(|err| Error::Llama {
                        op: "Failed to add embedding token",
                        message: err.to_string(),
                    })?;
            }
            context.decode(&mut batch).map_err(|err| Error::Llama {
                op: "Embedding decode failed",
                message: err.to_string(),
            })?;
            let native = context.embeddings_seq_ith(0).map_err(|err| Error::Llama {
                op: "Failed to read pooled embedding",
                message: err.to_string(),
            })?;
            normalize_matryoshka(native, source_dim, dim)
        })
    }
}

fn normalize_matryoshka(
    native: &[f32],
    expected_source_dim: u32,
    output_dim: u32,
) -> Result<Vec<f32>, Error> {
    let expected_source_dim = usize::try_from(expected_source_dim)
        .map_err(|_| Error::InvalidInput("source_dim is too large".to_string()))?;
    let output_dim = usize::try_from(output_dim)
        .map_err(|_| Error::InvalidInput("dim is too large".to_string()))?;
    if native.len() != expected_source_dim {
        return Err(Error::InvalidInput(format!(
            "embedding model returned {} components; expected {expected_source_dim}",
            native.len()
        )));
    }
    if native.iter().any(|component| !component.is_finite()) {
        return Err(Error::InvalidInput(
            "embedding contains a non-finite component".to_string(),
        ));
    }
    let prefix = native
        .get(..output_dim)
        .ok_or_else(|| Error::InvalidInput("dim exceeds source_dim".to_string()))?;

    let squared_norm = prefix
        .iter()
        .map(|component| f64::from(*component) * f64::from(*component))
        .sum::<f64>();
    if !squared_norm.is_finite() || squared_norm <= 0.0 {
        return Err(Error::InvalidInput(
            "embedding has zero or invalid norm".to_string(),
        ));
    }
    let inverse_norm = squared_norm.sqrt().recip() as f32;
    let normalized = prefix
        .iter()
        .map(|component| *component * inverse_norm)
        .collect::<Vec<_>>();
    if normalized.iter().any(|component| !component.is_finite()) {
        return Err(Error::InvalidInput(
            "normalized embedding contains a non-finite component".to_string(),
        ));
    }
    Ok(normalized)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_only_the_matryoshka_prefix() {
        let normalized = normalize_matryoshka(&[3.0, 4.0, 1_000.0], 3, 2).unwrap();
        assert_eq!(normalized.len(), 2);
        assert!((normalized[0] - 0.6).abs() < 1e-6);
        assert!((normalized[1] - 0.8).abs() < 1e-6);
    }

    #[test]
    fn rejects_wrong_shape_zero_and_non_finite_vectors() {
        assert!(normalize_matryoshka(&[1.0], 2, 1).is_err());
        assert!(normalize_matryoshka(&[0.0, 0.0], 2, 2).is_err());
        assert!(normalize_matryoshka(&[f32::NAN, 1.0], 2, 2).is_err());
        assert!(normalize_matryoshka(&[1.0, 2.0], 2, 3).is_err());
    }
}
