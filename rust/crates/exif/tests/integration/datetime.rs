use super::common::*;
use ente_exif::{DateTime, DateTimeKind, Ifd, Metadata, Mode, Tag, Value};

#[test]
fn complete_dates_preserve_local_time_fraction_and_offset() {
    for (input, nano, offset) in [
        (" 2004:02:29 12:34:56 ", 0, None),
        ("2004:02:29 12:34:56.125", 125_000_000, None),
        ("2004-02-29T12:34:56.1234567899Z", 123_456_789, Some(0)),
        ("2004-02-29 12:34:56:01-00:30", 10_000_000, Some(-30)),
        ("2004-02-29t12:34:56z", 0, Some(0)),
        ("2004-02-29T12:34:56+0545", 0, Some(345)),
        ("2004-02-29T12:34:56-03:30", 0, Some(-210)),
    ] {
        let date = DateTime::parse(input).unwrap();
        assert_eq!(
            date,
            DateTime {
                year: 2004,
                month: 2,
                day: 29,
                hour: 12,
                minute: 34,
                second: 56,
                nanosecond: nano,
                offset_minutes: offset
            }
        );
        assert_eq!(date.unix_micros().is_some(), offset.is_some());
        assert_eq!(DateTime::parse(&date.to_string()), Some(date));
    }
}

#[test]
fn dates_reject_invalid_calendar_fields_and_incomplete_values() {
    for value in [
        "",
        "2004",
        "2004-02",
        "2004-02-29",
        "2004-02-29T12:34",
        "0000:00:00 00:00:00",
        "    :  :     :  :  ",
        "0000-01-01T00:00:00Z",
        "1900-02-29T00:00:00Z",
        "2100-02-29T00:00:00Z",
        "2004-04-31T00:00:00Z",
        "2004-00-10T00:00:00Z",
        "2004-13-10T00:00:00Z",
        "2004-02-00T00:00:00Z",
        "2004-02-29T24:00:00Z",
        "2004-02-29T12:60:00Z",
        "2004-02-29T12:00:60Z",
        "2004-02-29T12:00:00+24:00",
        "2004-02-29T12:00:00+00:60",
        "2004-02-29T12:00:00+5:30",
        "2004-02-29T12:00:00UTC",
        "2004-02-29T12:00:00Ztail",
        "2004-02-29T12:00:00.Z",
        "2004-02-29T12:00:00.1xZ",
        "2004:02-29T12:00:00Z",
        "2004-02-29T12:00:0éZ",
        "2004-02-29T12:00:00.é",
        "٢٠٠٤-02-29T12:00:00Z",
    ] {
        assert_eq!(DateTime::parse(value), None, "{value}");
    }
}

#[test]
fn epoch_conversion_handles_leap_centuries_offsets_and_pre_epoch_fractions() {
    for (input, expected) in [
        ("1970-01-01T00:00:00Z", 0),
        ("1970-01-01T00:00:00+00:30", -1_800_000_000),
        ("1970-01-01T00:00:00-00:30", 1_800_000_000),
        ("1969-12-31T23:59:59.123456789Z", -876_544),
        ("2000-02-29T12:34:56.123456Z", 951_827_696_123_456),
        ("0001-01-01T00:00:00Z", -62_135_596_800_000_000),
        ("9999-12-31T23:59:59.999999Z", 253_402_300_799_999_999),
    ] {
        assert_eq!(
            DateTime::parse(input).unwrap().unix_micros(),
            Some(expected),
            "{input}"
        );
    }
    let valid = DateTime::parse("2000-01-01T00:00:00Z").unwrap();
    for invalid in [
        DateTime { year: 0, ..valid },
        DateTime {
            year: 10000,
            ..valid
        },
        DateTime { month: 0, ..valid },
        DateTime { month: 13, ..valid },
        DateTime { day: 0, ..valid },
        DateTime { day: 32, ..valid },
        DateTime { hour: 24, ..valid },
        DateTime {
            minute: 60,
            ..valid
        },
        DateTime {
            second: 60,
            ..valid
        },
        DateTime {
            nanosecond: 1_000_000_000,
            ..valid
        },
        DateTime {
            offset_minutes: Some(i16::MIN),
            ..valid
        },
    ] {
        assert_eq!(invalid.unix_micros(), None);
    }
}

