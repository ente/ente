use crate::{Metadata, Mode};
use std::fmt;
use std::io::{self, Read, Seek, SeekFrom};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Issue {
    pub offset: u64,
    pub message: &'static str,
}

#[derive(Debug)]
pub enum Error {
    Io(io::Error),
    Malformed(&'static str),
    Unsupported(&'static str),
    Limit(&'static str),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(e) => e.fmt(f),
            Self::Malformed(s) => write!(f, "malformed {s}"),
            Self::Unsupported(s) => write!(f, "unsupported {s}"),
            Self::Limit(s) => write!(f, "{s} limit exceeded"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            _ => None,
        }
    }
}
impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}
#[derive(Debug, Clone, Copy)]
pub struct Limits {
    pub read_bytes: usize,
    pub value_bytes: usize,
    pub output_bytes: usize,
    pub entries: usize,
    pub directories: usize,
    pub depth: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            read_bytes: 8 * 1024 * 1024,
            value_bytes: 64 * 1024,
            output_bytes: 512 * 1024,
            entries: 16384,
            directories: 64,
            depth: 32,
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Statistics {
    pub bytes_read: u64,
    pub reads: usize,
}

pub(crate) struct Reader<'a, R> {
    source: &'a mut R,
    pub len: u64,
    position: u64,
    remaining: usize,
    pub statistics: Statistics,
}

impl<'a, R: Read + Seek> Reader<'a, R> {
    pub fn new(source: &'a mut R, limits: Limits) -> Result<Self, Error> {
        let len = source.seek(SeekFrom::End(0))?;
        Ok(Self {
            source,
            len,
            position: len,
            remaining: limits.read_bytes,
            statistics: Statistics::default(),
        })
    }

    pub fn bytes(&mut self, offset: u64, count: usize) -> Result<Vec<u8>, Error> {
        self.check(offset, count)?;
        let mut bytes = vec![0; count];
        self.fill(offset, &mut bytes)?;
        Ok(bytes)
    }

    pub fn array<const N: usize>(&mut self, offset: u64) -> Result<[u8; N], Error> {
        let mut bytes = [0; N];
        self.fill(offset, &mut bytes)?;
        Ok(bytes)
    }

    pub fn fill(&mut self, offset: u64, bytes: &mut [u8]) -> Result<(), Error> {
        self.check(offset, bytes.len())?;
        if self.position != offset {
            if let Ok(delta) = i64::try_from(i128::from(offset) - i128::from(self.position)) {
                self.source.seek_relative(delta)?;
            } else {
                self.source.seek(SeekFrom::Start(offset))?;
            }
        }
        self.source.read_exact(bytes)?;
        self.position = offset + bytes.len() as u64;
        self.remaining -= bytes.len();
        self.statistics.bytes_read += bytes.len() as u64;
        self.statistics.reads += 1;
        Ok(())
    }

    pub fn check(&self, offset: u64, count: usize) -> Result<(), Error> {
        if offset > self.len || count as u64 > self.len - offset {
            return Err(Error::Malformed("range"));
        }
        if count > self.remaining {
            return Err(Error::Limit("read bytes"));
        }
        Ok(())
    }
}

pub(crate) struct State<'a> {
    pub metadata: Metadata,
    pub mode: Mode,
    pub limits: Limits,
    pub structure: Option<&'a mut crate::XmpStructure>,
    pub output: OutputBudget,
    entries: usize,
    expanded: usize,
}

pub(crate) struct OutputBudget {
    used: usize,
    limit: usize,
}

impl OutputBudget {
    pub fn retain(&mut self, count: usize) -> Result<(), Error> {
        self.used = self
            .used
            .checked_add(count)
            .ok_or(Error::Limit("output bytes"))?;
        if self.used > self.limit {
            return Err(Error::Limit("output bytes"));
        }
        Ok(())
    }
}

impl State<'_> {
    pub fn new(mode: Mode, limits: Limits) -> Self {
        Self {
            metadata: Metadata::default(),
            mode,
            limits,
            structure: None,
            output: OutputBudget {
                used: 0,
                limit: limits.output_bytes,
            },
            entries: 0,
            expanded: 0,
        }
    }

    pub fn entries(&mut self, count: usize) -> Result<(), Error> {
        self.entries = self
            .entries
            .checked_add(count)
            .ok_or(Error::Limit("entries"))?;
        if self.entries > self.limits.entries {
            return Err(Error::Limit("entries"));
        }
        Ok(())
    }

    pub fn retain(&mut self, count: usize) -> Result<(), Error> {
        self.output.retain(count)
    }

    pub fn expanded(&mut self, count: usize) -> Result<(), Error> {
        if count > self.limits.read_bytes.saturating_sub(self.expanded) {
            return Err(Error::Limit("expanded bytes"));
        }
        self.expanded += count;
        Ok(())
    }

    pub fn expansion_limit(&self) -> usize {
        self.limits.read_bytes - self.expanded
    }

    pub fn recover(&mut self, offset: u64, result: Result<(), Error>) -> Result<(), Error> {
        match result {
            Ok(()) => Ok(()),
            Err(Error::Malformed(message) | Error::Unsupported(message)) => {
                self.retain(std::mem::size_of::<Issue>())?;
                self.metadata.issues.push(Issue { offset, message });
                Ok(())
            }
            Err(e) => Err(e),
        }
    }
}

pub(crate) fn range(base: u64, length: u64, offset: u64, count: u64) -> Result<u64, Error> {
    if offset > length || count > length - offset {
        return Err(Error::Malformed("offset"));
    }
    base.checked_add(offset)
        .ok_or(Error::Malformed("offset overflow"))
}

pub(crate) fn be16(bytes: &[u8]) -> u16 {
    u16::from_be_bytes([bytes[0], bytes[1]])
}
pub(crate) fn be32(bytes: &[u8]) -> u32 {
    u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}
pub(crate) fn le32(bytes: &[u8]) -> u32 {
    u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

pub(crate) struct Cursor<'a> {
    pub bytes: &'a [u8],
    pub pos: usize,
}
impl<'a> Cursor<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, pos: 0 }
    }
    pub fn take(&mut self, count: usize) -> Result<&'a [u8], Error> {
        let end = self
            .pos
            .checked_add(count)
            .ok_or(Error::Malformed("length"))?;
        let bytes = self
            .bytes
            .get(self.pos..end)
            .ok_or(Error::Malformed("truncated field"))?;
        self.pos = end;
        Ok(bytes)
    }
    pub fn number(&mut self, width: usize) -> Result<u64, Error> {
        if width > 8 {
            return Err(Error::Unsupported("integer width"));
        }
        Ok(self
            .take(width)?
            .iter()
            .fold(0, |value, b| (value << 8) | u64::from(*b)))
    }
    pub fn string(&mut self) -> Result<&'a str, Error> {
        std::str::from_utf8(self.terminated_bytes()?).map_err(|_| Error::Malformed("UTF-8"))
    }
    pub fn terminated_bytes(&mut self) -> Result<&'a [u8], Error> {
        let length = self.bytes[self.pos..]
            .iter()
            .position(|b| *b == 0)
            .ok_or(Error::Malformed("terminated string"))?;
        let bytes = self.take(length + 1)?;
        Ok(&bytes[..length])
    }
}
