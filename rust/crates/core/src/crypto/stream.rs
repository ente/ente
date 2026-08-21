// Wire-compatible with libsodium's `crypto_secretstream_xchacha20poly1305`.
// A separate 24-byte header precedes the encrypted messages.
// The final tag is required to distinguish a complete stream from truncation.

use crypto_secretstream::{
    Header as UpstreamHeader, Key as UpstreamKey, PullStream, PushStream, Stream, Tag,
};
use rand_core_06::OsRng;
use std::io::{Read, Write};

use crate::crypto::{Error, Header, Key, Result};

// The typed Key/Header sizes must match the upstream secretstream sizes; the
// conversions below rely on it.
const _: () = assert!(Key::BYTES == UpstreamKey::BYTES);
const _: () = assert!(Header::BYTES == UpstreamHeader::BYTES);

pub const ABYTES: usize = Stream::ABYTES;

pub const ENCRYPTION_CHUNK_SIZE: usize = 4 * 1024 * 1024;

pub const DECRYPTION_CHUNK_SIZE: usize = ENCRYPTION_CHUNK_SIZE + ABYTES;

fn upstream_key(key: &Key) -> UpstreamKey {
    UpstreamKey::from(*key.as_bytes())
}

pub struct Encryptor {
    stream: PushStream,
    header: Header,
}

impl Encryptor {
    pub fn new(key: &Key) -> Self {
        let (header, stream) = PushStream::init(OsRng, &upstream_key(key));
        Self {
            stream,
            header: Header::from_bytes(*header.as_ref()),
        }
    }

    pub fn header(&self) -> &Header {
        &self.header
    }

    pub fn push(&mut self, data: &[u8], is_final: bool) -> Result<Vec<u8>> {
        let mut buffer = Vec::with_capacity(data.len() + ABYTES);
        buffer.extend_from_slice(data);
        self.push_in_place(&mut buffer, is_final)?;
        Ok(buffer)
    }

    fn push_in_place(&mut self, buffer: &mut Vec<u8>, is_final: bool) -> Result<()> {
        let tag = if is_final { Tag::Final } else { Tag::Message };
        self.stream
            .push(buffer, &[], tag)
            .map_err(|_| Error::StreamPushFailed)
    }
}

pub struct Decryptor {
    stream: PullStream,
    seen_final: bool,
}

impl Decryptor {
    pub fn new(header: &Header, key: &Key) -> Self {
        let header = UpstreamHeader::from(*header.as_bytes());
        let stream = PullStream::init(header, &upstream_key(key));
        Self {
            stream,
            seen_final: false,
        }
    }

    pub fn pull(&mut self, data: &[u8]) -> Result<(Vec<u8>, bool)> {
        let mut buffer = data.to_vec();
        let is_final = self.pull_in_place(&mut buffer)?;
        Ok((buffer, is_final))
    }

    fn pull_in_place(&mut self, buffer: &mut Vec<u8>) -> Result<bool> {
        if buffer.len() < ABYTES {
            return Err(Error::StreamPullFailed);
        }

        let tag = self
            .stream
            .pull(buffer, &[])
            .map_err(|_| Error::StreamPullFailed)?;

        let is_final = matches!(tag, Tag::Final);
        if is_final {
            self.seen_final = true;
        }
        Ok(is_final)
    }

    // EOF can follow a non-final chunk, so callers must finish the stream.
    pub fn finish(self) -> Result<()> {
        if self.seen_final {
            Ok(())
        } else {
            Err(Error::StreamTruncated)
        }
    }
}

#[inline]
pub fn estimate_encrypted_size(plaintext_len: usize) -> usize {
    if plaintext_len == 0 {
        return ABYTES;
    }

    let full_chunks = plaintext_len / ENCRYPTION_CHUNK_SIZE;
    let last_chunk_size = plaintext_len % ENCRYPTION_CHUNK_SIZE;

    let full_bytes = match full_chunks.checked_mul(DECRYPTION_CHUNK_SIZE) {
        Some(value) => value,
        None => return usize::MAX,
    };

    if last_chunk_size == 0 {
        return full_bytes;
    }

    let with_last = match full_bytes.checked_add(last_chunk_size) {
        Some(value) => value,
        None => return usize::MAX,
    };
    match with_last.checked_add(ABYTES) {
        Some(value) => value,
        None => usize::MAX,
    }
}

#[inline]
pub fn validate_sizes(plaintext_len: usize, ciphertext_len: usize) -> bool {
    let estimated = estimate_encrypted_size(plaintext_len);
    if estimated == usize::MAX {
        return false;
    }
    estimated == ciphertext_len
}

pub struct StreamingEncryptor<W: Write> {
    encryptor: Encryptor,
    writer: W,
    buffer: Vec<u8>,
    // Hold one full chunk until we know whether it needs the final tag.
    pending: Vec<u8>,
}

