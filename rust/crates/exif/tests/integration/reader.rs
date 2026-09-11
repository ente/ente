use super::common::*;
use ente_exif::{Error, Ifd, Limits, Mode, Rational, Value, namespace};
use std::io::Cursor;

#[test]
fn tiff_byte_orders_and_exact_typed_values() {
    for big in [false, true] {
        let number = |n: u32| {
            if big {
                n.to_be_bytes().to_vec()
            } else {
                n.to_le_bytes().to_vec()
            }
        };
        let ratio = [number((-1i32) as u32), number(125)].concat();
        let data = tiff(
            &[
                (0x10f, 2, 6, b"Canon\0".to_vec()),
                (0x112, 3, 1, if big { vec![0, 6] } else { vec![6, 0] }),
                (0x829a, 10, 1, ratio),
                (0x100, 4, 1, number(4032)),
                (0x101, 4, 1, number(3024)),
            ],
            big,
        );
        let metadata = read(&data, Mode::Details);
        assert_eq!(metadata.orientation(), Some(6));
        assert_eq!(
            metadata.tag(Ifd::Image(0), 0x10f).unwrap().value.text(),
            Some("Canon")
        );
        assert_eq!(
            metadata.tag(Ifd::Image(0), 0x829a).unwrap().value,
            Value::Rational(vec![Rational {
                numerator: -1,
                denominator: 125
            }])
        );
        assert_eq!(metadata.dimensions.unwrap().width, 4032);
    }
}

#[test]
fn summary_skips_large_opaque_values_without_fetching_them() {
    let mut data = tiff(
        &[(0x927c, 7, 4_000_000, 26u32.to_le_bytes().to_vec())],
        false,
    );
    data.resize(4_000_026, 0xab);
    let summary = read(&data, Mode::Summary);
    let details = read(&data, Mode::Details);
    assert!(summary.tags.is_empty());
    assert!(summary.statistics.bytes_read < 100);
    assert!(details.statistics.bytes_read < 100);
    assert_eq!(details.tags[0].value, Value::Omitted { bytes: 4_000_000 });
}

#[test]
fn jpeg_dimensions_override_stale_exif_and_pixels_are_skipped() {
    let exif = tiff(
        &[
            (0x100, 4, 1, 6000u32.to_le_bytes().to_vec()),
            (0x101, 4, 1, 4000u32.to_le_bytes().to_vec()),
        ],
        false,
    );
    let mut data = jpeg(&exif, "");
    let before = read(&data, Mode::Summary);
    data.resize(20_000_000, 0);
    let after = read(&data, Mode::Summary);
    assert_eq!(after.dimensions.unwrap().width, 30);
    assert_eq!(before.statistics.bytes_read, after.statistics.bytes_read);
}

#[test]
fn xmp_namespaces_elements_attributes_arrays_and_entities() {
    let source = xmp(
        r#"<p:ProjectionType>equirectangular</p:ProjectionType><e:DateTimeOriginal>2025-01-30T08:59:50.123456+05:30</e:DateTimeOriginal><d:description><r:Alt><r:li xml:lang="x-default">Sun &amp; snow &#x2603;</r:li><r:li xml:lang="fr">Neige</r:li></r:Alt></d:description>"#,
    );
    let metadata = read(source.as_bytes(), Mode::Summary);
    assert!(metadata.is_panorama());
    assert_eq!(
        metadata.property(namespace::EXIF, "DateTimeOriginal"),
        Some("2025-01-30T08:59:50.123456+05:30")
    );
    let captions: Vec<_> = metadata
        .xmp
        .iter()
        .filter(|p| p.name == "description")
        .collect();
    assert_eq!(captions.len(), 2);
    assert_eq!(captions[0].value, "Sun & snow ☃");
    assert_eq!(captions[0].language.as_deref(), Some("x-default"));
    assert_ne!(captions[0].item, captions[1].item);
}

#[test]
fn packetless_utf8_bom_xmp() {
    let xml = "\u{feff}  <?xml version=\"1.0\" encoding=\"UTF-8\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><r:RDF xmlns:r=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><r:Description xmlns:p=\"http://ns.adobe.com/photoshop/1.0/\" p:DateCreated=\"2023-04-27T14:51:16+05:30\"/></r:RDF></x:xmpmeta>";
    assert_eq!(
        read(xml.as_bytes(), Mode::Summary).property(namespace::PHOTOSHOP, "DateCreated"),
        Some("2023-04-27T14:51:16+05:30")
    );
}

