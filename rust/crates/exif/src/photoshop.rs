use crate::read::{Cursor, Error, State};
use crate::{iptc, xmp};

pub(crate) fn read(data: &[u8], state: &mut State) -> Result<(), Error> {
    let data = data.strip_prefix(b"Photoshop 3.0\0").unwrap_or(data);
    if !data.starts_with(b"8BIM") {
        return Ok(());
    }
    let mut cursor = Cursor::new(data);
    while cursor.pos < data.len() {
        state.entries(1)?;
        if cursor.take(4)? != b"8BIM" {
            return Err(Error::Malformed("Photoshop resource"));
        }
        let id = cursor.number(2)?;
        let name_length = cursor.number(1)? as usize;
        cursor.take(name_length + ((name_length + 1) & 1))?;
        let size = cursor.number(4)? as usize;
        let offset = cursor.pos as u64;
        let value = cursor.take(size)?;
        cursor.take(size & 1)?;
        let result = match id {
            0x404 => iptc::read(value, state),
            0x424 => xmp::read(value, state),
            _ => Ok(()),
        };
        state.recover(offset, result)?;
    }
    Ok(())
}
