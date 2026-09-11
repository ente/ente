use super::common::*;
use ente_exif::{Ifd, Location, Mode, Rational, Value, namespace};

#[test]
fn gps_hemispheres_zero_denominators_and_raw_dates() {
    let rational = |n: u32, d: u32| [n.to_le_bytes(), d.to_le_bytes()].concat();
    for (latitude, longitude, expected) in [
        ("N", "E", Some((0.0, 0.0))),
        ("S", "W", Some((-0.0, -0.0))),
        ("X", "W", None),
    ] {
        let gps = tiff(
            &[
                (1, 2, 2, vec![latitude.as_bytes()[0], 0]),
                (2, 5, 3, rational(0, 1).repeat(3)),
                (3, 2, 2, vec![longitude.as_bytes()[0], 0]),
                (4, 5, 3, rational(0, 1).repeat(3)),
            ],
            false,
        );
        let data = child_ifd(0x8825, gps);
        assert_eq!(
            read(&data, Mode::Summary).exif_location(),
            expected.map(|(latitude, longitude)| Location {
                latitude,
                longitude
            })
        );
    }
    for (latitude, longitude, expected) in [
        (b'N', b'E', (12.5, 20.25)),
        (b'N', b'W', (12.5, -20.25)),
        (b'S', b'E', (-12.5, 20.25)),
        (b'S', b'W', (-12.5, -20.25)),
    ] {
        let gps = child_ifd(
            0x8825,
            tiff(
                &[
                    (1, 2, 2, vec![latitude, 0]),
                    (3, 2, 2, vec![longitude, 0]),
                    (
                        2,
                        5,
                        3,
                        [rational(12, 1), rational(30, 1), rational(0, 1)].concat(),
                    ),
                    (
                        4,
                        5,
                        3,
                        [rational(20, 1), rational(15, 1), rational(0, 1)].concat(),
                    ),
                ],
                false,
            ),
        );
        for mode in [Mode::Summary, Mode::Details] {
            assert_eq!(
                read(&gps, mode).exif_location(),
                Some(Location {
                    latitude: expected.0,
                    longitude: expected.1
                })
            );
        }
    }
    let broken = child_ifd(
        0x8825,
        tiff(
            &[
                (2, 5, 3, rational(0, 0).repeat(3)),
                (4, 5, 3, rational(0, 1).repeat(3)),
            ],
            false,
        ),
    );
    assert_eq!(read(&broken, Mode::Summary).exif_location(), None);
    assert_eq!(
        read(&broken, Mode::Summary)
            .tag(Ifd::Gps(0), 2)
            .unwrap()
            .value
            .number(0),
        None
    );

    let exif = child_ifd(
        0x8769,
        tiff(
            &[
                (0x9003, 2, 20, b"2024:03:31 02:30:00\0".to_vec()),
                (0x9011, 2, 7, b"+05:30\0".to_vec()),
                (0x9291, 2, 7, b"123456\0".to_vec()),
                (0x829a, 5, 1, rational(1, 125)),
                (0xa401, 3, 1, vec![6, 0]),
            ],
            false,
        ),
    );
    let metadata = read(&exif, Mode::Summary);
    assert_eq!(
        metadata.tag(Ifd::Exif(0), 0x9003).unwrap().value.text(),
        Some("2024:03:31 02:30:00")
    );
    assert_eq!(
        metadata.tag(Ifd::Exif(0), 0x9011).unwrap().value.text(),
        Some("+05:30")
    );
    assert_eq!(
        metadata.tag(Ifd::Exif(0), 0x9291).unwrap().value.text(),
        Some("123456")
    );
    assert_eq!(
        metadata.tag(Ifd::Exif(0), 0x829a).unwrap().value,
        Value::Rational(vec![Rational {
            numerator: 1,
            denominator: 125
        }])
    );
    assert!(metadata.is_panorama());
}

