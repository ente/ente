use std::collections::TryReserveError;
use std::fs::File;
use std::io::{BufReader, ErrorKind, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use super::arena::{MAX_KEY_BYTES, validate_key};
use super::cipher::{Cipher, NONCE_LEN, TAG_LEN};
use super::crc::{Crc32, crc32};
use super::kernel::{
    StoredVector, VectorPayload, is_within_quantized_range, splitmix64, validate_dims,
    validate_dims_up_to,
};
use super::{AttrValue, Attribute, EncryptionMismatch, StorageKind, VecDbError};

pub(crate) const HEADER_LEN: usize = 32;
const MAGIC: [u8; 4] = *b"EVDB";
const SEALED_MAGIC: [u8; 4] = *b"EVDE";
const HEADER_FIELDS_LEN: usize = 28;
const HEADER_CRC_LEN: usize = 4;
pub(crate) const SEALED_HEADER_LEN: usize =
    HEADER_FIELDS_LEN + NONCE_LEN + TAG_LEN + HEADER_CRC_LEN;
const FORMAT_VERSION: u16 = 1;
const STORAGE_TAG_OFFSET: usize = 6;
const METRIC_TAG_OFFSET: usize = 7;
const COSINE_METRIC_TAG: u8 = 1;
const RECORD_TYPE_ADD: u8 = 1;
const RECORD_TYPE_TOMBSTONE: u8 = 2;
const RECORD_PREFIX_LEN: usize = 3;
const RECORD_CRC_LEN: usize = 4;
const MIN_RECORD_LEN: usize = RECORD_PREFIX_LEN + 1 + RECORD_CRC_LEN;
const FRAME_LEN_BYTES: usize = 4;
const FRAME_PREFIX_LEN: usize = FRAME_LEN_BYTES + NONCE_LEN;
const FRAME_OVERHEAD: usize = FRAME_PREFIX_LEN + TAG_LEN;
pub(crate) const ENCODE_FLUSH_BYTES: usize = 64 * 1024;
const MAX_ATTR_COUNT: usize = 16;
const MAX_ATTR_NAME_BYTES: usize = 64;
const MAX_ATTR_STR_BYTES: usize = 1024;
const MAX_ATTRS_TOTAL_BYTES: usize = 4096;
const ATTR_TAG_STR: u8 = 0;
const ATTR_TAG_BOOL: u8 = 1;
const ATTR_TAG_I64: u8 = 2;
const ATTR_TAG_F64: u8 = 3;
const TAIL_PROBE_STEP_BYTES: usize = 4 * 1024 * 1024;

static GENERATION_COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Copy)]
pub(crate) enum LogEntry<'a> {
    Add {
        key: &'a str,
        vector: VectorPayload<'a>,
        attrs: &'a [Attribute],
    },
    Tombstone {
        key: &'a str,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum LogRecord {
    Add {
        key: String,
        vector: StoredVector,
        attrs: Vec<Attribute>,
    },
    Tombstone {
        key: String,
    },
}

#[derive(Debug)]
pub(crate) struct Log {
    file: File,
    path: PathBuf,
    dims: usize,
    storage: StorageKind,
    generation: [u8; 16],
    end_offset: u64,
    encode_buffer: Vec<u8>,
    rollback_pending: bool,
    cipher: Option<Cipher>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct LogCheckpoint {
    generation: [u8; 16],
    end_offset: u64,
}

pub(crate) fn open_writer_file(path: &Path, create_new: bool) -> Result<File, VecDbError> {
    let mut options = File::options();
    options.read(true).write(true).create_new(create_new);
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;

        const FILE_SHARE_READ: u32 = 0x00000001;
        const FILE_SHARE_DELETE: u32 = 0x00000004;
        options.share_mode(FILE_SHARE_READ | FILE_SHARE_DELETE);
    }
    let file = options
        .open(path)
        .map_err(|source| writer_open_error(path, source))?;
    #[cfg(unix)]
    {
        use std::fs::TryLockError;

        match file.try_lock() {
            Ok(()) => {}
            Err(TryLockError::WouldBlock) => return Err(VecDbError::Locked(path.to_path_buf())),
            Err(TryLockError::Error(source)) => return Err(VecDbError::io(path, source)),
        }
    }
    Ok(file)
}

fn writer_open_error(path: &Path, source: std::io::Error) -> VecDbError {
    #[cfg(windows)]
    if source.raw_os_error() == Some(32) {
        return VecDbError::Locked(path.to_path_buf());
    }
    VecDbError::io(path, source)
}

impl Log {
    pub(crate) fn create(
        path: &Path,
        dims: usize,
        storage: StorageKind,
        cipher: Option<&Cipher>,
    ) -> Result<Self, VecDbError> {
        validate_log_dims(dims, storage, cipher)?;
        let file = open_writer_file(path, true)?;
        Self::initialize(file, path, dims, storage, cipher)
    }

    pub(crate) fn open(
        mut file: File,
        path: &Path,
        expected_dims: usize,
        requested: StorageKind,
        cipher: Option<&Cipher>,
    ) -> Result<Self, VecDbError> {
        let file_len = file
            .metadata()
            .map_err(|source| VecDbError::io(path, source))?
            .len();
        if !header_is_complete(&mut file, path, file_len, cipher)? {
            log::warn!(
                "reinitializing {} whose {file_len}-byte header was never completed",
                path.display()
            );
            validate_log_dims(expected_dims, requested, cipher)?;
            return Self::initialize(file, path, expected_dims, requested, cipher);
        }
        file.seek(SeekFrom::Start(0))
            .map_err(|source| VecDbError::io(path, source))?;
        let Header {
            generation,
            dims,
            storage,
        } = match cipher {
            None => {
                let mut header = [0u8; HEADER_LEN];
                file.read_exact(&mut header)
                    .map_err(|source| VecDbError::io(path, source))?;
                decode_header(&header)?
            }
            Some(cipher) => {
                let mut header = [0u8; SEALED_HEADER_LEN];
                file.read_exact(&mut header)
                    .map_err(|source| VecDbError::io(path, source))?;
                decode_sealed_header(&header, path, cipher)?
            }
        };
        if requested != storage {
            return Err(VecDbError::StorageMismatch {
                expected: requested,
                actual: storage,
            });
        }
        if dims != expected_dims {
            return Err(VecDbError::DimensionMismatch {
                expected: expected_dims,
                actual: dims,
            });
        }
        validate_log_dims(expected_dims, storage, cipher)?;
        Ok(Self {
            file,
            path: path.to_path_buf(),
            dims: expected_dims,
            storage,
            generation,
            end_offset: file_len,
            encode_buffer: Vec::new(),
            rollback_pending: false,
            cipher: cipher.cloned(),
        })
    }

    fn initialize(
        mut file: File,
        path: &Path,
        dims: usize,
        storage: StorageKind,
        cipher: Option<&Cipher>,
    ) -> Result<Self, VecDbError> {
        let (generation, header) = match cipher {
            None => {
                let generation = fresh_generation();
                (
                    generation,
                    encode_header(dims as u32, &generation, storage).to_vec(),
                )
            }
            Some(cipher) => {
                let generation = random_generation();
                let header = encode_sealed_header(dims as u32, &generation, storage, cipher)
                    .map_err(|error| VecDbError::io(path, std::io::Error::other(error)))?;
                (generation, header.to_vec())
            }
        };
        file.seek(SeekFrom::Start(0))
            .map_err(|source| VecDbError::io(path, source))?;
        file.write_all(&header)
            .map_err(|source| VecDbError::io(path, source))?;
        file.sync_all()
            .map_err(|source| VecDbError::io(path, source))?;
        sync_parent_dir(path)?;
        Ok(Self {
            file,
            path: path.to_path_buf(),
            dims,
            storage,
            generation,
            end_offset: header.len() as u64,
            encode_buffer: Vec::new(),
            rollback_pending: false,
            cipher: cipher.cloned(),
        })
    }

    pub(crate) fn create_temp_sibling(
        path: &Path,
        dims: usize,
        storage: StorageKind,
        cipher: Option<&Cipher>,
    ) -> Result<(Self, PathBuf), VecDbError> {
        remove_stale_temp_sibling(path)?;
        let temp_path = temp_sibling_path(path);
        let log = Self::create(&temp_path, dims, storage, cipher)?;
        Ok((log, temp_path))
    }

    pub(crate) fn scan(&mut self) -> Result<LogScanner<'_>, VecDbError> {
        let header_len = self.header_len();
        self.file
            .seek(SeekFrom::Start(header_len))
            .map_err(|source| VecDbError::io(&self.path, source))?;
        Ok(LogScanner {
            reader: BufReader::new(&mut self.file),
            path: &self.path,
            dims: self.dims,
            storage: self.storage,
            generation: self.generation,
            cipher: self.cipher.as_ref(),
            log_end: self.end_offset,
            offset: header_len,
            scratch: Vec::new(),
            done: false,
        })
    }

    pub(crate) fn append(&mut self, entries: &[LogEntry<'_>]) -> Result<(), VecDbError> {
        self.append_records(entries, true)
    }

    pub(crate) fn append_unsynced_for_staging(
        &mut self,
        entries: &[LogEntry<'_>],
    ) -> Result<(), VecDbError> {
        self.append_records(entries, false)
    }

    fn append_records(&mut self, entries: &[LogEntry<'_>], sync: bool) -> Result<(), VecDbError> {
        if entries.is_empty() {
            return Ok(());
        }
        for entry in entries {
            validate_entry(entry, self.dims, self.storage)?;
        }
        if self.rollback_pending {
            self.discard_unacked_tail()?;
            self.rollback_pending = false;
        }
        match self.write_records(entries, sync) {
            Ok(written) => {
                self.end_offset += written;
                Ok(())
            }
            Err(error) => {
                if let Err(rollback_error) = self.discard_unacked_tail() {
                    log::warn!(
                        "failed to discard the unacked tail of {} after a write failure, deferring the rollback: {rollback_error}",
                        self.path.display()
                    );
                    self.rollback_pending = true;
                }
                Err(error)
            }
        }
    }

    fn write_records(&mut self, entries: &[LogEntry<'_>], sync: bool) -> Result<u64, VecDbError> {
        self.file
            .seek(SeekFrom::Start(self.end_offset))
            .map_err(|source| VecDbError::io(&self.path, source))?;
        self.encode_buffer.clear();
        let mut written = 0u64;
        for entry in entries {
            match &self.cipher {
                None => encode_record_into(&mut self.encode_buffer, entry),
                Some(cipher) => {
                    let frame_offset = self.end_offset + written + self.encode_buffer.len() as u64;
                    encode_sealed_record_into(
                        &mut self.encode_buffer,
                        entry,
                        cipher,
                        &frame_additional_data(&self.generation, frame_offset),
                    )?;
                }
            }
            if self.encode_buffer.len() >= ENCODE_FLUSH_BYTES {
                written += self.drain_encode_buffer()?;
            }
        }
        written += self.drain_encode_buffer()?;
        if sync {
            self.file
                .sync_all()
                .map_err(|source| VecDbError::io(&self.path, source))?;
        }
        Ok(written)
    }

    fn discard_unacked_tail(&mut self) -> Result<(), VecDbError> {
        self.file
            .set_len(self.end_offset)
            .map_err(|source| VecDbError::io(&self.path, source))?;
        self.file
            .sync_all()
            .map_err(|source| VecDbError::io(&self.path, source))?;
        Ok(())
    }

    fn drain_encode_buffer(&mut self) -> Result<u64, VecDbError> {
        if self.encode_buffer.is_empty() {
            return Ok(0);
        }
        self.file
            .write_all(&self.encode_buffer)
            .map_err(|source| VecDbError::io(&self.path, source))?;
        let written = self.encode_buffer.len() as u64;
        self.encode_buffer.clear();
        Ok(written)
    }

    pub(crate) fn truncate_to(&mut self, offset: u64) -> Result<(), VecDbError> {
        let target = offset.max(self.header_len());
        if target >= self.end_offset {
            return Ok(());
        }
        log::warn!(
            "truncating torn tail of {} from {} to {target} bytes",
            self.path.display(),
            self.end_offset
        );
        self.file
            .set_len(target)
            .map_err(|source| VecDbError::io(&self.path, source))?;
        self.end_offset = target;
        self.file
            .sync_all()
            .map_err(|source| VecDbError::io(&self.path, source))?;
        Ok(())
    }

    pub(crate) fn tail_contains_valid_record(&mut self, after: u64) -> Result<bool, VecDbError> {
        self.tail_contains_valid_record_windowed(after, TAIL_PROBE_STEP_BYTES)
    }

    fn tail_contains_valid_record_windowed(
        &mut self,
        after: u64,
        step_bytes: usize,
    ) -> Result<bool, VecDbError> {
        let start = after + 1;
        if start >= self.end_offset {
            return Ok(false);
        }
        let tail_len = self.end_offset - start;
        let step = step_bytes.max(1);
        let max_frame_len = match self.cipher {
            None => max_record_len(self.storage, self.dims),
            Some(_) => max_sealed_frame_len(self.storage, self.dims),
        };
        let overlap = max_frame_len.saturating_sub(1);
        let window_len = (step.saturating_add(overlap) as u64).min(tail_len) as usize;
        let mut window = zeroed_buffer(window_len).map_err(|_| out_of_memory(&self.path))?;
        let mut sealed = Vec::new();
        let mut base = 0u64;
        loop {
            let len = (window.len() as u64).min(tail_len - base) as usize;
            self.file
                .seek(SeekFrom::Start(start + base))
                .map_err(|source| VecDbError::io(&self.path, source))?;
            self.file
                .read_exact(&mut window[..len])
                .map_err(|source| VecDbError::io(&self.path, source))?;
            let reaches_end = base + len as u64 == tail_len;
            let probe_end = if reaches_end { len } else { step.min(len) };
            for offset in 0..probe_end {
                let valid = match &self.cipher {
                    None => valid_record_at(&window[offset..len], self.storage, self.dims),
                    Some(cipher) => valid_sealed_frame_at(
                        &window[offset..len],
                        &frame_additional_data(&self.generation, start + base + offset as u64),
                        cipher,
                        self.storage,
                        self.dims,
                        &mut sealed,
                    )
                    .map_err(|_| out_of_memory(&self.path))?,
                };
                if valid {
                    return Ok(true);
                }
            }
            if reaches_end {
                return Ok(false);
            }
            base += step as u64;
        }
    }

    pub(crate) fn current_end_offset(&self) -> u64 {
        self.end_offset
    }

    pub(crate) fn checkpoint(&self) -> LogCheckpoint {
        LogCheckpoint {
            generation: self.generation,
            end_offset: self.end_offset,
        }
    }

    pub(crate) fn extend_end_offset_to(&mut self, target: u64) -> Result<(), VecDbError> {
        let file_len = self
            .file
            .metadata()
            .map_err(|source| VecDbError::io(&self.path, source))?
            .len();
        self.end_offset = self.end_offset.max(target.min(file_len));
        Ok(())
    }

    pub(crate) fn generation(&self) -> [u8; 16] {
        self.generation
    }

    pub(crate) fn storage(&self) -> StorageKind {
        self.storage
    }

    pub(crate) fn cipher(&self) -> Option<&Cipher> {
        self.cipher.as_ref()
    }

    pub(crate) fn header_len(&self) -> u64 {
        header_len(self.cipher.as_ref()) as u64
    }

    pub(crate) fn record_overhead(&self) -> u64 {
        match self.cipher {
            None => 0,
            Some(_) => FRAME_OVERHEAD as u64,
        }
    }

    pub(crate) fn path(&self) -> &Path {
        &self.path
    }

    pub(crate) fn sync_all(&self) -> Result<(), VecDbError> {
        self.file
            .sync_all()
            .map_err(|source| VecDbError::io(&self.path, source))
    }
}

#[cfg(unix)]
impl Drop for Log {
    fn drop(&mut self) {
        _ = self.file.unlock();
    }
}

pub(crate) struct LogScanner<'a> {
    reader: BufReader<&'a mut File>,
    path: &'a Path,
    dims: usize,
    storage: StorageKind,
    generation: [u8; 16],
    cipher: Option<&'a Cipher>,
    log_end: u64,
    offset: u64,
    scratch: Vec<u8>,
    done: bool,
}

impl LogScanner<'_> {
    pub(crate) fn next_record(&mut self) -> Result<Option<(LogRecord, u64)>, VecDbError> {
        if self.done {
            return Ok(None);
        }
        let start = self.offset;
        let remaining = self.log_end - start;
        if remaining == 0 {
            self.done = true;
            return Ok(None);
        }
        let read = match self.cipher {
            None => self.read_record(remaining)?,
            Some(cipher) => self.read_sealed_record(start, remaining, cipher)?,
        };
        let Some((record, len)) = read else {
            return Ok(self.stop());
        };
        self.offset = start + len;
        Ok(Some((record, start)))
    }

    fn read_record(&mut self, remaining: u64) -> Result<Option<(LogRecord, u64)>, VecDbError> {
        if remaining < (RECORD_PREFIX_LEN + RECORD_CRC_LEN) as u64 {
            return Ok(None);
        }
        let mut prefix = [0u8; RECORD_PREFIX_LEN];
        if !self.fill(&mut prefix)? {
            return Ok(None);
        }
        let record_type = prefix[0];
        let key_len = u16::from_le_bytes([prefix[1], prefix[2]]) as usize;
        if key_len == 0 || key_len > MAX_KEY_BYTES {
            return Ok(None);
        }
        let fixed_len = match record_type {
            RECORD_TYPE_ADD => key_len + vector_payload_len(self.storage, self.dims) + 1,
            RECORD_TYPE_TOMBSTONE => key_len,
            _ => return Ok(None),
        };
        let body_budget = remaining - (RECORD_PREFIX_LEN + RECORD_CRC_LEN) as u64;
        self.scratch.clear();
        if fixed_len as u64 > body_budget || !self.fill_scratch(fixed_len)? {
            return Ok(None);
        }
        if record_type == RECORD_TYPE_ADD && !self.read_attr_bytes(body_budget)? {
            return Ok(None);
        }
        let mut crc_bytes = [0u8; RECORD_CRC_LEN];
        if !self.fill(&mut crc_bytes)? {
            return Ok(None);
        }
        let mut hasher = Crc32::new();
        hasher.update(&prefix);
        hasher.update(&self.scratch);
        if hasher.finalize() != u32::from_le_bytes(crc_bytes) {
            return Ok(None);
        }
        let len = (RECORD_PREFIX_LEN + self.scratch.len() + RECORD_CRC_LEN) as u64;
        Ok(
            decode_body(record_type, key_len, self.storage, self.dims, &self.scratch)
                .map(|record| (record, len)),
        )
    }

    fn read_sealed_record(
        &mut self,
        start: u64,
        remaining: u64,
        cipher: &Cipher,
    ) -> Result<Option<(LogRecord, u64)>, VecDbError> {
        let mut prefix = [0u8; FRAME_PREFIX_LEN];
        if remaining < FRAME_PREFIX_LEN as u64 || !self.fill(&mut prefix)? {
            return Ok(None);
        }
        let len_bytes = [prefix[0], prefix[1], prefix[2], prefix[3]];
        let Some(frame_len) = plausible_frame_len(len_bytes, self.storage, self.dims) else {
            return Ok(None);
        };
        if frame_len as u64 > remaining {
            return Ok(None);
        }
        let sealed_len = frame_len - FRAME_PREFIX_LEN;
        self.scratch.clear();
        if !self.fill_scratch(sealed_len)? {
            return Ok(None);
        }
        let (record, tag) = self.scratch.split_at_mut(sealed_len - TAG_LEN);
        let additional_data = frame_additional_data(&self.generation, start);
        if !cipher.open(record, &additional_data, &prefix[FRAME_LEN_BYTES..], tag) {
            return Ok(None);
        }
        Ok(decode_record(record, self.storage, self.dims).map(|record| (record, frame_len as u64)))
    }

    pub(crate) fn recoverable_end(&self) -> u64 {
        self.offset
    }

    fn stop(&mut self) -> Option<(LogRecord, u64)> {
        self.done = true;
        None
    }

    fn read_attr_bytes(&mut self, body_budget: u64) -> Result<bool, VecDbError> {
        #[expect(
            clippy::expect_used,
            reason = "The add-record header includes an attribute count byte"
        )]
        let attr_count = *self
            .scratch
            .last()
            .expect("add record includes an attribute count");
        if attr_count as usize > MAX_ATTR_COUNT {
            return Ok(false);
        }
        let attrs_start = self.scratch.len();
        for _ in 0..attr_count {
            if !self.extend_within(body_budget, 1)? {
                return Ok(false);
            }
            #[expect(
                clippy::expect_used,
                reason = "extend_within just appended the name length byte"
            )]
            let name_len = *self.scratch.last().expect("attribute name length was read") as usize;
            if name_len == 0 || name_len > MAX_ATTR_NAME_BYTES {
                return Ok(false);
            }
            if !self.extend_within(body_budget, name_len + 1)? {
                return Ok(false);
            }
            #[expect(
                clippy::expect_used,
                reason = "extend_within just appended the value tag byte"
            )]
            let value_len = match *self.scratch.last().expect("attribute value tag was read") {
                ATTR_TAG_STR => {
                    if !self.extend_within(body_budget, 2)? {
                        return Ok(false);
                    }
                    let len_start = self.scratch.len() - 2;
                    let str_len =
                        u16::from_le_bytes([self.scratch[len_start], self.scratch[len_start + 1]])
                            as usize;
                    if str_len > MAX_ATTR_STR_BYTES {
                        return Ok(false);
                    }
                    str_len
                }
                ATTR_TAG_BOOL => 1,
                ATTR_TAG_I64 | ATTR_TAG_F64 => 8,
                _ => return Ok(false),
            };
            if !self.extend_within(body_budget, value_len)? {
                return Ok(false);
            }
            if self.scratch.len() - attrs_start > MAX_ATTRS_TOTAL_BYTES {
                return Ok(false);
            }
        }
        Ok(true)
    }

    fn extend_within(&mut self, body_budget: u64, len: usize) -> Result<bool, VecDbError> {
        if (self.scratch.len() + len) as u64 > body_budget {
            return Ok(false);
        }
        self.fill_scratch(len)
    }

    fn fill_scratch(&mut self, len: usize) -> Result<bool, VecDbError> {
        if self.scratch.try_reserve(len).is_err() {
            self.done = true;
            return Err(out_of_memory(self.path));
        }
        let old_len = self.scratch.len();
        self.scratch.resize(old_len + len, 0);
        match self.reader.read_exact(&mut self.scratch[old_len..]) {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == ErrorKind::UnexpectedEof => {
                self.scratch.truncate(old_len);
                Ok(false)
            }
            Err(source) => {
                self.done = true;
                Err(VecDbError::io(self.path, source))
            }
        }
    }

    fn fill(&mut self, buffer: &mut [u8]) -> Result<bool, VecDbError> {
        match self.reader.read_exact(buffer) {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == ErrorKind::UnexpectedEof => Ok(false),
            Err(source) => {
                self.done = true;
                Err(VecDbError::io(self.path, source))
            }
        }
    }
}