impl<W: Write> StreamingEncryptor<W> {
    pub fn new(key: &Key, mut writer: W) -> Result<Self> {
        let encryptor = Encryptor::new(key);
        writer.write_all(encryptor.header().as_bytes())?;
        Ok(Self {
            encryptor,
            writer,
            buffer: Vec::with_capacity(ENCRYPTION_CHUNK_SIZE + ABYTES),
            pending: Vec::with_capacity(ENCRYPTION_CHUNK_SIZE + ABYTES),
        })
    }

    fn flush_pending(&mut self, is_final: bool) -> Result<()> {
        if self.pending.is_empty() {
            return Ok(());
        }

        self.encryptor.push_in_place(&mut self.pending, is_final)?;
        self.writer.write_all(&self.pending)?;
        self.pending.clear();
        Ok(())
    }

    fn push_full_chunk(&mut self) -> Result<()> {
        if !self.pending.is_empty() {
            self.flush_pending(false)?;
        }

        std::mem::swap(&mut self.pending, &mut self.buffer);
        self.buffer.clear();
        Ok(())
    }

    pub fn write(&mut self, data: &[u8]) -> Result<()> {
        let mut input_pos = 0;

        if !self.buffer.is_empty() {
            let space_in_buffer = ENCRYPTION_CHUNK_SIZE - self.buffer.len();
            let bytes_to_add = std::cmp::min(space_in_buffer, data.len());
            self.buffer.extend_from_slice(&data[..bytes_to_add]);
            input_pos = bytes_to_add;

            if self.buffer.len() == ENCRYPTION_CHUNK_SIZE {
                self.push_full_chunk()?;
            } else {
                return Ok(());
            }
        }

        while input_pos + ENCRYPTION_CHUNK_SIZE <= data.len() {
            self.buffer.clear();
            self.buffer
                .extend_from_slice(&data[input_pos..input_pos + ENCRYPTION_CHUNK_SIZE]);
            input_pos += ENCRYPTION_CHUNK_SIZE;
            self.push_full_chunk()?;
        }

        if input_pos < data.len() {
            self.buffer.extend_from_slice(&data[input_pos..]);
        }

        Ok(())
    }

    pub fn finish(mut self) -> Result<W> {
        if !self.pending.is_empty() {
            if !self.buffer.is_empty() {
                self.flush_pending(false)?;
            } else {
                self.flush_pending(true)?;
                return Ok(self.writer);
            }
        }

        self.encryptor.push_in_place(&mut self.buffer, true)?;
        self.writer.write_all(&self.buffer)?;
        Ok(self.writer)
    }
}

pub struct StreamingDecryptor<R: Read> {
    decryptor: Decryptor,
    reader: R,
    buffer: Vec<u8>,
    data_start: usize,
    finished: bool,
    seen_final: bool,
}

fn ensure_reader_exhausted<R: Read>(reader: &mut R) -> Result<()> {
    let mut extra = [0u8; 1];

    loop {
        match reader.read(&mut extra) {
            Ok(0) => return Ok(()),
            Ok(_) => return Err(Error::StreamTrailingData),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.into()),
        }
    }
}

impl<R: Read> StreamingDecryptor<R> {
    pub fn new(key: &Key, mut reader: R) -> Result<Self> {
        let mut header = [0u8; Header::BYTES];
        reader.read_exact(&mut header)?;
        let decryptor = Decryptor::new(&Header::from_bytes(header), key);
        Ok(Self {
            decryptor,
            reader,
            buffer: Vec::with_capacity(DECRYPTION_CHUNK_SIZE),
            data_start: 0,
            finished: false,
            seen_final: false,
        })
    }

    pub fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        // A final chunk may still have unread plaintext, so drain it before
        // honoring `finished`.
        let buffered_remaining = self.buffer.len() - self.data_start;
        if buffered_remaining > 0 {
            let to_copy = std::cmp::min(buf.len(), buffered_remaining);
            buf[..to_copy]
                .copy_from_slice(&self.buffer[self.data_start..self.data_start + to_copy]);
            self.data_start += to_copy;

            if self.data_start == self.buffer.len() {
                self.buffer.clear();
                self.data_start = 0;
            }
            return Ok(to_copy);
        }

        if self.finished {
            return Ok(0);
        }

        self.buffer.clear();
        self.buffer.resize(DECRYPTION_CHUNK_SIZE, 0);
        let mut total_read = 0;

        loop {
            match self.reader.read(&mut self.buffer[total_read..]) {
                Ok(0) => break,
                Ok(n) => {
                    total_read += n;
                    if total_read >= DECRYPTION_CHUNK_SIZE {
                        break;
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e.into()),
            }
        }

        if total_read == 0 {
            self.buffer.clear();
            if !self.seen_final {
                return Err(Error::StreamTruncated);
            }
            self.finished = true;
            return Ok(0);
        }

        self.buffer.truncate(total_read);
        let is_final = self.decryptor.pull_in_place(&mut self.buffer)?;

        if is_final {
            self.seen_final = true;
            ensure_reader_exhausted(&mut self.reader)?;
            self.finished = true;
        }

        self.data_start = 0;
        let plaintext_len = self.buffer.len();
        let to_copy = std::cmp::min(buf.len(), plaintext_len);
        buf[..to_copy].copy_from_slice(&self.buffer[..to_copy]);
        self.data_start = to_copy;

        if self.data_start == self.buffer.len() {
            self.buffer.clear();
            self.data_start = 0;
        }

        Ok(to_copy)
    }