#[test]
fn gps_rejects_malformed_references_and_components() {
    let gps = |mut refs: Vec<(u16, u16, u32, Vec<u8>)>, minutes: i32, seconds: i32| {
        let ratio = |n: i32| [n.to_le_bytes(), 1i32.to_le_bytes()].concat();
        refs.extend([
            (
                2,
                10,
                3,
                [ratio(-12), ratio(minutes), ratio(seconds)].concat(),
            ),
            (4, 10, 3, [ratio(-20), ratio(15), ratio(0)].concat()),
        ]);
        child_ifd(0x8825, tiff(&refs, false))
    };
    for (refs, expected) in [
        (
            vec![],
            Some(Location {
                latitude: -12.5,
                longitude: -20.25,
            }),
        ),
        (
            vec![(1, 2, 2, b"N\0".to_vec()), (3, 2, 2, b"E\0".to_vec())],
            Some(Location {
                latitude: 12.5,
                longitude: 20.25,
            }),
        ),
        (vec![(1, 2, 2, b"N\0".to_vec())], None),
        (vec![(1, 2, 2, vec![255, 0]), (3, 2, 2, vec![255, 0])], None),
        (vec![(1, 2, 1, vec![0]), (3, 2, 1, vec![0])], None),
        (
            vec![(1, 4, 1, vec![1, 0, 0, 0]), (3, 4, 1, vec![1, 0, 0, 0])],
            None,
        ),
    ] {
        for mode in [Mode::Summary, Mode::Details] {
            assert_eq!(
                read(&gps(refs.clone(), 30, 0), mode).exif_location(),
                expected
            );
        }
    }
    for (minutes, seconds) in [(60, 0), (-60, 0), (0, 60), (0, -60), (90, 0)] {
        for mode in [Mode::Summary, Mode::Details] {
            assert_eq!(
                read(&gps(vec![], minutes, seconds), mode).exif_location(),
                None
            );
        }
    }
}

#[test]
fn heif_contiguous_exif_skips_opaque_values_within_the_read_budget() {
    let exif = child_ifd(
        0x8769,
        tiff(
            &[
                (0x927c, 7, 256 * 1024, vec![1; 256 * 1024]),
                (0xa434, 2, 5, b"Lens\0".to_vec()),
            ],
            false,
        ),
    );
    for method in [0, 1] {
        for mode in [Mode::Summary, Mode::Details] {
            let limits = ente_exif::Limits {
                read_bytes: 1024,
                ..ente_exif::Limits::default()
            };
            let direct = ente_exif::read(
                &mut std::io::Cursor::new(heif(&exif, method, false)),
                mode,
                limits,
            )
            .unwrap();
            let assembled = read(&heif(&exif, method, true), mode);
            assert_eq!(direct.tags, assembled.tags);
            assert_eq!(
                direct.tag(Ifd::Exif(0), 0xa434).unwrap().value.text(),
                Some("Lens")
            );
            assert!(direct.issues.is_empty());
            assert!(direct.statistics.bytes_read < 1024);
            assert!(assembled.statistics.bytes_read > 256 * 1024);
        }
    }
}

#[test]
fn heif_exif_cannot_read_beyond_its_declared_extent() {
    let exif = tiff(&[(0x112, 3, 1, vec![6, 0])], false);
    for method in [0, 1] {
        for size in [0u32, 3, 11, 12] {
            let mut bytes = heif(&exif, method, false);
            let iloc = bytes.windows(4).position(|b| b == b"iloc").unwrap() + 4;
            bytes[iloc + 24..iloc + 28].copy_from_slice(&size.to_be_bytes());
            for mode in [Mode::Summary, Mode::Details] {
                let metadata = read(&bytes, mode);
                assert_eq!(metadata.orientation(), None);
                assert!(metadata.dimensions.is_some());
                assert!(!metadata.issues.is_empty());
            }
        }
    }
}