#[test]
fn heif_file_and_idat_extents_and_primary_properties() {
    let exif = tiff(&[(0x112, 3, 1, vec![6, 0])], false);
    for method in [0, 1] {
        for split in [false, true] {
            let metadata = read(&heif(&exif, method, split), Mode::Summary);
            assert_eq!(metadata.dimensions.unwrap().width, 800);
            assert_eq!(metadata.transforms.len(), 2);
            assert_eq!(metadata.transforms[0], ente_exif::Transform::Rotate(1));
            let ente_exif::Transform::Crop(crop) = metadata.transforms[1] else {
                panic!("missing crop");
            };
            assert_eq!(crop.width.as_f64(), Some(640.0));
            assert_eq!(crop.horizontal_offset.as_f64(), Some(-0.5));
            assert_eq!(metadata.orientation(), Some(6));
            assert!(metadata.issues.is_empty(), "{:?}", metadata.issues);
        }
    }
}

#[test]
fn png_metadata_after_image_data_and_compressed_xmp() {
    let source = xmp("<p:ProjectionType>cylindrical</p:ProjectionType>");
    let compressed = miniz_oxide::deflate::compress_to_vec_zlib(source.as_bytes(), 6);
    let text = [b"XML:com.adobe.xmp\0\x01\0\0\0".to_vec(), compressed].concat();
    let mut ihdr = [800u32.to_be_bytes(), 600u32.to_be_bytes()].concat();
    ihdr.extend([8, 2, 0, 0, 0]);
    let data = [
        b"\x89PNG\r\n\x1a\n".to_vec(),
        png_chunk(*b"IHDR", &ihdr),
        png_chunk(*b"IDAT", &vec![0; 1_000_000]),
        png_chunk(*b"iTXt", &text),
        png_chunk(*b"IEND", &[]),
    ]
    .concat();
    let metadata = read(&data, Mode::Summary);
    assert!(metadata.is_panorama());
    assert!(metadata.statistics.bytes_read < 2000);
    assert!(metadata.issues.is_empty());
}

#[test]
fn malformed_metadata_does_not_discard_valid_dimensions() {
    let metadata = read(&jpeg(b"MM\0*\xff\xff\xff\xff", ""), Mode::Summary);
    assert_eq!(metadata.dimensions.unwrap().width, 30);
    assert!(!metadata.issues.is_empty());
}

#[test]
fn cycles_and_limits_are_explicit() {
    let mut data = tiff(&[], false);
    data[10..14].copy_from_slice(&8u32.to_le_bytes());
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&data), Mode::Details, Limits::default()),
        Err(Error::Malformed("cyclic IFD"))
    ));
    let data = tiff(&[(0x10f, 2, 6, b"Canon\0".to_vec())], false);
    let limits = Limits {
        value_bytes: 4,
        ..Limits::default()
    };
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&data), Mode::Summary, limits),
        Err(Error::Limit(_))
    ));
    let limits = Limits {
        output_bytes: 4,
        ..Limits::default()
    };
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&data), Mode::Summary, limits),
        Err(Error::Limit(_))
    ));
}

#[test]
fn dtd_and_deep_xml_are_rejected() {
    let data = b"<!DOCTYPE r [<!ENTITY payload SYSTEM 'file:///etc/passwd'>]><r/>";
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(data), Mode::Summary, Limits::default()),
        Err(Error::Unsupported("XML DTD"))
    ));
    let source = xmp(&format!("{}{}", "<t:n>".repeat(50), "</t:n>".repeat(50)));
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(source), Mode::Summary, Limits::default()),
        Err(Error::Limit("XML depth"))
    ));
}

#[test]
fn truncations_and_header_mutations_never_panic() {
    let tiff = tiff(&[(0x10f, 2, 6, b"Canon\0".to_vec())], false);
    let packet = xmp("<d:subject><r:Bag><r:li>café</r:li></r:Bag></d:subject>");
    let png = [
        b"\x89PNG\r\n\x1a\n".to_vec(),
        png_chunk(*b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]),
        png_chunk(*b"tEXt", b"Caf\xe9\0Caption"),
        png_chunk(*b"IEND", &[]),
    ]
    .concat();
    let seeds = [
        tiff.clone(),
        jpeg(&tiff, &packet),
        heif(&tiff, 0, false),
        heif(&tiff, 1, true),
        packet.into_bytes(),
        png,
    ];
    for seed in seeds {
        for limits in [
            Limits::default(),
            Limits {
                read_bytes: 128,
                value_bytes: 8,
                output_bytes: 64,
                entries: 8,
                directories: 1,
                depth: 2,
            },
        ] {
            for len in 0..=seed.len() {
                exercise(&seed[..len], limits);
            }
            for index in 0..seed.len() {
                for value in [0, 0xff] {
                    let mut bytes = seed.clone();
                    bytes[index] = value;
                    exercise(&bytes, limits);
                }
            }
        }
    }
}