fn vector_payload_len(storage: StorageKind, dims: usize) -> usize {
    match storage {
        StorageKind::F32 => dims.saturating_mul(size_of::<f32>()),
        StorageKind::I8 => dims.saturating_add(size_of::<f32>()),
    }
}

fn decode_body(
    record_type: u8,
    key_len: usize,
    storage: StorageKind,
    dims: usize,
    body: &[u8],
) -> Option<LogRecord> {
    let (key_bytes, rest) = body.split_at(key_len);
    let key = std::str::from_utf8(key_bytes).ok()?.to_string();
    if record_type == RECORD_TYPE_TOMBSTONE {
        return Some(LogRecord::Tombstone { key });
    }
    let (payload, attr_bytes) = rest.split_at(vector_payload_len(storage, dims));
    let vector = decode_vector(storage, payload)?;
    let attrs = decode_attrs(attr_bytes)?;
    Some(LogRecord::Add { key, vector, attrs })
}

fn decode_vector(storage: StorageKind, payload: &[u8]) -> Option<StoredVector> {
    match storage {
        StorageKind::F32 => Some(StoredVector::F32(
            payload
                .as_chunks::<4>()
                .0
                .iter()
                .map(|bytes| f32::from_le_bytes(*bytes))
                .collect(),
        )),
        StorageKind::I8 => {
            let (scale_bytes, values) = payload.split_at(size_of::<f32>());
            let values: Vec<i8> = values
                .iter()
                .map(|&byte| i8::from_le_bytes([byte]))
                .collect();
            if !values.iter().all(|&value| is_within_quantized_range(value)) {
                return None;
            }
            Some(StoredVector::I8 {
                scale: f32::from_le_bytes([
                    scale_bytes[0],
                    scale_bytes[1],
                    scale_bytes[2],
                    scale_bytes[3],
                ]),
                values,
            })
        }
    }
}

fn decode_attrs(bytes: &[u8]) -> Option<Vec<Attribute>> {
    let (&count, mut rest) = bytes.split_first()?;
    let mut attrs = Vec::with_capacity(count as usize);
    for _ in 0..count {
        let (&name_len, after) = rest.split_first()?;
        let (name_bytes, after) = after.split_at_checked(name_len as usize)?;
        let name = std::str::from_utf8(name_bytes).ok()?.to_string();
        let (&tag, after) = after.split_first()?;
        let (value, after) = match tag {
            ATTR_TAG_STR => {
                let (len_bytes, after) = after.split_at_checked(2)?;
                let str_len = u16::from_le_bytes([len_bytes[0], len_bytes[1]]) as usize;
                let (value_bytes, after) = after.split_at_checked(str_len)?;
                let value = std::str::from_utf8(value_bytes).ok()?.to_string();
                (AttrValue::Str(value), after)
            }
            ATTR_TAG_BOOL => {
                let (&value, after) = after.split_first()?;
                if value > 1 {
                    return None;
                }
                (AttrValue::Bool(value == 1), after)
            }
            ATTR_TAG_I64 => {
                let (value_bytes, after) = after.split_at_checked(8)?;
                (
                    AttrValue::I64(i64::from_le_bytes(value_bytes.try_into().ok()?)),
                    after,
                )
            }
            ATTR_TAG_F64 => {
                let (value_bytes, after) = after.split_at_checked(8)?;
                (
                    AttrValue::F64(f64::from_le_bytes(value_bytes.try_into().ok()?)),
                    after,
                )
            }
            _ => return None,
        };
        attrs.push(Attribute { name, value });
        rest = after;
    }
    rest.is_empty().then_some(attrs)
}

fn max_record_len(storage: StorageKind, dims: usize) -> usize {
    vector_payload_len(storage, dims).saturating_add(
        RECORD_PREFIX_LEN + MAX_KEY_BYTES + 1 + MAX_ATTRS_TOTAL_BYTES + RECORD_CRC_LEN,
    )
}

fn max_sealed_frame_len(storage: StorageKind, dims: usize) -> usize {
    max_record_len(storage, dims).saturating_add(FRAME_OVERHEAD)
}

fn plausible_frame_len(
    len_bytes: [u8; FRAME_LEN_BYTES],
    storage: StorageKind,
    dims: usize,
) -> Option<usize> {
    let sealed_len = usize::try_from(u32::from_le_bytes(len_bytes)).ok()?;
    let max_sealed_len = max_record_len(storage, dims).saturating_add(TAG_LEN);
    if !(MIN_RECORD_LEN + TAG_LEN..=max_sealed_len).contains(&sealed_len) {
        return None;
    }
    FRAME_PREFIX_LEN.checked_add(sealed_len)
}

fn frame_additional_data(generation: &[u8; 16], frame_offset: u64) -> [u8; 24] {
    let mut additional_data = [0u8; 24];
    additional_data[..16].copy_from_slice(generation);
    additional_data[16..].copy_from_slice(&frame_offset.to_le_bytes());
    additional_data
}

fn valid_record_at(bytes: &[u8], storage: StorageKind, dims: usize) -> bool {
    plausible_record_len(bytes, storage, dims)
        .is_some_and(|record_len| record_crc_matches(&bytes[..record_len]))
}

fn valid_sealed_frame_at(
    bytes: &[u8],
    additional_data: &[u8],
    cipher: &Cipher,
    storage: StorageKind,
    dims: usize,
    scratch: &mut Vec<u8>,
) -> Result<bool, TryReserveError> {
    let Some(frame) = bytes
        .first_chunk::<FRAME_LEN_BYTES>()
        .and_then(|&len_bytes| plausible_frame_len(len_bytes, storage, dims))
        .and_then(|frame_len| bytes.get(..frame_len))
    else {
        return Ok(false);
    };
    let sealed = &frame[FRAME_PREFIX_LEN..];
    scratch.clear();
    scratch.try_reserve(sealed.len())?;
    scratch.extend_from_slice(sealed);
    let (record, tag) = scratch.split_at_mut(sealed.len() - TAG_LEN);
    Ok(cipher.open(
        record,
        additional_data,
        &frame[FRAME_LEN_BYTES..FRAME_PREFIX_LEN],
        tag,
    ))
}

fn zeroed_buffer(len: usize) -> Result<Vec<u8>, TryReserveError> {
    let mut buffer = Vec::new();
    buffer.try_reserve_exact(len)?;
    buffer.resize(len, 0);
    Ok(buffer)
}

fn out_of_memory(path: &Path) -> VecDbError {
    VecDbError::io(path, std::io::Error::from(ErrorKind::OutOfMemory))
}

fn record_crc_matches(record: &[u8]) -> bool {
    let (body, crc) = record.split_at(record.len() - RECORD_CRC_LEN);
    crc32(body).to_le_bytes() == crc
}

fn decode_record(bytes: &[u8], storage: StorageKind, dims: usize) -> Option<LogRecord> {
    if plausible_record_len(bytes, storage, dims)? != bytes.len() || !record_crc_matches(bytes) {
        return None;
    }
    let key_len = u16::from_le_bytes([bytes[1], bytes[2]]) as usize;
    decode_body(
        bytes[0],
        key_len,
        storage,
        dims,
        &bytes[RECORD_PREFIX_LEN..bytes.len() - RECORD_CRC_LEN],
    )
}

fn plausible_record_len(bytes: &[u8], storage: StorageKind, dims: usize) -> Option<usize> {
    if bytes.len() < RECORD_PREFIX_LEN + RECORD_CRC_LEN {
        return None;
    }
    let key_len = u16::from_le_bytes([bytes[1], bytes[2]]) as usize;
    if key_len == 0 || key_len > MAX_KEY_BYTES {
        return None;
    }
    let body_len = match bytes[0] {
        RECORD_TYPE_ADD => {
            let fixed = key_len + vector_payload_len(storage, dims);
            fixed + plausible_attrs_len(bytes.get(RECORD_PREFIX_LEN + fixed..)?)?
        }
        RECORD_TYPE_TOMBSTONE => key_len,
        _ => return None,
    };
    let total = RECORD_PREFIX_LEN + body_len + RECORD_CRC_LEN;
    (bytes.len() >= total).then_some(total)
}

fn plausible_attrs_len(bytes: &[u8]) -> Option<usize> {
    let (&count, mut rest) = bytes.split_first()?;
    if count as usize > MAX_ATTR_COUNT {
        return None;
    }
    let mut attr_bytes = 0usize;
    for _ in 0..count {
        let (&name_len, after) = rest.split_first()?;
        if name_len == 0 || name_len as usize > MAX_ATTR_NAME_BYTES {
            return None;
        }
        let (_, after) = after.split_at_checked(name_len as usize)?;
        let (&tag, after) = after.split_first()?;
        let value_len = match tag {
            ATTR_TAG_STR => {
                let (len_bytes, _) = after.split_at_checked(2)?;
                let str_len = u16::from_le_bytes([len_bytes[0], len_bytes[1]]) as usize;
                if str_len > MAX_ATTR_STR_BYTES {
                    return None;
                }
                2 + str_len
            }
            ATTR_TAG_BOOL => 1,
            ATTR_TAG_I64 | ATTR_TAG_F64 => 8,
            _ => return None,
        };
        let (_, after) = after.split_at_checked(value_len)?;
        attr_bytes += 2 + name_len as usize + value_len;
        if attr_bytes > MAX_ATTRS_TOTAL_BYTES {
            return None;
        }
        rest = after;
    }
    Some(1 + attr_bytes)
}

pub(crate) fn header_len(cipher: Option<&Cipher>) -> usize {
    match cipher {
        None => HEADER_LEN,
        Some(_) => SEALED_HEADER_LEN,
    }
}

pub(crate) fn header_is_complete(
    file: &mut File,
    path: &Path,
    file_len: u64,
    cipher: Option<&Cipher>,
) -> Result<bool, VecDbError> {
    if file_len < MAGIC.len() as u64 {
        return Ok(false);
    }
    let mut magic = [0u8; 4];
    read_from_start(file, path, &mut magic)?;
    match (cipher, magic) {
        (None, MAGIC) => Ok(file_len >= HEADER_LEN as u64),
        (Some(_), SEALED_MAGIC) if file_len >= SEALED_HEADER_LEN as u64 => Ok(true),
        (Some(_), SEALED_MAGIC) => Err(VecDbError::Corrupt(format!(
            "encrypted log header has only {file_len} of {SEALED_HEADER_LEN} bytes"
        ))),
        (None, SEALED_MAGIC) => {
            let prefix = read_header_prefix(file, path, file_len, SEALED_HEADER_LEN)?;
            let relabeled_plaintext = prefix.len() < SEALED_HEADER_LEN
                && prefix
                    .get(..HEADER_LEN)
                    .is_some_and(|header| header_crc_matches_with_magic(header, MAGIC));
            if relabeled_plaintext {
                return Err(bad_magic(magic));
            }
            Err(format_mismatch(
                &prefix,
                SEALED_HEADER_LEN,
                path,
                EncryptionMismatch::MissingKey,
            ))
        }
        (Some(_), MAGIC) => {
            let prefix = read_header_prefix(file, path, file_len, HEADER_LEN)?;
            Err(format_mismatch(
                &prefix,
                HEADER_LEN,
                path,
                EncryptionMismatch::UnexpectedKey,
            ))
        }
        _ if file_len >= HEADER_LEN as u64 => Err(bad_magic(magic)),
        _ => Ok(false),
    }
}

fn read_from_start(file: &mut File, path: &Path, buffer: &mut [u8]) -> Result<(), VecDbError> {
    file.seek(SeekFrom::Start(0))
        .and_then(|_| file.read_exact(buffer))
        .map_err(|source| VecDbError::io(path, source))
}

fn read_header_prefix(
    file: &mut File,
    path: &Path,
    file_len: u64,
    header_len: usize,
) -> Result<Vec<u8>, VecDbError> {
    let mut prefix = vec![0u8; file_len.min(header_len as u64) as usize];
    read_from_start(file, path, &mut prefix)?;
    Ok(prefix)
}

fn header_crc_matches_with_magic(header: &[u8], magic: [u8; 4]) -> bool {
    let (covered, crc) = header.split_at(header.len() - HEADER_CRC_LEN);
    let mut hasher = Crc32::new();
    hasher.update(&magic);
    hasher.update(&covered[magic.len()..]);
    hasher.finalize().to_le_bytes() == crc
}

fn bad_magic(magic: [u8; 4]) -> VecDbError {
    VecDbError::Corrupt(format!("bad log magic {magic:02x?}"))
}

fn format_mismatch(
    prefix: &[u8],
    header_len: usize,
    path: &Path,
    mismatch: EncryptionMismatch,
) -> VecDbError {
    match prefix.get(..header_len).map(verify_header_crc) {
        Some(Err(corrupt)) => corrupt,
        _ => VecDbError::encryption_mismatch(path, mismatch),
    }
}