#[test]
fn heif_protected_metadata_preserves_image_dimensions() {
    let exif = [vec![0; 4], tiff(&[(0x112, 3, 1, vec![6, 0])], false)].concat();
    let packet = xmp("<p:ProjectionType>equirectangular</p:ProjectionType>");
    for mime in [
        None,
        Some("application/rdf+xml"),
        Some("application/xml"),
        Some("text/xml"),
    ] {
        for protected in [false, true] {
            let data = if mime.is_some() {
                packet.as_bytes()
            } else {
                &exif
            };
            let mut info = vec![2, 0, 0, 0, 0, 2, 0, u8::from(protected)];
            info.extend(if mime.is_some() { b"mime\0" } else { b"Exif\0" });
            if let Some(mime) = mime {
                info.extend(mime.as_bytes());
                info.extend([0, 0]);
            }
            let mut location = vec![1, 0, 0, 0, 0x44, 0, 0, 1, 0, 2, 0, 1, 0, 0, 0, 1];
            location.extend(0u32.to_be_bytes());
            location.extend((data.len() as u32).to_be_bytes());
            let image_size = box_bytes(*b"ispe", &[0u32, 640, 480].map(u32::to_be_bytes).concat());
            let mut properties = box_bytes(*b"ipco", &image_size);
            properties.extend(box_bytes(*b"ipma", &[0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1]));
            let mut meta = vec![0; 4];
            meta.extend(box_bytes(*b"pitm", &[0, 0, 0, 0, 0, 1]));
            meta.extend(box_bytes(
                *b"iinf",
                &[vec![0, 0, 0, 0, 0, 1], box_bytes(*b"infe", &info)].concat(),
            ));
            meta.extend(box_bytes(*b"iloc", &location));
            meta.extend(box_bytes(*b"iprp", &properties));
            meta.extend(box_bytes(*b"idat", data));
            let bytes = [
                box_bytes(*b"ftyp", b"heic\0\0\0\0mif1"),
                box_bytes(*b"meta", &meta),
            ]
            .concat();
            for mode in [Mode::Summary, Mode::Details] {
                let metadata = read(&bytes, mode);
                assert_eq!(
                    (metadata.width(), metadata.height()),
                    (Some(640), Some(480))
                );
                assert_eq!(
                    metadata.orientation(),
                    (!protected && mime.is_none()).then_some(6)
                );
                assert_eq!(metadata.is_panorama(), !protected && mime.is_some());
                assert_eq!(metadata.issues.len(), usize::from(protected));
                if protected {
                    assert_eq!(metadata.issues[0].message, "protected metadata");
                }
            }
        }
    }
}

#[test]
fn heif_metadata_prefers_primary_references() {
    for mime in [
        None,
        Some("application/rdf+xml"),
        Some("application/xml"),
        Some("text/xml"),
    ] {
        for (targets, expected, ambiguous) in [
            ([Some(1u16), None], Some(6), false),
            ([None, Some(1)], Some(3), false),
            ([Some(1), Some(1)], None, true),
            ([None, None], None, true),
            ([Some(4), Some(1)], Some(3), false),
            ([Some(1), Some(4)], Some(6), false),
            ([None, Some(4)], Some(6), false),
            ([Some(4), None], Some(3), false),
            ([Some(4), Some(4)], None, false),
        ] {
            let mut info = vec![0, 0, 0, 0, 0, 2];
            let mut locations = vec![1, 0, 0, 0, 0x44, 0, 0, 2];
            let mut references = vec![0; 4];
            let mut data = Vec::new();
            for (index, target) in targets.into_iter().enumerate() {
                let id = index as u16 + 2;
                let orientation = if index == 0 { 6 } else { 3 };
                let value = if mime.is_some() {
                    xmp(&format!("<t:Orientation>{orientation}</t:Orientation>")).into_bytes()
                } else {
                    [
                        vec![0; 4],
                        tiff(&[(0x112, 3, 1, vec![orientation, 0])], false),
                    ]
                    .concat()
                };
                let mut entry = vec![2, 0, 0, 0];
                entry.extend(id.to_be_bytes());
                entry.extend([0, 0]);
                entry.extend(if mime.is_some() { b"mime\0" } else { b"Exif\0" });
                if let Some(mime) = mime {
                    entry.extend(mime.as_bytes());
                    entry.extend([0, 0]);
                }
                info.extend(box_bytes(*b"infe", &entry));
                locations.extend([id, 1, 0, 1].map(u16::to_be_bytes).concat());
                locations.extend((data.len() as u32).to_be_bytes());
                locations.extend((value.len() as u32).to_be_bytes());
                data.extend(value);
                if let Some(target) = target {
                    references.extend(box_bytes(
                        *b"cdsc",
                        &[id, 1, target].map(u16::to_be_bytes).concat(),
                    ));
                }
            }
            let mut meta = vec![0; 4];
            meta.extend(box_bytes(*b"pitm", &[0, 0, 0, 0, 0, 1]));
            meta.extend(box_bytes(*b"iinf", &info));
            meta.extend(box_bytes(*b"iloc", &locations));
            meta.extend(box_bytes(*b"iref", &references));
            meta.extend(box_bytes(*b"idat", &data));
            let bytes = [
                box_bytes(*b"ftyp", b"heic\0\0\0\0mif1"),
                box_bytes(*b"meta", &meta),
            ]
            .concat();
            for mode in [Mode::Summary, Mode::Details] {
                let metadata = read(&bytes, mode);
                let orientation = if mime.is_some() {
                    metadata
                        .property(namespace::TIFF, "Orientation")
                        .map(|value| value.parse::<u32>().unwrap())
                } else {
                    metadata.orientation()
                };
                assert_eq!(orientation, expected, "{mime:?} {targets:?} {mode:?}");
                assert_eq!(metadata.issues.len(), usize::from(ambiguous));
                if ambiguous {
                    assert_eq!(metadata.issues[0].message, "ambiguous primary metadata");
                }
            }
        }
    }
}

