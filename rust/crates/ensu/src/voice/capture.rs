use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard, PoisonError};

use super::{Result, VoiceError};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureFeedResult {
    Accepted,
    Closed,
}

#[derive(Clone, Copy, Debug)]
pub struct CaptureFormat {
    pub sample_rate: u32,
    pub channels: u16,
}

impl CaptureFormat {
    pub fn validate(self) -> Result<Self> {
        if !(8_000..=48_000).contains(&self.sample_rate) || !matches!(self.channels, 1 | 2) {
            return Err(VoiceError::InvalidAudio(
                "Capture requires 8–48 kHz PCM16 with one or two channels".into(),
            ));
        }
        Ok(self)
    }

    pub(crate) fn bytes_per_frame(self) -> usize {
        usize::from(self.channels) * 2
    }
}

#[derive(Default)]
struct Pending {
    chunks: VecDeque<Vec<u8>>,
    bytes: usize,
    closed: bool,
}

pub(crate) struct CaptureQueue {
    format: CaptureFormat,
    pending: Mutex<Pending>,
    failed: AtomicBool,
    cancelled: AtomicBool,
    submitted_frames: AtomicU64,
}

impl CaptureQueue {
    pub fn new(format: CaptureFormat) -> Result<Self> {
        Ok(Self {
            format: format.validate()?,
            pending: Mutex::new(Pending::default()),
            failed: AtomicBool::new(false),
            cancelled: AtomicBool::new(false),
            submitted_frames: AtomicU64::new(0),
        })
    }

    pub fn format(&self) -> CaptureFormat {
        self.format
    }

    pub fn push(&self, pcm: &[u8]) -> Result<CaptureFeedResult> {
        if self.cancelled.load(Ordering::Acquire) {
            return Err(VoiceError::Cancelled);
        }
        if self.failed.load(Ordering::Acquire) {
            return Err(VoiceError::BacklogFull);
        }
        let frame_bytes = self.format.bytes_per_frame();
        if pcm.is_empty()
            || !pcm.len().is_multiple_of(frame_bytes)
            || pcm.len() / frame_bytes > self.format.sample_rate as usize / 5
        {
            self.failed.store(true, Ordering::Release);
            return Err(VoiceError::InvalidAudio(
                "Capture buffer must contain complete PCM16 frames and at most 200 ms of audio"
                    .into(),
            ));
        }
        let owned = pcm.to_vec();
        let mut pending = self.lock();
        if pending.closed {
            return Ok(CaptureFeedResult::Closed);
        }
        self.submitted_frames
            .fetch_add((pcm.len() / frame_bytes) as u64, Ordering::AcqRel);
        if pending.bytes + pcm.len() > self.format.sample_rate as usize * frame_bytes * 2
            || pending.chunks.len() >= 128
        {
            self.failed.store(true, Ordering::Release);
            return Err(VoiceError::BacklogFull);
        }
        pending.bytes += pcm.len();
        pending.chunks.push_back(owned);
        Ok(CaptureFeedResult::Accepted)
    }

    pub fn take(&self) -> Option<Vec<u8>> {
        let mut pending = self.lock();
        let chunk = pending.chunks.pop_front()?;
        pending.bytes -= chunk.len();
        Some(chunk)
    }

    pub fn finish(&self) {
        self.lock().closed = true;
    }

    pub fn finish_if_empty(&self) -> bool {
        let mut pending = self.lock();
        if !pending.chunks.is_empty() {
            return false;
        }
        pending.closed = true;
        true
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.finish();
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    pub fn failed(&self) -> bool {
        self.failed.load(Ordering::Acquire)
    }

    pub fn is_drained(&self) -> bool {
        let pending = self.lock();
        pending.closed && pending.chunks.is_empty()
    }

    pub fn is_closed(&self) -> bool {
        self.lock().closed
    }

    pub fn submitted_frames(&self) -> u64 {
        self.submitted_frames.load(Ordering::Acquire)
    }

    pub fn clear(&self) {
        let mut pending = self.lock();
        pending.closed = true;
        pending.chunks.clear();
        pending.bytes = 0;
    }

    fn lock(&self) -> MutexGuard<'_, Pending> {
        self.pending.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn queue_bounds_bytes_and_saturation_is_sticky() {
        let queue = CaptureQueue::new(CaptureFormat {
            sample_rate: 48000,
            channels: 2,
        })
        .unwrap();
        let chunk = vec![7; 48000 / 5 * 4];
        for _ in 0..10 {
            queue.push(&chunk).unwrap();
        }
        assert_eq!(queue.push(&chunk), Err(VoiceError::BacklogFull));
        assert_eq!(queue.lock().bytes, 96000 * 4);
        assert_eq!(queue.take().unwrap(), chunk);
        assert!(queue.failed());
        assert_eq!(queue.push(&chunk), Err(VoiceError::BacklogFull));
    }

    #[test]
    fn countdown_cannot_skip_queued_speech_and_stop_drains_tail() {
        let queue = CaptureQueue::new(CaptureFormat {
            sample_rate: 16000,
            channels: 1,
        })
        .unwrap();
        queue.push(&[1, 0]).unwrap();
        assert!(!queue.finish_if_empty());
        assert_eq!(queue.take(), Some(vec![1, 0]));
        assert!(queue.finish_if_empty());
        assert!(queue.is_drained());
        assert_eq!(queue.push(&[1, 0]), Ok(CaptureFeedResult::Closed));
        assert_eq!(queue.submitted_frames(), 1);
        assert!(!queue.failed());
        queue.cancel();
        assert_eq!(queue.push(&[1, 0]), Err(VoiceError::Cancelled));
    }
}
