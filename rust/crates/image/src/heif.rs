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
        bounded::tests::options, decode::decode_image_from_path, decode_bounded,
        resample::tests::area_reference,
    };

    const GRID_FIXTURES: [&str; 3] = [
        "IMG_0983.HEIC",
        "IMG_0682_pano.HEIC",
        "IMG_8606_rotate_90_cw_contains_text.HEIC",
    ];

    fn fixtures_dir() -> Option<PathBuf> {
        if let Some(path) = std::env::var_os("ENTE_TEST_FIXTURES_DIR") {
            return Some(PathBuf::from(path));
        }
        let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
        let repo_root = manifest_dir.parent()?.parent()?.parent()?;
        Some(repo_root.parent()?.join("test-fixtures"))
    }

    #[test]
    fn grid_heic_fixtures_match_the_full_decoder_when_present() {
        let Some(directory) = fixtures_dir()
            .map(|path| path.join("media/heic/v1/files"))
            .filter(|path| path.exists())
        else {
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