#[test]
fn png_keywords_use_latin1_and_text_obeys_its_chunk_encoding() {
    for (kind, value) in [
        (b"tEXt", b"Caf\xe9\0Andr\xe9".to_vec()),
        (
            b"zTXt",
            [
                b"Caf\xe9\0\0".to_vec(),
                miniz_oxide::deflate::compress_to_vec_zlib(b"Andr\xe9", 6),
            ]
            .concat(),
        ),
        (
            b"iTXt",
            [b"Caf\xe9\0\0\0\0\0".to_vec(), "André".as_bytes().to_vec()].concat(),
        ),
    ] {
        let bytes = [
            b"\x89PNG\r\n\x1a\n".to_vec(),
            png_chunk(*b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]),
            png_chunk(*kind, &value),
            png_chunk(*b"IEND", &[]),
        ]
        .concat();
        let details = read(&bytes, Mode::Details);
        assert_eq!(details.property("urn:png:text", "Café"), Some("André"));
        assert!(details.issues.is_empty());
        let summary = read(&bytes, Mode::Summary);
        assert!(summary.xmp.is_empty());
        assert!(summary.issues.is_empty());
    }
}

#[test]
fn webp_padding_and_all_frame_headers() {
    let packet = xmp("<p:ProjectionType>cylindrical</p:ProjectionType>");
    let exif = tiff(&[(0x112, 3, 1, vec![8, 0])], false);
    for (kind, data) in [
        (b"VP8X", vec![0; 10]),
        (b"VP8 ", vec![0, 0, 0, 0x9d, 1, 0x2a, 1, 0, 1, 0]),
        (b"VP8L", vec![0x2f, 0, 0, 0, 0]),
    ] {
        let chunk = |kind: &[u8; 4], data: &[u8]| {
            [
                kind.to_vec(),
                (data.len() as u32).to_le_bytes().to_vec(),
                data.to_vec(),
                vec![0; data.len() & 1],
            ]
            .concat()
        };
        let body = [
            b"WEBP".to_vec(),
            chunk(b"JUNK", &[1]),
            chunk(kind, &data),
            chunk(b"EXIF", &exif),
            chunk(b"XMP ", packet.as_bytes()),
        ]
        .concat();
        let bytes = [
            b"RIFF".to_vec(),
            (body.len() as u32).to_le_bytes().to_vec(),
            body,
        ]
        .concat();
        let metadata = read(&bytes, Mode::Summary);
        assert_eq!(metadata.dimensions.unwrap().width, 1);
        assert_eq!(metadata.orientation(), Some(8));
        assert!(metadata.is_panorama());
        assert!(metadata.issues.is_empty());
    }
}

