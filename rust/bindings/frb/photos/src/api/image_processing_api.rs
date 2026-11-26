use ente_image::{
    BoundedDecodeOptions, DecodedImage, ImageError, ImageInput,
    decode::decode_image_from_path,
    decode_bounded,
    image_compression::{EncodedImageFormat, encode_rgb},
};
use ente_ml::face::thumbnail::{FaceBox, generate_face_thumbnails_from_path};

#[derive(Clone, Debug)]
pub enum RustImageDecodeError {
    TooLarge { message: String },
    Other { message: String },
}

#[derive(Clone, Debug)]
pub struct RustFaceBox {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

pub fn generate_face_thumbnails(
    image_path: String,
    face_boxes: Vec<RustFaceBox>,
) -> Result<Vec<Vec<u8>>, String> {
    let face_boxes = face_boxes
        .into_iter()
        .enumerate()
        .map(|(index, face_box)| {
            FaceBox::try_from(face_box)
                .map_err(|e| format!("invalid face box at index {index}: {e}"))
        })
        .collect::<Result<Vec<_>, _>>()?;

    generate_face_thumbnails_from_path(&image_path, &face_boxes).map_err(|e| e.to_string())
}

// Use ente_heic instead of the platform decoder, which may fail on HEIC/HEIF.
pub fn decode_to_jpeg(
    image_path: String,
    max_side: u32,
    quality: Option<u8>,
) -> Result<Vec<u8>, RustImageDecodeError> {
    let options = BoundedDecodeOptions {
        max_side,
        ..BoundedDecodeOptions::default()
    };
    let decoded = decode_bounded(ImageInput::Path(&image_path), options)?.image;
    Ok(encode_jpeg(&decoded, quality)?)
}

pub fn decode_full_to_jpeg(
    image_path: String,
    quality: Option<u8>,
) -> Result<Vec<u8>, RustImageDecodeError> {
    let decoded = decode_image_from_path(&image_path)?;
    Ok(encode_jpeg(&decoded, quality)?)
}

fn encode_jpeg(decoded: &DecodedImage, quality: Option<u8>) -> Result<Vec<u8>, ImageError> {
    encode_rgb(
        &decoded.rgb,
        decoded.dimensions.width,
        decoded.dimensions.height,
        EncodedImageFormat::Jpeg420 {
            quality: quality.unwrap_or(95),
        },
    )
}

impl From<ImageError> for RustImageDecodeError {
    fn from(error: ImageError) -> Self {
        let message = error.to_string();
        match error {
            ImageError::TooLarge(_) => Self::TooLarge { message },
            ImageError::Decode(_) | ImageError::Postprocess(_) => Self::Other { message },
        }
    }
}

impl TryFrom<RustFaceBox> for FaceBox {
    type Error = String;

    fn try_from(value: RustFaceBox) -> Result<Self, Self::Error> {
        if !value.x.is_finite()
            || !value.y.is_finite()
            || !value.width.is_finite()
            || !value.height.is_finite()
        {
            return Err("non-finite values are not allowed".to_string());
        }
        if value.width <= 0.0 || value.height <= 0.0 {
            return Err("width and height must be greater than 0".to_string());
        }

        Ok(Self {
            x: value.x as f32,
            y: value.y as f32,
            width: value.width as f32,
            height: value.height as f32,
        })
    }
}
