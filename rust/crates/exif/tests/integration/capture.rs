use super::common::*;
use ente_exif::{
    DateTime, DateTimeKind, DateTimePrecision, DateTimeSource, Ifd, Iptc, Metadata, Mode, Tag,
    Value, namespace,
};

#[test]
fn source_dates_preserve_precision_without_assuming_utc() {
    use DateTimePrecision::{Day, Minute, Month, Second, Year};
    for mode in [Mode::Summary, Mode::Details] {
        for (input, precision, complete) in [
            ("2004", Year, "2004-01-01T00:00:00"),
            ("2004-02", Month, "2004-02-01T00:00:00"),
            ("2004-02-29", Day, "2004-02-29T00:00:00"),
            ("2004-02-29T12:34", Minute, "2004-02-29T12:34:00"),
            ("2004-02-29T12:34Z", Minute, "2004-02-29T12:34:00Z"),
            ("2004-02-29T12:34-0030", Minute, "2004-02-29T12:34:00-00:30"),
            ("2004-02-29T12:34:56.125", Second, "2004-02-29T12:34:56.125"),
        ] {
            let metadata = read(
                packet(&format!("<x:CreateDate>{input}</x:CreateDate>")).as_bytes(),
                mode,
            );
            let value = metadata
                .date_time(DateTimeSource::Xmp(namespace::XMP, "CreateDate"))
                .unwrap();
            assert_eq!(value.precision, precision, "{input}");
            assert_eq!(
                value.date_time,
                DateTime::parse(complete).unwrap(),
                "{input}"
            );
            assert_eq!(
                value.date_time.unix_micros().is_some(),
                value.date_time.offset_minutes.is_some()
            );
        }
    }
}

#[test]
fn source_dates_do_not_select_another_family_or_fallback() {
    let mut metadata = read(
        packet("<e:DateTimeOriginal>invalid</e:DateTimeOriginal><x:CreateDate>2004</x:CreateDate>")
            .as_bytes(),
        Mode::Summary,
    );
    metadata.iptc = vec![iptc(55, b"20040229"), iptc(63, b"123456+0530")];
    metadata
        .tags
        .push(tag(Ifd::Exif(0), 0x9003, "2003:01:02 03:04:05"));
    assert_eq!(
        metadata.date_time(DateTimeSource::Xmp(namespace::EXIF, "DateTimeOriginal")),
        None
    );
    assert_eq!(
        metadata.date_time(DateTimeSource::Exif(DateTimeKind::Modified)),
        None
    );
    assert_eq!(metadata.date_time(DateTimeSource::Iptc(62, 63)), None);
    let original = metadata
        .date_time(DateTimeSource::Exif(DateTimeKind::Original))
        .unwrap();
    assert_eq!(original.precision, DateTimePrecision::Second);
    assert_eq!(
        original.date_time,
        DateTime::parse("2003-01-02T03:04:05").unwrap()
    );
    let iptc_date = metadata.date_time(DateTimeSource::Iptc(55, 60)).unwrap();
    assert_eq!(iptc_date.precision, DateTimePrecision::Day);
    assert_eq!(
        iptc_date.date_time,
        DateTime::parse("2004-02-29T00:00:00").unwrap()
    );
    assert_eq!(iptc_date.date_time.unix_micros(), None);
    metadata.iptc.push(iptc(60, b"123456+0530"));
    let iptc_date = metadata.date_time(DateTimeSource::Iptc(55, 60)).unwrap();
    assert_eq!(iptc_date.precision, DateTimePrecision::Second);
    assert_eq!(
        iptc_date.date_time,
        DateTime::parse("2004-02-29T12:34:56+05:30").unwrap()
    );
}

