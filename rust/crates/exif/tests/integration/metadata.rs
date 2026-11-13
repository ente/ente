use super::common::*;
use ente_exif::{Error, Ifd, Limits, Location, Mode, namespace};
use std::io::Cursor;

#[test]
fn xmp_coordinate_forms_and_invalid_axes() {
    for (lat, lon, refs, expected) in [
        ("12.97236N", "77.59457E", "", Some((12.97236, 77.59457))),
        ("33.8688S", "151.2093W", "", Some((-33.8688, -151.2093))),
        (
            "37,46.5N",
            "122,25W",
            "",
            Some((37.775, -(122.0 + 25.0 / 60.0))),
        ),
        (
            "37,46,30N",
            "122,25,0W",
            "",
            Some((37.775, -(122.0 + 25.0 / 60.0))),
        ),
        (
            "8.5",
            "76.25",
            "<e:GPSLatitudeRef>n</e:GPSLatitudeRef><e:GPSLongitudeRef> E </e:GPSLongitudeRef>",
            Some((8.5, 76.25)),
        ),
        ("0N", "0E", "", Some((0.0, 0.0))),
        ("90N", "180E", "", Some((90.0, 180.0))),
        ("12E", "77N", "", None),
        ("91N", "181E", "", None),
        ("12,60N", "77E", "", None),
        ("NaNN", "77E", "", None),
        ("infN", "77E", "", None),
        ("12N", "", "", None),
        ("12", "77", "", None),
        ("12,0,0,1N", "77E", "", None),
    ] {
        let source = xmp(&format!(
            "<e:GPSLatitude>{lat}</e:GPSLatitude><e:GPSLongitude>{lon}</e:GPSLongitude>{refs}"
        ));
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(source.as_bytes(), mode);
            assert_eq!(
                metadata.xmp_location(),
                expected.map(|(latitude, longitude)| Location {
                    latitude,
                    longitude
                })
            );
            assert_eq!(metadata.exif_location(), None);
        }
    }
}

#[test]
fn descriptions_preserve_alternatives_and_choose_language_on_demand() {
    let source = xmp(
        r#"<d:description><r:Alt><r:li xml:lang="fr">Neige</r:li><r:li xml:lang="x-default">Snow</r:li><r:li xml:lang="en">White snow</r:li></r:Alt></d:description>"#,
    );
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(source.as_bytes(), mode);
        assert_eq!(metadata.xmp_description(None), Some("Snow"));
        assert_eq!(metadata.xmp_description(Some("FR")), Some("Neige"));
        assert_eq!(metadata.xmp_description(Some("de")), Some("Snow"));
        assert_eq!(metadata.properties(namespace::DC, "description").count(), 3);
    }
}

#[test]
fn xmp_prefixes_do_not_change_keywords_descriptions_or_attributes() {
    for (rdf, dc, tiff) in [("rdf", "dc", "tiff"), ("n", "words", "camera")] {
        let source = format!(
            r#"<{rdf}:RDF xmlns:{rdf}="{}" xmlns:{dc}="{}" xmlns:{tiff}="{}">
            <{rdf}:Description {tiff}:Make="Test camera">
              <{dc}:subject><{rdf}:Bag>
                <{rdf}:li>forest</{rdf}:li><{rdf}:li>café</{rdf}:li><{rdf}:li>forest</{rdf}:li>
              </{rdf}:Bag></{dc}:subject>
              <{dc}:description><{rdf}:Alt>
                <{rdf}:li xml:lang="x-default">Morning</{rdf}:li>
                <{rdf}:li xml:lang="fr">Matin</{rdf}:li>
              </{rdf}:Alt></{dc}:description>
            </{rdf}:Description></{rdf}:RDF>"#,
            namespace::RDF,
            namespace::DC,
            namespace::TIFF,
        );
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(source.as_bytes(), mode);
            assert_eq!(
                metadata.property(namespace::TIFF, "Make"),
                Some("Test camera")
            );
            assert_eq!(metadata.xmp_description(None), Some("Morning"));
            assert_eq!(metadata.xmp_description(Some("fr")), Some("Matin"));
            let keywords: Vec<_> = metadata
                .properties(namespace::DC, "subject")
                .map(|p| p.value.as_str())
                .collect();
            if mode == Mode::Details {
                assert_eq!(keywords, ["forest", "café", "forest"]);
            } else {
                assert!(keywords.is_empty());
            }
        }
    }
}

