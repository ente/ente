use super::common::*;
use ente_exif::{CleanAperture, Dimensions, Limits, Metadata, Mode, Rational, Transform};
use std::io::Cursor;

#[test]
fn display_orientation_uses_valid_exif_then_xmp_and_complete_sizes() {
    for mode in [Mode::Summary, Mode::Details] {
        let mut metadata = read(
            xmp("<t:ImageWidth>800</t:ImageWidth><t:ImageLength>600</t:ImageLength><t:Orientation>6</t:Orientation>").as_bytes(),
            mode,
        );
        assert_eq!(metadata.display_dimensions(), Some(size(600, 800)));
        for (orientation, expected) in [
            (1u32, size(900, 700)),
            (8, size(700, 900)),
            (0, size(700, 900)),
        ] {
            metadata.tags = read(
                &tiff(&[(0x112, 4, 1, orientation.to_le_bytes().to_vec())], false),
                mode,
            )
            .tags;
            assert_eq!(metadata.display_dimensions(), Some(size(600, 800)));
            metadata.dimensions = Some(size(900, 700));
            assert_eq!(metadata.display_dimensions(), Some(expected));
            metadata.dimensions = None;
        }
        for orientation in ["0", "9", "left", "6.0", ""] {
            let metadata = read(xmp(&format!("<e:PixelXDimension>800</e:PixelXDimension><e:PixelYDimension>600</e:PixelYDimension><t:Orientation>{orientation}</t:Orientation>")).as_bytes(), mode);
            assert_eq!(metadata.display_dimensions(), Some(size(800, 600)));
        }
    }
}

#[test]
fn heif_orientation_suppresses_duplicate_exif_and_xmp_rotation() {
    for mode in [Mode::Summary, Mode::Details] {
        let mut metadata = read(
            &heif(&tiff(&[(0x112, 3, 1, vec![6, 0])], false), 0, false),
            mode,
        );
        for (transform, expected) in [
            (Transform::Rotate(0), size(600, 800)),
            (Transform::Rotate(1), size(600, 800)),
            (Transform::Rotate(2), size(800, 600)),
            (Transform::Rotate(3), size(600, 800)),
            (Transform::Mirror(0), size(800, 600)),
            (Transform::Mirror(1), size(800, 600)),
        ] {
            metadata.transforms = vec![transform];
            assert_eq!(metadata.display_dimensions(), Some(expected));
        }
        metadata.tags.clear();
        metadata.xmp = read(xmp("<t:Orientation>8</t:Orientation>").as_bytes(), mode).xmp;
        metadata.transforms = vec![Transform::Rotate(3)];
        assert_eq!(metadata.display_dimensions(), Some(size(600, 800)));
        metadata.transforms.clear();
        assert_eq!(metadata.display_dimensions(), Some(size(600, 800)));
    }
}

#[test]
fn heif_applies_primary_properties_in_association_order() {
    for mode in [Mode::Summary, Mode::Details] {
        for (order, expected) in [
            (vec![1, 2, 3, 4], size(200, 400)),
            (vec![1, 3, 4, 2], size(400, 200)),
        ] {
            let bytes = transformed_heif(&order);
            let metadata = read(&bytes, mode);
            assert_eq!(metadata.dimensions, Some(size(800, 600)));
            assert_eq!(metadata.display_dimensions(), Some(expected));
            assert_eq!(metadata.transforms.len(), 3);
            assert!(metadata.issues.is_empty());
        }
        let bytes = transformed_heif(&[1, 2, 3, 4]);
        assert!(matches!(
            ente_exif::read(
                &mut Cursor::new(bytes),
                mode,
                Limits {
                    output_bytes: std::mem::size_of::<Transform>() * 2,
                    ..Limits::default()
                }
            ),
            Err(ente_exif::Error::Limit("output bytes"))
        ));
    }
}