#[test]
fn capture_prefers_original_sources_before_digitized_metadata_and_modified() {
    use DateTimeKind::{Digitized, Modified, Original};
    use DateTimeSource::{Exif, Iptc, Xmp};
    let mut metadata = Metadata::default();
    for (kind, value) in [
        (Original, "2003:01:02 03:04:05"),
        (Digitized, "2007:01:02 03:04:05"),
        (Modified, "2011:01:02 03:04:05"),
    ] {
        let (ifd, id) = if kind == Modified {
            (Ifd::Image(0), 0x132)
        } else {
            (Ifd::Exif(0), if kind == Original { 0x9003 } else { 0x9004 })
        };
        metadata.tags.push(tag(ifd, id, value));
    }
    metadata.xmp = read(
        packet(
            r#"
        <e:DateTimeOriginal>2001-01-02T03:04:05Z</e:DateTimeOriginal>
        <p:DateCreated>2004-01-02T03:04:05Z</p:DateCreated>
        <e:DateTimeDigitized>2005-01-02T03:04:05Z</e:DateTimeDigitized>
        <x:CreateDate>2008-01-02T03:04:05Z</x:CreateDate>
        <x:MetadataDate>2009-01-02T03:04:05Z</x:MetadataDate>
        <t:DateTime>2010-01-02T03:04:05Z</t:DateTime>
        <x:ModifyDate>2012-01-02T03:04:05Z</x:ModifyDate>"#,
        )
        .as_bytes(),
        Mode::Summary,
    )
    .xmp;
    metadata.iptc = vec![
        iptc(55, b"20020102"),
        iptc(60, b"030405+0000"),
        iptc(62, b"20060102"),
        iptc(63, b"030405+0000"),
    ];
    for (index, source) in [
        Xmp(namespace::EXIF, "DateTimeOriginal"),
        Iptc(55, 60),
        Exif(Original),
        Xmp(namespace::PHOTOSHOP, "DateCreated"),
        Xmp(namespace::EXIF, "DateTimeDigitized"),
        Iptc(62, 63),
        Exif(Digitized),
        Xmp(namespace::XMP, "CreateDate"),
        Xmp(namespace::XMP, "MetadataDate"),
        Xmp(namespace::TIFF, "DateTime"),
        Exif(Modified),
        Xmp(namespace::XMP, "ModifyDate"),
    ]
    .into_iter()
    .enumerate()
    {
        let capture = metadata.capture_date_time().unwrap();
        assert_eq!(capture.source, source);
        assert_eq!(
            capture.date_time,
            format!("{}-01-02T03:04:05", 2001 + index)
        );
        match source {
            Exif(kind) => metadata.tags.retain(|t| {
                t.id != match kind {
                    Original => 0x9003,
                    Digitized => 0x9004,
                    Modified => 0x132,
                }
            }),
            Xmp(ns, name) => metadata.xmp.retain(|p| p.namespace != ns || p.name != name),
            Iptc(date, time) => metadata
                .iptc
                .retain(|p| p.dataset != date && p.dataset != time),
        }
    }
    assert_eq!(metadata.capture_date_time(), None);
}

#[test]
fn offsets_stay_separate_from_local_time_and_epoch_microseconds() {
    for mode in [Mode::Summary, Mode::Details] {
        for (value, local, offset, timestamp) in [
            (
                "1970-01-02T00:15:00.123456789+0030",
                "1970-01-02T00:15:00.123456789",
                Some("+00:30"),
                Some(85_500_123_456),
            ),
            (
                "1970-01-02T00:15:00-00:30",
                "1970-01-02T00:15:00",
                Some("-00:30"),
                Some(89_100_000_000),
            ),
            (
                "1970-01-02T00:15:00Z",
                "1970-01-02T00:15:00",
                Some("+00:00"),
                Some(87_300_000_000),
            ),
            ("1970-01-02T00:15:00", "1970-01-02T00:15:00", None, None),
            (
                "1970-01-01T00:00:00Z",
                "1970-01-01T00:00:00",
                Some("+00:00"),
                Some(0),
            ),
        ] {
            let metadata = read(
                packet(&format!("<p:DateCreated>{value}</p:DateCreated>")).as_bytes(),
                mode,
            );
            let capture = metadata.capture_date_time().unwrap();
            assert_eq!(capture.date_time, local);
            assert_eq!(capture.offset_time.as_deref(), offset);
            assert_eq!(capture.timestamp_micros, timestamp);
        }
    }
}