#[test]
fn skipped_xmp_values_do_not_consume_retention_budgets() {
    let source = xmp(&format!(
        r#"<r:Description xmlns:c="{}" c:HdrPlusMakernote="{}"/><p:ProjectionType>cylindrical</p:ProjectionType>"#,
        namespace::CAMERA,
        "x".repeat(Limits::default().value_bytes + 1)
    ));
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(source.as_bytes(), mode);
        assert!(metadata.is_panorama());
        assert_eq!(
            metadata.property(namespace::CAMERA, "HdrPlusMakernote"),
            None
        );
    }
    let source = xmp(&format!(
        "<d:subject>{}</d:subject><d:description>Kept</d:description>",
        "x".repeat(Limits::default().value_bytes + 1)
    ));
    assert_eq!(
        read(source.as_bytes(), Mode::Summary).xmp_description(None),
        Some("Kept")
    );
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&source), Mode::Details, Limits::default()),
        Err(Error::Limit(_))
    ));
    let limits = Limits {
        read_bytes: 100,
        ..Limits::default()
    };
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&source), Mode::Summary, limits),
        Err(Error::Limit(_))
    ));
}

#[test]
fn structured_read_preserves_region_owners_and_nested_list_identity() {
    let source = xmp(
        r#"<m:Regions xmlns:m="urn:regions" xmlns:a="urn:area"><m:RegionList><r:Bag>
      <r:li r:parseType="Resource"><m:Name>Alice</m:Name><m:Area a:x="0.2" a:y="0.3"/><d:subject><r:Bag><r:li>family</r:li></r:Bag></d:subject></r:li>
      <r:li r:parseType="Resource"><m:Name>Bob</m:Name><m:Area a:x="0.8" a:y="0.7"/></r:li>
    </r:Bag></m:RegionList></m:Regions>"#,
    );
    let structured =
        ente_exif::read_structured(&mut Cursor::new(source.as_bytes()), Limits::default()).unwrap();
    let metadata = &structured.metadata;
    assert_eq!(metadata, &read(source.as_bytes(), Mode::Details));
    assert_eq!(structured.xmp.parents.len(), metadata.xmp.len());
    let owner = |property: &ente_exif::Property| {
        let index = metadata
            .xmp
            .iter()
            .position(|p| std::ptr::eq(p, property))
            .unwrap();
        let mut node = structured.xmp.parents[index];
        while let Some(index) = node {
            let n = &structured.xmp.nodes[index as usize];
            if n.namespace == namespace::RDF && n.name == "li" && n.item == Some(1) {
                return n.item;
            }
            node = n.parent;
        }
        None
    };
    let alice = metadata
        .properties("urn:regions", "Name")
        .find(|p| p.value == "Alice")
        .unwrap();
    let family = metadata
        .properties(namespace::DC, "subject")
        .next()
        .unwrap();
    assert_ne!(alice.item, family.item);
    assert_eq!(owner(alice), Some(1));
    assert_eq!(owner(family), Some(1));
    let coordinates: Vec<_> = metadata.properties("urn:area", "x").collect();
    assert_eq!(owner(coordinates[0]), Some(1));
    assert_eq!(owner(coordinates[1]), None);
    assert_ne!(coordinates[0].item, coordinates[1].item);
}