    pub fn read_to_end(&mut self) -> Result<Vec<u8>> {
        let mut result = Vec::new();
        let mut buf = [0u8; 8192];

        loop {
            match self.read(&mut buf)? {
                0 => break,
                n => result.extend_from_slice(&buf[..n]),
            }
        }

        Ok(result)
    }
}

pub fn encrypt_file<R: Read, W: Write>(
    reader: &mut R,
    writer: &mut W,
    key: &Key,
) -> Result<Header> {
    let mut encryptor = Encryptor::new(key);
    let header = *encryptor.header();

    let mut read_chunk = |buf: &mut [u8]| -> Result<usize> {
        let mut total_read = 0;
        while total_read < ENCRYPTION_CHUNK_SIZE {
            match reader.read(&mut buf[total_read..]) {
                Ok(0) => break,
                Ok(n) => total_read += n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e.into()),
            }
        }
        Ok(total_read)
    };

    let mut curr = vec![0u8; ENCRYPTION_CHUNK_SIZE];
    let mut next = vec![0u8; ENCRYPTION_CHUNK_SIZE];

    let mut encrypt_buffer = Vec::with_capacity(ENCRYPTION_CHUNK_SIZE + ABYTES);

    let mut curr_len = read_chunk(&mut curr)?;

    if curr_len == 0 {
        encrypt_buffer.clear();
        encryptor.push_in_place(&mut encrypt_buffer, true)?;
        writer.write_all(&encrypt_buffer)?;
        return Ok(header);
    }

    loop {
        if curr_len < ENCRYPTION_CHUNK_SIZE {
            encrypt_buffer.clear();
            encrypt_buffer.extend_from_slice(&curr[..curr_len]);
            encryptor.push_in_place(&mut encrypt_buffer, true)?;
            writer.write_all(&encrypt_buffer)?;
            break;
        }

        let next_len = read_chunk(&mut next)?;
        let is_final = next_len == 0;

        encrypt_buffer.clear();
        encrypt_buffer.extend_from_slice(&curr[..curr_len]);
        encryptor.push_in_place(&mut encrypt_buffer, is_final)?;
        writer.write_all(&encrypt_buffer)?;

        if is_final {
            break;
        }

        std::mem::swap(&mut curr, &mut next);
        curr_len = next_len;
    }

    Ok(header)
}

pub fn decrypt_file<R: Read, W: Write>(
    reader: &mut R,
    writer: &mut W,
    header: &Header,
    key: &Key,
) -> Result<()> {
    let mut decryptor = Decryptor::new(header, key);
    let mut read_buffer = vec![0u8; DECRYPTION_CHUNK_SIZE];
    let mut decrypt_buffer = Vec::with_capacity(DECRYPTION_CHUNK_SIZE);

    loop {
        let mut total_read = 0;
        while total_read < DECRYPTION_CHUNK_SIZE {
            match reader.read(&mut read_buffer[total_read..]) {
                Ok(0) => break,
                Ok(n) => total_read += n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e.into()),
            }
        }

        if total_read == 0 {
            return decryptor.finish();
        }

        decrypt_buffer.clear();
        decrypt_buffer.extend_from_slice(&read_buffer[..total_read]);
        let is_final = decryptor.pull_in_place(&mut decrypt_buffer)?;
        writer.write_all(&decrypt_buffer)?;

        if is_final {
            ensure_reader_exhausted(reader)?;
            return Ok(());
        }
    }
}

