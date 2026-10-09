use std::ffi::{CString, c_char};

use super::{Error, format_error};

#[repr(C)]
struct RenderResult {
    data: *mut c_char,
    len: usize,
    status: i32,
}

#[expect(
    unsafe_code,
    reason = "Declarations for the private, synchronous C++ chat bridge"
)]
unsafe extern "C" {
    fn ensu_chat_render(
        source: *const c_char,
        bos: *const c_char,
        eos: *const c_char,
        messages: *const c_char,
        add_assistant: bool,
    ) -> RenderResult;
    fn ensu_chat_free(data: *mut c_char);
}

impl Drop for RenderResult {
    #[expect(
        unsafe_code,
        reason = "The bridge allocated this buffer and frees it with the same allocator; null is allowed"
    )]
    fn drop(&mut self) {
        unsafe { ensu_chat_free(self.data) };
    }
}

#[expect(
    unsafe_code,
    reason = "CString inputs live for the synchronous call; the result owns len initialized bytes until Drop frees them"
)]
pub(super) fn render(
    source: &str,
    bos: &str,
    eos: &str,
    messages: &str,
    add_assistant: bool,
) -> Result<String, Error> {
    let cstring = |value: &str| {
        CString::new(value)
            .map_err(|err| Error::InvalidInput(format_error("Invalid template input", err)))
    };
    let source = cstring(source)?;
    let bos = cstring(bos)?;
    let eos = cstring(eos)?;
    let messages = cstring(messages)?;
    let result = unsafe {
        ensu_chat_render(
            source.as_ptr(),
            bos.as_ptr(),
            eos.as_ptr(),
            messages.as_ptr(),
            add_assistant,
        )
    };
    let failure = |message| Error::Llama {
        op: "Failed to apply chat template",
        message,
    };
    if result.data.is_null() {
        return Err(failure("Could not allocate template output".to_owned()));
    }
    let bytes = unsafe { std::slice::from_raw_parts(result.data.cast::<u8>(), result.len) };
    let text = std::str::from_utf8(bytes)
        .map_err(|err| failure(err.to_string()))?
        .to_owned();
    if result.status != 0 {
        return Err(failure(text));
    }
    Ok(text)
}
