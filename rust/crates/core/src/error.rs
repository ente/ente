//! Helpers for working with errors.

use std::fmt::Write;

/// Render an error and its chain of causes as one string.
///
/// The causes are appended, colon separated, to the error's own message.
pub fn chain(error: &dyn std::error::Error) -> String {
    let mut message = error.to_string();
    let mut source = error.source();
    while let Some(cause) = source {
        let _ = write!(message, ": {cause}");
        source = cause.source();
    }
    message
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug)]
    struct Leaf;

    impl std::fmt::Display for Leaf {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            write!(f, "leaf")
        }
    }

    impl std::error::Error for Leaf {}

    #[derive(Debug)]
    struct Wrapper(Leaf);

    impl std::fmt::Display for Wrapper {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            write!(f, "wrapper")
        }
    }

    impl std::error::Error for Wrapper {
        fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
            Some(&self.0)
        }
    }

    #[test]
    fn chain_renders_the_causes() {
        assert_eq!(chain(&Leaf), "leaf");
        assert_eq!(chain(&Wrapper(Leaf)), "wrapper: leaf");
    }
}
