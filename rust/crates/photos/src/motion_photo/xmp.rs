use super::MotionPhotoError;
use std::collections::HashMap;

const XMP_MARKER_BEGIN: &[u8] = b"<x:xmpmeta";
const XMP_MARKER_END: &[u8] = b"</x:xmpmeta>";

pub(crate) fn extract_xmp(source: &[u8]) -> Result<HashMap<String, String>, MotionPhotoError> {
    let (begin, end) = extract_xmp_bounds(source)
        .ok_or_else(|| MotionPhotoError::Xml("xmp markers not found".to_string()))?;
    let xml_bytes = &source[begin..end];
    parse_xmp_attributes(xml_bytes)
}

fn extract_xmp_bounds(source: &[u8]) -> Option<(usize, usize)> {
    let offset_begin = find_subslice(source, XMP_MARKER_BEGIN)?;
    let offset_end_start = find_subslice(&source[offset_begin..], XMP_MARKER_END)? + offset_begin;
    let offset_end = offset_end_start + XMP_MARKER_END.len();
    Some((offset_begin, offset_end))
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
                    let key = std::str::from_utf8(attribute.key.as_ref())
                        .map_err(|err| MotionPhotoError::Xml(format!("invalid key bytes: {err}")))?
                        .trim()
                        .to_string();
                    if key.starts_with("xmlns:") || key.starts_with("xml:") {
                        continue;
                    }

                    let value = attribute
                        .decoded_and_normalized_value(XmlVersion::Implicit1_0, reader.decoder())
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

fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}