#[test]
fn structured_ancestors_share_the_output_budget() {
    let source = xmp(
        "<d:a><d:b><d:c><d:d><d:e><d:f><d:subject><r:Bag><r:li>family</r:li></r:Bag></d:subject></d:f></d:e></d:d></d:c></d:b></d:a>",
    );
    let limits = Limits {
        output_bytes: 512,
        ..Limits::default()
    };
    assert!(ente_exif::read(&mut Cursor::new(&source), Mode::Details, limits).is_ok());
    assert!(matches!(
        ente_exif::read_structured(&mut Cursor::new(&source), limits),
        Err(Error::Limit(_))
    ));
}

#[test]
fn broken_secondary_directory_does_not_hide_primary_exif() {
    let mut bytes = tiff(&[(0x8769, 4, 1, 26u32.to_le_bytes().to_vec())], false);
    bytes[22..26].copy_from_slice(&u32::MAX.to_le_bytes());
    bytes.extend_from_slice(&tiff(&[(0xa401, 3, 1, vec![6, 0])], false)[8..]);
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(&bytes, mode);
        assert_eq!(
            metadata.tag(Ifd::Exif(0), 0xa401).unwrap().value.unsigned(),
            Some(6)
        );
        assert!(metadata.is_panorama());
        assert_eq!(metadata.issues.len(), usize::from(mode == Mode::Details));
    }
}

#[test]
fn utf16_sidecars_decode_both_orders_and_reject_invalid_surrogates() {
    let source = xmp("<d:description>Snow ☃</d:description>");
    for little in [false, true] {
        let mut bytes = if little {
            vec![0xff, 0xfe]
        } else {
            vec![0xfe, 0xff]
        };
        for unit in source.encode_utf16() {
            bytes.extend(if little {
                unit.to_le_bytes()
            } else {
                unit.to_be_bytes()
            });
        }
        for mode in [Mode::Summary, Mode::Details] {
            assert_eq!(read(&bytes, mode).xmp_description(None), Some("Snow ☃"));
        }
    }
    assert!(
        ente_exif::read(
            &mut Cursor::new([0xff, 0xfe, 0, 0xd8]),
            Mode::Summary,
            Limits::default()
        )
        .is_err()
    );
}

#[test]
fn dimensions_keep_stored_size_and_explicit_orientation_separate() {
    use ente_exif::Dimensions;
    let stored = Dimensions {
        width: 640,
        height: 480,
    };
    for orientation in [0u32, 1, 2, 3, 4, 5, 6, 7, 8, 9, u32::MAX] {
        let bytes = tiff(
            &[
                (0x100, 4, 1, 640u32.to_le_bytes().to_vec()),
                (0x101, 4, 1, 480u32.to_le_bytes().to_vec()),
                (0x112, 4, 1, orientation.to_le_bytes().to_vec()),
            ],
            false,
        );
        let expected = if (5..=8).contains(&orientation) {
            Dimensions {
                width: 480,
                height: 640,
            }
        } else {
            stored
        };
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(&bytes, mode);
            assert_eq!(
                (metadata.width(), metadata.height()),
                (Some(640), Some(480))
            );
            assert_eq!(metadata.display_dimensions(), Some(expected));
            assert_eq!(stored.with_exif_orientation(orientation), expected);
        }
    }
    let empty = ente_exif::Metadata::default();
    assert_eq!(empty.width(), None);
    assert_eq!(empty.height(), None);
    assert_eq!(empty.display_dimensions(), None);
    let no_orientation = ente_exif::Metadata {
        dimensions: Some(stored),
        ..empty
    };
    assert_eq!(no_orientation.display_dimensions(), Some(stored));
}