pub fn decrypt_file_data(encrypted_data: &[u8], header: &Header, key: &Key) -> Result<Vec<u8>> {
    use std::io::Cursor;

    let mut reader = Cursor::new(encrypted_data);
    let mut output = Vec::new();
    decrypt_file(&mut reader, &mut output, header, key)?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn test_key() -> Key {
        Key::from_bytes([0x42u8; Key::BYTES])
    }

    #[test]
    fn test_streaming_roundtrip() {
        let key = test_key();
        let plaintext = b"Hello, world! This is a test message.";

        let mut encrypted = Vec::new();
        {
            let mut encryptor =
                StreamingEncryptor::new(&key, &mut encrypted).expect("encryptor creation failed");
            encryptor.write(plaintext).expect("write failed");
            encryptor.finish().expect("finish failed");
        }

        let reader = Cursor::new(&encrypted);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let decrypted = decryptor.read_to_end().expect("read_to_end failed");

        assert_eq!(plaintext.as_slice(), decrypted.as_slice());
    }

    #[test]
    fn test_truncation_detection_empty_stream() {
        let key = test_key();

        let encryptor = Encryptor::new(&key);
        let truncated_data = encryptor.header().as_bytes().to_vec();

        let reader = Cursor::new(&truncated_data);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let result = decryptor.read_to_end();

        assert!(
            matches!(result, Err(Error::StreamTruncated)),
            "Expected StreamTruncated error, got {:?}",
            result
        );
    }

    #[test]
    fn test_truncation_detection_missing_final() {
        let key = test_key();
        let plaintext = b"Hello, world!";

        let mut encryptor = Encryptor::new(&key);
        let mut truncated_data = encryptor.header().as_bytes().to_vec();
        let encrypted_chunk = encryptor.push(plaintext, false).expect("push failed");
        truncated_data.extend_from_slice(&encrypted_chunk);

        let reader = Cursor::new(&truncated_data);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let result = decryptor.read_to_end();

        assert!(
            matches!(result, Err(Error::StreamTruncated)),
            "Expected StreamTruncated error, got {:?}",
            result
        );
    }

    #[test]
    fn test_valid_stream_with_final_tag() {
        let key = test_key();
        let plaintext = b"Hello, world!";

        let mut encryptor = Encryptor::new(&key);
        let mut data = encryptor.header().as_bytes().to_vec();
        let encrypted_chunk = encryptor.push(plaintext, true).expect("push failed");
        data.extend_from_slice(&encrypted_chunk);

        let reader = Cursor::new(&data);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let decrypted = decryptor.read_to_end().expect("read_to_end failed");

        assert_eq!(plaintext.as_slice(), decrypted.as_slice());
    }

    #[test]
    fn test_decryptor_finish_detects_missing_final_tag() {
        let key = test_key();

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let chunk1 = encryptor.push(b"chunk one", false).unwrap();
        let chunk2 = encryptor.push(b"chunk two", false).unwrap();

        let mut decryptor = Decryptor::new(&header, &key);
        let (pt1, is_final1) = decryptor.pull(&chunk1).unwrap();
        let (pt2, is_final2) = decryptor.pull(&chunk2).unwrap();
        assert_eq!(pt1, b"chunk one");
        assert_eq!(pt2, b"chunk two");
        assert!(!is_final1 && !is_final2);

        assert!(matches!(decryptor.finish(), Err(Error::StreamTruncated)));
    }

    #[test]
    fn test_decryptor_finish_accepts_complete_stream() {
        let key = test_key();

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let chunk = encryptor.push(b"only chunk", true).unwrap();

        let mut decryptor = Decryptor::new(&header, &key);
        let (_, is_final) = decryptor.pull(&chunk).unwrap();
        assert!(is_final);
        decryptor.finish().unwrap();
    }

    #[test]
    fn test_small_buffer_reads_no_quadratic() {
        let key = test_key();
        let plaintext: Vec<u8> = (0..10000).map(|i| (i % 256) as u8).collect();

        let mut encrypted = Vec::new();
        {
            let mut encryptor =
                StreamingEncryptor::new(&key, &mut encrypted).expect("encryptor creation failed");
            encryptor.write(&plaintext).expect("write failed");
            encryptor.finish().expect("finish failed");
        }

        let reader = Cursor::new(&encrypted);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");

        let mut decrypted = Vec::new();
        let mut tiny_buf = [0u8; 1];
        loop {
            match decryptor.read(&mut tiny_buf).expect("read failed") {
                0 => break,
                n => decrypted.extend_from_slice(&tiny_buf[..n]),
            }
        }

        assert_eq!(plaintext, decrypted);
    }

    #[test]
    fn test_varied_buffer_sizes() {
        let key = test_key();
        let plaintext: Vec<u8> = (0..5000).map(|i| (i % 256) as u8).collect();

        let mut encrypted = Vec::new();
        {
            let mut encryptor =
                StreamingEncryptor::new(&key, &mut encrypted).expect("encryptor creation failed");
            encryptor.write(&plaintext).expect("write failed");
            encryptor.finish().expect("finish failed");
        }

        for buf_size in [1, 7, 13, 64, 100, 1000, 8192] {
            let reader = Cursor::new(&encrypted);
            let mut decryptor =
                StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");

            let mut decrypted = Vec::new();
            let mut buf = vec![0u8; buf_size];
            loop {
                match decryptor.read(&mut buf).expect("read failed") {
                    0 => break,
                    n => decrypted.extend_from_slice(&buf[..n]),
                }
            }

            assert_eq!(
                plaintext, decrypted,
                "Mismatch with buffer size {}",
                buf_size
            );
        }
    }

    #[test]
    fn test_large_slice_write_no_quadratic() {
        let key = test_key();

        let size = ENCRYPTION_CHUNK_SIZE * 3 + 1234;
        let plaintext: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();

        let mut encrypted = Vec::new();
        {
            let mut encryptor =
                StreamingEncryptor::new(&key, &mut encrypted).expect("encryptor creation failed");
            encryptor.write(&plaintext).expect("write failed");
            encryptor.finish().expect("finish failed");
        }

        let reader = Cursor::new(&encrypted);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let decrypted = decryptor.read_to_end().expect("read_to_end failed");

        assert_eq!(plaintext.len(), decrypted.len());
        assert_eq!(plaintext, decrypted);

        let ciphertext_len = encrypted.len() - Header::BYTES;
        assert_eq!(ciphertext_len, estimate_encrypted_size(plaintext.len()));
    }

    #[test]
    fn test_write_with_partial_buffer_then_large_slice() {
        let key = test_key();

        let mut encrypted = Vec::new();
        {
            let mut encryptor =
                StreamingEncryptor::new(&key, &mut encrypted).expect("encryptor creation failed");

            let small_data: Vec<u8> = (0..1000).map(|i| (i % 256) as u8).collect();
            encryptor.write(&small_data).expect("write small failed");

            let large_size = ENCRYPTION_CHUNK_SIZE * 2 + 500;
            let large_data: Vec<u8> = (0..large_size).map(|i| ((i + 1000) % 256) as u8).collect();
            encryptor.write(&large_data).expect("write large failed");

            encryptor.finish().expect("finish failed");
        }

        let total_plaintext_size = 1000 + ENCRYPTION_CHUNK_SIZE * 2 + 500;
        let reader = Cursor::new(&encrypted);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let decrypted = decryptor.read_to_end().expect("read_to_end failed");

        assert_eq!(decrypted.len(), total_plaintext_size);

        for (i, byte) in decrypted.iter().take(1000).enumerate() {
            assert_eq!(*byte, (i % 256) as u8, "Mismatch at small_data[{}]", i);
        }
        for (i, byte) in decrypted[1000..]
            .iter()
            .take(ENCRYPTION_CHUNK_SIZE * 2 + 500)
            .enumerate()
        {
            assert_eq!(
                *byte,
                ((i + 1000) % 256) as u8,
                "Mismatch at large_data[{}]",
                i
            );
        }
    }

    #[test]
    fn test_empty_streaming() {
        let key = test_key();

        let mut encrypted = Vec::new();
        {
            let encryptor =
                StreamingEncryptor::new(&key, &mut encrypted).expect("encryptor creation failed");
            encryptor.finish().expect("finish failed");
        }

        assert_eq!(encrypted.len(), Header::BYTES + ABYTES);

        let reader = Cursor::new(&encrypted);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let decrypted = decryptor.read_to_end().expect("read_to_end failed");

        assert!(decrypted.is_empty());
    }

    #[test]
    fn test_multi_chunk_roundtrip() {
        let key = test_key();
        let chunk_size = 1024;
        let num_chunks = 3;
        let plaintext: Vec<u8> = (0..(chunk_size * num_chunks + 500))
            .map(|i| (i % 256) as u8)
            .collect();

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();

        let mut ciphertext = Vec::new();
        let mut offset = 0;
        while offset < plaintext.len() {
            let end = std::cmp::min(offset + chunk_size, plaintext.len());
            let is_final = end == plaintext.len();
            let chunk_ct = encryptor
                .push(&plaintext[offset..end], is_final)
                .expect("push failed");
            ciphertext.extend_from_slice(&chunk_ct);
            offset = end;
        }

        let mut decryptor = Decryptor::new(&header, &key);
        let mut decrypted = Vec::new();
        let mut ct_offset = 0;

        loop {
            let chunk_end = std::cmp::min(ct_offset + chunk_size + ABYTES, ciphertext.len());
            let (chunk_pt, is_final) = decryptor
                .pull(&ciphertext[ct_offset..chunk_end])
                .expect("pull failed");
            decrypted.extend_from_slice(&chunk_pt);
            ct_offset = chunk_end;

            if is_final {
                break;
            }
        }

        decryptor.finish().expect("finish failed");
        assert_eq!(plaintext, decrypted);
    }

    #[test]
    fn test_tamper_detection_ciphertext() {
        let key = test_key();
        let plaintext = b"Secret message that should not be tampered with";

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let mut ciphertext = encryptor.push(plaintext, true).expect("push failed");

        let mid = ciphertext.len() / 2;
        ciphertext[mid] ^= 0x01;

        let mut decryptor = Decryptor::new(&header, &key);
        let result = decryptor.pull(&ciphertext);

        assert!(
            matches!(result, Err(Error::StreamPullFailed)),
            "Expected StreamPullFailed error on tampered ciphertext, got {:?}",
            result
        );
    }

    #[test]
    fn test_tamper_detection_header() {
        let key = test_key();
        let plaintext = b"Secret message";

        let mut encryptor = Encryptor::new(&key);
        let mut header_bytes = *encryptor.header().as_bytes();
        let ciphertext = encryptor.push(plaintext, true).expect("push failed");

        header_bytes[0] ^= 0x01;

        let mut decryptor = Decryptor::new(&Header::from_bytes(header_bytes), &key);
        let result = decryptor.pull(&ciphertext);

        assert!(
            matches!(result, Err(Error::StreamPullFailed)),
            "Expected StreamPullFailed error on tampered header, got {:?}",
            result
        );
    }

    #[test]
    fn test_tamper_detection_mac() {
        let key = test_key();
        let plaintext = b"Secret message";

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let mut ciphertext = encryptor.push(plaintext, true).expect("push failed");

        let last = ciphertext.len() - 1;
        ciphertext[last] ^= 0x01;

        let mut decryptor = Decryptor::new(&header, &key);
        let result = decryptor.pull(&ciphertext);

        assert!(
            matches!(result, Err(Error::StreamPullFailed)),
            "Expected StreamPullFailed error on tampered MAC, got {:?}",
            result
        );
    }

    #[test]
    fn test_wrong_key() {
        let key = test_key();
        let wrong_key = Key::from_bytes([0x43u8; Key::BYTES]);
        let plaintext = b"Secret message";

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let ciphertext = encryptor.push(plaintext, true).expect("push failed");

        let mut decryptor = Decryptor::new(&header, &wrong_key);
        let result = decryptor.pull(&ciphertext);

        assert!(
            matches!(result, Err(Error::StreamPullFailed)),
            "Expected StreamPullFailed error with wrong key, got {:?}",
            result
        );
    }

    #[test]
    fn test_constants_match_upstream() {
        assert_eq!(Header::BYTES, 24);
        assert_eq!(Key::BYTES, 32);
        assert_eq!(ABYTES, 17);
    }

    #[test]
    fn test_estimate_encrypted_size() {
        assert_eq!(estimate_encrypted_size(0), ABYTES);

        assert_eq!(estimate_encrypted_size(100), 100 + ABYTES);

        assert_eq!(
            estimate_encrypted_size(ENCRYPTION_CHUNK_SIZE),
            DECRYPTION_CHUNK_SIZE
        );

        let two_chunks_plus = ENCRYPTION_CHUNK_SIZE * 2 + 500;
        let expected = 2 * DECRYPTION_CHUNK_SIZE + 500 + ABYTES;
        assert_eq!(estimate_encrypted_size(two_chunks_plus), expected);
    }

    #[test]
    fn test_validate_sizes() {
        assert!(validate_sizes(0, ABYTES));
        assert!(validate_sizes(100, 100 + ABYTES));
        assert!(validate_sizes(ENCRYPTION_CHUNK_SIZE, DECRYPTION_CHUNK_SIZE));
        assert!(!validate_sizes(100, 100));
        assert!(!validate_sizes(100, 200));
    }

    #[test]
    fn test_ciphertext_too_short() {
        let key = test_key();
        let header = Header::from_bytes([0u8; Header::BYTES]);

        let mut decryptor = Decryptor::new(&header, &key);
        let result = decryptor.pull(&[0u8; ABYTES - 1]);

        assert!(
            matches!(result, Err(Error::StreamPullFailed)),
            "Expected StreamPullFailed for short ciphertext, got {:?}",
            result
        );
    }

    #[test]
    fn test_file_encrypt_decrypt_roundtrip() {
        let key = test_key();
        let plaintext: Vec<u8> = (0..10000).map(|i| (i % 256) as u8).collect();

        let mut encrypted = Vec::new();
        let mut reader = Cursor::new(&plaintext);
        let header = encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

        let mut decrypted = Vec::new();
        let mut enc_reader = Cursor::new(&encrypted);
        decrypt_file(&mut enc_reader, &mut decrypted, &header, &key).expect("decrypt_file failed");

        assert_eq!(plaintext, decrypted);
    }

    #[test]
    fn test_file_encrypt_decrypt_multi_chunk() {
        let key = test_key();

        let size = ENCRYPTION_CHUNK_SIZE * 2 + 1000;
        let plaintext: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();

        let mut encrypted = Vec::new();
        let mut reader = Cursor::new(&plaintext);
        let header = encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

        let expected_ct_size = 2 * DECRYPTION_CHUNK_SIZE + (1000 + ABYTES);
        assert_eq!(
            encrypted.len(),
            expected_ct_size,
            "Ciphertext size mismatch"
        );

        let mut decrypted = Vec::new();
        let mut enc_reader = Cursor::new(&encrypted);
        decrypt_file(&mut enc_reader, &mut decrypted, &header, &key).expect("decrypt_file failed");

        assert_eq!(plaintext.len(), decrypted.len());
        assert_eq!(plaintext, decrypted);
    }

    #[test]
    fn test_file_encrypt_decrypt_exact_chunk_boundary() {
        let key = test_key();

        let plaintext: Vec<u8> = (0..ENCRYPTION_CHUNK_SIZE)
            .map(|i| (i % 256) as u8)
            .collect();

        let mut encrypted = Vec::new();
        let mut reader = Cursor::new(&plaintext);
        let header = encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

        assert_eq!(encrypted.len(), DECRYPTION_CHUNK_SIZE);
        assert_eq!(encrypted.len(), estimate_encrypted_size(plaintext.len()));

        let mut decrypted = Vec::new();
        let mut enc_reader = Cursor::new(&encrypted);
        decrypt_file(&mut enc_reader, &mut decrypted, &header, &key).expect("decrypt_file failed");

        assert_eq!(plaintext, decrypted);
    }

    #[test]
    fn test_file_encrypt_decrypt_empty() {
        let key = test_key();
        let plaintext: Vec<u8> = Vec::new();

        let mut encrypted = Vec::new();
        let mut reader = Cursor::new(&plaintext);
        let header = encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

        assert_eq!(encrypted.len(), ABYTES);

        let mut decrypted = Vec::new();
        let mut enc_reader = Cursor::new(&encrypted);
        decrypt_file(&mut enc_reader, &mut decrypted, &header, &key).expect("decrypt_file failed");

        assert!(decrypted.is_empty());
    }

    #[test]
    fn test_decrypt_file_data() {
        let key = test_key();
        let plaintext = b"Test decrypt_file_data function";

        let mut encrypted = Vec::new();
        let mut reader = Cursor::new(plaintext.as_slice());
        let header = encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

        let decrypted =
            decrypt_file_data(&encrypted, &header, &key).expect("decrypt_file_data failed");
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_decrypt_file_truncation_empty_ciphertext() {
        let key = test_key();
        let header = Header::from_bytes([0u8; Header::BYTES]);
        let empty_ciphertext: &[u8] = &[];

        let mut reader = Cursor::new(empty_ciphertext);
        let mut output = Vec::new();
        let result = decrypt_file(&mut reader, &mut output, &header, &key);

        assert!(
            matches!(result, Err(Error::StreamTruncated)),
            "Expected StreamTruncated for empty ciphertext, got {:?}",
            result
        );
    }

    #[test]
    fn test_decrypt_file_truncation_at_chunk_boundary() {
        let key = test_key();
        let plaintext = b"Test message for truncation detection";

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let encrypted_chunk = encryptor.push(plaintext, false).expect("push failed");

        let mut reader = Cursor::new(&encrypted_chunk);
        let mut output = Vec::new();
        let result = decrypt_file(&mut reader, &mut output, &header, &key);

        assert!(
            matches!(result, Err(Error::StreamTruncated)),
            "Expected StreamTruncated at chunk boundary, got {:?}",
            result
        );
    }

    #[test]
    fn test_decrypt_file_truncation_via_encrypt_file() {
        let key = test_key();
        let plaintext = b"Test data that will be truncated";

        let mut encrypted = Vec::new();
        let mut reader = Cursor::new(plaintext.as_slice());
        let header = encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

        let truncated_len = encrypted.len() - 5;
        let truncated = &encrypted[..truncated_len];

        let mut reader = Cursor::new(truncated);
        let mut output = Vec::new();
        let result = decrypt_file(&mut reader, &mut output, &header, &key);

        assert!(
            result.is_err(),
            "Expected error from truncated ciphertext, got {:?}",
            result
        );
    }

    #[test]
    fn test_decrypt_file_valid_single_chunk() {
        let key = test_key();
        let plaintext = b"Valid single chunk";

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let ciphertext = encryptor.push(plaintext, true).expect("push failed");

        let mut reader = Cursor::new(&ciphertext);
        let mut output = Vec::new();
        decrypt_file(&mut reader, &mut output, &header, &key).expect("decrypt_file failed");

        assert_eq!(output, plaintext);
    }

    #[test]
    fn test_decrypt_file_rejects_trailing_data_after_exact_final_chunk() {
        let key = test_key();
        let plaintext = vec![0xA5; ENCRYPTION_CHUNK_SIZE];

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let mut ciphertext = encryptor.push(&plaintext, true).expect("push failed");
        ciphertext.extend_from_slice(b"TRAILING");

        let mut reader = Cursor::new(&ciphertext);
        let mut output = Vec::new();
        let result = decrypt_file(&mut reader, &mut output, &header, &key);

        assert!(
            matches!(result, Err(Error::StreamTrailingData)),
            "Expected StreamTrailingData for trailing bytes after FINAL, got {:?}",
            result
        );
    }

    #[test]
    fn test_decrypt_file_via_encrypt_file_roundtrip() {
        let key = test_key();
        let plaintext: Vec<u8> = (0..5000).map(|i| (i % 256) as u8).collect();

        let mut encrypted = Vec::new();
        let mut reader = Cursor::new(&plaintext);
        let header = encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

        let mut reader = Cursor::new(&encrypted);
        let mut output = Vec::new();
        decrypt_file(&mut reader, &mut output, &header, &key).expect("decrypt_file failed");

        assert_eq!(plaintext, output);
    }

    #[test]
    fn test_decrypt_file_data_truncation() {
        let key = test_key();
        let plaintext = b"Test decrypt_file_data truncation";

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let encrypted_chunk = encryptor.push(plaintext, false).expect("push failed");

        let result = decrypt_file_data(&encrypted_chunk, &header, &key);

        assert!(
            matches!(result, Err(Error::StreamTruncated)),
            "Expected StreamTruncated from decrypt_file_data, got {:?}",
            result
        );
    }

    #[test]
    fn test_decrypt_file_data_rejects_trailing_data_after_exact_final_chunk() {
        let key = test_key();
        let plaintext = vec![0x5A; ENCRYPTION_CHUNK_SIZE];

        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let mut ciphertext = encryptor.push(&plaintext, true).expect("push failed");
        ciphertext.extend_from_slice(b"TRAILING");

        let result = decrypt_file_data(&ciphertext, &header, &key);

        assert!(
            matches!(result, Err(Error::StreamTrailingData)),
            "Expected StreamTrailingData from decrypt_file_data, got {:?}",
            result
        );
    }

    #[test]
    fn test_streaming_decryptor_rejects_trailing_data_after_exact_final_chunk() {
        let key = test_key();
        let plaintext = vec![0x3C; ENCRYPTION_CHUNK_SIZE];

        let mut encryptor = Encryptor::new(&key);
        let mut encrypted = encryptor.header().as_bytes().to_vec();
        let mut ciphertext = encryptor.push(&plaintext, true).expect("push failed");
        ciphertext.extend_from_slice(b"TRAILING");
        encrypted.extend_from_slice(&ciphertext);

        let reader = Cursor::new(&encrypted);
        let mut decryptor =
            StreamingDecryptor::new(&key, reader).expect("decryptor creation failed");
        let result = decryptor.read_to_end();

        assert!(
            matches!(result, Err(Error::StreamTrailingData)),
            "Expected StreamTrailingData from StreamingDecryptor, got {:?}",
            result
        );
    }

    #[test]
    fn test_encrypt_file_size_matches_estimate() {
        let key = test_key();

        for size in [
            0usize,
            1000,
            ENCRYPTION_CHUNK_SIZE,
            ENCRYPTION_CHUNK_SIZE * 2,
        ] {
            let plaintext: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();

            let mut encrypted = Vec::new();
            let mut reader = Cursor::new(&plaintext);
            encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

            let expected = estimate_encrypted_size(plaintext.len());
            assert_eq!(
                encrypted.len(),
                expected,
                "size={}: encrypt_file output {} != estimate {}",
                size,
                encrypted.len(),
                expected
            );
        }
    }

    #[test]
    fn test_encrypt_file_and_streaming_encryptor_same_size() {
        let key = test_key();

        for multiplier in [0, 1, 2, 3] {
            let extra = [0, 1, 100, ENCRYPTION_CHUNK_SIZE / 2];
            for &e in &extra {
                let size = ENCRYPTION_CHUNK_SIZE * multiplier + e;
                if size > ENCRYPTION_CHUNK_SIZE * 3 {
                    continue;
                }
                let plaintext: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();

                let mut enc_file = Vec::new();
                let mut reader = Cursor::new(&plaintext);
                encrypt_file(&mut reader, &mut enc_file, &key).expect("encrypt_file failed");

                let mut enc_stream = Vec::new();
                {
                    let mut encryptor =
                        StreamingEncryptor::new(&key, &mut enc_stream).expect("encryptor failed");
                    encryptor.write(&plaintext).expect("write failed");
                    encryptor.finish().expect("finish failed");
                }
                let stream_ciphertext_len = enc_stream.len() - Header::BYTES;

                let expected = estimate_encrypted_size(size);

                assert_eq!(
                    enc_file.len(),
                    expected,
                    "encrypt_file: size={}, output {} != estimate {}",
                    size,
                    enc_file.len(),
                    expected
                );

                assert_eq!(
                    stream_ciphertext_len, expected,
                    "StreamingEncryptor: size={}, output {} != estimate {}",
                    size, stream_ciphertext_len, expected
                );
            }
        }
    }

    #[test]
    fn test_validate_sizes_with_encrypt_file() {
        let key = test_key();

        for size in [0, 100, ENCRYPTION_CHUNK_SIZE, ENCRYPTION_CHUNK_SIZE + 500] {
            let plaintext: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();

            let mut encrypted = Vec::new();
            let mut reader = Cursor::new(&plaintext);
            encrypt_file(&mut reader, &mut encrypted, &key).expect("encrypt_file failed");

            assert!(
                validate_sizes(plaintext.len(), encrypted.len()),
                "validate_sizes failed for size {}",
                size
            );
        }
    }
}