#[test]
fn host_policy_can_resolve_local_time_and_reject_candidates_before_fallback() {
    let metadata = read(packet("<e:DateTimeOriginal>1970-01-02T12:00:00</e:DateTimeOriginal><x:CreateDate>1970-01-03T12:00:00Z</x:CreateDate>").as_bytes(), Mode::Summary);
    let mut visits = 0;
    let capture = metadata
        .capture_date_time_with(|candidate| {
            visits += 1;
            assert_eq!(candidate.timestamp_micros, None);
            assert_eq!(candidate.offset_time, None);
            candidate.timestamp_micros = Some(109_800_000_000);
            true
        })
        .unwrap();
    assert_eq!(visits, 1);
    assert_eq!(capture.timestamp_micros, Some(109_800_000_000));
    assert_eq!(capture.offset_time, None);
    let capture = metadata
        .capture_date_time_with(|candidate| candidate.timestamp_micros.is_some())
        .unwrap();
    assert_eq!(
        capture.source,
        DateTimeSource::Xmp(namespace::XMP, "CreateDate")
    );
    assert_eq!(metadata.capture_date_time_with(|_| false), None);

    let metadata = read(packet("<x:MetadataDate>1970-01-02T12:00:00Z</x:MetadataDate><t:DateTime>1970-01-03T12:00:00Z</t:DateTime><x:ModifyDate>1970-01-04T12:00:00Z</x:ModifyDate>").as_bytes(), Mode::Summary);
    let capture = metadata
        .capture_date_time_with(|candidate| candidate.date_time.starts_with("1970-01-04"))
        .unwrap();
    assert_eq!(
        capture.source,
        DateTimeSource::Xmp(namespace::XMP, "ModifyDate")
    );
}

#[test]
fn reduced_xmp_dates_use_period_start_without_inventing_an_embedded_offset() {
    use DateTimePrecision::{Day, Minute, Month, Year};
    for (value, expected, timestamp, precision) in [
        (
            "1971",
            "1971-01-01T00:00:00",
            Some(31_536_000_000_000),
            Year,
        ),
        (
            "1970-02",
            "1970-02-01T00:00:00",
            Some(2_678_400_000_000),
            Month,
        ),
        (
            "1970-01-02",
            "1970-01-02T00:00:00",
            Some(86_400_000_000),
            Day,
        ),
        ("1970-01-02T00:15", "1970-01-02T00:15:00", None, Minute),
        (
            "1970-01-02T00:15+00:30",
            "1970-01-02T00:15:00",
            Some(85_500_000_000),
            Minute,
        ),
    ] {
        assert_eq!(DateTime::parse(value), None);
        for mode in [Mode::Summary, Mode::Details] {
            let capture = read(
                packet(&format!("<x:CreateDate>{value}</x:CreateDate>")).as_bytes(),
                mode,
            )
            .capture_date_time()
            .unwrap();
            assert_eq!(capture.date_time, expected);
            assert_eq!(capture.timestamp_micros, timestamp);
            assert_eq!(capture.precision, precision);
            if value.len() <= 10 {
                assert_eq!(capture.offset_time, None);
            }
        }
    }
}

#[test]
fn malformed_preferred_fields_fall_through_without_mixing_date_families() {
    for value in [
        "",
        "bad",
        "1970-13",
        "1900-02-29",
        "1970-01-02T00:00:99Z",
        "1970-01-02T00:00+24:00",
        "1970-01-02T00:00日本",
    ] {
        let mut metadata = read(packet(&format!("<e:DateTimeOriginal>{value}</e:DateTimeOriginal><t:DateTime>{value}</t:DateTime><x:ModifyDate>1970-01-03T00:00:00Z</x:ModifyDate>")).as_bytes(), Mode::Summary);
        metadata.tags = vec![
            tag(Ifd::Image(0), 0x132, "1970:01:02 00:00:00"),
            tag(Ifd::Exif(0), 0x9011, "+06:00"),
        ];
        let capture = metadata.capture_date_time().unwrap();
        assert_eq!(capture.source, DateTimeSource::Exif(DateTimeKind::Modified));
        assert_eq!(capture.offset_time, None);
        assert_eq!(capture.timestamp_micros, None);
    }
}

