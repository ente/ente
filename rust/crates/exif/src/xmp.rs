use crate::Mode;
use crate::read::{Error, OutputBudget, State};
use quick_xml::events::Event;
use quick_xml::name::ResolveResult;
use quick_xml::{NsReader, XmlVersion};
use std::borrow::Cow;

pub mod namespace {
    pub const EXIF: &str = "http://ns.adobe.com/exif/1.0/";
    pub const EXIF_EX: &str = "http://cipa.jp/exif/1.0/";
    pub const TIFF: &str = "http://ns.adobe.com/tiff/1.0/";
    pub const XMP: &str = "http://ns.adobe.com/xap/1.0/";
    pub const DC: &str = "http://purl.org/dc/elements/1.1/";
    pub const PHOTOSHOP: &str = "http://ns.adobe.com/photoshop/1.0/";
    pub const GPANO: &str = "http://ns.google.com/photos/1.0/panorama/";
    pub const CAMERA: &str = "http://ns.google.com/photos/1.0/camera/";
    pub const CONTAINER: &str = "http://ns.google.com/photos/1.0/container/";
    pub const ITEM: &str = "http://ns.google.com/photos/1.0/container/item/";
    pub const NOTE: &str = "http://ns.adobe.com/xmp/note/";
    pub const RDF: &str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
    pub const XML: &str = "http://www.w3.org/XML/1998/namespace";
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Property {
    pub namespace: String,
    pub name: String,
    pub value: String,
    pub language: Option<String>,
    pub item: Option<u32>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct XmpStructure {
    pub nodes: Vec<XmpNode>,
    pub parents: Vec<Option<u32>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmpNode {
    pub namespace: String,
    pub name: String,
    pub parent: Option<u32>,
    pub item: Option<u32>,
}

pub(crate) fn read(bytes: &[u8], state: &mut State) -> Result<(), Error> {
    if bytes.len() > state.limits.read_bytes {
        return Err(Error::Limit("XMP bytes"));
    }
    let text = text(bytes, state)?;
    let mut reader = NsReader::from_str(text.trim_end_matches('\0'));
    reader.resolver_mut().set_max_declarations_per_element(64);
    let mut stack: Vec<Frame> = Vec::new();
    let mut paths = Vec::new();
    let mut item_id = state
        .metadata
        .xmp
        .iter()
        .filter_map(|p| p.item)
        .max()
        .unwrap_or(0);
    let mut saw_rdf = false;
    let mut saw_root = false;
    loop {
        state.entries(1)?;
        let event = reader
            .read_event()
            .map_err(|_| Error::Malformed("XMP XML"))?;
        let empty = matches!(event, Event::Empty(_));
        match event {
            Event::Start(element) | Event::Empty(element) => {
                if stack.is_empty() {
                    if saw_root {
                        return Err(Error::Malformed("multiple XML roots"));
                    }
                    saw_root = true;
                }
                if stack.len() >= state.limits.depth {
                    return Err(Error::Limit("XML depth"));
                }
                let (ns, local) = reader.resolver().resolve_element(element.name());
                let ns = namespace_text(ns)?;
                let name = std::str::from_utf8(local.as_ref())
                    .map_err(|_| Error::Malformed("XML name"))?;
                if ns.len() + name.len() > state.limits.value_bytes {
                    return Err(Error::Limit("XML name"));
                }
                saw_rdf |= ns == namespace::RDF && name == "RDF";
                let item = if ns == namespace::RDF && name == "li" {
                    item_id = item_id.checked_add(1).ok_or(Error::Limit("RDF items"))?;
                    Some(item_id)
                } else {
                    stack.last().and_then(|f| f.item)
                };
                let mut language = stack.last().and_then(|f| f.language.clone());
                for attribute in element.attributes() {
                    let attribute = attribute.map_err(|_| Error::Malformed("XML attribute"))?;
                    if attribute.key.as_ref() == b"xml:lang" {
                        if attribute.value.len() > state.limits.value_bytes {
                            return Err(Error::Limit("XML language"));
                        }
                        language = Some(
                            attribute
                                .decoded_and_normalized_value(
                                    XmlVersion::Implicit1_0,
                                    reader.decoder(),
                                )
                                .map_err(|_| Error::Malformed("XML language"))?
                                .into_owned(),
                        );
                    }
                }
                if state.structure.is_some() {
                    let key = if ns == "adobe:ns:meta/"
                        || (ns == namespace::RDF && !matches!(name, "Bag" | "Seq" | "Alt" | "li"))
                    {
                        None
                    } else {
                        Some((ns.to_owned(), name.to_owned()))
                    };
                    paths.push(PathFrame {
                        key,
                        item,
                        node: None,
                        ready: false,
                    });
                }
                let key = if ns == namespace::RDF {
                    stack.last().and_then(|f| f.key.clone())
                } else if ns == "adobe:ns:meta/" || !wanted(state.mode, ns, name) {
                    None
                } else {
                    Some((ns.to_owned(), name.to_owned()))
                };
                stack.push(Frame {
                    key,
                    language,
                    item,
                    text: String::new(),
                });
                for attribute in element.attributes() {
                    state.entries(1)?;
                    let attribute = attribute.map_err(|_| Error::Malformed("XML attribute"))?;
                    if attribute.key.as_ref() == b"xmlns"
                        || attribute.key.as_ref().starts_with(b"xmlns:")
                    {
                        continue;
                    }
                    let (ans, aname) = reader.resolver().resolve_attribute(attribute.key);
                    let ans = namespace_text(ans)?;
                    let aname = std::str::from_utf8(aname.as_ref())
                        .map_err(|_| Error::Malformed("XML attribute name"))?;
                    let (ans, aname) = if ans == namespace::RDF && aname == "resource" {
                        let Some((ns, name)) = stack.last().and_then(|f| f.key.as_ref()) else {
                            continue;
                        };
                        (ns.as_str(), name.as_str())
                    } else if ans == namespace::RDF || ans == namespace::XML || ans.is_empty() {
                        continue;
                    } else {
                        (ans, aname)
                    };
                    if !wanted(state.mode, ans, aname) {
                        continue;
                    }
                    if attribute.value.len() > state.limits.value_bytes {
                        return Err(Error::Limit("XML attribute"));
                    }
                    let value = attribute
                        .decoded_and_normalized_value(XmlVersion::Implicit1_0, reader.decoder())
                        .map_err(|_| Error::Malformed("XML attribute value"))?;
                    let language = stack.last().and_then(|f| f.language.as_deref());
                    let parent = if let Some(structure) = &mut state.structure {
                        path(&mut paths, &mut structure.nodes, &mut state.output)?
                    } else {
                        None
                    };
                    store(state, ans, aname, &value, language, item, parent)?;
                }
                if empty {
                    finish(&mut stack, &mut paths, state)?;
                }
            }
            Event::End(_) => {
                finish(&mut stack, &mut paths, state)?;
            }
            Event::Text(text) => {
                if stack.last().is_some_and(|f| f.key.is_none()) {
                    continue;
                }
                let text = text
                    .xml_content(XmlVersion::Implicit1_0)
                    .map_err(|_| Error::Malformed("XML text"))?;
                append(&mut stack, &text, state)?;
            }
            Event::CData(text) => {
                if stack.last().is_some_and(|f| f.key.is_none()) {
                    continue;
                }
                let text = text.decode().map_err(|_| Error::Malformed("XML CDATA"))?;
                append(&mut stack, &text, state)?;
            }
            Event::GeneralRef(entity) => {
                let text = if let Some(c) = entity
                    .resolve_char_ref()
                    .map_err(|_| Error::Malformed("XML character reference"))?
                {
                    c.to_string()
                } else {
                    match entity.as_ref() {
                        b"amp" => "&",
                        b"lt" => "<",
                        b"gt" => ">",
                        b"apos" => "'",
                        b"quot" => "\"",
                        _ => return Err(Error::Unsupported("XML entity")),
                    }
                    .to_owned()
                };
                append(&mut stack, &text, state)?;
            }
            Event::DocType(_) => return Err(Error::Unsupported("XML DTD")),
            Event::Eof => break,
            _ => {}
        }
    }
    if !stack.is_empty() {
        return Err(Error::Malformed("unclosed XML"));
    }
    if !saw_rdf {
        return Err(Error::Unsupported("XMP document"));
    }
    Ok(())
}

fn text<'a>(bytes: &'a [u8], state: &mut State) -> Result<Cow<'a, str>, Error> {
    let little = bytes.starts_with(b"\xff\xfe");
    if !little && !bytes.starts_with(b"\xfe\xff") {
        return std::str::from_utf8(bytes)
            .map(Cow::Borrowed)
            .map_err(|_| Error::Unsupported("XMP encoding"));
    }
    if !bytes.len().is_multiple_of(2) {
        return Err(Error::Malformed("UTF-16 XMP"));
    }
    let units = bytes[2..].as_chunks::<2>().0.iter().map(|b| {
        if little {
            u16::from_le_bytes(*b)
        } else {
            u16::from_be_bytes(*b)
        }
    });
    let mut decoded = String::with_capacity(bytes.len());
    for ch in char::decode_utf16(units) {
        let ch = ch.map_err(|_| Error::Malformed("UTF-16 XMP"))?;
        if decoded.len() + ch.len_utf8() > state.limits.read_bytes {
            return Err(Error::Limit("XMP bytes"));
        }
        decoded.push(ch);
    }
    state.expanded(decoded.len())?;
    Ok(Cow::Owned(decoded))
}

pub(crate) fn store(
    state: &mut State,
    ns: &str,
    name: &str,
    value: &str,
    language: Option<&str>,
    item: Option<u32>,
    parent: Option<u32>,
) -> Result<(), Error> {
    if !wanted(state.mode, ns, name) {
        return Ok(());
    }
    if value.len() > state.limits.value_bytes {
        return Err(Error::Limit("property value"));
    }
    state.retain(
        std::mem::size_of::<Property>()
            + ns.len()
            + name.len()
            + value.len()
            + language.map_or(0, str::len),
    )?;
    if let Some(structure) = &mut state.structure {
        state.output.retain(std::mem::size_of::<Option<u32>>())?;
        structure.parents.push(parent);
    }
    state.metadata.xmp.push(Property {
        namespace: ns.to_owned(),
        name: name.to_owned(),
        value: value.to_owned(),
        language: language.map(str::to_owned),
        item,
    });
    Ok(())
}

fn wanted(mode: Mode, ns: &str, name: &str) -> bool {
    if ns == namespace::CAMERA && name == "HdrPlusMakernote" {
        return false;
    }
    mode == Mode::Details || selected(ns, name)
}

fn selected(ns: &str, name: &str) -> bool {
    match ns {
        namespace::EXIF | namespace::EXIF_EX | namespace::TIFF => matches!(
            name,
            "DateTimeOriginal"
                | "DateTimeDigitized"
                | "DateTime"
                | "ImageWidth"
                | "ImageLength"
                | "PixelXDimension"
                | "PixelYDimension"
                | "Orientation"
                | "GPSLatitude"
                | "GPSLongitude"
                | "GPSLatitudeRef"
                | "GPSLongitudeRef"
                | "Make"
                | "Model"
        ),
        namespace::XMP => matches!(name, "CreateDate" | "ModifyDate" | "MetadataDate"),
        namespace::PHOTOSHOP => name == "DateCreated",
        namespace::DC => name == "description",
        namespace::GPANO => name == "ProjectionType",
        namespace::CAMERA => matches!(
            name,
            "MotionPhoto"
                | "MicroVideo"
                | "MicroVideoOffset"
                | "MotionPhotoPresentationTimestampUs"
        ),
        namespace::ITEM => matches!(name, "Mime" | "Semantic" | "Length" | "Padding"),
        namespace::NOTE => name == "HasExtendedXMP",
        _ => false,
    }
}

struct Frame {
    key: Option<(String, String)>,
    language: Option<String>,
    item: Option<u32>,
    text: String,
}

struct PathFrame {
    key: Option<(String, String)>,
    item: Option<u32>,
    node: Option<u32>,
    ready: bool,
}

fn path(
    stack: &mut [PathFrame],
    nodes: &mut Vec<XmpNode>,
    output: &mut OutputBudget,
) -> Result<Option<u32>, Error> {
    let Some((frame, rest)) = stack.split_last_mut() else {
        return Ok(None);
    };
    if frame.ready {
        return Ok(frame.node);
    }
    let parent = path(rest, nodes, output)?;
    frame.ready = true;
    let Some((ns, name)) = &frame.key else {
        frame.node = parent;
        return Ok(parent);
    };
    output.retain(std::mem::size_of::<XmpNode>() + ns.len() + name.len())?;
    let index = u32::try_from(nodes.len()).map_err(|_| Error::Limit("XMP nodes"))?;
    nodes.push(XmpNode {
        namespace: ns.to_owned(),
        name: name.to_owned(),
        parent,
        item: frame.item,
    });
    frame.node = Some(index);
    Ok(Some(index))
}

fn append(stack: &mut [Frame], text: &str, state: &State) -> Result<(), Error> {
    if let Some(frame) = stack.last_mut() {
        if frame.key.is_none() {
            return Ok(());
        }
        if text.len() > state.limits.value_bytes.saturating_sub(frame.text.len()) {
            return Err(Error::Limit("XML text"));
        }
        frame.text.push_str(text);
    } else if !text.trim().is_empty() {
        return Err(Error::Malformed("XML text outside root"));
    }
    Ok(())
}

fn finish(
    stack: &mut Vec<Frame>,
    paths: &mut Vec<PathFrame>,
    state: &mut State,
) -> Result<(), Error> {
    let frame = stack.pop().ok_or(Error::Malformed("XML nesting"))?;
    if let Some((ns, name)) = frame.key
        && !frame.text.trim().is_empty()
    {
        let parent = if let Some(structure) = &mut state.structure {
            let is_item = paths
                .last()
                .and_then(|p| p.key.as_ref())
                .is_some_and(|(ns, n)| ns == namespace::RDF && n == "li");
            let len = paths.len() - usize::from(!is_item);
            path(&mut paths[..len], &mut structure.nodes, &mut state.output)?
        } else {
            None
        };
        store(
            state,
            &ns,
            &name,
            frame.text.trim(),
            frame.language.as_deref(),
            frame.item,
            parent,
        )?;
    }
    paths.pop();
    Ok(())
}

fn namespace_text(ns: ResolveResult<'_>) -> Result<&str, Error> {
    match ns {
        ResolveResult::Bound(ns) => {
            std::str::from_utf8(ns.0).map_err(|_| Error::Malformed("XML namespace"))
        }
        ResolveResult::Unbound => Ok(""),
        ResolveResult::Unknown(_) => Err(Error::Malformed("undeclared XML namespace")),
    }
}
