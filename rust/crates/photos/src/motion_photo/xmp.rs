use super::{BUFFER_SIZE, MotionPhotoError};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read};

const XMP_MARKER_BEGIN: &[u8] = b"<x:xmpmeta";
const XMP_MARKER_END: &[u8] = b"</x:xmpmeta>";

pub(super) const MAX_XMP_SIZE: usize = 8 * 1024 * 1024;

pub(super) fn extract_xmp<R: Read>(source: R) -> Result<HashMap<String, String>, MotionPhotoError> {
    let mut reader = BufReader::with_capacity(BUFFER_SIZE, source);
    let mut matched = 0;
    while matched < XMP_MARKER_BEGIN.len() {
        let bytes = reader.fill_buf()?;
        if bytes.is_empty() {
            return Err(MotionPhotoError::Xml("xmp markers not found".to_string()));
        }
        let consumed = through_marker(bytes, XMP_MARKER_BEGIN, &mut matched);
        reader.consume(consumed);
    }

    let mut xml = XMP_MARKER_BEGIN.to_vec();
    matched = 0;
    while matched < XMP_MARKER_END.len() {
        let bytes = reader.fill_buf()?;
        if bytes.is_empty() {
            return Err(MotionPhotoError::Xml("xmp markers not found".to_string()));
        }
        let consumed = through_marker(bytes, XMP_MARKER_END, &mut matched);
        if consumed > MAX_XMP_SIZE - xml.len() {
            return Err(MotionPhotoError::XmpTooLarge);
        }
        xml.extend_from_slice(&bytes[..consumed]);
        reader.consume(consumed);
    }
    parse_xmp_attributes(&xml)
}

fn through_marker(bytes: &[u8], marker: &[u8], matched: &mut usize) -> usize {
    for (index, &byte) in bytes.iter().enumerate() {
        if byte == marker[*matched] {
            *matched += 1;
            if *matched == marker.len() {
                return index + 1;
            }
        } else {
            *matched = usize::from(byte == marker[0]);
        }
    }
    bytes.len()
}

fn parse_xmp_attributes(xml_bytes: &[u8]) -> Result<HashMap<String, String>, MotionPhotoError> {
    use quick_xml::events::Event;
    use quick_xml::{Reader, XmlVersion};

    let xml_buffer = String::from_utf8_lossy(xml_bytes);
    let mut reader = Reader::from_str(&xml_buffer);
    let mut result = HashMap::<String, String>::new();
    let mut scratch = Vec::<u8>::new();

    loop {
        match reader.read_event_into(&mut scratch) {
            Ok(Event::Start(element)) | Ok(Event::Empty(element)) => {
                for attribute in element.attributes() {
                    let attribute = attribute.map_err(|err| {
                        MotionPhotoError::Xml(format!("invalid attribute: {err}"))
                    })?;
                    let key = attribute.key.as_ref().trim().to_string();
                    if key.starts_with("xmlns:") || key.starts_with("xml:") {
                        continue;
                    }

                    let value = attribute
                        .normalized_value(XmlVersion::Implicit1_0)
                        .map_err(|err| MotionPhotoError::Xml(format!("invalid value: {err}")))?
                        .to_string();
                    result.insert(key, value);
                }
            }
            Ok(Event::Eof) => break,
            Ok(_) => {}
            Err(err) => return Err(MotionPhotoError::Xml(format!("xml parse failed: {err}"))),
        }
        scratch.clear();
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn restarts_marker_matching_after_a_partial_match() {
        for marker in [XMP_MARKER_BEGIN, XMP_MARKER_END] {
            for prefix_length in 1..marker.len() {
                let mut matched = 0;
                through_marker(&marker[..prefix_length], marker, &mut matched);
                assert_eq!(through_marker(marker, marker, &mut matched), marker.len());
                assert_eq!(matched, marker.len());
            }
        }
    }

    #[test]
    fn reads_first_packet_across_chunks() {
        let begin = br#"<x:xmpmeta Item:Length="7">"#;
        for marker in [XMP_MARKER_BEGIN, XMP_MARKER_END] {
            for split in 1..marker.len() {
                let prefix = if marker == XMP_MARKER_BEGIN {
                    BUFFER_SIZE - split
                } else {
                    BUFFER_SIZE - split - begin.len()
                };
                let source = [
                    vec![0; prefix],
                    begin.to_vec(),
                    XMP_MARKER_END.to_vec(),
                    br#"<x:xmpmeta Item:Length="8"></x:xmpmeta>"#.to_vec(),
                ]
                .concat();
                let result = extract_xmp(source.as_slice()).unwrap();
                assert_eq!(result.get("Item:Length").unwrap(), "7");
            }
        }
    }

    #[test]
    fn bounds_metadata_without_limiting_photo_size() {
        let begin = b"<x:xmpmeta>";
        let mut xml = begin.to_vec();
        xml.resize(MAX_XMP_SIZE - XMP_MARKER_END.len(), b' ');
        xml.extend_from_slice(XMP_MARKER_END);
        xml.extend_from_slice(&[0; 32]);
        assert!(extract_xmp(xml.as_slice()).unwrap().is_empty());
        xml.insert(begin.len(), b' ');
        assert!(matches!(
            extract_xmp(xml.as_slice()),
            Err(MotionPhotoError::XmpTooLarge)
        ));
        assert!(matches!(
            extract_xmp(b"<x:xmpmeta>".as_slice()),
            Err(MotionPhotoError::Xml(_))
        ));
    }
}