fn encode_header_fields(
    magic: [u8; 4],
    dims: u32,
    generation: &[u8; 16],
    storage: StorageKind,
) -> [u8; HEADER_FIELDS_LEN] {
    let mut bytes = [0u8; HEADER_FIELDS_LEN];
    bytes[0..4].copy_from_slice(&magic);
    bytes[4..6].copy_from_slice(&FORMAT_VERSION.to_le_bytes());
    bytes[STORAGE_TAG_OFFSET] = storage.header_tag();
    bytes[METRIC_TAG_OFFSET] = COSINE_METRIC_TAG;
    bytes[8..12].copy_from_slice(&dims.to_le_bytes());
    bytes[12..28].copy_from_slice(generation);
    bytes
}

fn encode_header(dims: u32, generation: &[u8; 16], storage: StorageKind) -> [u8; HEADER_LEN] {
    let mut bytes = [0u8; HEADER_LEN];
    bytes[..HEADER_FIELDS_LEN]
        .copy_from_slice(&encode_header_fields(MAGIC, dims, generation, storage));
    let crc = crc32(&bytes[..HEADER_FIELDS_LEN]);
    bytes[HEADER_FIELDS_LEN..].copy_from_slice(&crc.to_le_bytes());
    bytes
}

fn encode_sealed_header(
    dims: u32,
    generation: &[u8; 16],
    storage: StorageKind,
    cipher: &Cipher,
) -> ente_core::crypto::Result<[u8; SEALED_HEADER_LEN]> {
    let fields = encode_header_fields(SEALED_MAGIC, dims, generation, storage);
    let (nonce, tag) = cipher.seal(&mut [], &fields)?;
    let mut bytes = [0u8; SEALED_HEADER_LEN];
    let tag_start = HEADER_FIELDS_LEN + NONCE_LEN;
    let crc_start = tag_start + TAG_LEN;
    bytes[..HEADER_FIELDS_LEN].copy_from_slice(&fields);
    bytes[HEADER_FIELDS_LEN..tag_start].copy_from_slice(nonce.as_bytes());
    bytes[tag_start..crc_start].copy_from_slice(&tag);
    let crc = crc32(&bytes[..crc_start]);
    bytes[crc_start..].copy_from_slice(&crc.to_le_bytes());
    Ok(bytes)
}

#[derive(Debug, PartialEq, Eq)]
struct Header {
    generation: [u8; 16],
    dims: usize,
    storage: StorageKind,
}

fn decode_header(bytes: &[u8; HEADER_LEN]) -> Result<Header, VecDbError> {
    verify_header_integrity(bytes, MAGIC)?;
    decode_header_fields(bytes)
}

fn decode_sealed_header(
    bytes: &[u8; SEALED_HEADER_LEN],
    path: &Path,
    cipher: &Cipher,
) -> Result<Header, VecDbError> {
    verify_header_integrity(bytes, SEALED_MAGIC)?;
    let header = decode_header_fields(bytes)?;
    let tag_start = HEADER_FIELDS_LEN + NONCE_LEN;
    let authentic = cipher.open(
        &mut [],
        &bytes[..HEADER_FIELDS_LEN],
        &bytes[HEADER_FIELDS_LEN..tag_start],
        &bytes[tag_start..tag_start + TAG_LEN],
    );
    if !authentic {
        return Err(VecDbError::encryption_mismatch(
            path,
            EncryptionMismatch::WrongKey,
        ));
    }
    Ok(header)
}

fn verify_header_integrity(bytes: &[u8], magic: [u8; 4]) -> Result<(), VecDbError> {
    if bytes[0..4] != magic {
        return Err(VecDbError::Corrupt(format!(
            "bad log magic {:02x?}",
            &bytes[0..4]
        )));
    }
    verify_header_crc(bytes)
}

pub(crate) fn validate_log_dims(
    dims: usize,
    storage: StorageKind,
    cipher: Option<&Cipher>,
) -> Result<(), VecDbError> {
    match cipher {
        None => validate_dims(dims, storage),
        Some(_) => validate_dims_up_to(dims, storage, max_sealed_dims(storage)),
    }
}

fn max_sealed_dims(storage: StorageKind) -> usize {
    let record_budget = u32::MAX as usize - TAG_LEN - max_record_len(storage, 0);
    let bytes_per_dim = vector_payload_len(storage, 1) - vector_payload_len(storage, 0);
    let lane_width = storage.lane_width();
    (record_budget / bytes_per_dim / lane_width * lane_width).min(storage.max_dims())
}

fn verify_header_crc(bytes: &[u8]) -> Result<(), VecDbError> {
    let (covered, crc) = bytes.split_at(bytes.len() - HEADER_CRC_LEN);
    let stored_crc = u32::from_le_bytes([crc[0], crc[1], crc[2], crc[3]]);
    let computed_crc = crc32(covered);
    if stored_crc != computed_crc {
        return Err(VecDbError::Corrupt(format!(
            "log header crc mismatch: stored {stored_crc:08x}, computed {computed_crc:08x}"
        )));
    }
    Ok(())
}

fn decode_header_fields(bytes: &[u8]) -> Result<Header, VecDbError> {
    let version = u16::from_le_bytes([bytes[4], bytes[5]]);
    if version != FORMAT_VERSION {
        return Err(VecDbError::Corrupt(format!(
            "unsupported log format version {version}"
        )));
    }
    let storage = StorageKind::from_header_tag(bytes[STORAGE_TAG_OFFSET]).ok_or_else(|| {
        VecDbError::Corrupt(format!("unknown scalar tag {}", bytes[STORAGE_TAG_OFFSET]))
    })?;
    if bytes[METRIC_TAG_OFFSET] != COSINE_METRIC_TAG {
        return Err(VecDbError::Corrupt(format!(
            "unknown metric tag {}",
            bytes[METRIC_TAG_OFFSET]
        )));
    }
    let dims = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]) as usize;
    let mut generation = [0u8; 16];
    generation.copy_from_slice(&bytes[12..28]);
    Ok(Header {
        generation,
        dims,
        storage,
    })
}

pub(crate) fn validate_entry(
    entry: &LogEntry<'_>,
    dims: usize,
    storage: StorageKind,
) -> Result<(), VecDbError> {
    match entry {
        LogEntry::Add { key, vector, attrs } => {
            validate_key(key)?;
            if vector.storage() != storage {
                return Err(VecDbError::StorageMismatch {
                    expected: storage,
                    actual: vector.storage(),
                });
            }
            if vector.dims() != dims {
                return Err(VecDbError::DimensionMismatch {
                    expected: dims,
                    actual: vector.dims(),
                });
            }
            validate_attrs(attrs)
        }
        LogEntry::Tombstone { key } => validate_key(key),
    }
}

fn validate_attrs(attrs: &[Attribute]) -> Result<(), VecDbError> {
    if attrs.len() > MAX_ATTR_COUNT {
        return Err(VecDbError::InvalidAttributes(format!(
            "{} attributes, limit is {MAX_ATTR_COUNT}",
            attrs.len()
        )));
    }
    let mut total = 0usize;
    for (index, attr) in attrs.iter().enumerate() {
        if attr.name.is_empty() {
            return Err(VecDbError::InvalidAttributes(format!(
                "attribute {index} has an empty name"
            )));
        }
        if attr.name.len() > MAX_ATTR_NAME_BYTES {
            return Err(VecDbError::InvalidAttributes(format!(
                "attribute name {:?} is {} bytes, limit is {MAX_ATTR_NAME_BYTES}",
                attr.name,
                attr.name.len()
            )));
        }
        if let AttrValue::Str(value) = &attr.value
            && value.len() > MAX_ATTR_STR_BYTES
        {
            return Err(VecDbError::InvalidAttributes(format!(
                "value of attribute {:?} is {} bytes, limit is {MAX_ATTR_STR_BYTES}",
                attr.name,
                value.len()
            )));
        }
        if attrs[..index].iter().any(|prior| prior.name == attr.name) {
            return Err(VecDbError::InvalidAttributes(format!(
                "duplicate attribute name {:?}",
                attr.name
            )));
        }
        total += encoded_attr_len(attr);
    }
    if total > MAX_ATTRS_TOTAL_BYTES {
        return Err(VecDbError::InvalidAttributes(format!(
            "attributes encode to {total} bytes, limit is {MAX_ATTRS_TOTAL_BYTES}"
        )));
    }
    Ok(())
}

fn encoded_attr_len(attr: &Attribute) -> usize {
    2 + attr.name.len()
        + match &attr.value {
            AttrValue::Str(value) => 2 + value.len(),
            AttrValue::Bool(_) => 1,
            AttrValue::I64(_) | AttrValue::F64(_) => 8,
        }
}

pub(crate) fn add_record_len(
    key: &str,
    dims: usize,
    storage: StorageKind,
    attrs: &[Attribute],
) -> u64 {
    (RECORD_PREFIX_LEN
        + key.len()
        + vector_payload_len(storage, dims)
        + 1
        + attrs.iter().map(encoded_attr_len).sum::<usize>()
        + RECORD_CRC_LEN) as u64
}

fn encode_record_into(buffer: &mut Vec<u8>, entry: &LogEntry<'_>) {
    let start = buffer.len();
    match entry {
        LogEntry::Add { key, vector, attrs } => {
            buffer.push(RECORD_TYPE_ADD);
            buffer.extend_from_slice(&(key.len() as u16).to_le_bytes());
            buffer.extend_from_slice(key.as_bytes());
            match vector {
                VectorPayload::F32(values) => {
                    for value in *values {
                        buffer.extend_from_slice(&value.to_le_bytes());
                    }
                }
                VectorPayload::I8 { scale, values } => {
                    buffer.extend_from_slice(&scale.to_le_bytes());
                    buffer.extend(values.iter().flat_map(|value| value.to_le_bytes()));
                }
            }
            buffer.push(attrs.len() as u8);
            for attr in *attrs {
                encode_attr_into(buffer, attr);
            }
        }
        LogEntry::Tombstone { key } => {
            buffer.push(RECORD_TYPE_TOMBSTONE);
            buffer.extend_from_slice(&(key.len() as u16).to_le_bytes());
            buffer.extend_from_slice(key.as_bytes());
        }
    }
    let crc = crc32(&buffer[start..]);
    buffer.extend_from_slice(&crc.to_le_bytes());
}

fn encode_sealed_record_into(
    buffer: &mut Vec<u8>,
    entry: &LogEntry<'_>,
    cipher: &Cipher,
    additional_data: &[u8],
) -> Result<(), VecDbError> {
    let frame_start = buffer.len();
    let record_start = frame_start + FRAME_PREFIX_LEN;
    buffer.resize(record_start, 0);
    encode_record_into(buffer, entry);
    let too_large = || VecDbError::InvalidVector("the record is too large to encrypt".to_string());
    let sealed_len =
        u32::try_from(buffer.len() - record_start + TAG_LEN).map_err(|_| too_large())?;
    let (nonce, tag) = cipher
        .seal(&mut buffer[record_start..], additional_data)
        .map_err(|_| too_large())?;
    buffer.extend_from_slice(&tag);
    buffer[frame_start..frame_start + FRAME_LEN_BYTES].copy_from_slice(&sealed_len.to_le_bytes());
    buffer[frame_start + FRAME_LEN_BYTES..record_start].copy_from_slice(nonce.as_bytes());
    Ok(())
}

fn encode_attr_into(buffer: &mut Vec<u8>, attr: &Attribute) {
    buffer.push(attr.name.len() as u8);
    buffer.extend_from_slice(attr.name.as_bytes());
    match &attr.value {
        AttrValue::Str(value) => {
            buffer.push(ATTR_TAG_STR);
            buffer.extend_from_slice(&(value.len() as u16).to_le_bytes());
            buffer.extend_from_slice(value.as_bytes());
        }
        AttrValue::Bool(value) => {
            buffer.push(ATTR_TAG_BOOL);
            buffer.push(u8::from(*value));
        }
        AttrValue::I64(value) => {
            buffer.push(ATTR_TAG_I64);
            buffer.extend_from_slice(&value.to_le_bytes());
        }
        AttrValue::F64(value) => {
            buffer.push(ATTR_TAG_F64);
            buffer.extend_from_slice(&value.to_le_bytes());
        }
    }
}

fn fresh_generation() -> [u8; 16] {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_nanos() as u64);
    let pid = u64::from(std::process::id());
    let counter = GENERATION_COUNTER.fetch_add(1, Ordering::Relaxed);
    let mut state = nanos ^ pid.rotate_left(32) ^ counter.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    let mut generation = [0u8; 16];
    generation[0..8].copy_from_slice(&splitmix64(&mut state).to_le_bytes());
    generation[8..16].copy_from_slice(&splitmix64(&mut state).to_le_bytes());
    generation
}

fn random_generation() -> [u8; 16] {
    let mut generation = [0u8; 16];
    generation.copy_from_slice(&ente_core::crypto::random_bytes(16));
    generation
}

pub(crate) fn remove_stale_temp_sibling(path: &Path) -> Result<(), VecDbError> {
    remove_if_present(&temp_sibling_path(path))
}

pub(crate) fn remove_if_present(path: &Path) -> Result<(), VecDbError> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
        Err(source) => Err(VecDbError::io(path, source)),
    }
}

pub(crate) fn rename_with_windows_fallback(from: &Path, to: &Path) -> Result<(), VecDbError> {
    match std::fs::rename(from, to) {
        Ok(()) => Ok(()),
        #[cfg(windows)]
        Err(_) => {
            let _ = std::fs::remove_file(to);
            std::fs::rename(from, to).map_err(|source| VecDbError::io(from, source))
        }
        #[cfg(not(windows))]
        Err(source) => Err(VecDbError::io(from, source)),
    }
}

fn temp_sibling_path(path: &Path) -> PathBuf {
    let mut temp = path.as_os_str().to_os_string();
    temp.push(".tmp");
    PathBuf::from(temp)
}

#[cfg(unix)]
pub(crate) fn sync_parent_dir(path: &Path) -> Result<(), VecDbError> {
    let parent = match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    };
    File::open(parent)
        .and_then(|dir| dir.sync_all())
        .map_err(|source| VecDbError::io(parent, source))
}

