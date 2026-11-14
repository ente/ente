use ente_core::b64;

use super::{Batch, Error, ImportedCode, Otp, Result, base32, build_uri};

pub const PREFIX: &str = "otpauth-migration://offline?data=";

pub struct GoogleMigration {
    pub batch: Batch,
    pub batch_id: i32,
    pub batch_size: i32,
    pub batch_index: i32,
}

pub fn parse_google_migration(input: &str) -> Result<GoogleMigration> {
    let payload = input
        .strip_prefix(PREFIX)
        .ok_or_else(|| Error::invalid("Invalid Google Authenticator migration URI"))?;
    let payload = urlencoding::decode(payload)
        .map_err(|_| Error::invalid("Invalid Google Authenticator migration URI"))?;
    let bytes = b64::decode(&payload)
        .map_err(|_| Error::invalid("Invalid Google Authenticator migration payload"))?;
    parse_payload(&bytes)
}

fn parse_payload(bytes: &[u8]) -> Result<GoogleMigration> {
    let mut reader = Reader::new(bytes);
    let mut codes = Vec::new();
    let mut batch_size = 0;
    let mut batch_index = 0;
    let mut batch_id = 0;
    while let Some((field, wire)) = reader.key()? {
        match (field, wire) {
            (1, 2) => codes.push(parse_otp(reader.bytes()?)?),
            (3, 0) => batch_size = reader.varint_i32()?,
            (4, 0) => batch_index = reader.varint_i32()?,
            (5, 0) => batch_id = reader.varint_i32()?,
            _ => reader.skip(wire)?,
        }
    }
    Ok(GoogleMigration {
        batch: Batch { codes, skipped: 0 },
        batch_id,
        batch_size,
        batch_index,
    })
}

fn parse_otp(bytes: &[u8]) -> Result<ImportedCode> {
    let mut reader = Reader::new(bytes);
    let mut secret = Vec::new();
    let mut account = String::new();
    let mut issuer = String::new();
    let mut algorithm = 0;
    let mut digits = 0;
    let mut kind = 0;
    let mut counter = 0;
    while let Some((field, wire)) = reader.key()? {
        match (field, wire) {
            (1, 2) => secret = reader.bytes()?.to_vec(),
            (2, 2) => account = reader.string()?,
            (3, 2) => issuer = reader.string()?,
            (4, 0) => algorithm = reader.varint_i32()?,
            (5, 0) => digits = reader.varint_i32()?,
            (6, 0) => kind = reader.varint_i32()?,
            (7, 0) => counter = reader.varint_i64()?,
            _ => reader.skip(wire)?,
        }
    }
    let algorithm = match algorithm {
        0 | 1 => "SHA1",
        2 => "SHA256",
        3 => "SHA512",
        4 => return Err(Error::invalid("Google Authenticator MD5 is not supported")),
        _ => return Err(Error::invalid("Invalid Google Authenticator algorithm")),
    };
    let digits = match digits {
        0 | 1 => 6,
        2 => 8,
        _ => return Err(Error::invalid("Invalid Google Authenticator digit count")),
    };
    let kind = match kind {
        0 | 2 => "totp",
        1 => "hotp",
        _ => return Err(Error::invalid("Invalid Google Authenticator OTP type")),
    };
    let uri = build_uri(Otp {
        kind,
        issuer: &issuer,
        account: &account,
        secret: &padded_base32(&secret),
        algorithm,
        digits: Some(i64::from(digits)),
        period: Some(30),
        counter: Some(counter),
        allow_steam: true,
    })?;
    Ok(ImportedCode { uri, display: None })
}

fn padded_base32(bytes: &[u8]) -> String {
    let mut output = base32(bytes);
    while !output.len().is_multiple_of(8) {
        output.push('=');
    }
    output
}

struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn key(&mut self) -> Result<Option<(u32, u8)>> {
        if self.offset == self.bytes.len() {
            return Ok(None);
        }
        let key = self.varint()?;
        let field = u32::try_from(key >> 3)
            .map_err(|_| Error::invalid("Invalid Google Authenticator payload"))?;
        if field == 0 {
            return Err(Error::invalid("Invalid Google Authenticator payload"));
        }
        Ok(Some((field, (key & 7) as u8)))
    }

    fn varint(&mut self) -> Result<u64> {
        let mut value = 0u64;
        for shift in (0..70).step_by(7) {
            let byte = *self
                .bytes
                .get(self.offset)
                .ok_or_else(|| Error::invalid("Truncated Google Authenticator payload"))?;
            self.offset += 1;
            if shift == 63 && byte > 1 {
                return Err(Error::invalid("Invalid Google Authenticator varint"));
            }
            value |= u64::from(byte & 0x7f) << shift;
            if byte & 0x80 == 0 {
                return Ok(value);
            }
        }
        Err(Error::invalid("Invalid Google Authenticator varint"))
    }

    fn varint_i32(&mut self) -> Result<i32> {
        Ok(self.varint()? as u32 as i32)
    }

    fn varint_i64(&mut self) -> Result<i64> {
        i64::try_from(self.varint()?)
            .map_err(|_| Error::invalid("Invalid Google Authenticator integer"))
    }

    fn bytes(&mut self) -> Result<&'a [u8]> {
        let length = usize::try_from(self.varint()?)
            .map_err(|_| Error::invalid("Invalid Google Authenticator payload length"))?;
        let end = self
            .offset
            .checked_add(length)
            .filter(|end| *end <= self.bytes.len())
            .ok_or_else(|| Error::invalid("Truncated Google Authenticator payload"))?;
        let value = &self.bytes[self.offset..end];
        self.offset = end;
        Ok(value)
    }

    fn string(&mut self) -> Result<String> {
        String::from_utf8(self.bytes()?.to_vec())
            .map_err(|_| Error::invalid("Invalid Google Authenticator text"))
    }

    fn skip(&mut self, wire: u8) -> Result<()> {
        match wire {
            0 => {
                self.varint()?;
            }
            1 => self.advance(8)?,
            2 => {
                self.bytes()?;
            }
            5 => self.advance(4)?,
            _ => return Err(Error::invalid("Invalid Google Authenticator wire type")),
        }
        Ok(())
    }

    fn advance(&mut self, length: usize) -> Result<()> {
        self.offset = self
            .offset
            .checked_add(length)
            .filter(|offset| *offset <= self.bytes.len())
            .ok_or_else(|| Error::invalid("Truncated Google Authenticator payload"))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_google_migration_payload_and_metadata() {
        let otp = message(&[
            field_bytes(1, b"Hello!\xde\xad\xbe\xef"),
            field_bytes(2, b"alice@example.com"),
            field_bytes(3, b"Example"),
            field_varint(4, 2),
            field_varint(5, 2),
            field_varint(6, 1),
            field_varint(7, 42),
        ]);
        let payload = message(&[
            field_bytes(1, &otp),
            field_varint(3, 3),
            field_varint(4, 1),
            field_varint(5, 99),
        ]);
        let migration = parse_payload(&payload).unwrap();
        assert_eq!(migration.batch.codes.len(), 1);
        assert_eq!(migration.batch_id, 99);
        assert_eq!(migration.batch_size, 3);
        assert_eq!(migration.batch_index, 1);
        let uri = &migration.batch.codes[0].uri;
        assert!(uri.starts_with("otpauth://hotp/Example:alice%40example.com?"));
        assert!(uri.contains("secret=JBSWY3DPEHPK3PXP"));
        assert!(uri.contains("algorithm=SHA256"));
        assert!(uri.contains("digits=8"));
        assert!(uri.contains("counter=42"));
    }

    #[test]
    fn protobuf_zero_enums_use_google_defaults() {
        let otp = message(&[
            field_bytes(1, b"secret"),
            field_bytes(2, b"alice"),
            field_varint(4, 0),
            field_varint(5, 0),
            field_varint(6, 0),
        ]);
        let payload = message(&[field_bytes(1, &otp)]);
        let uri = &parse_payload(&payload).unwrap().batch.codes[0].uri;
        assert!(uri.starts_with("otpauth://totp/:alice?"));
        assert!(uri.contains("algorithm=SHA1"));
        assert!(uri.contains("digits=6"));
        assert!(uri.contains("period=30"));
    }

    fn message(fields: &[Vec<u8>]) -> Vec<u8> {
        fields.iter().flatten().copied().collect()
    }

    fn field_bytes(number: u8, value: &[u8]) -> Vec<u8> {
        let mut bytes = vec![number << 3 | 2, value.len() as u8];
        bytes.extend_from_slice(value);
        bytes
    }

    fn field_varint(number: u8, value: u8) -> Vec<u8> {
        vec![number << 3, value]
    }
}
