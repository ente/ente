use super::common::{png_chunk, read, tiff, xmp};
use ente_exif::{Error, Limits, Mode, TextEncoding};
use std::io::Cursor;

#[test]
fn profiles_use_existing_exif_xmp_and_iptc_readers() {
    let exif = tiff(
        &[
            (0x10f, 2, 6, b"Maker\0".to_vec()),
            (0x132, 2, 20, b"2024:02:29 12:34:56\0".to_vec()),
        ],
        false,
    );
    let packet = xmp("<d:description>山</d:description>");
    let iim = b"\x1c\x01\x5a\0\x03\x1b%G\x1c\x02\x78\0\x03sea";
    let resource = [
        b"8BIM\x04\x04\0\0".as_slice(),
        &(iim.len() as u32).to_be_bytes(),
        iim,
    ]
    .concat();
    for kind in [b"tEXt", b"zTXt", b"iTXt"] {
        let bytes = png(&[
            profile(*kind, "exif", &[b"Exif\0\0".as_slice(), &exif].concat()),
            profile(*kind, "iptc", &resource),
            profile(*kind, "xmp", packet.as_bytes()),
        ]);
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(&bytes, mode);
            assert!(metadata.issues.is_empty(), "{:?}", metadata.issues);
            assert_eq!(metadata.camera_make(), Some("Maker"));
            assert_eq!(
                metadata.capture_date_time().unwrap().date_time,
                "2024-02-29T12:34:56"
            );
            assert_eq!(
                metadata.iptc_caption(TextEncoding::Ascii).as_deref(),
                Some("sea")
            );
            assert_eq!(metadata.xmp_description(None), Some("山"));
            assert!(!metadata.xmp.iter().any(|p| p.namespace == "urn:png:text"));
        }
    }
}

#[test]
fn app1_profiles_and_direct_iim_are_supported() {
    let exif = tiff(&[(0x10f, 2, 6, b"Maker\0".to_vec())], true);
    let xml = [
        b"http://ns.adobe.com/xap/1.0/\0".as_slice(),
        xmp("<d:description>mist</d:description>").as_bytes(),
    ]
    .concat();
    let bytes = png(&[
        profile(*b"zTXt", "APP1", &[b"Exif\0\0".as_slice(), &exif].concat()),
        profile(*b"zTXt", "APP1", &xml),
        profile(*b"tEXt", "iptc", b"\x1c\x02\x78\0\x04dawn"),
    ]);
    let metadata = read(&bytes, Mode::Summary);
    assert!(metadata.issues.is_empty());
    assert_eq!(metadata.camera_make(), Some("Maker"));
    assert_eq!(metadata.xmp_description(None), Some("mist"));
    assert_eq!(
        metadata.iptc_caption(TextEncoding::Utf8).as_deref(),
        Some("dawn")
    );
}

#[test]
fn malformed_profiles_do_not_hide_later_metadata() {
    let good = profile(
        *b"tEXt",
        "xmp",
        xmp("<d:description>later</d:description>").as_bytes(),
    );
    for text in [
        "exif\n1\n00",
        "\nexif\nno\n00",
        "\nexif\n2\n00",
        "\nexif\n1\n0z",
        "\nexif\n1\n000",
        "\nexif\n184467440737095516160\n00",
    ] {
        let bad = png_chunk(
            *b"tEXt",
            &[b"Raw profile type exif\0".as_slice(), text.as_bytes()].concat(),
        );
        let metadata = read(&png(&[bad, good.clone()]), Mode::Summary);
        assert_eq!(metadata.issues.len(), 1, "{text}");
        assert_eq!(metadata.xmp_description(None), Some("later"));
    }
}

#[test]
fn decoded_profiles_share_the_expansion_budget() {
    let exif = tiff(
        &[
            (0x10f, 2, 6, b"Maker\0".to_vec()),
            (0x927c, 7, 1000, vec![0; 1000]),
        ],
        false,
    );
    let bytes = png(&[profile(*b"zTXt", "exif", &exif)]);
    let limits = Limits {
        value_bytes: 32,
        ..Default::default()
    };
    let metadata = ente_exif::read(&mut Cursor::new(&bytes), Mode::Summary, limits).unwrap();
    assert_eq!(metadata.camera_make(), Some("Maker"));
    let limits = Limits {
        read_bytes: 2500,
        ..limits
    };
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&bytes), Mode::Summary, limits),
        Err(Error::Limit(_))
    ));
}

#[test]
fn raw_profiles_tolerate_hex_case_and_ascii_whitespace() {
    let text = b"Raw profile type iptc\0\ngeneric profile\n  8\n1c 02 78 00 03 73\t65\r\n41\n";
    let metadata = read(&png(&[png_chunk(*b"tEXt", text)]), Mode::Summary);
    assert!(metadata.issues.is_empty());
    assert_eq!(
        metadata.iptc_caption(TextEncoding::Ascii).as_deref(),
        Some("seA")
    );
}

fn profile(kind: [u8; 4], name: &str, bytes: &[u8]) -> Vec<u8> {
    use std::fmt::Write;
    let mut text = format!("\n{name}\n{:8}\n", bytes.len());
    for (index, byte) in bytes.iter().enumerate() {
        write!(text, "{byte:02x}").unwrap();
        if index % 36 == 35 {
            text.push('\n');
        }
    }
    text.push('\n');
    let mut data = format!("Raw profile type {name}\0").into_bytes();
    if kind == *b"zTXt" {
        data.push(0);
        data.extend(miniz_oxide::deflate::compress_to_vec_zlib(
            text.as_bytes(),
            6,
        ));
    } else {
        if kind == *b"iTXt" {
            data.extend([0; 4]);
        }
        data.extend(text.as_bytes());
    }
    png_chunk(kind, &data)
}

fn png(chunks: &[Vec<u8>]) -> Vec<u8> {
    let ihdr = [
        2u32.to_be_bytes().as_slice(),
        &3u32.to_be_bytes(),
        &[8, 2, 0, 0, 0],
    ]
    .concat();
    [
        b"\x89PNG\r\n\x1a\n".to_vec(),
        png_chunk(*b"IHDR", &ihdr),
        chunks.concat(),
        png_chunk(*b"IEND", &[]),
    ]
    .concat()
}
