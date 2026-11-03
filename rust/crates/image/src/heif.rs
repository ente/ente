use std::path::Path;

use ente_heic::{BoundedDecodeError, BoundedInput};

use crate::{
    BoundedDecodeOptions, BoundedDecodedImage, DecodedImage, Dimensions, ImageError, ImageInput,
    ImageResult, bounded::too_large,
};

pub(crate) fn decode(
    input: ImageInput<'_>,
    options: BoundedDecodeOptions,
) -> ImageResult<BoundedDecodedImage> {
    let source = match input {
        ImageInput::Path(path) => BoundedInput::Path(Path::new(path)),
        ImageInput::Bytes(bytes) => BoundedInput::Bytes(bytes),
    };
    let heic_options = ente_heic::BoundedDecodeOptions {
        max_side: options.max_side,
        max_memory_bytes: usize::try_from(options.max_memory_bytes).unwrap_or(usize::MAX),
    };
    match ente_heic::decode_bounded(source, heic_options) {
        Ok(decoded) => Ok(BoundedDecodedImage {
            image: DecodedImage {
                dimensions: Dimensions {
                    width: decoded.image.width,
                    height: decoded.image.height,
                },
                rgb: decoded.image.pixels,
            },
            original_dimensions: Dimensions {
                width: decoded.original_dimensions.0,
                height: decoded.original_dimensions.1,
            },
        }),
        Err(
            BoundedDecodeError::LimitExceeded(_)
            | BoundedDecodeError::MemoryBudgetExceeded { .. }
            | BoundedDecodeError::AllocationFailed,
        ) => Err(too_large()),
        Err(error @ BoundedDecodeError::InvalidOptions(_)) => {
            Err(ImageError::Postprocess(error.to_string()))
        }
        Err(
            error @ (BoundedDecodeError::Io(_)
            | BoundedDecodeError::Unsupported(_)
            | BoundedDecodeError::Malformed(_)
            | BoundedDecodeError::Decode(_)),
        ) => Err(ImageError::Decode(error.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::{
        bounded::{target_dimensions, tests::options},
        decode::decode_image_from_path,
        decode_bounded,
        resample::tests::area_reference,
    };

    const GRID_FIXTURES: [&str; 3] = [
        "IMG_0983.HEIC",
        "IMG_0682_pano.HEIC",
        "IMG_8606_rotate_90_cw_contains_text.HEIC",
    ];

    const NON_GRID_FIXTURES: [&str; 3] = [
        "1718_rotate_90_cw.HEIC",
        "7765_horizontal_normal.HEIC",
        "7949_mirror_horizontal_rotate_270_cw.HEIC",
    ];

    fn fixtures_dir() -> Option<PathBuf> {
        if let Some(path) = std::env::var_os("ENTE_TEST_FIXTURES_DIR") {
            return Some(PathBuf::from(path));
        }
        let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
        let repo_root = manifest_dir.parent()?.parent()?.parent()?;
        Some(repo_root.parent()?.join("test-fixtures"))
    }

    fn heic_fixtures_dir() -> Option<PathBuf> {
        fixtures_dir()
            .map(|path| path.join("media/heic/v1/files"))
            .filter(|path| path.exists())
    }

    #[test]
    fn memory_budget_failures_are_too_large() {
        let bytes = b"\0\0\0\x18ftypheic\0\0\0\0mif1heic\0\0\0\x0cmeta\0\0\0\0";
        assert!(matches!(
            decode_bounded(
                ImageInput::Bytes(bytes),
                BoundedDecodeOptions {
                    max_memory_bytes: 64 * 1024,
                    ..BoundedDecodeOptions::default()
                }
            ),
            Err(ImageError::TooLarge(_))
        ));
        assert!(matches!(
            decode_bounded(ImageInput::Bytes(bytes), BoundedDecodeOptions::default()),
            Err(ImageError::Decode(_))
        ));
    }

    #[test]
    fn non_grid_heic_fixtures_are_rejected_when_present() {
        let Some(directory) = heic_fixtures_dir() else {
            eprintln!("Skipping: external HEIC fixtures not present");
            return;
        };
        for name in NON_GRID_FIXTURES {
            let path = directory.join(name);
            assert!(
                matches!(
                    decode_bounded(ImageInput::Path(path.to_str().unwrap()), options(6000)),
                    Err(ImageError::Decode(_))
                ),
                "{name}"
            );
        }
    }

    #[test]
    fn grid_heic_fixtures_match_the_full_decoder_when_present() {
        let Some(directory) = heic_fixtures_dir() else {
            eprintln!("Skipping: external HEIC fixtures not present");
            return;
        };
        for name in GRID_FIXTURES {
            let path = directory.join(name);
            let path = path.to_str().unwrap();
            let full = decode_image_from_path(path).unwrap();
            for max_side in [6000, 97] {
                let bounded = decode_bounded(ImageInput::Path(path), options(max_side)).unwrap();
                assert_eq!(bounded.original_dimensions, full.dimensions, "{name}");
                assert_eq!(
                    bounded.image.dimensions,
                    target_dimensions(&full.dimensions, max_side),
                    "{name}"
                );
                let expected = area_reference(
                    &full.rgb,
                    full.dimensions.width,
                    full.dimensions.height,
                    &bounded.image.dimensions,
                );
                assert_eq!(bounded.image.rgb.len(), expected.len(), "{name}");
                for (actual, expected) in bounded.image.rgb.iter().zip(expected) {
                    assert!(
                        actual.abs_diff(expected) <= 1,
                        "{name}, max {max_side}: {actual} != {expected}"
                    );
                }
            }
        }
    }
}
