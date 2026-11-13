use super::common::{jpeg, read, segment, tiff};
use ente_exif::{Iptc, Metadata, Mode, TextEncoding, Value};
use std::borrow::Cow;

#[test]
fn text_decoding_is_explicit_lazy_and_preserves_original_bytes() {
    let value = Value::Ascii(b"Coffee \xe9\0tail".to_vec());
    assert_eq!(value.text(), None);
    assert_eq!(value.text_with(TextEncoding::Utf8), None);
    assert_eq!(value.text_with(TextEncoding::Ascii), None);
    assert_eq!(
        value.text_with(TextEncoding::Latin1).as_deref(),
        Some("Coffee é")
    );
    assert_eq!(value, Value::Ascii(b"Coffee \xe9\0tail".to_vec()));

    let ascii = Value::Ascii(b"camera\0tail".to_vec());
    for encoding in [
        TextEncoding::Ascii,
        TextEncoding::Utf8,
        TextEncoding::Latin1,
        TextEncoding::Windows1252,
    ] {
        assert!(matches!(
            ascii.text_with(encoding),
            Some(Cow::Borrowed("camera"))
        ));
    }
    let utf8 = Value::Ascii("星空\0".as_bytes().to_vec());
    assert!(matches!(
        utf8.text_with(TextEncoding::Utf8),
        Some(Cow::Borrowed("星空"))
    ));
    assert_eq!(
        Value::Bytes(b"text".to_vec()).text_with(TextEncoding::Utf8),
        None
    );
}

#[test]
fn windows_1252_and_latin1_are_not_interchangeable() {
    let value = Value::Ascii(b"\x80\x91\x92\x93\x94\x96\x97\x99\xe9".to_vec());
    assert_eq!(
        value.text_with(TextEncoding::Windows1252).as_deref(),
        Some("€‘’“”–—™é")
    );
    assert_eq!(
        value.text_with(TextEncoding::Latin1).as_deref(),
        Some("\u{80}\u{91}\u{92}\u{93}\u{94}\u{96}\u{97}\u{99}é")
    );
}

#[test]
fn iptc_announcements_override_the_explicit_fallback() {
    let mut metadata = Metadata {
        iptc: vec![Iptc {
            record: 2,
            dataset: 120,
            value: b"  coast \x97 caf\xe9  ".to_vec(),
        }],
        ..Default::default()
    };
    assert_eq!(
        metadata.iptc_caption(TextEncoding::Windows1252).as_deref(),
        Some("  coast — café  ")
    );
    assert_eq!(metadata.iptc_caption(TextEncoding::Utf8), None);
    metadata.iptc.push(Iptc {
        record: 1,
        dataset: 90,
        value: b"\x1b%G".to_vec(),
    });
    assert_eq!(metadata.iptc_caption(TextEncoding::Windows1252), None);
    metadata.iptc[0].value = "海辺".as_bytes().to_vec();
    assert!(matches!(
        metadata.iptc_caption(TextEncoding::Windows1252),
        Some(Cow::Borrowed("海辺"))
    ));
    metadata.iptc[1].value = b"\x1b-A".to_vec();
    assert_eq!(metadata.iptc_caption(TextEncoding::Windows1252), None);
    metadata.iptc.push(Iptc {
        record: 1,
        dataset: 5,
        value: b"\xe9".to_vec(),
    });
    assert_eq!(metadata.iptc_text(1, 5, TextEncoding::Latin1), None);
}

#[test]
fn jpeg_retains_legacy_text_for_on_demand_decoding_in_both_modes() {
    let value = b"Woodland \xe9\0";
    let exif = tiff(&[(0x10e, 2, value.len() as u32, value.to_vec())], false);
    let caption = b"Trail \x97 river";
    let iim = [
        b"\x1c\x02\x78".as_slice(),
        &(caption.len() as u16).to_be_bytes(),
        caption,
    ]
    .concat();
    let mut resource = b"8BIM\x04\x04\0\0".to_vec();
    resource.extend((iim.len() as u32).to_be_bytes());
    resource.extend(&iim);
    resource.resize(resource.len() + (iim.len() & 1), 0);
    let mut bytes = jpeg(&exif, "");
    bytes.splice(2..2, segment(0xed, &resource));
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(&bytes, mode);
        assert!(metadata.issues.is_empty());
        assert_eq!(metadata.exif_description(), None);
        assert_eq!(
            metadata
                .tag(ente_exif::Ifd::Image(0), 0x10e)
                .unwrap()
                .value
                .text_with(TextEncoding::Latin1)
                .as_deref(),
            Some("Woodland é")
        );
        assert_eq!(
            metadata.iptc_caption(TextEncoding::Windows1252).as_deref(),
            Some("Trail — river")
        );
    }
}