#[test]
fn png_summary_skips_text_within_a_small_read_budget() {
    for (kind, fields, compressed) in [
        (b"tEXt", b"".as_slice(), false),
        (b"zTXt", b"\0".as_slice(), true),
        (b"iTXt", b"\0\0en\0Comment\0".as_slice(), false),
        (b"iTXt", b"\x01\0en\0Comment\0".as_slice(), true),
    ] {
        for size in [1024, 4096] {
            let text = vec![b'a'; size];
            let text = if compressed {
                miniz_oxide::deflate::compress_to_vec_zlib(&text, 0)
            } else {
                text
            };
            let bytes = [
                b"\x89PNG\r\n\x1a\n".to_vec(),
                png_chunk(*b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 2, 8, 2, 0, 0, 0]),
                png_chunk(
                    *kind,
                    &[vec![b'C'; 79], vec![0], fields.to_vec(), text].concat(),
                ),
                png_chunk(*b"eXIf", &tiff(&[(0x112, 3, 1, vec![6, 0])], false)),
                png_chunk(*b"IEND", &[]),
            ]
            .concat();
            let limits = ente_exif::Limits {
                read_bytes: 256,
                ..ente_exif::Limits::default()
            };
            let metadata =
                ente_exif::read(&mut std::io::Cursor::new(&bytes), Mode::Summary, limits).unwrap();
            assert_eq!((metadata.width(), metadata.height()), (Some(1), Some(2)));
            assert_eq!(metadata.orientation(), Some(6));
            assert!(metadata.issues.is_empty());
            assert!(metadata.xmp.is_empty());
            assert!(matches!(
                ente_exif::read(&mut std::io::Cursor::new(&bytes), Mode::Details, limits),
                Err(ente_exif::Error::Limit("read bytes"))
            ));
        }
    }
}

#[test]
fn gif_xmp_after_image_subblocks() {
    let mut bytes = b"GIF89a\x02\0\x03\0\0\0\0".to_vec();
    bytes.extend([0x2c, 0, 0, 0, 0, 2, 0, 3, 0, 0, 2, 3, 0, 1, 2, 0]);
    bytes.extend(b"\x21\xff\x0bXMP DataXMP");
    bytes.extend(xmp("<p:ProjectionType>equirectangular</p:ProjectionType>").as_bytes());
    bytes.push(1);
    bytes.extend((0..=255).rev());
    bytes.extend([0, 0x3b]);
    let metadata = read(&bytes, Mode::Summary);
    assert_eq!(metadata.dimensions.unwrap().height, 3);
    assert!(metadata.is_panorama());
    assert!(metadata.issues.is_empty());
}

#[test]
fn photoshop_iptc_preserves_encoding_dates_and_caption() {
    let dataset = |r, d, text: &[u8]| {
        [
            vec![0x1c, r, d],
            (text.len() as u16).to_be_bytes().to_vec(),
            text.to_vec(),
        ]
        .concat()
    };
    let iptc = [
        dataset(1, 90, b"\x1b%G"),
        dataset(2, 55, b"20250131"),
        dataset(2, 60, b"101112+0530"),
        dataset(2, 120, "Snow ☃".as_bytes()),
    ]
    .concat();
    let resource = [
        b"Photoshop 3.0\0".to_vec(),
        b"8BIM\x04\x04\0\0".to_vec(),
        (iptc.len() as u32).to_be_bytes().to_vec(),
        iptc.clone(),
        vec![0; iptc.len() & 1],
    ]
    .concat();
    let bytes = [
        vec![0xff, 0xd8],
        segment(0xed, &resource),
        jpeg(&[], "")[2..].to_vec(),
    ]
    .concat();
    let metadata = read(&bytes, Mode::Summary);
    assert_eq!(metadata.iptc.len(), 4);
    assert_eq!(metadata.iptc[0].value, b"\x1b%G");
    assert_eq!(metadata.iptc[3].value, "Snow ☃".as_bytes());
    assert!(metadata.issues.is_empty());
}

#[test]
fn photoshop_recovers_each_metadata_resource() {
    let resource = |id: u16, value: &[u8]| {
        let mut bytes = b"8BIM".to_vec();
        bytes.extend(id.to_be_bytes());
        bytes.extend([0, 0]);
        bytes.extend((value.len() as u32).to_be_bytes());
        bytes.extend(value);
        bytes.resize(bytes.len() + (value.len() & 1), 0);
        bytes
    };
    let packet = xmp("<p:ProjectionType>equirectangular</p:ProjectionType>");
    for (id, malformed) in [
        (0x404, b"\x1c\x02\x78\0\x05x".as_slice()),
        (0x424, b"<".as_slice()),
    ] {
        let resources = [
            b"Photoshop 3.0\0".to_vec(),
            resource(id, malformed),
            resource(0x424, packet.as_bytes()),
        ]
        .concat();
        let jpeg = [
            vec![0xff, 0xd8],
            segment(0xed, &resources),
            jpeg(&[], "")[2..].to_vec(),
        ]
        .concat();
        let tiff = tiff(&[(0x8649, 7, resources.len() as u32, resources)], false);
        for bytes in [&jpeg, &tiff] {
            for mode in [Mode::Summary, Mode::Details] {
                let metadata = read(bytes, mode);
                assert!(metadata.is_panorama());
                assert_eq!(metadata.issues.len(), 1);
            }
        }
    }
}

