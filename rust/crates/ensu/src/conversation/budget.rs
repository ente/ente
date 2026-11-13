use super::{Error, input_budget};

#[derive(Debug, PartialEq, Eq)]
pub struct GenerationBudget {
    pub context: usize,
    pub output: usize,
    pub input: usize,
}

pub fn resolve_generation_budget(
    context: usize,
    output: Option<usize>,
) -> Result<GenerationBudget, Error> {
    if context > i32::MAX as usize || context <= super::SAFETY_TOKENS + 1 {
        return Err(Error::InvalidLimits);
    }
    let output = output.unwrap_or_else(|| 2048.min(context / 4));
    Ok(GenerationBudget {
        context,
        output,
        input: input_budget(context, output)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_generation_budgets() {
        for (name, context, configured, expected) in [
            ("native Auto", 12000, None, Some((2048, 9696))),
            ("native small", 2048, None, Some((512, 1280))),
            ("Auto impossible", 300, None, None),
            (
                "preserve long output",
                12000,
                Some(6000),
                Some((6000, 5744)),
            ),
            ("reject oversized override", 2048, Some(2048), None),
            ("zero output", 12000, Some(0), None),
            ("too small context", 257, Some(1), None),
            ("small explicit valid", 258, Some(1), Some((1, 1))),
            ("no prompt room", 4096, Some(3840), None),
            ("last token room", 4096, Some(3839), Some((3839, 1))),
            ("context too large", 2147483648, None, None),
        ] {
            let result = resolve_generation_budget(context, configured);
            if let Some((output, input)) = expected {
                assert_eq!(
                    result.unwrap(),
                    GenerationBudget {
                        context,
                        output,
                        input,
                    },
                    "{name}"
                );
            } else {
                assert!(result.is_err(), "{name}");
            }
        }
    }
}