#[test]
fn xmp_dimensions_require_a_complete_positive_integer_pair() {
    for (fields, expected) in [
        (
            "<t:ImageWidth>640</t:ImageWidth><t:ImageLength>480</t:ImageLength>",
            Some((640, 480)),
        ),
        (
            "<e:PixelXDimension>1280</e:PixelXDimension><e:PixelYDimension>720</e:PixelYDimension>",
            Some((1280, 720)),
        ),
        (
            "<t:ImageWidth>640</t:ImageWidth><e:PixelYDimension>480</e:PixelYDimension>",
            None,
        ),
        (
            "<t:ImageWidth>0</t:ImageWidth><t:ImageLength>480</t:ImageLength>",
            None,
        ),
        (
            "<t:ImageWidth>640px</t:ImageWidth><t:ImageLength>480</t:ImageLength>",
            None,
        ),
        (
            "<t:ImageWidth>-640</t:ImageWidth><t:ImageLength>480</t:ImageLength>",
            None,
        ),
        (
            "<t:ImageWidth>4294967296</t:ImageWidth><t:ImageLength>480</t:ImageLength>",
            None,
        ),
    ] {
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(xmp(fields).as_bytes(), mode);
            assert_eq!(
                metadata.xmp_dimensions().map(|d| (d.width, d.height)),
                expected
            );
            assert_eq!(metadata.dimensions, None);
        }
    }
}

#[test]
fn camera_and_description_helpers_borrow_trimmed_exif_text() {
    let bytes = tiff(
        &[
            (0x10f, 2, 9, b" Camera \0".to_vec()),
            (0x110, 2, 9, b" Model  \0".to_vec()),
            (0x10e, 2, 10, b" Caption \0".to_vec()),
        ],
        false,
    );
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(&bytes, mode);
        assert_eq!(metadata.camera_make(), Some("Camera"));
        assert_eq!(metadata.camera_model(), Some("Model"));
        assert_eq!(metadata.exif_description(), Some("Caption"));
        let raw = metadata
            .tag(Ifd::Image(0), 0x10f)
            .unwrap()
            .value
            .text()
            .unwrap();
        assert_eq!(raw, " Camera ");
        assert_eq!(metadata.camera_make().unwrap().as_ptr(), raw[1..].as_ptr());
    }
    for entry in [
        (0x10f, 2, 3, b"  \0".to_vec()),
        (0x10f, 2, 2, vec![255, 0]),
        (0x10f, 3, 1, vec![1, 0]),
    ] {
        assert_eq!(
            read(&tiff(&[entry], false), Mode::Summary).camera_make(),
            None
        );
    }
}

#[test]
fn photographic_helpers_preserve_exact_exposure_and_legacy_sensitivity() {
    use ente_exif::Rational;
    let rational = |n: u32, d: u32| [n.to_le_bytes(), d.to_le_bytes()].concat();
    let bytes = child_ifd(
        0x8769,
        tiff(
            &[
                (0xa434, 2, 9, b" Lens   \0".to_vec()),
                (0x829a, 5, 1, rational(1, 125)),
                (0x829d, 5, 1, rational(28, 10)),
                (0x920a, 5, 1, rational(35, 1)),
                (
                    0x8827,
                    3,
                    2,
                    [200u16.to_le_bytes(), 65535u16.to_le_bytes()].concat(),
                ),
            ],
            false,
        ),
    );
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(&bytes, mode);
        assert_eq!(metadata.lens_model(), Some("Lens"));
        assert_eq!(
            metadata.exposure_time(),
            Some(Rational {
                numerator: 1,
                denominator: 125
            })
        );
        assert_eq!(metadata.f_number(), Some(2.8));
        assert_eq!(metadata.focal_length(), Some(35.0));
        assert_eq!(metadata.iso_speed_ratings(), Some([200, 65535].as_slice()));
    }
    for (count, value) in [
        (1, rational(0, 1)),
        (1, rational(1, 0)),
        (2, rational(1, 2).repeat(2)),
    ] {
        let bytes = child_ifd(
            0x8769,
            tiff(
                &[
                    (0x829a, 5, count, value.clone()),
                    (0x829d, 5, count, value.clone()),
                    (0x920a, 5, count, value),
                ],
                false,
            ),
        );
        let metadata = read(&bytes, Mode::Summary);
        assert_eq!(metadata.exposure_time(), None);
        assert_eq!(metadata.f_number(), None);
        assert_eq!(metadata.focal_length(), None);
    }
}