#[test]
fn generated_iptc_dates_pair_only_their_own_time_dataset() {
    for mode in [Mode::Summary, Mode::Details] {
        for (time, offset, timestamp) in [
            (None, None, Some(86_400_000_000)),
            (Some("001500"), None, None),
            (Some("001500-0030"), Some("-00:30"), Some(89_100_000_000)),
        ] {
            let mut fields = vec![
                (55, b"19700102".as_slice()),
                (63, b"120000+0600".as_slice()),
            ];
            if let Some(time) = time {
                fields.push((60, time.as_bytes()));
            }
            let metadata = read(&iptc_tiff(&fields), mode);
            let capture = metadata.capture_date_time().unwrap();
            assert_eq!(capture.source, DateTimeSource::Iptc(55, 60));
            assert_eq!(
                capture.precision,
                if time.is_some() {
                    DateTimePrecision::Second
                } else {
                    DateTimePrecision::Day
                }
            );
            assert_eq!(capture.offset_time.as_deref(), offset);
            assert_eq!(capture.timestamp_micros, timestamp);
        }
        for (date, time) in [
            ("19700100", "120000+0000"),
            ("00000102", "120000+0000"),
            ("19700102", ""),
            ("19700102", "240000+0000"),
            ("19700102", "120000+2460"),
        ] {
            let metadata = read(
                &iptc_tiff(&[
                    (55, date.as_bytes()),
                    (60, time.as_bytes()),
                    (62, b"19700103"),
                    (63, b"120000+0000"),
                ]),
                mode,
            );
            let capture = metadata.capture_date_time().unwrap();
            assert_eq!(capture.source, DateTimeSource::Iptc(62, 63));
            assert_eq!(capture.date_time, "1970-01-03T12:00:00");
        }
    }
}

#[test]
fn generated_exif_capture_uses_matching_subseconds_and_offset() {
    let bytes = child_ifd(
        0x8769,
        tiff(
            &[
                (0x9003, 2, 20, b"1970:01:02 00:15:00\0".to_vec()),
                (0x9291, 2, 4, b"125\0".to_vec()),
                (0x9011, 2, 7, b"+00:30\0".to_vec()),
            ],
            false,
        ),
    );
    for mode in [Mode::Summary, Mode::Details] {
        let capture = read(&bytes, mode).capture_date_time().unwrap();
        assert_eq!(capture.date_time, "1970-01-02T00:15:00.125000000");
        assert_eq!(capture.offset_time.as_deref(), Some("+00:30"));
        assert_eq!(capture.timestamp_micros, Some(85_500_125_000));
    }
}

#[test]
fn partial_date_and_iptc_mutations_do_not_panic() {
    for input in [b"2000-02-29T12:34-0030".as_slice(), b"2000-02-29"] {
        for len in 0..=input.len() {
            let mut metadata = read(packet("").as_bytes(), Mode::Summary);
            for replacement in 0..=127 {
                let mut value = input[..len].to_vec();
                if let Some(last) = value.last_mut() {
                    *last = replacement;
                }
                metadata.xmp = read(
                    packet("<x:CreateDate>2000</x:CreateDate>").as_bytes(),
                    Mode::Summary,
                )
                .xmp;
                metadata.xmp[0].value = String::from_utf8(value.clone()).unwrap();
                let _ = metadata.capture_date_time();
                metadata.xmp.clear();
                metadata.iptc = vec![iptc(55, &value), iptc(60, &value)];
                let _ = metadata.capture_date_time();
            }
        }
    }
}

fn packet(body: &str) -> String {
    format!(
        r#"<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:e="http://ns.adobe.com/exif/1.0/" xmlns:p="http://ns.adobe.com/photoshop/1.0/" xmlns:t="http://ns.adobe.com/tiff/1.0/" xmlns:x="http://ns.adobe.com/xap/1.0/">{body}</r:Description></r:RDF>"#
    )
}

fn tag(ifd: Ifd, id: u16, value: &str) -> Tag {
    Tag {
        ifd,
        id,
        field_type: 2,
        count: value.len() as u32,
        value: Value::Ascii(value.as_bytes().to_vec()),
    }
}

fn iptc(dataset: u8, value: &[u8]) -> Iptc {
    Iptc {
        record: 2,
        dataset,
        value: value.to_vec(),
    }
}

fn iptc_tiff(fields: &[(u8, &[u8])]) -> Vec<u8> {
    let mut bytes = vec![];
    for (dataset, value) in fields {
        bytes.extend([0x1c, 2, *dataset]);
        bytes.extend((value.len() as u16).to_be_bytes());
        bytes.extend(*value);
    }
    tiff(&[(0x83bb, 7, bytes.len() as u32, bytes)], false)
}
