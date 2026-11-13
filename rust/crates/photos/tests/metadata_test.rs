use std::io::Write;

use ente_exif::{DateTimeSource, Dimensions, Location, namespace};
use ente_photos::metadata::{PhotoMetadata, read_photo_metadata};

type TestResult<T = ()> = Result<T, Box<dyn std::error::Error>>;

#[test]
fn reads_display_dimensions_capture_time_and_xmp_location() -> TestResult {
    let properties = r#"tiff:Orientation="6" exif:DateTimeOriginal="2024-01-01T12:00:00.123456-00:30"
        exif:GPSLatitude="40,30N" exif:GPSLongitude="74,15W""#;
    let metadata = read(properties)?;
    assert_eq!(
        metadata.dimensions,
        Some(Dimensions {
            width: 48,
            height: 64
        })
    );
    assert_eq!(
        metadata.capture_date_time.as_ref().map(|date| (
            date.date_time.as_str(),
            date.offset_time.as_deref(),
            date.timestamp_micros,
        )),
        Some((
            "2024-01-01T12:00:00.123456000",
            Some("-00:30"),
            Some(1_704_112_200_123_456),
        ))
    );
    assert_eq!(
        metadata.location,
        Some(Location {
            latitude: 40.5,
            longitude: -74.25
        })
    );
    Ok(())
}

#[test]
fn skips_partial_and_sentinel_capture_dates_and_continues_to_fallbacks() -> TestResult {
    for (original, rejected) in [
        ("2004", true),
        ("2004-06", true),
        ("2004-06-15", true),
        ("2004-06-15T12:30Z", true),
        ("1970-01-01T00:00:00Z", true),
        ("1970-01-01T00:00:00", true),
        ("1970-01-01T00:00:01", false),
        ("1970-01-01T05:30:00+05:30", true),
        ("4501-01-01T00:00:00.000Z", true),
        ("4501-01-01T00:00:00+05:30", true),
        ("1970-01-01T00:00:00+05:30", false),
        ("1969-12-31T23:59:59Z", false),
        ("2024-01-01T12:00:00", false),
        ("2024-01-01T00:00:00Z", false),
        ("4501-01-02T00:00:00Z", false),
    ] {
        let metadata = read(&format!(
            r#"exif:DateTimeOriginal="{original}" xmp:CreateDate="2024-01-02T12:00:00Z""#
        ))?;
        let expected = if rejected {
            DateTimeSource::Xmp(namespace::XMP, "CreateDate")
        } else {
            DateTimeSource::Xmp(namespace::EXIF, "DateTimeOriginal")
        };
        assert_eq!(
            metadata.capture_date_time.as_ref().map(|d| d.source),
            Some(expected),
            "{original}"
        );
    }
    assert!(
        read(r#"exif:DateTimeOriginal="2004" xmp:CreateDate="2004-06-15""#)?
            .capture_date_time
            .is_none()
    );
    assert!(
        read(
            r#"exif:DateTimeOriginal="4501-01-01T00:00:00Z" xmp:CreateDate="1970-01-01T00:00:00Z""#
        )?
        .capture_date_time
        .is_none()
    );
    Ok(())
}

#[test]
fn reads_panorama_and_motion_video() -> TestResult {
    let plain = read("")?;
    assert!(!plain.is_panorama);
    assert_eq!(plain.motion_video, None);
    let video = b"\0\0\0\x10ftypisom\0\0\0\0\0\0\0\x08moov\0\0\0\x08mdat";
    let metadata = read_with_tail(
        r#"xmlns:GPano="http://ns.google.com/photos/1.0/panorama/"
            GPano:ProjectionType="equirectangular"
            xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
            GCamera:MicroVideoOffset="32""#,
        video,
    )?;
    assert!(metadata.is_panorama);
    assert!(
        metadata.motion_video.as_ref().is_some_and(|range| {
            range.start > 0 && range.end - range.start == video.len() as u64
        })
    );
    Ok(())
}

fn read(properties: &str) -> TestResult<PhotoMetadata> {
    read_with_tail(properties, &[])
}

fn read_with_tail(properties: &str, tail: &[u8]) -> TestResult<PhotoMetadata> {
    let xmp = format!(
        "http://ns.adobe.com/xap/1.0/\0<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:exif=\"http://ns.adobe.com/exif/1.0/\" xmlns:tiff=\"http://ns.adobe.com/tiff/1.0/\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" {properties}/></rdf:RDF>"
    );
    let mut file = tempfile::NamedTempFile::new()?;
    file.write_all(&[0xff, 0xd8, 0xff, 0xe1])?;
    file.write_all(&u16::try_from(xmp.len() + 2)?.to_be_bytes())?;
    file.write_all(xmp.as_bytes())?;
    file.write_all(&[
        0xff, 0xc0, 0, 11, 8, 0, 48, 0, 64, 1, 1, 0x11, 0, 0xff, 0xd9,
    ])?;
    file.write_all(tail)?;
    Ok(read_photo_metadata(file.path())?)
}
