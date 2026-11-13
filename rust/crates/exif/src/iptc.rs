use crate::read::{Cursor, Error, State};
use crate::{Metadata, Mode, TextEncoding, text};
use std::borrow::Cow;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Iptc {
    pub record: u8,
    pub dataset: u8,
    pub value: Vec<u8>,
}

impl Metadata {
    pub fn iptc_caption(&self, fallback: TextEncoding) -> Option<Cow<'_, str>> {
        self.iptc_text(2, 120, fallback)
    }
    pub fn iptc_text(
        &self,
        record: u8,
        dataset: u8,
        fallback: TextEncoding,
    ) -> Option<Cow<'_, str>> {
        let encoding = match record {
            1 => TextEncoding::Ascii,
            2..=6 | 8 => match self.iptc.iter().find(|v| v.record == 1 && v.dataset == 90) {
                Some(v) if v.value == b"\x1b%G" => TextEncoding::Utf8,
                Some(_) => return None,
                None => fallback,
            },
            _ => return None,
        };
        let value = &self
            .iptc
            .iter()
            .find(|v| v.record == record && v.dataset == dataset)?
            .value;
        text::decode(value, encoding)
    }
}

pub(crate) fn read(data: &[u8], state: &mut State) -> Result<(), Error> {
    let mut cursor = Cursor::new(data);
    while cursor.pos < data.len() {
        state.entries(1)?;
        if data[cursor.pos] == 0 && data[cursor.pos..].iter().all(|b| *b == 0) {
            break;
        }
        if cursor.number(1)? != 0x1c {
            return Err(Error::Malformed("IPTC dataset"));
        }
        let record = cursor.number(1)? as u8;
        let dataset = cursor.number(1)? as u8;
        let size = cursor.number(2)? as usize;
        let size = if size & 0x8000 != 0 {
            let width = size & 0x7fff;
            if width == 0 || width > 4 {
                return Err(Error::Malformed("IPTC extended size"));
            }
            cursor.number(width)? as usize
        } else {
            size
        };
        let value = cursor.take(size)?;
        if state.mode == Mode::Details
            || matches!((record, dataset), (1, 90) | (2, 55 | 60 | 62 | 63 | 120))
        {
            if size > state.limits.value_bytes {
                return Err(Error::Limit("IPTC value"));
            }
            state.retain(std::mem::size_of::<Iptc>() + size)?;
            state.metadata.iptc.push(Iptc {
                record,
                dataset,
                value: value.to_vec(),
            });
        }
    }
    Ok(())
}
