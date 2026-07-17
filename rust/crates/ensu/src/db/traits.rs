use std::time::{SystemTime, UNIX_EPOCH};

use uuid::Uuid;

pub trait Clock: Send + Sync {
    fn now_us(&self) -> i64;
}

pub trait UuidGen: Send + Sync {
    fn new_uuid(&self) -> Uuid;
}

#[derive(Debug, Default, Clone)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now_us(&self) -> i64 {
        let duration = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default();
        let micros = duration.as_secs() as i64 * 1_000_000;
        let sub_micros = duration.subsec_micros() as i64;
        micros + sub_micros
    }
}

#[derive(Debug, Default, Clone)]
pub struct RandomUuidGen;

impl UuidGen for RandomUuidGen {
    fn new_uuid(&self) -> Uuid {
        Uuid::new_v4()
    }
}