#[test]
fn iptc_zero_tail_and_malformed_tail_recovery() {
    for tail in [b"".as_slice(), b"\0", b"\0\0", b"\0\0\0", b"\0\x01"] {
        let payload = [b"\x1c\x02\x78\0\x03Sky".as_slice(), tail].concat();
        let bytes = tiff(&[(0x83bb, 7, payload.len() as u32, payload)], false);
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(&bytes, mode);
            assert_eq!(metadata.iptc.len(), 1);
            assert_eq!(metadata.iptc[0].value, b"Sky");
            assert_eq!(metadata.issues.len(), usize::from(tail.contains(&1)));
        }
    }
}

#[test]
fn extended_xmp_reorders_fragments_and_rejects_overlap() {
    let id = "0123456789ABCDEF0123456789ABCDEF";
    let base = xmp(&format!(
        r#"<n:HasExtendedXMP xmlns:n="{}">{id}</n:HasExtendedXMP>"#,
        namespace::NOTE
    ));
    let extension = xmp("<p:ProjectionType>equirectangular</p:ProjectionType>");
    let split = extension.len() / 2;
    let fragment = |offset: usize, bytes: &[u8]| {
        segment(
            0xe1,
            &[
                b"http://ns.adobe.com/xmp/extension/\0".as_slice(),
                id.as_bytes(),
                &(extension.len() as u32).to_be_bytes(),
                &(offset as u32).to_be_bytes(),
                bytes,
            ]
            .concat(),
        )
    };
    for overlap in [false, true] {
        let bytes = [
            vec![0xff, 0xd8],
            fragment(
                if overlap { 0 } else { split },
                &extension.as_bytes()[split..],
            ),
            fragment(0, &extension.as_bytes()[..split]),
            jpeg(&[], &base)[2..].to_vec(),
        ]
        .concat();
        let metadata = read(&bytes, Mode::Summary);
        assert_eq!(metadata.is_panorama(), !overlap);
        assert_eq!(metadata.issues.is_empty(), !overlap);
    }
}

#[test]
fn motion_requires_real_boxes_and_respects_explicit_disable() {
    let video = [
        box_bytes(*b"ftyp", b"isom\0\0\0\0isom"),
        box_bytes(*b"moov", &[]),
        box_bytes(*b"mdat", &[0; 256]),
    ]
    .concat();
    for flag in ["0", "1"] {
        for valid in [false, true] {
            let mut payload = video.clone();
            if !valid {
                payload[24..28].copy_from_slice(b"junk");
            }
            let packet = xmp(&format!(
                r#"<c:MotionPhoto xmlns:c="{}">{flag}</c:MotionPhoto><c:MicroVideoOffset xmlns:c="{}">{}</c:MicroVideoOffset>"#,
                namespace::CAMERA,
                namespace::CAMERA,
                payload.len()
            ));
            let mut bytes = jpeg(&[], &packet);
            let start = bytes.len() as u64;
            bytes.extend(payload);
            let metadata = read(&bytes, Mode::Summary);
            assert_eq!(metadata.motion_video.is_some(), valid && flag == "1");
            if let Some(range) = metadata.motion_video {
                assert_eq!(range.start, start);
                assert_eq!(range.end, bytes.len() as u64);
            }
        }
    }
}

