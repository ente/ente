use ente_photobook::{Error as E, PageSize};
use wasm_bindgen::prelude::*;

pub struct Error(E);

impl From<E> for Error {
    fn from(error: E) -> Self {
        Self(error)
    }
}

impl From<Error> for JsValue {
    fn from(Error(error): Error) -> Self {
        let name = match error {
            E::InvalidProfile(_) | E::NotCmykProfile => Some("invalid_profile"),
            E::InvalidPageSize => Some("invalid_page_size"),
            E::InvalidDimensions { .. } => Some("invalid_dimensions"),
            E::NoPages => Some("no_pages"),
            E::TooLarge => Some("too_large"),
            E::Convert(_) | E::Encode(_) => None,
        };
        ente_wasm_lib::js_error(&error, name)
    }
}

#[wasm_bindgen]
pub struct PdfX4Writer(ente_photobook::PdfX4Writer);

#[wasm_bindgen]
impl PdfX4Writer {
    #[wasm_bindgen(constructor)]
    pub fn new(
        output_profile: &[u8],
        output_condition_identifier: &str,
        width_mm: f64,
        height_mm: f64,
        created_at_ms: f64,
    ) -> Result<Self, Error> {
        Ok(Self(ente_photobook::PdfX4Writer::new(
            output_profile,
            output_condition_identifier,
            PageSize {
                width_mm,
                height_mm,
            },
            (created_at_ms / 1000.0).floor() as i64,
        )?))
    }

    #[wasm_bindgen(js_name = addPage)]
    pub fn add_page(
        &mut self,
        srgb_rgba: Vec<u8>,
        width: u16,
        height: u16,
    ) -> Result<Vec<u8>, Error> {
        Ok(self.0.add_page(srgb_rgba, width, height)?)
    }

    pub fn finish(self) -> Result<Vec<u8>, Error> {
        Ok(self.0.finish()?)
    }
}