#[test]
fn crops_require_exact_pixel_rectangles_at_each_step() {
    let base = crop(400, 200);
    let metadata = |crop| Metadata {
        dimensions: Some(size(800, 600)),
        transforms: vec![Transform::Crop(crop)],
        ..Metadata::default()
    };
    assert_eq!(metadata(base).display_dimensions(), Some(size(400, 200)));
    for offset in [-200, 200] {
        let edge = CleanAperture {
            horizontal_offset: rational(offset, 1),
            ..base
        };
        assert_eq!(metadata(edge).display_dimensions(), Some(size(400, 200)));
    }
    let half_offset = CleanAperture {
        width: rational(798, 2),
        horizontal_offset: rational(-1, 2),
        ..base
    };
    assert_eq!(
        metadata(half_offset).display_dimensions(),
        Some(size(399, 200))
    );
    for invalid in [
        CleanAperture {
            width: rational(0, 1),
            ..base
        },
        CleanAperture {
            width: rational(801, 1),
            ..base
        },
        CleanAperture {
            width: rational(801, 2),
            ..base
        },
        CleanAperture {
            width: rational(i64::MAX, 1),
            ..base
        },
        CleanAperture {
            width: rational(i64::MIN, -1),
            ..base
        },
        CleanAperture {
            height: rational(200, 0),
            ..base
        },
        CleanAperture {
            horizontal_offset: rational(201, 1),
            ..base
        },
        CleanAperture {
            horizontal_offset: rational(-201, 1),
            ..base
        },
        CleanAperture {
            vertical_offset: rational(1, 2),
            ..base
        },
        CleanAperture {
            vertical_offset: rational(i64::MIN, i64::MAX),
            ..base
        },
        CleanAperture {
            vertical_offset: rational(0, 0),
            ..base
        },
    ] {
        assert_eq!(metadata(invalid).display_dimensions(), None, "{invalid:?}");
    }
    let large = Metadata {
        dimensions: Some(size(u32::MAX, u32::MAX)),
        transforms: vec![Transform::Crop(CleanAperture {
            horizontal_offset: rational(0, i64::MAX),
            vertical_offset: rational(0, i64::MAX),
            ..crop(u32::MAX, u32::MAX)
        })],
        ..Metadata::default()
    };
    assert_eq!(large.display_dimensions(), large.dimensions);
    let successive = Metadata {
        transforms: vec![
            Transform::Crop(base),
            Transform::Rotate(1),
            Transform::Crop(crop(100, 300)),
        ],
        ..metadata(base)
    };
    assert_eq!(successive.display_dimensions(), Some(size(100, 300)));
    for transform in [Transform::Rotate(4), Transform::Mirror(2)] {
        let invalid = Metadata {
            transforms: vec![transform],
            ..metadata(base)
        };
        assert_eq!(invalid.display_dimensions(), None);
    }
}

fn size(width: u32, height: u32) -> Dimensions {
    Dimensions { width, height }
}

fn rational(numerator: i64, denominator: i64) -> Rational {
    Rational {
        numerator,
        denominator,
    }
}

fn crop(width: u32, height: u32) -> CleanAperture {
    CleanAperture {
        width: rational(i64::from(width), 1),
        height: rational(i64::from(height), 1),
        horizontal_offset: rational(0, 1),
        vertical_offset: rational(0, 1),
    }
}

fn transformed_heif(order: &[u8]) -> Vec<u8> {
    let ispe = [
        vec![0; 4],
        800u32.to_be_bytes().to_vec(),
        600u32.to_be_bytes().to_vec(),
    ]
    .concat();
    let clap: Vec<u8> = [400u32, 1, 200, 1, 0, 1, 0, 1]
        .into_iter()
        .flat_map(u32::to_be_bytes)
        .collect();
    let properties = [
        box_bytes(*b"ispe", &ispe),
        box_bytes(*b"clap", &clap),
        box_bytes(*b"irot", &[1]),
        box_bytes(*b"imir", &[0]),
        box_bytes(*b"irot", &[2]),
    ]
    .concat();
    let mut associations = vec![0, 0, 0, 0, 0, 0, 0, 2, 0, 1, order.len() as u8];
    associations.extend(order);
    associations.extend([0, 2, 1, 5]);
    [
        box_bytes(*b"ftyp", b"heic\0\0\0\0mif1"),
        box_bytes(
            *b"meta",
            &[
                vec![0; 4],
                box_bytes(*b"pitm", &[0, 0, 0, 0, 0, 1]),
                box_bytes(
                    *b"iprp",
                    &[
                        box_bytes(*b"ipco", &properties),
                        box_bytes(*b"ipma", &associations),
                    ]
                    .concat(),
                ),
            ]
            .concat(),
        ),
    ]
    .concat()
}