#[test]
fn motion_directory_accounts_for_primary_padding() {
    let video = [
        box_bytes(*b"ftyp", b"isom\0\0\0\0isom"),
        box_bytes(*b"moov", &[]),
        box_bytes(*b"mdat", &[0; 256]),
    ]
    .concat();
    let xml = xmp(&format!(
        r#"<c:Directory xmlns:c="{}" xmlns:i="{}"><r:Seq><r:li><c:Item i:Mime="image/jpeg" i:Semantic="Primary" i:Padding="4"/></r:li><r:li><c:Item i:Mime="video/mp4" i:Semantic="MotionPhoto" i:Length="{}" i:Padding="0"/></r:li></r:Seq></c:Directory>"#,
        namespace::CONTAINER,
        namespace::ITEM,
        video.len()
    ));
    let mut bytes = jpeg(&[], &xml);
    bytes.extend([0; 4]);
    let start = bytes.len() as u64;
    bytes.extend(video);
    assert_eq!(
        read(&bytes, Mode::Summary).motion_video.unwrap().start,
        start
    );
}

#[test]
fn png_text_encoding_and_bad_compressed_block_recovery() {
    let ihdr = [vec![0, 0, 0, 1, 0, 0, 0, 1], vec![8, 2, 0, 0, 0]].concat();
    let bytes = [
        b"\x89PNG\r\n\x1a\n".to_vec(),
        png_chunk(*b"IHDR", &ihdr),
        png_chunk(*b"tEXt", b"Author\0Andr\xe9"),
        png_chunk(*b"iTXt", "Description\0\0\0\0\0Snow ☃".as_bytes()),
        png_chunk(*b"zTXt", b"Broken\0\0invalid zlib"),
        png_chunk(*b"IEND", &[]),
    ]
    .concat();
    let metadata = read(&bytes, Mode::Details);
    assert_eq!(metadata.property("urn:png:text", "Author"), Some("André"));
    assert_eq!(
        metadata.property("urn:png:text", "Description"),
        Some("Snow ☃")
    );
    assert_eq!(metadata.issues.len(), 1);
    assert_eq!(metadata.issues[0].message, "compressed PNG text");
}

#[test]
fn motion_accepts_compatible_brands_but_not_the_minor_version() {
    for (brands, valid, malformed) in [
        (b"newv\0\0\0\0junkisom".as_slice(), true, false),
        (b"isom\0\0\0\0".as_slice(), true, false),
        (b"newvisomjunk".as_slice(), false, false),
        (b"newv\0\0\0\0iso".as_slice(), false, true),
    ] {
        let video = [
            box_bytes(*b"ftyp", brands),
            box_bytes(*b"moov", &[]),
            box_bytes(*b"mdat", &[0; 16]),
        ]
        .concat();
        let packet = xmp(&format!(
            r#"<c:MicroVideoOffset xmlns:c="{}">{}</c:MicroVideoOffset>"#,
            namespace::CAMERA,
            video.len()
        ));
        let mut bytes = jpeg(&[], &packet);
        let start = bytes.len() as u64;
        bytes.extend(video);
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(&bytes, mode);
            assert_eq!(
                metadata.motion_video.map(|v| (v.start, v.end)),
                valid.then_some((start, bytes.len() as u64))
            );
            assert_eq!(!metadata.issues.is_empty(), malformed);
        }
    }
}

#[test]
fn png_itxt_preserves_languages_with_and_without_compression() {
    let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
    bytes.extend(png_chunk(
        *b"IHDR",
        &[0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0],
    ));
    for (language, text, compressed) in [
        ("en", "Snow", false),
        ("fr", "Neige", true),
        ("", "Ice", false),
    ] {
        let mut data = b"Description\0".to_vec();
        data.extend([u8::from(compressed), 0]);
        data.extend(language.as_bytes());
        data.extend([0, 0]);
        data.extend(if compressed {
            miniz_oxide::deflate::compress_to_vec_zlib(text.as_bytes(), 6)
        } else {
            text.as_bytes().to_vec()
        });
        bytes.extend(png_chunk(*b"iTXt", &data));
    }
    bytes.extend(png_chunk(*b"IEND", &[]));
    let metadata = read(&bytes, Mode::Details);
    let values: Vec<_> = metadata
        .properties("urn:png:text", "Description")
        .map(|p| (p.language.as_deref(), p.value.as_str()))
        .collect();
    assert_eq!(
        values,
        [(Some("en"), "Snow"), (Some("fr"), "Neige"), (None, "Ice")]
    );
    assert_eq!(
        read(&bytes, Mode::Summary)
            .properties("urn:png:text", "Description")
            .count(),
        0
    );
}
