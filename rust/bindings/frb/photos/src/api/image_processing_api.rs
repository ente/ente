use ente_image::{
    BoundedDecodeOptions, DecodedImage, ImageError, ImageInput, decode::decode_image_from_path,
    decode_bounded,
};
use ente_ml::face::thumbnail::{FaceBox, generate_face_thumbnails_from_path};
use flutter_rust_bridge::frb;

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

#[frb(opaque)]
pub struct RustRgbaImage {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

impl RustRgbaImage {
    #[frb(sync)]
    pub fn width(&self) -> u32 {
        self.width
    }

    #[frb(sync)]
    pub fn height(&self) -> u32 {
        self.height
    }

    #[frb(sync)]
    pub fn pixels_address(&self) -> i64 {
        self.pixels.as_ptr() as i64
    }
}

pub fn decode_to_rgba(
    image_path: String,
    max_side: u32,
) -> Result<RustRgbaImage, RustImageDecodeError> {
    let options = BoundedDecodeOptions {
        max_side,
        ..BoundedDecodeOptions::default()
    };
    let decoded = decode_bounded(ImageInput::Path(&image_path), options)?.image;
    Ok(rgba_image(decoded))
}

pub fn decode_full_to_rgba(image_path: String) -> Result<RustRgbaImage, RustImageDecodeError> {
    Ok(rgba_image(decode_image_from_path(&image_path)?))
}

fn rgba_image(decoded: DecodedImage) -> RustRgbaImage {
    let (rgb, _) = decoded.rgb.as_chunks::<3>();
    let pixels = rgb
        .iter()
        .map(|&[r, g, b]| [r, g, b, u8::MAX])
        .collect::<Vec<_>>()
        .into_flattened();
    RustRgbaImage {
        width: decoded.dimensions.width,
        height: decoded.dimensions.height,
        pixels,
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use ente_image::Dimensions;

    #[test]
    fn rgba_image_appends_opaque_alpha() {
        let image = rgba_image(DecodedImage {
            dimensions: Dimensions {
                width: 2,
                height: 1,
            },
            rgb: vec![1, 2, 3, 4, 5, 6],
        });

        assert_eq!((image.width(), image.height()), (2, 1));
        assert_eq!(image.pixels, [1, 2, 3, 255, 4, 5, 6, 255]);
        assert_eq!(image.pixels_address(), image.pixels.as_ptr() as i64);
    }
}