#[cfg(not(unix))]
pub(crate) fn sync_parent_dir(_path: &Path) -> Result<(), VecDbError> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn add_record_size_matches_encoded_bytes_for_both_storage_formats() {
        let vector = seeded_vector(9, 32);
        let attrs = vec![
            Attribute {
                name: "name".into(),
                value: AttrValue::Str("影像".into()),
            },
            Attribute {
                name: "flag".into(),
                value: AttrValue::Bool(true),
            },
            Attribute {
                name: "count".into(),
                value: AttrValue::I64(-23),
            },
            Attribute {
                name: "score".into(),
                value: AttrValue::F64(0.125),
            },
        ];
        for stored in [
            StoredVector::F32(vector.clone()),
            StoredVector::quantize(&vector),
        ] {
            for attrs in [&[][..], attrs.as_slice()] {
                let payload = stored.as_payload();
                let entry = LogEntry::Add {
                    key: "photo-影像",
                    vector: payload,
                    attrs,
                };
                let mut encoded = Vec::new();
                encode_record_into(&mut encoded, &entry);
                assert_eq!(
                    add_record_len("photo-影像", 32, payload.storage(), attrs),
                    encoded.len() as u64
                );
            }
        }
    }

    fn seeded_vector(seed: u64, dims: usize) -> Vec<f32> {
        let mut state = seed;
        (0..dims)
            .map(|_| {
                let unit = (splitmix64(&mut state) >> 40) as f32 / (1u64 << 24) as f32;
                unit * 2.0 - 1.0
            })
            .collect()
    }

    fn reopen(path: &Path, dims: usize, storage: StorageKind) -> Log {
        let file = open_writer_file(path, false).unwrap();
        Log::open(file, path, dims, storage, None).unwrap()
    }

    fn append_bounds(log: &mut Log, entries: &[LogEntry<'_>]) -> (u64, u64) {
        let start = log.current_end_offset();
        log.append(entries).unwrap();
        (start, log.current_end_offset())
    }

    fn append_raw_bytes(log: &mut Log, bytes: &[u8]) {
        log.file.seek(SeekFrom::End(0)).unwrap();
        log.file.write_all(bytes).unwrap();
        log.file.sync_all().unwrap();
    }

    fn encoded_add(key: &str, vector: &[f32]) -> Vec<u8> {
        let mut bytes = Vec::new();
        encode_record_into(
            &mut bytes,
            &LogEntry::Add {
                key,
                vector: VectorPayload::F32(vector),
                attrs: &[],
            },
        );
        bytes
    }

    fn scan_all(log: &mut Log) -> (Vec<(LogRecord, u64)>, u64) {
        let mut scanner = log.scan().unwrap();
        let mut records = Vec::new();
        while let Some(pair) = scanner.next_record().unwrap() {
            records.push(pair);
        }
        (records, scanner.recoverable_end())
    }

    fn owned(vector: VectorPayload<'_>) -> StoredVector {
        match vector {
            VectorPayload::F32(values) => StoredVector::F32(values.to_vec()),
            VectorPayload::I8 { scale, values } => StoredVector::I8 {
                scale,
                values: values.to_vec(),
            },
        }
    }

    fn expected_record(entry: &LogEntry<'_>) -> LogRecord {
        match entry {
            LogEntry::Add { key, vector, attrs } => LogRecord::Add {
                key: (*key).to_string(),
                vector: owned(*vector),
                attrs: attrs.to_vec(),
            },
            LogEntry::Tombstone { key } => LogRecord::Tombstone {
                key: (*key).to_string(),
            },
        }
    }

    fn raw_record(record_type: u8, key_len: u16, key: &[u8], payload: &[u8]) -> Vec<u8> {
        let mut bytes = vec![record_type];
        bytes.extend_from_slice(&key_len.to_le_bytes());
        bytes.extend_from_slice(key);
        bytes.extend_from_slice(payload);
        let crc = crc32(&bytes);
        bytes.extend_from_slice(&crc.to_le_bytes());
        bytes
    }

    fn write_log_file(path: &Path, dims: u32, record_bytes: &[u8]) {
        let mut bytes = encode_header(dims, &[9u8; 16], StorageKind::F32).to_vec();
        bytes.extend_from_slice(record_bytes);
        std::fs::write(path, bytes).unwrap();
    }

    fn refresh_crc(bytes: &mut [u8; HEADER_LEN]) {
        let crc = crc32(&bytes[0..28]);
        bytes[28..32].copy_from_slice(&crc.to_le_bytes());
    }

    fn open_with_header(
        mutate: impl FnOnce(&mut [u8; HEADER_LEN]),
        expected_dims: usize,
    ) -> Result<Log, VecDbError> {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut bytes = encode_header(8, &[7u8; 16], StorageKind::F32);
        mutate(&mut bytes);
        std::fs::write(&path, bytes).unwrap();
        let file = File::options().read(true).write(true).open(&path).unwrap();
        Log::open(file, &path, expected_dims, StorageKind::F32, None)
    }

    #[test]
    fn header_round_trips_through_create_and_reopen() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let created = Log::create(&path, 512, StorageKind::F32, None).unwrap();
        let generation = created.generation();
        assert_eq!(created.current_end_offset(), HEADER_LEN as u64);
        assert_eq!(created.path(), path.as_path());
        drop(created);
        let reopened = reopen(&path, 512, StorageKind::F32);
        assert_eq!(reopened.generation(), generation);
        assert_eq!(reopened.current_end_offset(), HEADER_LEN as u64);
    }

    #[cfg(any(unix, windows))]
    #[test]
    fn writer_exclusion_lasts_until_the_log_is_dropped() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let alias = dir.path().join("alias");
        let created = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        std::fs::hard_link(&path, &alias).unwrap();
        let reader = File::open(&alias).unwrap();
        assert_eq!(reader.metadata().unwrap().len(), HEADER_LEN as u64);
        assert!(matches!(
            open_writer_file(&alias, false),
            Err(VecDbError::Locked(_))
        ));
        drop(reader);
        assert!(matches!(
            open_writer_file(&alias, false),
            Err(VecDbError::Locked(_))
        ));
        drop(created);
        let reopened = reopen(&alias, 8, StorageKind::F32);
        assert!(matches!(
            open_writer_file(&path, false),
            Err(VecDbError::Locked(_))
        ));
        drop(reopened);
        assert!(open_writer_file(&path, false).is_ok());
    }

    #[cfg(unix)]
    #[test]
    fn dropping_a_log_releases_a_lock_whose_file_is_still_shared() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let created = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let _inherited = created.file.try_clone().unwrap();
        drop(created);
        assert!(open_writer_file(&path, false).is_ok());
    }

    #[cfg(windows)]
    #[test]
    fn only_sharing_violations_are_reported_as_locked() {
        let path = Path::new("log");
        assert!(matches!(
            writer_open_error(path, std::io::Error::from_raw_os_error(32)),
            VecDbError::Locked(_)
        ));
        assert!(matches!(
            writer_open_error(path, std::io::Error::from_raw_os_error(5)),
            VecDbError::Io { source, .. } if source.raw_os_error() == Some(5)
        ));
    }

    #[test]
    fn rejects_bad_magic() {
        let error = open_with_header(
            |bytes| {
                bytes[0] = b'X';
                refresh_crc(bytes);
            },
            8,
        )
        .unwrap_err();
        assert!(matches!(&error, VecDbError::Corrupt(message) if message.contains("magic")));
    }

    #[test]
    fn rejects_unsupported_version() {
        let error = open_with_header(
            |bytes| {
                bytes[4..6].copy_from_slice(&2u16.to_le_bytes());
                refresh_crc(bytes);
            },
            8,
        )
        .unwrap_err();
        assert!(matches!(&error, VecDbError::Corrupt(message) if message.contains("version")));
    }

    #[test]
    fn rejects_unknown_scalar_tag() {
        let error = open_with_header(
            |bytes| {
                bytes[6] = 2;
                refresh_crc(bytes);
            },
            8,
        )
        .unwrap_err();
        assert!(matches!(&error, VecDbError::Corrupt(message) if message.contains("scalar")));
    }

    #[test]
    fn rejects_every_metric_tag_but_cosine() {
        for tag in [0u8, 2, 3, 0xff] {
            let error = open_with_header(
                |bytes| {
                    bytes[METRIC_TAG_OFFSET] = tag;
                    refresh_crc(bytes);
                },
                8,
            )
            .unwrap_err();
            assert!(matches!(&error, VecDbError::Corrupt(message) if message.contains("metric")));
        }
    }

    #[test]
    fn rejects_header_crc_mismatch() {
        let error = open_with_header(|bytes| bytes[20] ^= 0x40, 8).unwrap_err();
        assert!(matches!(&error, VecDbError::Corrupt(message) if message.contains("crc")));
    }

    #[test]
    fn rejects_dims_mismatch() {
        let error = open_with_header(|_| {}, 16).unwrap_err();
        assert!(matches!(
            error,
            VecDbError::DimensionMismatch {
                expected: 16,
                actual: 8
            }
        ));
    }

    #[test]
    fn writer_open_reinitializes_files_shorter_than_the_header() {
        for junk_len in [0usize, 10, 31] {
            let dir = TempDir::new().unwrap();
            let path = dir.path().join("log");
            std::fs::write(&path, vec![1u8; junk_len]).unwrap();
            let file = File::options().read(true).write(true).open(&path).unwrap();
            let mut log = Log::open(file, &path, 8, StorageKind::F32, None).unwrap();
            assert_eq!(log.current_end_offset(), HEADER_LEN as u64);
            assert_eq!(std::fs::metadata(&path).unwrap().len(), HEADER_LEN as u64);
            let (records, _) = scan_all(&mut log);
            assert!(records.is_empty());
            let vector = seeded_vector(6, 8);
            let (start, end) = append_bounds(
                &mut log,
                &[LogEntry::Add {
                    key: "reborn",
                    vector: VectorPayload::F32(&vector),
                    attrs: &[],
                }],
            );
            assert_eq!(start, HEADER_LEN as u64);
            let generation = log.generation();
            drop(log);
            let reopened = reopen(&path, 8, StorageKind::F32);
            assert_eq!(reopened.generation(), generation);
            assert_eq!(reopened.current_end_offset(), end);
        }
    }

    #[test]
    fn create_rejects_invalid_dimensions() {
        let dir = TempDir::new().unwrap();
        assert!(matches!(
            Log::create(&dir.path().join("a"), 0, StorageKind::F32, None),
            Err(VecDbError::InvalidDimensions { dims: 0, .. })
        ));
        assert!(matches!(
            Log::create(&dir.path().join("b"), 12, StorageKind::F32, None),
            Err(VecDbError::InvalidDimensions { dims: 12, .. })
        ));
    }

    #[test]
    fn open_rejects_invalid_dimensions() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        drop(Log::create(&path, 8, StorageKind::F32, None).unwrap());
        let file = File::options().read(true).write(true).open(&path).unwrap();
        assert!(matches!(
            Log::open(file, &path, 12, StorageKind::F32, None),
            Err(VecDbError::DimensionMismatch {
                expected: 12,
                actual: 8
            })
        ));
    }

    #[test]
    fn golden_bytes_pin_format_v1() {
        let generation: [u8; 16] = std::array::from_fn(|index| index as u8);
        let golden_header: [u8; 32] = [
            0x45, 0x56, 0x44, 0x42, 0x01, 0x00, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
            0xc8, 0xb1, 0xb7, 0xce,
        ];
        let golden_add: [u8; 42] = [
            0x01, 0x02, 0x00, 0x6b, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x3f, 0x00,
            0x00, 0x80, 0xbf, 0x00, 0x00, 0x00, 0x3f, 0x00, 0x00, 0x00, 0xbf, 0x00, 0x00, 0x00,
            0x40, 0x00, 0x00, 0x00, 0xc0, 0x00, 0x00, 0xc0, 0x3f, 0x00, 0xc7, 0x91, 0x1a, 0x8d,
        ];
        let golden_attr_add: [u8; 75] = [
            0x01, 0x02, 0x00, 0x6b, 0x32, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x3f, 0x00,
            0x00, 0x80, 0xbf, 0x00, 0x00, 0x00, 0x3f, 0x00, 0x00, 0x00, 0xbf, 0x00, 0x00, 0x00,
            0x40, 0x00, 0x00, 0x00, 0xc0, 0x00, 0x00, 0xc0, 0x3f, 0x04, 0x01, 0x6d, 0x00, 0x02,
            0x00, 0x76, 0x31, 0x01, 0x62, 0x01, 0x01, 0x01, 0x69, 0x02, 0xfe, 0xff, 0xff, 0xff,
            0xff, 0xff, 0xff, 0xff, 0x01, 0x66, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8,
            0x3f, 0x4a, 0x4a, 0x73, 0x96,
        ];
        let golden_tombstone: [u8; 9] = [0x02, 0x02, 0x00, 0x6b, 0x31, 0xa0, 0xde, 0x3c, 0xc1];
        let vector = [0.0f32, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0, 1.5];
        let attrs = vec![
            Attribute {
                name: "m".to_string(),
                value: AttrValue::Str("v1".to_string()),
            },
            Attribute {
                name: "b".to_string(),
                value: AttrValue::Bool(true),
            },
            Attribute {
                name: "i".to_string(),
                value: AttrValue::I64(-2),
            },
            Attribute {
                name: "f".to_string(),
                value: AttrValue::F64(1.5),
            },
        ];
        assert_eq!(
            encode_header(8, &generation, StorageKind::F32),
            golden_header
        );
        let mut encoded = Vec::new();
        encode_record_into(
            &mut encoded,
            &LogEntry::Add {
                key: "k1",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            },
        );
        assert_eq!(encoded, golden_add);
        encoded.clear();
        encode_record_into(
            &mut encoded,
            &LogEntry::Add {
                key: "k2",
                vector: VectorPayload::F32(&vector),
                attrs: &attrs,
            },
        );
        assert_eq!(encoded, golden_attr_add);
        encoded.clear();
        encode_record_into(&mut encoded, &LogEntry::Tombstone { key: "k1" });
        assert_eq!(encoded, golden_tombstone);
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut bytes = golden_header.to_vec();
        bytes.extend_from_slice(&golden_add);
        bytes.extend_from_slice(&golden_attr_add);
        bytes.extend_from_slice(&golden_tombstone);
        std::fs::write(&path, &bytes).unwrap();
        let mut log = reopen(&path, 8, StorageKind::F32);
        assert_eq!(log.generation(), generation);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(
            records,
            vec![
                (
                    LogRecord::Add {
                        key: "k1".to_string(),
                        vector: StoredVector::F32(vector.to_vec()),
                        attrs: Vec::new()
                    },
                    32
                ),
                (
                    LogRecord::Add {
                        key: "k2".to_string(),
                        vector: StoredVector::F32(vector.to_vec()),
                        attrs: attrs.clone()
                    },
                    74
                ),
                (
                    LogRecord::Tombstone {
                        key: "k1".to_string()
                    },
                    149
                )
            ]
        );
        assert_eq!(recoverable_end, 158);
    }

    #[test]
    fn add_and_tombstone_records_round_trip() {
        for dims in [8usize, 512] {
            let dir = TempDir::new().unwrap();
            let path = dir.path().join("log");
            let mut log = Log::create(&path, dims, StorageKind::F32, None).unwrap();
            let vector = seeded_vector(1, dims);
            let entries = [
                LogEntry::Add {
                    key: "alpha",
                    vector: VectorPayload::F32(&vector),
                    attrs: &[],
                },
                LogEntry::Tombstone { key: "beta" },
            ];
            let (first, _) = append_bounds(&mut log, &entries[0..1]);
            let (second, end) = append_bounds(&mut log, &entries[1..2]);
            assert_eq!(first, HEADER_LEN as u64);
            let (records, recoverable_end) = scan_all(&mut log);
            assert_eq!(
                records,
                vec![
                    (expected_record(&entries[0]), first),
                    (expected_record(&entries[1]), second)
                ]
            );
            assert_eq!(recoverable_end, end);
        }
    }

    #[test]
    fn round_trips_boundary_and_multibyte_keys() {
        let long255 = "k".repeat(255);
        let long256 = "k".repeat(256);
        let multibyte256 = format!("{}🔑", "k".repeat(252));
        assert_eq!(multibyte256.len(), 256);
        let keys = [
            "a",
            long255.as_str(),
            long256.as_str(),
            multibyte256.as_str(),
            "ключ-🗝",
        ];
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(5, 8);
        for key in keys {
            log.append(&[LogEntry::Add {
                key,
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }])
            .unwrap();
            log.append(&[LogEntry::Tombstone { key }]).unwrap();
        }
        let (records, _) = scan_all(&mut log);
        assert_eq!(records.len(), 10);
        for (index, key) in keys.iter().enumerate() {
            assert_eq!(
                records[index * 2].0,
                LogRecord::Add {
                    key: (*key).to_string(),
                    vector: StoredVector::F32(vector.clone()),
                    attrs: Vec::new()
                }
            );
            assert_eq!(
                records[index * 2 + 1].0,
                LogRecord::Tombstone {
                    key: (*key).to_string()
                }
            );
        }
    }

    #[test]
    fn decodes_non_finite_components_without_panicking() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = [
            f32::NAN,
            f32::INFINITY,
            f32::NEG_INFINITY,
            -0.0,
            f32::MIN_POSITIVE,
            f32::MAX,
            -f32::MAX,
            0.5,
        ];
        log.append(&[LogEntry::Add {
            key: "weird",
            vector: VectorPayload::F32(&vector),
            attrs: &[],
        }])
        .unwrap();
        let (records, _) = scan_all(&mut log);
        let LogRecord::Add {
            key,
            vector: StoredVector::F32(decoded),
            ..
        } = &records[0].0
        else {
            panic!("expected an add record");
        };
        assert_eq!(key, "weird");
        let expected_bits: Vec<u32> = vector.iter().map(|value| value.to_bits()).collect();
        let decoded_bits: Vec<u32> = decoded.iter().map(|value| value.to_bits()).collect();
        assert_eq!(decoded_bits, expected_bits);
    }

    #[test]
    fn scanner_stops_at_last_complete_record_for_every_torn_length() {
        let dir = TempDir::new().unwrap();
        let build_path = dir.path().join("log");
        let mut log = Log::create(&build_path, 8, StorageKind::F32, None).unwrap();
        let vectors: Vec<Vec<f32>> = (0..3).map(|seed| seeded_vector(seed, 8)).collect();
        let mut boundaries = Vec::new();
        for (index, vector) in vectors.iter().enumerate() {
            let key = format!("key-{index}");
            boundaries.push(append_bounds(
                &mut log,
                &[LogEntry::Add {
                    key: &key,
                    vector: VectorPayload::F32(vector),
                    attrs: &[],
                }],
            ));
        }
        drop(log);
        let full_bytes = std::fs::read(&build_path).unwrap();
        let intact_end = boundaries[1].1;
        for cut in intact_end..boundaries[2].1 {
            let torn_path = dir.path().join(format!("torn-{cut}"));
            std::fs::write(&torn_path, &full_bytes[..cut as usize]).unwrap();
            let mut torn_log = reopen(&torn_path, 8, StorageKind::F32);
            let (records, recoverable_end) = scan_all(&mut torn_log);
            assert_eq!(records.len(), 2);
            assert_eq!(records[0].1, boundaries[0].0);
            assert_eq!(records[1].1, boundaries[1].0);
            assert_eq!(recoverable_end, intact_end);
        }
    }

    #[test]
    fn truncate_to_repairs_torn_tail_for_clean_appends() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(1, 8);
        let (_, first_end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "kept",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        let (_, torn_end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "torn",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        drop(log);
        let cut = first_end + (torn_end - first_end) / 2;
        let file = File::options().read(true).write(true).open(&path).unwrap();
        file.set_len(cut).unwrap();
        drop(file);
        let mut log = reopen(&path, 8, StorageKind::F32);
        assert_eq!(log.current_end_offset(), cut);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 1);
        assert_eq!(recoverable_end, first_end);
        log.truncate_to(recoverable_end).unwrap();
        assert_eq!(log.current_end_offset(), first_end);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), first_end);
        let (start, end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "fresh",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        assert_eq!(start, first_end);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 2);
        assert_eq!(records[1].1, start);
        assert_eq!(recoverable_end, end);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), end);
    }

    #[test]
    fn extend_end_offset_grows_to_target_clamps_to_file_and_never_shrinks() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(1, 8);
        let (_, captured_end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "first",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        log.extend_end_offset_to(captured_end).unwrap();
        assert_eq!(log.current_end_offset(), captured_end);
        log.extend_end_offset_to(captured_end + 1000).unwrap();
        assert_eq!(log.current_end_offset(), captured_end);
        let foreign = encoded_add("second", &vector);
        append_raw_bytes(&mut log, &foreign);
        assert_eq!(log.current_end_offset(), captured_end);
        let grown_end = captured_end + foreign.len() as u64;
        let partial_end = captured_end + foreign.len() as u64 / 2;
        log.extend_end_offset_to(partial_end).unwrap();
        assert_eq!(log.current_end_offset(), partial_end);
        log.extend_end_offset_to(grown_end).unwrap();
        assert_eq!(log.current_end_offset(), grown_end);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 2);
        assert_eq!(recoverable_end, grown_end);
        log.extend_end_offset_to(captured_end).unwrap();
        assert_eq!(log.current_end_offset(), grown_end);
        log.file.set_len(captured_end).unwrap();
        log.extend_end_offset_to(grown_end).unwrap();
        assert_eq!(log.current_end_offset(), grown_end);
        let generation = log.generation();
        drop(log);
        assert_eq!(generation, reopen(&path, 8, StorageKind::F32).generation());
    }

    #[test]
    fn discard_unacked_tail_drops_phantom_frames_before_reopen() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(1, 8);
        let (_, acked_end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "acked",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        let phantom = encoded_add("phantom", &vector);
        append_raw_bytes(&mut log, &phantom);
        assert_eq!(
            std::fs::metadata(&path).unwrap().len(),
            acked_end + phantom.len() as u64
        );
        log.discard_unacked_tail().unwrap();
        assert_eq!(std::fs::metadata(&path).unwrap().len(), acked_end);
        drop(log);
        let mut reopened = reopen(&path, 8, StorageKind::F32);
        let (records, recoverable_end) = scan_all(&mut reopened);
        assert_eq!(records.len(), 1);
        assert!(matches!(&records[0].0, LogRecord::Add { key, .. } if key == "acked"));
        assert_eq!(recoverable_end, acked_end);
    }

    #[test]
    fn pending_rollback_truncates_stale_records_before_the_next_append() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(6, 8);
        let (_, acked_end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "acked",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        let stale = encoded_add("stale-with-a-much-longer-key", &vector);
        append_raw_bytes(&mut log, &stale);
        assert_eq!(
            std::fs::metadata(&path).unwrap().len(),
            acked_end + stale.len() as u64
        );
        log.rollback_pending = true;
        let fresh = seeded_vector(7, 8);
        let (start, end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "fresh",
                vector: VectorPayload::F32(&fresh),
                attrs: &[],
            }],
        );
        assert!(!log.rollback_pending);
        assert_eq!(start, acked_end);
        assert!(end < acked_end + stale.len() as u64);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), end);
        drop(log);
        let mut reopened = reopen(&path, 8, StorageKind::F32);
        let (records, recoverable_end) = scan_all(&mut reopened);
        assert_eq!(records.len(), 2);
        assert!(matches!(&records[0].0, LogRecord::Add { key, .. } if key == "acked"));
        assert!(matches!(&records[1].0, LogRecord::Add { key, vector, .. }
            if key == "fresh" && vector == &StoredVector::F32(fresh.clone())));
        assert_eq!(records[1].1, acked_end);
        assert_eq!(recoverable_end, end);
    }

    #[test]
    fn unsynced_staging_appends_produce_bytes_identical_to_synced_appends() {
        let dir = TempDir::new().unwrap();
        let synced_path = dir.path().join("synced");
        let staged_path = dir.path().join("staged");
        let mut synced = Log::create(&synced_path, 8, StorageKind::F32, None).unwrap();
        let mut staged = Log::create(&staged_path, 8, StorageKind::F32, None).unwrap();
        let vectors: Vec<Vec<f32>> = (0..3).map(|seed| seeded_vector(seed, 8)).collect();
        let attrs = [Attribute {
            name: "model".to_string(),
            value: AttrValue::Str("v1".to_string()),
        }];
        let batches: Vec<Vec<LogEntry<'_>>> = vec![
            vec![
                LogEntry::Add {
                    key: "a",
                    vector: VectorPayload::F32(&vectors[0]),
                    attrs: &[],
                },
                LogEntry::Add {
                    key: "b",
                    vector: VectorPayload::F32(&vectors[1]),
                    attrs: &attrs,
                },
            ],
            vec![
                LogEntry::Tombstone { key: "a" },
                LogEntry::Add {
                    key: "c",
                    vector: VectorPayload::F32(&vectors[2]),
                    attrs: &[],
                },
            ],
        ];
        for batch in &batches {
            synced.append(batch).unwrap();
            staged.append_unsynced_for_staging(batch).unwrap();
        }
        assert_eq!(staged.current_end_offset(), synced.current_end_offset());
        staged.sync_all().unwrap();
        drop(staged);
        drop(synced);
        let synced_bytes = std::fs::read(&synced_path).unwrap();
        let staged_bytes = std::fs::read(&staged_path).unwrap();
        assert_eq!(staged_bytes.len(), synced_bytes.len());
        assert_eq!(staged_bytes[HEADER_LEN..], synced_bytes[HEADER_LEN..]);
        let (synced_records, synced_end) = scan_all(&mut reopen(&synced_path, 8, StorageKind::F32));
        let (staged_records, staged_end) = scan_all(&mut reopen(&staged_path, 8, StorageKind::F32));
        assert_eq!(staged_records.len(), 4);
        assert_eq!(staged_records, synced_records);
        assert_eq!(staged_end, synced_end);
    }

    #[test]
    fn append_failure_rolls_back_without_disturbing_acked_records() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(2, 8);
        let (_, acked_end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "kept",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        drop(log);
        let unwritable = File::open(&path).unwrap();
        let mut log = Log::open(unwritable, &path, 8, StorageKind::F32, None).unwrap();
        assert!(matches!(
            log.append(&[LogEntry::Add {
                key: "lost",
                vector: VectorPayload::F32(&vector),
                attrs: &[]
            }]),
            Err(VecDbError::Io { .. })
        ));
        assert_eq!(log.current_end_offset(), acked_end);
        drop(log);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), acked_end);
        let mut reopened = reopen(&path, 8, StorageKind::F32);
        let (records, _) = scan_all(&mut reopened);
        assert_eq!(records.len(), 1);
        assert!(matches!(&records[0].0, LogRecord::Add { key, .. } if key == "kept"));
    }

    #[test]
    fn append_after_phantom_frames_overwrites_at_the_acked_offset() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(3, 8);
        let (_, acked_end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "first",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }],
        );
        append_raw_bytes(&mut log, &encoded_add("ghost", &vector));
        let replacement = seeded_vector(4, 8);
        let (start, end) = append_bounds(
            &mut log,
            &[LogEntry::Add {
                key: "third",
                vector: VectorPayload::F32(&replacement),
                attrs: &[],
            }],
        );
        assert_eq!(start, acked_end);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 2);
        assert_eq!(records[1].1, acked_end);
        assert!(matches!(&records[1].0, LogRecord::Add { key, .. } if key == "third"));
        assert_eq!(recoverable_end, end);
        drop(log);
        let mut reopened = reopen(&path, 8, StorageKind::F32);
        let (records, _) = scan_all(&mut reopened);
        assert_eq!(records.len(), 2);
        assert!(
            records
                .iter()
                .all(|(record, _)| !matches!(record, LogRecord::Add { key, .. } if key == "ghost"))
        );
    }

    #[test]
    fn scanner_stops_at_corrupted_middle_record() {
        let dir = TempDir::new().unwrap();
        let build_path = dir.path().join("log");
        let mut log = Log::create(&build_path, 8, StorageKind::F32, None).unwrap();
        let vectors: Vec<Vec<f32>> = (0..3).map(|seed| seeded_vector(seed, 8)).collect();
        let mut boundaries = Vec::new();
        for (index, vector) in vectors.iter().enumerate() {
            let key = format!("key-{index}");
            boundaries.push(append_bounds(
                &mut log,
                &[LogEntry::Add {
                    key: &key,
                    vector: VectorPayload::F32(vector),
                    attrs: &[],
                }],
            ));
        }
        drop(log);
        let bytes = std::fs::read(&build_path).unwrap();
        let middle_start = boundaries[1].0 as usize;
        let key_len = "key-1".len();
        let payload_len = 8 * size_of::<f32>();
        let corrupt_positions = [
            middle_start + RECORD_PREFIX_LEN,
            middle_start + RECORD_PREFIX_LEN + key_len,
            middle_start + RECORD_PREFIX_LEN + key_len + payload_len,
        ];
        for (index, position) in corrupt_positions.iter().enumerate() {
            let corrupt_path = dir.path().join(format!("corrupt-{index}"));
            let mut corrupted = bytes.clone();
            corrupted[*position] ^= 0x01;
            std::fs::write(&corrupt_path, &corrupted).unwrap();
            let mut corrupt_log = reopen(&corrupt_path, 8, StorageKind::F32);
            let (records, recoverable_end) = scan_all(&mut corrupt_log);
            assert_eq!(records.len(), 1);
            assert_eq!(records[0].1, boundaries[0].0);
            assert_eq!(recoverable_end, boundaries[1].0);
        }
    }

    #[test]
    fn scanner_stops_at_malformed_records() {
        let dims = 8usize;
        let vector = seeded_vector(3, dims);
        let mut good = Vec::new();
        encode_record_into(
            &mut good,
            &LogEntry::Add {
                key: "good",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            },
        );
        let payload: Vec<u8> = vector
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        let malformed = [
            raw_record(3, 4, b"keyy", &[]),
            raw_record(RECORD_TYPE_TOMBSTONE, 0, &[], &[]),
            raw_record(RECORD_TYPE_ADD, 257, &[b'k'; 257], &payload),
            raw_record(RECORD_TYPE_TOMBSTONE, 2, &[0xFF, 0xFE], &[]),
            vec![RECORD_TYPE_ADD, 200, 0, b'a', b'b', b'c'],
        ];
        let dir = TempDir::new().unwrap();
        for (index, bad) in malformed.iter().enumerate() {
            let path = dir.path().join(format!("malformed-{index}"));
            let mut record_bytes = good.clone();
            record_bytes.extend_from_slice(bad);
            write_log_file(&path, dims as u32, &record_bytes);
            let mut log = reopen(&path, dims, StorageKind::F32);
            let (records, recoverable_end) = scan_all(&mut log);
            assert_eq!(records.len(), 1);
            assert_eq!(records[0].1, HEADER_LEN as u64);
            assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        }
    }

    #[test]
    fn append_offsets_match_scanner_offsets() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        log.append(&[]).unwrap();
        assert_eq!(log.current_end_offset(), HEADER_LEN as u64);
        let vector = seeded_vector(7, 8);
        let mut expected_offsets = Vec::new();
        let mut previous_end = HEADER_LEN as u64;
        for index in 0..5u32 {
            let key = format!("entry-{index}");
            let (start, end) = append_bounds(
                &mut log,
                &[LogEntry::Add {
                    key: &key,
                    vector: VectorPayload::F32(&vector),
                    attrs: &[],
                }],
            );
            assert_eq!(start, previous_end);
            expected_offsets.push(start);
            previous_end = end;
        }
        assert_eq!(log.current_end_offset(), previous_end);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), previous_end);
        let (records, recoverable_end) = scan_all(&mut log);
        let offsets: Vec<u64> = records.iter().map(|(_, offset)| *offset).collect();
        assert_eq!(offsets, expected_offsets);
        assert_eq!(recoverable_end, previous_end);
        drop(log);
        let reopened = reopen(&path, 8, StorageKind::F32);
        assert_eq!(reopened.current_end_offset(), previous_end);
    }

    #[test]
    fn append_validates_keys_and_vector_dims() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(1, 8);
        let wrong_dims = seeded_vector(1, 16);
        assert!(matches!(
            log.append(&[LogEntry::Add {
                key: "",
                vector: VectorPayload::F32(&vector),
                attrs: &[]
            }]),
            Err(VecDbError::InvalidKey(_))
        ));
        assert!(matches!(
            log.append(&[LogEntry::Add {
                key: "ok",
                vector: VectorPayload::F32(&wrong_dims),
                attrs: &[]
            }]),
            Err(VecDbError::DimensionMismatch {
                expected: 8,
                actual: 16
            })
        ));
        assert!(
            log.append(&[
                LogEntry::Add {
                    key: "good",
                    vector: VectorPayload::F32(&vector),
                    attrs: &[]
                },
                LogEntry::Tombstone { key: "" }
            ])
            .is_err()
        );
        assert_eq!(log.current_end_offset(), HEADER_LEN as u64);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), HEADER_LEN as u64);
        let (records, _) = scan_all(&mut log);
        assert!(records.is_empty());
    }

    #[test]
    fn generation_is_distinct_across_creates() {
        let dir = TempDir::new().unwrap();
        let first = Log::create(&dir.path().join("first"), 8, StorageKind::F32, None).unwrap();
        let second = Log::create(&dir.path().join("second"), 8, StorageKind::F32, None).unwrap();
        assert_ne!(first.generation(), second.generation());
    }

    #[test]
    fn temp_sibling_gets_fresh_generation_and_replaces_stale_tmp() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let stale_path = dir.path().join("log.tmp");
        std::fs::write(&stale_path, b"stale leftover").unwrap();
        let (temp_log, temp_path) =
            Log::create_temp_sibling(&path, 8, StorageKind::F32, None).unwrap();
        assert_eq!(temp_path, stale_path);
        assert_ne!(temp_log.generation(), log.generation());
        assert_eq!(temp_log.current_end_offset(), HEADER_LEN as u64);
        assert_eq!(
            std::fs::metadata(&temp_path).unwrap().len(),
            HEADER_LEN as u64
        );
        let temp_generation = temp_log.generation();
        drop(temp_log);
        let reopened = reopen(&temp_path, 8, StorageKind::F32);
        assert_eq!(reopened.generation(), temp_generation);
    }

    #[test]
    fn large_bulk_append_matches_sequential_framing() {
        let dims = 512usize;
        let dir = TempDir::new().unwrap();
        let bulk_path = dir.path().join("bulk");
        let sequential_path = dir.path().join("sequential");
        let vectors: Vec<Vec<f32>> = (0..40).map(|seed| seeded_vector(seed, dims)).collect();
        let keys: Vec<String> = (0..40)
            .map(|index| format!("bulk-key-{index:03}"))
            .collect();
        let entries: Vec<LogEntry<'_>> = keys
            .iter()
            .zip(&vectors)
            .map(|(key, vector)| LogEntry::Add {
                key,
                vector: VectorPayload::F32(vector),
                attrs: &[],
            })
            .collect();
        let mut bulk_log = Log::create(&bulk_path, dims, StorageKind::F32, None).unwrap();
        let mut sequential_log =
            Log::create(&sequential_path, dims, StorageKind::F32, None).unwrap();
        let (_, bulk_end) = append_bounds(&mut bulk_log, &entries);
        let mut sequential_end = 0;
        for entry in &entries {
            sequential_end = append_bounds(&mut sequential_log, std::slice::from_ref(entry)).1;
        }
        assert_eq!(bulk_end, sequential_end);
        assert!(bulk_end - HEADER_LEN as u64 > ENCODE_FLUSH_BYTES as u64);
        assert!(bulk_log.encode_buffer.capacity() <= 2 * ENCODE_FLUSH_BYTES);
        assert_eq!(
            std::fs::read(&bulk_path).unwrap()[HEADER_LEN..],
            std::fs::read(&sequential_path).unwrap()[HEADER_LEN..]
        );
        assert_eq!(scan_all(&mut bulk_log), scan_all(&mut sequential_log));
    }

    #[test]
    fn bulk_append_framing_equals_sequential_appends() {
        let dir = TempDir::new().unwrap();
        let bulk_path = dir.path().join("bulk");
        let sequential_path = dir.path().join("sequential");
        let vectors: Vec<Vec<f32>> = (0..4).map(|seed| seeded_vector(seed, 8)).collect();
        let entries = vec![
            LogEntry::Add {
                key: "a",
                vector: VectorPayload::F32(&vectors[0]),
                attrs: &[],
            },
            LogEntry::Tombstone { key: "b" },
            LogEntry::Add {
                key: "c",
                vector: VectorPayload::F32(&vectors[2]),
                attrs: &[],
            },
            LogEntry::Add {
                key: "d",
                vector: VectorPayload::F32(&vectors[3]),
                attrs: &[],
            },
        ];
        let mut bulk_log = Log::create(&bulk_path, 8, StorageKind::F32, None).unwrap();
        let mut sequential_log = Log::create(&sequential_path, 8, StorageKind::F32, None).unwrap();
        let (bulk_start, bulk_end) = append_bounds(&mut bulk_log, &entries);
        let mut sequential_end = 0;
        for entry in &entries {
            sequential_end = append_bounds(&mut sequential_log, std::slice::from_ref(entry)).1;
        }
        assert_eq!(bulk_start, HEADER_LEN as u64);
        assert_eq!(bulk_end, sequential_end);
        let bulk_bytes = std::fs::read(&bulk_path).unwrap();
        let sequential_bytes = std::fs::read(&sequential_path).unwrap();
        assert_eq!(bulk_bytes[HEADER_LEN..], sequential_bytes[HEADER_LEN..]);
        assert_eq!(scan_all(&mut bulk_log), scan_all(&mut sequential_log));
    }

    fn attr(name: &str, value: AttrValue) -> Attribute {
        Attribute {
            name: name.to_string(),
            value,
        }
    }

    fn scan_attrs_of_single_add(log: &mut Log) -> Vec<Attribute> {
        let (records, _) = scan_all(log);
        assert_eq!(records.len(), 1);
        let LogRecord::Add { attrs, .. } = records[0].0.clone() else {
            panic!("expected an add record");
        };
        attrs
    }

    #[test]
    fn attr_records_round_trip_every_type_in_caller_order() {
        let full_set = vec![
            attr("zulu", AttrValue::I64(i64::MIN)),
            attr("alpha", AttrValue::Str(String::new())),
            attr("mike", AttrValue::Bool(false)),
            attr("delta", AttrValue::F64(-0.0)),
        ];
        let singles: Vec<Vec<Attribute>> = vec![
            vec![attr("s", AttrValue::Str("héllo-🔑".to_string()))],
            vec![attr("b", AttrValue::Bool(true))],
            vec![attr("i", AttrValue::I64(-1))],
            vec![attr("f", AttrValue::F64(f64::MAX))],
            Vec::new(),
        ];
        let dir = TempDir::new().unwrap();
        let vector = seeded_vector(8, 8);
        for (index, attrs) in singles.iter().chain([&full_set]).enumerate() {
            let path = dir.path().join(format!("log-{index}"));
            let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
            log.append(&[LogEntry::Add {
                key: "k",
                vector: VectorPayload::F32(&vector),
                attrs,
            }])
            .unwrap();
            assert_eq!(&scan_attrs_of_single_add(&mut log), attrs);
            drop(log);
            let mut reopened = reopen(&path, 8, StorageKind::F32);
            assert_eq!(&scan_attrs_of_single_add(&mut reopened), attrs);
        }
    }

    #[test]
    fn attr_boundary_sizes_round_trip() {
        let cases = [
            vec![attr(&"n".repeat(64), AttrValue::Bool(true))],
            vec![attr("s", AttrValue::Str("v".repeat(1024)))],
            (0..16)
                .map(|index| attr(&format!("a{index:02}"), AttrValue::I64(index)))
                .collect::<Vec<_>>(),
            ["a", "b", "c", "d"]
                .iter()
                .map(|name| attr(name, AttrValue::Str("x".repeat(1019))))
                .collect::<Vec<_>>(),
        ];
        assert_eq!(
            cases[3].iter().map(encoded_attr_len).sum::<usize>(),
            MAX_ATTRS_TOTAL_BYTES
        );
        let dir = TempDir::new().unwrap();
        let vector = seeded_vector(9, 8);
        for (index, attrs) in cases.iter().enumerate() {
            let path = dir.path().join(format!("log-{index}"));
            let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
            log.append(&[LogEntry::Add {
                key: "k",
                vector: VectorPayload::F32(&vector),
                attrs,
            }])
            .unwrap();
            assert_eq!(&scan_attrs_of_single_add(&mut log), attrs);
        }
    }

    #[test]
    fn append_rejects_attrs_beyond_the_caps() {
        let over_total: Vec<Attribute> = ["a", "b", "c"]
            .iter()
            .map(|name| attr(name, AttrValue::Str("x".repeat(1019))))
            .chain([attr("e", AttrValue::Str("x".repeat(1020)))])
            .collect();
        assert_eq!(
            over_total.iter().map(encoded_attr_len).sum::<usize>(),
            MAX_ATTRS_TOTAL_BYTES + 1
        );
        let invalid: Vec<Vec<Attribute>> = vec![
            (0..17)
                .map(|index| attr(&format!("a{index:02}"), AttrValue::Bool(true)))
                .collect(),
            vec![attr("", AttrValue::Bool(true))],
            vec![attr(&"n".repeat(65), AttrValue::Bool(true))],
            vec![attr("s", AttrValue::Str("v".repeat(1025)))],
            over_total,
            vec![
                attr("same", AttrValue::Bool(true)),
                attr("other", AttrValue::I64(1)),
                attr("same", AttrValue::Str("again".to_string())),
            ],
        ];
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut log = Log::create(&path, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(10, 8);
        for attrs in &invalid {
            assert!(matches!(
                log.append(&[LogEntry::Add {
                    key: "k",
                    vector: VectorPayload::F32(&vector),
                    attrs,
                }]),
                Err(VecDbError::InvalidAttributes(_))
            ));
            assert!(matches!(
                log.append(&[
                    LogEntry::Add {
                        key: "good",
                        vector: VectorPayload::F32(&vector),
                        attrs: &[],
                    },
                    LogEntry::Add {
                        key: "bad",
                        vector: VectorPayload::F32(&vector),
                        attrs,
                    }
                ]),
                Err(VecDbError::InvalidAttributes(_))
            ));
        }
        assert_eq!(log.current_end_offset(), HEADER_LEN as u64);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), HEADER_LEN as u64);
    }

    #[test]
    fn non_finite_f64_attrs_round_trip_bit_exactly() {
        let payloads = [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, -0.0];
        let attrs: Vec<Attribute> = payloads
            .iter()
            .enumerate()
            .map(|(index, value)| attr(&format!("f{index}"), AttrValue::F64(*value)))
            .collect();
        let dir = TempDir::new().unwrap();
        let mut log = Log::create(&dir.path().join("log"), 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(11, 8);
        log.append(&[LogEntry::Add {
            key: "k",
            vector: VectorPayload::F32(&vector),
            attrs: &attrs,
        }])
        .unwrap();
        let decoded = scan_attrs_of_single_add(&mut log);
        assert_eq!(decoded.len(), payloads.len());
        for (entry, expected) in decoded.iter().zip(&payloads) {
            let AttrValue::F64(value) = entry.value else {
                panic!("expected an f64 attribute");
            };
            assert_eq!(value.to_bits(), expected.to_bits());
        }
    }

    #[test]
    fn scanner_stops_at_malformed_attr_records() {
        let dims = 8usize;
        let vector = seeded_vector(12, dims);
        let mut good = Vec::new();
        encode_record_into(
            &mut good,
            &LogEntry::Add {
                key: "good",
                vector: VectorPayload::F32(&vector),
                attrs: &[attr("kept", AttrValue::Bool(true))],
            },
        );
        let vector_bytes: Vec<u8> = vector
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        let encoded_attr = |name: &[u8], tag: u8, value: &[u8]| {
            let mut bytes = vec![name.len() as u8];
            bytes.extend_from_slice(name);
            bytes.push(tag);
            bytes.extend_from_slice(value);
            bytes
        };
        let str_value = |len: usize| {
            let mut bytes = (len as u16).to_le_bytes().to_vec();
            bytes.extend_from_slice(&vec![b'v'; len]);
            bytes
        };
        let with_attrs = |attr_bytes: &[u8]| {
            let mut payload = vector_bytes.clone();
            payload.extend_from_slice(attr_bytes);
            raw_record(RECORD_TYPE_ADD, 2, b"k1", &payload)
        };
        let five_over_total: Vec<u8> = {
            let mut bytes = vec![5u8];
            for name in [b"a", b"b", b"c", b"d", b"e"] {
                bytes.extend_from_slice(&encoded_attr(name, ATTR_TAG_STR, &str_value(1019)));
            }
            bytes
        };
        let oversized_name: Vec<u8> = {
            let mut bytes = vec![1u8];
            bytes.extend_from_slice(&encoded_attr(&[b'n'; 65], ATTR_TAG_BOOL, &[1]));
            bytes
        };
        let malformed = [
            with_attrs(&[17]),
            with_attrs(&[1, 0, ATTR_TAG_BOOL, 1]),
            with_attrs(&oversized_name),
            with_attrs(&{
                let mut bytes = vec![1u8];
                bytes.extend_from_slice(&encoded_attr(b"t", 4, &[0; 8]));
                bytes
            }),
            with_attrs(&{
                let mut bytes = vec![1u8];
                bytes.extend_from_slice(&encoded_attr(b"s", ATTR_TAG_STR, &str_value(1025)));
                bytes
            }),
            with_attrs(&{
                let mut bytes = vec![1u8];
                bytes.extend_from_slice(&encoded_attr(b"b", ATTR_TAG_BOOL, &[2]));
                bytes
            }),
            with_attrs(&{
                let mut bytes = vec![1u8];
                bytes.extend_from_slice(&encoded_attr(&[0xFF, 0xFE], ATTR_TAG_BOOL, &[1]));
                bytes
            }),
            with_attrs(&five_over_total),
            with_attrs(&[2, 1, b'a', ATTR_TAG_BOOL, 1]),
            with_attrs(&[1]),
        ];
        let dir = TempDir::new().unwrap();
        for (index, bad) in malformed.iter().enumerate() {
            let path = dir.path().join(format!("malformed-{index}"));
            let mut record_bytes = good.clone();
            record_bytes.extend_from_slice(bad);
            write_log_file(&path, dims as u32, &record_bytes);
            let mut log = reopen(&path, dims, StorageKind::F32);
            let (records, recoverable_end) = scan_all(&mut log);
            assert_eq!(records.len(), 1, "case {index}");
            assert_eq!(records[0].1, HEADER_LEN as u64, "case {index}");
            assert_eq!(
                recoverable_end,
                HEADER_LEN as u64 + good.len() as u64,
                "case {index}"
            );
        }
    }

    #[test]
    fn scanner_stops_when_attrs_are_cut_by_the_log_end() {
        let dims = 8usize;
        let vector = seeded_vector(13, dims);
        let mut good = Vec::new();
        encode_record_into(
            &mut good,
            &LogEntry::Add {
                key: "good",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            },
        );
        let mut torn = Vec::new();
        encode_record_into(
            &mut torn,
            &LogEntry::Add {
                key: "torn",
                vector: VectorPayload::F32(&vector),
                attrs: &[
                    attr("first", AttrValue::Str("value".to_string())),
                    attr("second", AttrValue::I64(7)),
                ],
            },
        );
        let attrs_start = 3 + 4 + dims * size_of::<f32>();
        let dir = TempDir::new().unwrap();
        for cut in attrs_start..torn.len() {
            let path = dir.path().join(format!("cut-{cut}"));
            let mut record_bytes = good.clone();
            record_bytes.extend_from_slice(&torn[..cut]);
            write_log_file(&path, dims as u32, &record_bytes);
            let mut log = reopen(&path, dims, StorageKind::F32);
            let (records, recoverable_end) = scan_all(&mut log);
            assert_eq!(records.len(), 1, "cut {cut}");
            assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        }
    }

    #[test]
    fn tail_probe_finds_an_intact_record_beyond_mid_log_damage() {
        let dims = 8usize;
        let vector = seeded_vector(21, dims);
        let first = encoded_add("first", &vector);
        let mut tombstone = Vec::new();
        encode_record_into(&mut tombstone, &LogEntry::Tombstone { key: "gone" });
        let survivors = [encoded_add("second", &vector), tombstone];
        let dir = TempDir::new().unwrap();
        for (index, survivor) in survivors.iter().enumerate() {
            for garbage_len in [1usize, 7, 19] {
                let path = dir.path().join(format!("log-{index}-{garbage_len}"));
                let mut record_bytes = first.clone();
                record_bytes.extend_from_slice(&vec![0xAA; garbage_len]);
                record_bytes.extend_from_slice(survivor);
                write_log_file(&path, dims as u32, &record_bytes);
                let mut log = reopen(&path, dims, StorageKind::F32);
                let (records, recoverable_end) = scan_all(&mut log);
                assert_eq!(records.len(), 1);
                assert_eq!(recoverable_end, HEADER_LEN as u64 + first.len() as u64);
                assert!(log.tail_contains_valid_record(recoverable_end).unwrap());
            }
        }
    }

    #[test]
    fn tail_probe_rejects_regions_without_a_crc_valid_record() {
        let dims = 8usize;
        let vector = seeded_vector(22, dims);
        let good = encoded_add("good", &vector);
        let payload: Vec<u8> = vector
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        let mut crc_flipped_add = encoded_add("evil", &vector);
        *crc_flipped_add.last_mut().unwrap() ^= 0x01;
        let mut crc_flipped_tombstone = Vec::new();
        encode_record_into(
            &mut crc_flipped_tombstone,
            &LogEntry::Tombstone { key: "gone" },
        );
        *crc_flipped_tombstone.last_mut().unwrap() ^= 0x01;
        let mut oversized_key_payload = payload.clone();
        oversized_key_payload.push(0);
        let mut over_counted_attrs = payload;
        over_counted_attrs.push(17);
        let mut truncated = good.clone();
        truncated.pop();
        let tails = [
            vec![0xFF; 64],
            vec![0x00; 64],
            vec![0x01; 64],
            vec![0x02; 64],
            crc_flipped_add,
            crc_flipped_tombstone,
            raw_record(RECORD_TYPE_ADD, 257, &[b'k'; 257], &oversized_key_payload),
            raw_record(RECORD_TYPE_ADD, 2, b"k1", &over_counted_attrs),
            truncated,
            Vec::new(),
        ];
        let dir = TempDir::new().unwrap();
        for (index, tail) in tails.iter().enumerate() {
            let path = dir.path().join(format!("tail-{index}"));
            let mut record_bytes = good.clone();
            record_bytes.push(0xAA);
            record_bytes.extend_from_slice(tail);
            write_log_file(&path, dims as u32, &record_bytes);
            let mut log = reopen(&path, dims, StorageKind::F32);
            let (records, recoverable_end) = scan_all(&mut log);
            assert_eq!(records.len(), 1, "case {index}");
            assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
            assert!(
                !log.tail_contains_valid_record(recoverable_end).unwrap(),
                "case {index}"
            );
        }
    }

    #[test]
    fn windowed_probe_finds_the_only_valid_record_straddling_a_window_boundary() {
        let dims = 8usize;
        let step = 4096usize;
        let vector = seeded_vector(31, dims);
        let good = encoded_add("good", &vector);
        let straddler = encoded_add("straddler", &vector);
        let mut record_bytes = good.clone();
        record_bytes.extend_from_slice(&vec![0xAA; step - 19]);
        record_bytes.extend_from_slice(&straddler);
        record_bytes.extend_from_slice(&vec![0xAA; step + max_record_len(StorageKind::F32, dims)]);
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        write_log_file(&path, dims as u32, &record_bytes);
        let mut log = reopen(&path, dims, StorageKind::F32);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 1);
        assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        let straddler_start = (step - 20) as u64;
        let straddler_end = straddler_start + straddler.len() as u64;
        assert!(straddler_start < step as u64);
        assert!(straddler_end > step as u64);
        let tail_len = log.current_end_offset() - recoverable_end - 1;
        assert!(tail_len as usize > step + max_record_len(StorageKind::F32, dims) - 1);
        assert!(
            log.tail_contains_valid_record_windowed(recoverable_end, step)
                .unwrap()
        );
        assert!(log.tail_contains_valid_record(recoverable_end).unwrap());
    }

    #[test]
    fn windowed_probe_scans_an_all_garbage_multi_window_tail_without_a_false_positive() {
        let dims = 8usize;
        let step = 64usize;
        let vector = seeded_vector(32, dims);
        let good = encoded_add("good", &vector);
        let mut record_bytes = good.clone();
        record_bytes.extend_from_slice(&vec![
            0x01;
            3 * (step + max_record_len(StorageKind::F32, dims))
        ]);
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        write_log_file(&path, dims as u32, &record_bytes);
        let mut log = reopen(&path, dims, StorageKind::F32);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 1);
        assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        assert!(
            !log.tail_contains_valid_record_windowed(recoverable_end, step)
                .unwrap()
        );
        assert!(!log.tail_contains_valid_record(recoverable_end).unwrap());
    }

    #[test]
    fn windowed_probe_with_a_step_smaller_than_a_record_terminates_and_finds_a_straddler() {
        let dims = 8usize;
        let step = 4usize;
        let vector = seeded_vector(33, dims);
        let good = encoded_add("good", &vector);
        let straddler = encoded_add("straddler", &vector);
        assert!(step < straddler.len());
        let mut record_bytes = good.clone();
        record_bytes.extend_from_slice(&vec![0x01; 5000]);
        record_bytes.extend_from_slice(&straddler);
        record_bytes.extend_from_slice(&[0x01; 20]);
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        write_log_file(&path, dims as u32, &record_bytes);
        let mut log = reopen(&path, dims, StorageKind::F32);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 1);
        assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        let tail_len = log.current_end_offset() - recoverable_end - 1;
        assert!(tail_len as usize > step + max_record_len(StorageKind::F32, dims) - 1);
        assert!(
            log.tail_contains_valid_record_windowed(recoverable_end, step)
                .unwrap()
        );
        assert!(
            !log.tail_contains_valid_record_windowed(recoverable_end - 1 + tail_len, step)
                .unwrap()
        );
    }

    #[test]
    fn windowed_probe_sees_a_max_length_record_ending_exactly_at_the_window_visible_end() {
        let dims = 8usize;
        let step = 4096usize;
        let overlap = max_record_len(StorageKind::F32, dims) - 1;
        let vector = seeded_vector(34, dims);
        let good = encoded_add("good", &vector);
        let attrs: Vec<Attribute> = (b'a'..b'a' + 16)
            .map(|name| Attribute {
                name: (name as char).to_string(),
                value: AttrValue::Str("v".repeat(251)),
            })
            .collect();
        let key = "k".repeat(256);
        let mut max_record = Vec::new();
        encode_record_into(
            &mut max_record,
            &LogEntry::Add {
                key: &key,
                vector: VectorPayload::F32(&vector),
                attrs: &attrs,
            },
        );
        assert_eq!(max_record.len(), max_record_len(StorageKind::F32, dims));
        let mut record_bytes = good.clone();
        record_bytes.extend_from_slice(&vec![0xAA; step]);
        record_bytes.extend_from_slice(&max_record);
        record_bytes.extend_from_slice(&vec![0xAA; 256]);
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        write_log_file(&path, dims as u32, &record_bytes);
        let mut log = reopen(&path, dims, StorageKind::F32);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 1);
        assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        let record_tail_start = step - 1;
        assert_eq!(record_tail_start + max_record.len(), step + overlap);
        let tail_len = (log.current_end_offset() - recoverable_end - 1) as usize;
        assert!(tail_len > step + overlap);
        assert!(
            log.tail_contains_valid_record_windowed(recoverable_end, step)
                .unwrap()
        );
        assert!(log.tail_contains_valid_record(recoverable_end).unwrap());
        let mut corrupted_bytes = record_bytes.clone();
        let crc_last = good.len() + step + max_record.len() - 1;
        corrupted_bytes[crc_last] ^= 0xFF;
        let corrupted_path = dir.path().join("log-corrupted");
        write_log_file(&corrupted_path, dims as u32, &corrupted_bytes);
        let mut corrupted_log = reopen(&corrupted_path, dims, StorageKind::F32);
        let (corrupted_records, corrupted_end) = scan_all(&mut corrupted_log);
        assert_eq!(corrupted_records.len(), 1);
        assert!(
            !corrupted_log
                .tail_contains_valid_record_windowed(corrupted_end, step)
                .unwrap()
        );
    }

    fn encoded_i8_add(key: &str, scale: f32, values: &[i8]) -> Vec<u8> {
        let mut bytes = Vec::new();
        encode_record_into(
            &mut bytes,
            &LogEntry::Add {
                key,
                vector: VectorPayload::I8 { scale, values },
                attrs: &[],
            },
        );
        bytes
    }

    #[test]
    fn scanner_stops_at_an_int8_payload_outside_the_quantized_range() {
        let dims = 32usize;
        let scale = 0.25f32;
        let within_range = vec![3i8; dims];
        let mut beyond_range = vec![5i8; dims];
        beyond_range[7] = i8::MIN;
        let first = encoded_i8_add("first", scale, &within_range);
        let rejected = encoded_i8_add("rejected", scale, &beyond_range);
        let survivor = encoded_i8_add("survivor", scale, &within_range);
        let dir = TempDir::new().unwrap();
        let cases = [
            ("mid-log", [rejected.clone(), survivor].concat(), true),
            ("tail", rejected, false),
        ];
        for (name, after_first, intact_record_beyond) in cases {
            let path = dir.path().join(name);
            let mut bytes = encode_header(dims as u32, &[9u8; 16], StorageKind::I8).to_vec();
            bytes.extend_from_slice(&first);
            bytes.extend_from_slice(&after_first);
            std::fs::write(&path, &bytes).unwrap();
            let mut log = reopen(&path, dims, StorageKind::I8);
            let (records, recoverable_end) = scan_all(&mut log);
            assert_eq!(records.len(), 1);
            assert!(matches!(&records[0].0, LogRecord::Add { key, .. } if key == "first"));
            assert_eq!(recoverable_end, HEADER_LEN as u64 + first.len() as u64);
            assert_eq!(
                log.tail_contains_valid_record(recoverable_end).unwrap(),
                intact_record_beyond
            );
        }
    }

    fn write_i8_log_file(path: &Path, dims: u32, record_bytes: &[u8]) {
        let mut bytes = encode_header(dims, &[9u8; 16], StorageKind::I8).to_vec();
        bytes.extend_from_slice(record_bytes);
        std::fs::write(path, bytes).unwrap();
    }

    fn seeded_i8_values(seed: u64, dims: usize) -> Vec<i8> {
        let mut state = seed;
        (0..dims)
            .map(|_| (splitmix64(&mut state) % 255) as i64 as i8)
            .collect::<Vec<i8>>()
            .into_iter()
            .map(|value| value.max(-127))
            .collect()
    }

    fn golden_i8_values() -> Vec<i8> {
        let mut values: Vec<i8> = (0..32).map(|index| (index * 8 - 124) as i8).collect();
        values[0] = -127;
        values[1] = 127;
        values[2] = 0;
        values[3] = -1;
        values
    }

    #[test]
    fn i8_golden_bytes_pin_the_header_and_add_record() {
        let generation: [u8; 16] = std::array::from_fn(|index| index as u8);
        let golden_header: [u8; 32] = [
            0x45, 0x56, 0x44, 0x42, 0x01, 0x00, 0x01, 0x01, 0x20, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
            0xb1, 0x53, 0xb8, 0x5e,
        ];
        let golden_add: [u8; 46] = [
            0x01, 0x02, 0x00, 0x6b, 0x31, 0x0a, 0xd7, 0x23, 0x3c, 0x81, 0x7f, 0x00, 0xff, 0xa4,
            0xac, 0xb4, 0xbc, 0xc4, 0xcc, 0xd4, 0xdc, 0xe4, 0xec, 0xf4, 0xfc, 0x04, 0x0c, 0x14,
            0x1c, 0x24, 0x2c, 0x34, 0x3c, 0x44, 0x4c, 0x54, 0x5c, 0x64, 0x6c, 0x74, 0x7c, 0x00,
            0x72, 0x96, 0xfc, 0xa0,
        ];
        let scale = 0.01f32;
        assert_eq!(scale.to_bits(), 0x3c23_d70a);
        let values = golden_i8_values();
        let header = encode_header(32, &generation, StorageKind::I8);
        assert_eq!(header[STORAGE_TAG_OFFSET], 1);
        assert_eq!(header[..28], golden_header[..28]);
        let encoded = encoded_i8_add("k1", scale, &values);
        assert_eq!(encoded.len(), 46);
        assert_eq!(encoded[..42], golden_add[..42]);
        assert_eq!(header, golden_header);
        assert_eq!(encoded, golden_add);
        let mut tombstone = Vec::new();
        encode_record_into(&mut tombstone, &LogEntry::Tombstone { key: "k1" });
        assert_eq!(
            tombstone,
            [0x02, 0x02, 0x00, 0x6b, 0x31, 0xa0, 0xde, 0x3c, 0xc1]
        );
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let mut bytes = golden_header.to_vec();
        bytes.extend_from_slice(&golden_add);
        bytes.extend_from_slice(&tombstone);
        std::fs::write(&path, &bytes).unwrap();
        let mut log = reopen(&path, 32, StorageKind::I8);
        assert_eq!(log.storage(), StorageKind::I8);
        assert_eq!(log.generation(), generation);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(
            records,
            vec![
                (
                    LogRecord::Add {
                        key: "k1".to_string(),
                        vector: StoredVector::I8 { scale, values },
                        attrs: Vec::new()
                    },
                    32
                ),
                (
                    LogRecord::Tombstone {
                        key: "k1".to_string()
                    },
                    78
                )
            ]
        );
        assert_eq!(recoverable_end, 87);
    }

    #[test]
    fn f32_headers_leave_the_storage_tag_zero() {
        let header = encode_header(8, &[7u8; 16], StorageKind::F32);
        assert_eq!(header[STORAGE_TAG_OFFSET], 0);
        assert_eq!(header[METRIC_TAG_OFFSET], COSINE_METRIC_TAG);
        assert_eq!(
            decode_header(&header).unwrap(),
            Header {
                generation: [7u8; 16],
                dims: 8,
                storage: StorageKind::F32,
            }
        );
    }

    #[test]
    fn rejects_unknown_storage_tag() {
        for tag in [2u8, 3, 0x7f, 0xff] {
            let error = open_with_header(
                |bytes| {
                    bytes[STORAGE_TAG_OFFSET] = tag;
                    refresh_crc(bytes);
                },
                8,
            )
            .unwrap_err();
            assert!(matches!(&error, VecDbError::Corrupt(message) if message.contains("scalar")));
        }
    }

    #[test]
    fn storage_kind_round_trips_and_mismatches_are_reported() {
        let dir = TempDir::new().unwrap();
        let i8_path = dir.path().join("i8");
        let f32_path = dir.path().join("f32");
        let created = Log::create(&i8_path, 32, StorageKind::I8, None).unwrap();
        assert_eq!(created.storage(), StorageKind::I8);
        let generation = created.generation();
        drop(created);
        drop(Log::create(&f32_path, 32, StorageKind::F32, None).unwrap());
        let open = |path: &Path, requested: StorageKind| {
            let file = File::options().read(true).write(true).open(path).unwrap();
            Log::open(file, path, 32, requested, None)
        };
        let detected = open(&i8_path, StorageKind::I8).unwrap();
        assert_eq!(detected.storage(), StorageKind::I8);
        assert_eq!(detected.generation(), generation);
        assert_eq!(
            open(&i8_path, StorageKind::I8).unwrap().storage(),
            StorageKind::I8
        );
        assert!(matches!(
            open(&i8_path, StorageKind::F32),
            Err(VecDbError::StorageMismatch {
                expected: StorageKind::F32,
                actual: StorageKind::I8
            })
        ));
        assert_eq!(
            open(&f32_path, StorageKind::F32).unwrap().storage(),
            StorageKind::F32
        );
        assert!(matches!(
            open(&f32_path, StorageKind::I8),
            Err(VecDbError::StorageMismatch {
                expected: StorageKind::I8,
                actual: StorageKind::F32
            })
        ));
        assert_eq!(std::fs::read(&i8_path).unwrap()[STORAGE_TAG_OFFSET], 1);
        assert_eq!(std::fs::read(&f32_path).unwrap()[STORAGE_TAG_OFFSET], 0);
    }

    #[test]
    fn short_files_reinitialize_with_the_requested_storage() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        std::fs::write(&path, [1u8; 5]).unwrap();
        let file = File::options().read(true).write(true).open(&path).unwrap();
        let log = Log::open(file, &path, 64, StorageKind::I8, None).unwrap();
        assert_eq!(log.storage(), StorageKind::I8);
        drop(log);
        assert_eq!(
            reopen(&path, 64, StorageKind::I8).storage(),
            StorageKind::I8
        );
        let other = dir.path().join("other");
        std::fs::write(&other, [1u8; 5]).unwrap();
        let file = File::options().read(true).write(true).open(&other).unwrap();
        assert_eq!(
            Log::open(file, &other, 64, StorageKind::I8, None)
                .unwrap()
                .storage(),
            StorageKind::I8
        );
    }

    #[test]
    fn i8_logs_require_a_multiple_of_32_dims() {
        let dir = TempDir::new().unwrap();
        for dims in [8usize, 16, 24, 40] {
            assert!(matches!(
                Log::create(&dir.path().join(format!("a{dims}")), dims, StorageKind::I8, None),
                Err(VecDbError::InvalidDimensions {
                    dims: rejected,
                    storage: StorageKind::I8, ..
                }) if rejected == dims
            ));
            assert!(
                Log::create(
                    &dir.path().join(format!("b{dims}")),
                    dims,
                    StorageKind::F32,
                    None
                )
                .is_ok()
            );
        }
        assert!(Log::create(&dir.path().join("c"), 32, StorageKind::I8, None).is_ok());
        let path = dir.path().join("c");
        let file = File::options().read(true).write(true).open(&path).unwrap();
        assert!(matches!(
            Log::open(file, &path, 8, StorageKind::I8, None),
            Err(VecDbError::DimensionMismatch {
                expected: 8,
                actual: 32
            })
        ));
        let mut forged = encode_header(8, &[3u8; 16], StorageKind::I8);
        refresh_crc(&mut forged);
        let forged_path = dir.path().join("forged");
        std::fs::write(&forged_path, forged).unwrap();
        let file = File::options()
            .read(true)
            .write(true)
            .open(&forged_path)
            .unwrap();
        assert!(matches!(
            Log::open(file, &forged_path, 8, StorageKind::I8, None),
            Err(VecDbError::InvalidDimensions {
                dims: 8,
                storage: StorageKind::I8,
                ..
            })
        ));
    }

    #[test]
    fn i8_add_records_round_trip_bit_for_bit() {
        for dims in [32usize, 512] {
            let dir = TempDir::new().unwrap();
            let path = dir.path().join("log");
            let mut log = Log::create(&path, dims, StorageKind::I8, None).unwrap();
            let scales = [
                f32::from_bits(0x3a1f_8f3c),
                0.0,
                f32::NAN,
                -2.5,
                f32::MIN_POSITIVE,
            ];
            let mut expected = Vec::new();
            for (index, scale) in scales.iter().enumerate() {
                let mut values = seeded_i8_values(index as u64, dims);
                values[0] = -127;
                values[1] = 127;
                let key = format!("key-{index}");
                let (start, _) = append_bounds(
                    &mut log,
                    &[LogEntry::Add {
                        key: &key,
                        vector: VectorPayload::I8 {
                            scale: *scale,
                            values: &values,
                        },
                        attrs: &[],
                    }],
                );
                expected.push((key, *scale, values, start));
            }
            let (records, _) = scan_all(&mut log);
            assert_eq!(records.len(), scales.len());
            for ((record, offset), (key, scale, values, start)) in records.iter().zip(&expected) {
                assert_eq!(offset, start);
                let LogRecord::Add {
                    key: decoded_key,
                    vector:
                        StoredVector::I8 {
                            scale: decoded_scale,
                            values: decoded_values,
                        },
                    ..
                } = record
                else {
                    panic!("expected an i8 add record");
                };
                assert_eq!(decoded_key, key);
                assert_eq!(decoded_scale.to_bits(), scale.to_bits());
                assert_eq!(decoded_values, values);
            }
            drop(log);
            let (reopened, _) = scan_all(&mut reopen(&path, dims, StorageKind::I8));
            assert_eq!(reopened.len(), records.len());
            for ((record, offset), (again, again_offset)) in records.iter().zip(&reopened) {
                assert_eq!(offset, again_offset);
                assert_eq!(format!("{record:?}"), format!("{again:?}"));
            }
        }
    }

    #[test]
    fn payload_kind_must_match_the_log_storage() {
        let dir = TempDir::new().unwrap();
        let i8_path = dir.path().join("i8");
        let f32_path = dir.path().join("f32");
        let mut i8_log = Log::create(&i8_path, 32, StorageKind::I8, None).unwrap();
        let mut f32_log = Log::create(&f32_path, 32, StorageKind::F32, None).unwrap();
        let values = seeded_vector(4, 32);
        let quantized = StoredVector::quantize(&values);
        assert!(matches!(
            i8_log.append(&[LogEntry::Add {
                key: "k",
                vector: VectorPayload::F32(&values),
                attrs: &[],
            }]),
            Err(VecDbError::StorageMismatch {
                expected: StorageKind::I8,
                actual: StorageKind::F32
            })
        ));
        assert!(matches!(
            f32_log.append(&[LogEntry::Add {
                key: "k",
                vector: quantized.as_payload(),
                attrs: &[],
            }]),
            Err(VecDbError::StorageMismatch {
                expected: StorageKind::F32,
                actual: StorageKind::I8
            })
        ));
        assert!(matches!(
            i8_log.append(&[LogEntry::Add {
                key: "k",
                vector: VectorPayload::I8 {
                    scale: 1.0,
                    values: &[1i8; 64],
                },
                attrs: &[],
            }]),
            Err(VecDbError::DimensionMismatch {
                expected: 32,
                actual: 64
            })
        ));
        assert_eq!(i8_log.current_end_offset(), HEADER_LEN as u64);
        assert_eq!(f32_log.current_end_offset(), HEADER_LEN as u64);
        assert_eq!(
            std::fs::metadata(&i8_path).unwrap().len(),
            HEADER_LEN as u64
        );
        assert_eq!(
            std::fs::metadata(&f32_path).unwrap().len(),
            HEADER_LEN as u64
        );
    }

    #[test]
    fn max_record_len_is_storage_aware() {
        let fixed = RECORD_PREFIX_LEN + MAX_KEY_BYTES + 1 + MAX_ATTRS_TOTAL_BYTES + RECORD_CRC_LEN;
        assert_eq!(max_record_len(StorageKind::F32, 32), fixed + 128);
        assert_eq!(max_record_len(StorageKind::I8, 32), fixed + 36);
        assert_eq!(max_record_len(StorageKind::F32, 512), fixed + 2048);
        assert_eq!(max_record_len(StorageKind::I8, 512), fixed + 516);
        assert_eq!(vector_payload_len(StorageKind::I8, 512), 516);
        assert_eq!(vector_payload_len(StorageKind::F32, 512), 2048);
    }

    #[test]
    fn i8_scanner_stops_at_every_torn_length_and_at_f32_sized_records() {
        let dims = 32usize;
        let dir = TempDir::new().unwrap();
        let build_path = dir.path().join("log");
        let mut log = Log::create(&build_path, dims, StorageKind::I8, None).unwrap();
        let mut boundaries = Vec::new();
        for index in 0..3u64 {
            let key = format!("key-{index}");
            let values = seeded_i8_values(index, dims);
            boundaries.push(append_bounds(
                &mut log,
                &[LogEntry::Add {
                    key: &key,
                    vector: VectorPayload::I8 {
                        scale: 0.25,
                        values: &values,
                    },
                    attrs: &[],
                }],
            ));
        }
        drop(log);
        let full_bytes = std::fs::read(&build_path).unwrap();
        let intact_end = boundaries[1].1;
        for cut in intact_end..boundaries[2].1 {
            let torn_path = dir.path().join(format!("torn-{cut}"));
            std::fs::write(&torn_path, &full_bytes[..cut as usize]).unwrap();
            let mut torn_log = reopen(&torn_path, dims, StorageKind::I8);
            let (records, recoverable_end) = scan_all(&mut torn_log);
            assert_eq!(records.len(), 2);
            assert_eq!(recoverable_end, intact_end);
        }
        let f32_sized = encoded_add("f32-sized", &seeded_vector(5, dims));
        let mut mixed = full_bytes[..intact_end as usize].to_vec();
        mixed.extend_from_slice(&f32_sized);
        let mixed_path = dir.path().join("mixed");
        std::fs::write(&mixed_path, &mixed).unwrap();
        let mut mixed_log = reopen(&mixed_path, dims, StorageKind::I8);
        let (records, recoverable_end) = scan_all(&mut mixed_log);
        assert_eq!(records.len(), 2);
        assert_eq!(recoverable_end, intact_end);
        assert!(
            !mixed_log
                .tail_contains_valid_record(recoverable_end)
                .unwrap()
        );
    }

    #[test]
    fn i8_tail_probe_finds_an_intact_record_beyond_mid_log_damage() {
        let dims = 32usize;
        let first = encoded_i8_add("first", 0.5, &seeded_i8_values(21, dims));
        let mut tombstone = Vec::new();
        encode_record_into(&mut tombstone, &LogEntry::Tombstone { key: "gone" });
        let survivors = [
            encoded_i8_add("second", 0.75, &seeded_i8_values(22, dims)),
            tombstone,
        ];
        let dir = TempDir::new().unwrap();
        for (index, survivor) in survivors.iter().enumerate() {
            for garbage_len in [1usize, 7, 19] {
                let path = dir.path().join(format!("log-{index}-{garbage_len}"));
                let mut record_bytes = first.clone();
                record_bytes.extend_from_slice(&vec![0xAA; garbage_len]);
                record_bytes.extend_from_slice(survivor);
                write_i8_log_file(&path, dims as u32, &record_bytes);
                let mut log = reopen(&path, dims, StorageKind::I8);
                assert_eq!(log.storage(), StorageKind::I8);
                let (records, recoverable_end) = scan_all(&mut log);
                assert_eq!(records.len(), 1);
                assert_eq!(recoverable_end, HEADER_LEN as u64 + first.len() as u64);
                assert!(log.tail_contains_valid_record(recoverable_end).unwrap());
            }
        }
    }

    #[test]
    fn i8_windowed_probe_sees_a_max_length_record_ending_exactly_at_the_window_visible_end() {
        let dims = 32usize;
        let step = 4096usize;
        let overlap = max_record_len(StorageKind::I8, dims) - 1;
        let good = encoded_i8_add("good", 0.5, &seeded_i8_values(34, dims));
        let attrs: Vec<Attribute> = (b'a'..b'a' + 16)
            .map(|name| Attribute {
                name: (name as char).to_string(),
                value: AttrValue::Str("v".repeat(251)),
            })
            .collect();
        let key = "k".repeat(256);
        let values = seeded_i8_values(35, dims);
        let mut max_record = Vec::new();
        encode_record_into(
            &mut max_record,
            &LogEntry::Add {
                key: &key,
                vector: VectorPayload::I8 {
                    scale: 0.125,
                    values: &values,
                },
                attrs: &attrs,
            },
        );
        assert_eq!(max_record.len(), max_record_len(StorageKind::I8, dims));
        assert!(max_record.len() < max_record_len(StorageKind::F32, dims));
        let mut record_bytes = good.clone();
        record_bytes.extend_from_slice(&vec![0xAA; step]);
        record_bytes.extend_from_slice(&max_record);
        record_bytes.extend_from_slice(&vec![0xAA; 256]);
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        write_i8_log_file(&path, dims as u32, &record_bytes);
        let mut log = reopen(&path, dims, StorageKind::I8);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 1);
        assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        let record_tail_start = step - 1;
        assert_eq!(record_tail_start + max_record.len(), step + overlap);
        let tail_len = (log.current_end_offset() - recoverable_end - 1) as usize;
        assert!(tail_len > step + overlap);
        assert!(
            log.tail_contains_valid_record_windowed(recoverable_end, step)
                .unwrap()
        );
        assert!(log.tail_contains_valid_record(recoverable_end).unwrap());
        let mut corrupted_bytes = record_bytes.clone();
        let crc_last = good.len() + step + max_record.len() - 1;
        corrupted_bytes[crc_last] ^= 0xFF;
        let corrupted_path = dir.path().join("log-corrupted");
        write_i8_log_file(&corrupted_path, dims as u32, &corrupted_bytes);
        let mut corrupted_log = reopen(&corrupted_path, dims, StorageKind::I8);
        let (corrupted_records, corrupted_end) = scan_all(&mut corrupted_log);
        assert_eq!(corrupted_records.len(), 1);
        assert!(
            !corrupted_log
                .tail_contains_valid_record_windowed(corrupted_end, step)
                .unwrap()
        );
    }

    #[test]
    fn i8_windowed_probe_finds_a_straddling_record_with_a_step_smaller_than_the_record() {
        let dims = 32usize;
        let step = 4usize;
        let good = encoded_i8_add("good", 0.5, &seeded_i8_values(36, dims));
        let straddler = encoded_i8_add("straddler", 0.5, &seeded_i8_values(37, dims));
        assert!(step < straddler.len());
        let mut record_bytes = good.clone();
        record_bytes.extend_from_slice(&vec![0x01; 5000]);
        record_bytes.extend_from_slice(&straddler);
        record_bytes.extend_from_slice(&[0x01; 20]);
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        write_i8_log_file(&path, dims as u32, &record_bytes);
        let mut log = reopen(&path, dims, StorageKind::I8);
        let (records, recoverable_end) = scan_all(&mut log);
        assert_eq!(records.len(), 1);
        assert_eq!(recoverable_end, HEADER_LEN as u64 + good.len() as u64);
        assert!(
            log.tail_contains_valid_record_windowed(recoverable_end, step)
                .unwrap()
        );
        let tail_len = log.current_end_offset() - recoverable_end - 1;
        assert!(
            !log.tail_contains_valid_record_windowed(recoverable_end - 1 + tail_len, step)
                .unwrap()
        );
    }

    fn test_cipher(seed: u8) -> Cipher {
        Cipher::new(&ente_core::crypto::Key::from_bytes([seed; 32]))
    }

    fn reopen_sealed(path: &Path, dims: usize, cipher: Option<&Cipher>) -> Result<Log, VecDbError> {
        let file = open_writer_file(path, false).unwrap();
        Log::open(file, path, dims, StorageKind::F32, cipher)
    }

    fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
        haystack
            .windows(needle.len())
            .any(|window| window == needle)
    }

    fn assert_mismatch(opened: Result<Log, VecDbError>, expected: EncryptionMismatch) {
        assert!(
            matches!(opened, Err(VecDbError::Encryption { mismatch, .. }) if mismatch == expected)
        );
    }

    fn sealed_log_with_adds(path: &Path, cipher: &Cipher, count: usize) -> Vec<(u64, u64)> {
        let mut log = Log::create(path, 8, StorageKind::F32, Some(cipher)).unwrap();
        (0..count)
            .map(|index| {
                let key = format!("key-{index}");
                let vector = seeded_vector(index as u64, 8);
                append_bounds(
                    &mut log,
                    &[LogEntry::Add {
                        key: &key,
                        vector: VectorPayload::F32(&vector),
                        attrs: &[],
                    }],
                )
            })
            .collect()
    }

    #[test]
    fn sealed_records_round_trip_without_plaintext_on_disk() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let cipher = test_cipher(1);
        let mut log = Log::create(&path, 8, StorageKind::F32, Some(&cipher)).unwrap();
        assert_eq!(log.current_end_offset(), SEALED_HEADER_LEN as u64);
        let vector = seeded_vector(3, 8);
        let attrs = vec![Attribute {
            name: "label".into(),
            value: AttrValue::Str("needle".into()),
        }];
        let entries = [
            LogEntry::Add {
                key: "alpha",
                vector: VectorPayload::F32(&vector),
                attrs: &attrs,
            },
            LogEntry::Tombstone { key: "beta" },
            LogEntry::Add {
                key: "gamma",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            },
        ];
        let (first, _) = append_bounds(&mut log, &entries[..1]);
        let (second, end) = append_bounds(&mut log, &entries[1..]);
        assert_eq!(first, SEALED_HEADER_LEN as u64);
        assert_eq!(
            second - first,
            add_record_len("alpha", 8, StorageKind::F32, &attrs) + log.record_overhead()
        );
        drop(log);
        let mut reopened = reopen_sealed(&path, 8, Some(&cipher)).unwrap();
        let (records, recoverable_end) = scan_all(&mut reopened);
        assert_eq!(
            records
                .iter()
                .map(|(record, _)| record.clone())
                .collect::<Vec<_>>(),
            entries.iter().map(expected_record).collect::<Vec<_>>()
        );
        assert_eq!(records[0].1, first);
        assert_eq!(records[1].1, second);
        assert_eq!(recoverable_end, end);
        let bytes = std::fs::read(&path).unwrap();
        assert_eq!(bytes[..4], SEALED_MAGIC);
        let vector_bytes: Vec<u8> = vector[..2]
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        for needle in [
            &b"alpha"[..],
            b"beta",
            b"gamma",
            b"label",
            b"needle",
            &vector_bytes,
        ] {
            assert!(!contains_bytes(&bytes, needle));
        }
    }

    #[test]
    fn sealed_header_reports_wrong_keys_and_corruption_separately() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let cipher = test_cipher(2);
        sealed_log_with_adds(&path, &cipher, 1);
        let clean = std::fs::read(&path).unwrap();
        assert_mismatch(
            reopen_sealed(&path, 8, Some(&test_cipher(3))),
            EncryptionMismatch::WrongKey,
        );
        assert_mismatch(
            reopen_sealed(&path, 8, None),
            EncryptionMismatch::MissingKey,
        );
        assert_eq!(std::fs::read(&path).unwrap(), clean);

        let mut corrupted = clean.clone();
        corrupted[8] ^= 0x01;
        std::fs::write(&path, &corrupted).unwrap();
        assert!(matches!(
            reopen_sealed(&path, 8, Some(&cipher)),
            Err(VecDbError::Corrupt(_))
        ));

        let mut retagged = clean;
        retagged[HEADER_FIELDS_LEN + NONCE_LEN] ^= 0x01;
        let crc_start = SEALED_HEADER_LEN - HEADER_CRC_LEN;
        let crc = crc32(&retagged[..crc_start]);
        retagged[crc_start..SEALED_HEADER_LEN].copy_from_slice(&crc.to_le_bytes());
        std::fs::write(&path, &retagged).unwrap();
        assert_mismatch(
            reopen_sealed(&path, 8, Some(&cipher)),
            EncryptionMismatch::WrongKey,
        );
        assert_eq!(std::fs::read(&path).unwrap(), retagged);
    }

    #[test]
    fn plaintext_logs_refuse_a_key_and_short_files_follow_their_magic() {
        let dir = TempDir::new().unwrap();
        let cipher = test_cipher(4);

        let plain = dir.path().join("plain");
        drop(Log::create(&plain, 8, StorageKind::F32, None).unwrap());
        let plain_bytes = std::fs::read(&plain).unwrap();
        assert_mismatch(
            reopen_sealed(&plain, 8, Some(&cipher)),
            EncryptionMismatch::UnexpectedKey,
        );
        assert_eq!(std::fs::read(&plain).unwrap(), plain_bytes);

        let torn_plain = dir.path().join("torn-plain");
        std::fs::write(&torn_plain, &plain_bytes[..10]).unwrap();
        assert_mismatch(
            reopen_sealed(&torn_plain, 8, Some(&cipher)),
            EncryptionMismatch::UnexpectedKey,
        );
        assert_eq!(std::fs::read(&torn_plain).unwrap(), plain_bytes[..10]);

        let sealed = dir.path().join("sealed");
        drop(Log::create(&sealed, 8, StorageKind::F32, Some(&cipher)).unwrap());
        let sealed_bytes = std::fs::read(&sealed).unwrap();
        for cut in [
            4,
            14,
            SEALED_HEADER_LEN - HEADER_CRC_LEN,
            SEALED_HEADER_LEN - 1,
        ] {
            let torn_sealed = dir.path().join(format!("torn-sealed-{cut}"));
            std::fs::write(&torn_sealed, &sealed_bytes[..cut]).unwrap();
            assert_mismatch(
                reopen_sealed(&torn_sealed, 8, None),
                EncryptionMismatch::MissingKey,
            );
            for key in [&cipher, &test_cipher(5)] {
                assert!(matches!(
                    reopen_sealed(&torn_sealed, 8, Some(key)),
                    Err(VecDbError::Corrupt(_))
                ));
            }
            assert_eq!(std::fs::read(&torn_sealed).unwrap(), sealed_bytes[..cut]);
        }

        let stub = dir.path().join("stub");
        std::fs::write(&stub, [0u8; 2]).unwrap();
        let created = reopen_sealed(&stub, 8, Some(&cipher)).unwrap();
        assert_eq!(created.current_end_offset(), SEALED_HEADER_LEN as u64);
        assert_eq!(std::fs::read(&stub).unwrap()[..4], SEALED_MAGIC);
    }

    #[test]
    fn sealed_scanner_stops_at_the_last_complete_frame_for_every_torn_length() {
        let dir = TempDir::new().unwrap();
        let build_path = dir.path().join("log");
        let cipher = test_cipher(5);
        let boundaries = sealed_log_with_adds(&build_path, &cipher, 3);
        let full_bytes = std::fs::read(&build_path).unwrap();
        let intact_end = boundaries[1].1;
        for cut in intact_end..boundaries[2].1 {
            let torn_path = dir.path().join(format!("torn-{cut}"));
            std::fs::write(&torn_path, &full_bytes[..cut as usize]).unwrap();
            let mut torn_log = reopen_sealed(&torn_path, 8, Some(&cipher)).unwrap();
            let (records, recoverable_end) = scan_all(&mut torn_log);
            assert_eq!(records.len(), 2);
            assert_eq!(records[1].1, boundaries[1].0);
            assert_eq!(recoverable_end, intact_end);
            assert!(
                !torn_log
                    .tail_contains_valid_record(recoverable_end)
                    .unwrap()
            );
        }
    }

    #[test]
    fn sealed_frames_are_bound_to_their_offset_and_their_log() {
        let dir = TempDir::new().unwrap();
        let cipher = test_cipher(6);
        let path = dir.path().join("log");
        let boundaries = sealed_log_with_adds(&path, &cipher, 3);
        let frame_len = (boundaries[0].1 - boundaries[0].0) as usize;
        let bytes = std::fs::read(&path).unwrap();
        let second_start = SEALED_HEADER_LEN + frame_len;
        let third_start = second_start + frame_len;

        let mut swapped = bytes[..SEALED_HEADER_LEN].to_vec();
        swapped.extend_from_slice(&bytes[second_start..third_start]);
        swapped.extend_from_slice(&bytes[SEALED_HEADER_LEN..second_start]);
        swapped.extend_from_slice(&bytes[third_start..]);
        let swapped_path = dir.path().join("swapped");
        std::fs::write(&swapped_path, &swapped).unwrap();
        let mut swapped_log = reopen_sealed(&swapped_path, 8, Some(&cipher)).unwrap();
        let (records, recoverable_end) = scan_all(&mut swapped_log);
        assert!(records.is_empty());
        assert_eq!(recoverable_end, SEALED_HEADER_LEN as u64);
        assert!(
            swapped_log
                .tail_contains_valid_record(recoverable_end)
                .unwrap()
        );

        let other_path = dir.path().join("other");
        drop(Log::create(&other_path, 8, StorageKind::F32, Some(&cipher)).unwrap());
        let mut spliced = std::fs::read(&other_path).unwrap();
        spliced.extend_from_slice(&bytes[SEALED_HEADER_LEN..]);
        std::fs::write(&other_path, &spliced).unwrap();
        let mut spliced_log = reopen_sealed(&other_path, 8, Some(&cipher)).unwrap();
        let (records, recoverable_end) = scan_all(&mut spliced_log);
        assert!(records.is_empty());
        assert!(
            !spliced_log
                .tail_contains_valid_record(recoverable_end)
                .unwrap()
        );
    }

    #[test]
    fn recovery_buffers_report_unrepresentable_sizes_instead_of_panicking() {
        assert!(zeroed_buffer(isize::MAX as usize + 1).is_err());
        assert_eq!(zeroed_buffer(3).unwrap(), vec![0u8; 3]);
        let path = Path::new("/vectors/log");
        let error = out_of_memory(path);
        assert!(
            matches!(&error, VecDbError::Io { path: reported, source } if reported == path && source.kind() == ErrorKind::OutOfMemory)
        );
    }

    #[test]
    fn sealed_tail_probe_finds_frames_across_window_boundaries() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("log");
        let cipher = test_cipher(7);
        let boundaries = sealed_log_with_adds(&path, &cipher, 6);
        let frame_len = (boundaries[0].1 - boundaries[0].0) as usize;
        let last_start = boundaries[boundaries.len() - 1].0;
        let mut log = reopen_sealed(&path, 8, Some(&cipher)).unwrap();
        for step in [1, 7, frame_len - 1, frame_len, 4096] {
            for &(start, _) in &boundaries[1..] {
                assert!(
                    log.tail_contains_valid_record_windowed(start - 1, step)
                        .unwrap()
                );
            }
            assert!(
                !log.tail_contains_valid_record_windowed(last_start, step)
                    .unwrap()
            );
        }
    }

    #[test]
    fn damaged_headers_of_the_other_format_are_corrupt_rather_than_a_key_mismatch() {
        let dir = TempDir::new().unwrap();
        let cipher = test_cipher(8);
        let plain = dir.path().join("plain");
        let mut plain_log = Log::create(&plain, 8, StorageKind::F32, None).unwrap();
        let vector = seeded_vector(8, 8);
        plain_log
            .append(&[LogEntry::Add {
                key: "plain-record",
                vector: VectorPayload::F32(&vector),
                attrs: &[],
            }])
            .unwrap();
        drop(plain_log);
        let sealed = dir.path().join("sealed");
        sealed_log_with_adds(&sealed, &cipher, 1);

        let mut relabeled = std::fs::read(&plain).unwrap();
        assert!(relabeled.len() >= SEALED_HEADER_LEN);
        relabeled[..4].copy_from_slice(&SEALED_MAGIC);
        let mut sealed_bad_crc = std::fs::read(&sealed).unwrap();
        sealed_bad_crc[8] ^= 0x01;
        let mut plain_bad_crc = std::fs::read(&plain).unwrap();
        plain_bad_crc[8] ^= 0x01;
        let cases = [
            ("relabeled", relabeled, None),
            ("sealed-bad-crc", sealed_bad_crc, None),
            ("plain-bad-crc", plain_bad_crc, Some(&cipher)),
        ];
        for (name, bytes, key) in cases {
            let path = dir.path().join(name);
            std::fs::write(&path, &bytes).unwrap();
            assert!(
                matches!(reopen_sealed(&path, 8, key), Err(VecDbError::Corrupt(_))),
                "{name}"
            );
            assert_eq!(std::fs::read(&path).unwrap(), bytes, "{name}");
        }
    }

    #[test]
    fn malformed_frame_lengths_stop_the_scan_without_panicking() {
        let dir = TempDir::new().unwrap();
        let cipher = test_cipher(9);
        let path = dir.path().join("log");
        let boundaries = sealed_log_with_adds(&path, &cipher, 2);
        let bytes = std::fs::read(&path).unwrap();
        let first_start = boundaries[0].0 as usize;
        for length in [
            u32::MAX,
            u32::MAX - 27,
            0,
            (MIN_RECORD_LEN + TAG_LEN - 1) as u32,
        ] {
            let mut tail = bytes.clone();
            tail.extend_from_slice(&length.to_le_bytes());
            tail.extend_from_slice(&[0xAB; FRAME_PREFIX_LEN]);
            let tail_path = dir.path().join(format!("tail-{length}"));
            std::fs::write(&tail_path, &tail).unwrap();
            let mut tail_log = reopen_sealed(&tail_path, 8, Some(&cipher)).unwrap();
            let (records, recoverable_end) = scan_all(&mut tail_log);
            assert_eq!(records.len(), 2);
            assert_eq!(recoverable_end, boundaries[1].1);
            assert!(
                !tail_log
                    .tail_contains_valid_record(recoverable_end)
                    .unwrap()
            );

            let mut middle = bytes.clone();
            middle[first_start..first_start + FRAME_LEN_BYTES]
                .copy_from_slice(&length.to_le_bytes());
            let middle_path = dir.path().join(format!("middle-{length}"));
            std::fs::write(&middle_path, &middle).unwrap();
            let mut middle_log = reopen_sealed(&middle_path, 8, Some(&cipher)).unwrap();
            let (records, recoverable_end) = scan_all(&mut middle_log);
            assert!(records.is_empty());
            assert_eq!(recoverable_end, boundaries[0].0);
            assert!(
                middle_log
                    .tail_contains_valid_record(recoverable_end)
                    .unwrap()
            );
        }
    }
}