#[test]
fn exif_date_families_use_their_own_subseconds_and_offsets() {
    let metadata = dates(&[
        (Ifd::Image(0), 0x132, "2010:05:06 07:08:09"),
        (Ifd::Exif(0), 0x9003, "2000:01:02 03:04:05"),
        (Ifd::Exif(0), 0x9004, "2001:02:03 04:05:06"),
        (Ifd::Exif(0), 0x9290, "1"),
        (Ifd::Exif(0), 0x9010, "+01:00"),
        (Ifd::Exif(0), 0x9291, "25"),
        (Ifd::Exif(0), 0x9011, "-00:30"),
        (Ifd::Exif(0), 0x9292, "125"),
        (Ifd::Exif(0), 0x9012, "+05:45"),
    ]);
    for (kind, expected) in [
        (
            DateTimeKind::Original,
            "2000-01-02T03:04:05.250000000-00:30",
        ),
        (
            DateTimeKind::Digitized,
            "2001-02-03T04:05:06.125000000+05:45",
        ),
        (
            DateTimeKind::Modified,
            "2010-05-06T07:08:09.100000000+01:00",
        ),
    ] {
        assert_eq!(metadata.exif_date_time(kind).unwrap().to_string(), expected);
    }
    let metadata = dates(&[
        (Ifd::Image(0), 0x132, "2010:05:06 07:08:09"),
        (Ifd::Exif(0), 0x9003, "2000:01:02 03:04:05"),
        (Ifd::Exif(0), 0x9010, "+05:00"),
    ]);
    assert_eq!(
        metadata
            .exif_date_time(DateTimeKind::Original)
            .unwrap()
            .offset_minutes,
        None
    );
    assert_eq!(metadata.exif_date_time(DateTimeKind::Digitized), None);
}

#[test]
fn exif_auxiliary_fields_distinguish_blank_from_malformed() {
    for (subsec, offset, expected) in [
        ("", "", Some("2000-01-02T03:04:05")),
        ("  ", "   :  ", Some("2000-01-02T03:04:05")),
        (
            "05  ",
            " +0530 ",
            Some("2000-01-02T03:04:05.050000000+05:30"),
        ),
        ("bad", "+00:00", None),
        ("1.2", "+00:00", None),
        ("1", "CDT", None),
        ("1", "+05:99", None),
    ] {
        let metadata = dates(&[
            (Ifd::Exif(0), 0x9003, "2000:01:02 03:04:05"),
            (Ifd::Exif(0), 0x9291, subsec),
            (Ifd::Exif(0), 0x9011, offset),
        ]);
        assert_eq!(
            metadata
                .exif_date_time(DateTimeKind::Original)
                .map(|d| d.to_string())
                .as_deref(),
            expected
        );
    }
    let mut metadata = dates(&[
        (Ifd::Exif(0), 0x9003, "2000-01-02T03:04:05.25-00:30"),
        (Ifd::Exif(0), 0x9291, "75"),
        (Ifd::Exif(0), 0x9011, "+05:00"),
    ]);
    assert_eq!(
        metadata
            .exif_date_time(DateTimeKind::Original)
            .unwrap()
            .to_string(),
        "2000-01-02T03:04:05.250000000-00:30"
    );
    for tag in &mut metadata.tags[1..] {
        tag.value = ente_exif::Value::Unsigned(vec![1]);
    }
    assert_eq!(
        metadata.exif_date_time(DateTimeKind::Original),
        DateTime::parse("2000-01-02T03:04:05.25-00:30")
    );
    metadata.tags[0].value = ente_exif::Value::Ascii(b"2000:01:02 03:04:05".to_vec());
    assert_eq!(metadata.exif_date_time(DateTimeKind::Original), None);
}

#[test]
fn generated_exif_dates_work_in_both_modes_and_retain_raw_precision() {
    let bytes = child_ifd(
        0x8769,
        tiff(
            &[
                (0x9003, 2, 20, b"2000:01:02 03:04:05\0".to_vec()),
                (0x9291, 2, 11, b"1234567899\0".to_vec()),
                (0x9011, 2, 7, b"-00:30\0".to_vec()),
            ],
            false,
        ),
    );
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(&bytes, mode);
        assert_eq!(
            metadata
                .exif_date_time(DateTimeKind::Original)
                .unwrap()
                .to_string(),
            "2000-01-02T03:04:05.123456789-00:30"
        );
        assert_eq!(
            metadata.tag(Ifd::Exif(0), 0x9291).unwrap().value.text(),
            Some("1234567899")
        );
    }
}

#[test]
fn timestamp_truncations_and_mutations_do_not_panic() {
    let seed = b"2000-02-29T12:34:56.123456789-00:30";
    for len in 0..=seed.len() {
        let _ = DateTime::parse(std::str::from_utf8(&seed[..len]).unwrap());
    }
    for index in 0..seed.len() {
        for value in 0..=127 {
            let mut bytes = *seed;
            bytes[index] = value;
            if let Some(date) = DateTime::parse(std::str::from_utf8(&bytes).unwrap()) {
                assert_eq!(DateTime::parse(&date.to_string()), Some(date));
                assert_eq!(date.unix_micros().is_some(), date.offset_minutes.is_some());
            }
        }
    }
}

fn dates(entries: &[(Ifd, u16, &str)]) -> Metadata {
    Metadata {
        tags: entries
            .iter()
            .map(|(ifd, id, text)| Tag {
                ifd: *ifd,
                id: *id,
                field_type: 2,
                count: text.len() as u32,
                value: Value::Ascii(text.as_bytes().to_vec()),
            })
            .collect(),
        ..Metadata::default()
    }
}
