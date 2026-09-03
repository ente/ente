use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use super::OcrError;

type Flags = HashMap<String, Arc<AtomicBool>>;

#[derive(Default)]
pub(crate) struct RequestRegistry {
    flags: Mutex<Flags>,
}

impl RequestRegistry {
    pub(crate) fn begin(&self, request_id: Option<&str>) -> RequestGuard<'_> {
        let flag = Arc::new(AtomicBool::new(false));
        if let Some(id) = request_id
            && let Some(replaced) = self.flags().insert(id.to_string(), Arc::clone(&flag))
        {
            replaced.store(true, Ordering::SeqCst);
        }
        RequestGuard {
            registry: self,
            request_id: request_id.map(str::to_string),
            flag,
        }
    }

    pub(crate) fn cancel(&self, request_id: &str) {
        if let Some(flag) = self.flags().get(request_id) {
            flag.store(true, Ordering::SeqCst);
        }
    }

    fn finish(&self, request_id: &str, flag: &Arc<AtomicBool>) {
        let mut flags = self.flags();
        if flags
            .get(request_id)
            .is_some_and(|current| Arc::ptr_eq(current, flag))
        {
            flags.remove(request_id);
        }
    }

    fn flags(&self) -> MutexGuard<'_, Flags> {
        self.flags.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

pub(crate) struct RequestGuard<'a> {
    registry: &'a RequestRegistry,
    request_id: Option<String>,
    flag: Arc<AtomicBool>,
}

impl RequestGuard<'_> {
    pub(crate) fn check(&self) -> Result<(), OcrError> {
        if self.flag.load(Ordering::SeqCst) {
            Err(OcrError::Cancelled)
        } else {
            Ok(())
        }
    }
}

impl Drop for RequestGuard<'_> {
    fn drop(&mut self) {
        if let Some(request_id) = &self.request_id {
            self.registry.finish(request_id, &self.flag);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn is_cancelled(guard: &RequestGuard<'_>) -> bool {
        matches!(guard.check(), Err(OcrError::Cancelled))
    }

    #[test]
    fn cancel_marks_the_registered_request() {
        let registry = RequestRegistry::default();
        let guard = registry.begin(Some("req-1"));
        assert!(guard.check().is_ok());

        registry.cancel("req-1");

        assert!(is_cancelled(&guard));
    }

    #[test]
    fn cancelling_an_unknown_or_anonymous_request_is_a_no_op() {
        let registry = RequestRegistry::default();
        let anonymous = registry.begin(None);

        registry.cancel("missing");

        assert!(anonymous.check().is_ok());
        assert!(registry.flags().is_empty());
    }

    #[test]
    fn a_new_request_with_the_same_id_cancels_and_replaces_the_older_one() {
        let registry = RequestRegistry::default();
        let first = registry.begin(Some("shared"));
        let second = registry.begin(Some("shared"));

        assert!(is_cancelled(&first));
        assert!(second.check().is_ok());

        drop(first);
        assert_eq!(registry.flags().len(), 1);
        registry.cancel("shared");
        assert!(is_cancelled(&second));
    }

    #[test]
    fn finishing_a_request_removes_its_flag() {
        let registry = RequestRegistry::default();
        let guard = registry.begin(Some("done"));
        assert_eq!(registry.flags().len(), 1);

        drop(guard);

        assert!(registry.flags().is_empty());
    }
}
