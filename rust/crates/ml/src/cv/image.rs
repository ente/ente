use super::OpResult;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ImageU8 {
    pub width: i32,
    pub height: i32,
    pub channels: i32,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct ImageF32 {
    pub width: i32,
    pub height: i32,
    pub channels: i32,
    pub data: Vec<f32>,
}

fn check_len(width: i32, height: i32, channels: i32, len: usize) -> OpResult<()> {
    if width <= 0 || height <= 0 || channels <= 0 {
        return Err(format!(
            "invalid image geometry {width}x{height}x{channels}"
        ));
    }
    let expected = width as usize * height as usize * channels as usize;
    if len != expected {
        return Err(format!(
            "image buffer length {len} does not match {width}x{height}x{channels} ({expected})"
        ));
    }
    Ok(())
}

impl ImageU8 {
    pub(crate) fn new(width: i32, height: i32, channels: i32, data: Vec<u8>) -> OpResult<Self> {
        check_len(width, height, channels, data.len())?;
        Ok(Self {
            width,
            height,
            channels,
            data,
        })
    }

    pub(crate) fn zeros(width: i32, height: i32, channels: i32) -> OpResult<Self> {
        if width <= 0 || height <= 0 || channels <= 0 {
            return Err(format!(
                "invalid image geometry {width}x{height}x{channels}"
            ));
        }
        let len = width as usize * height as usize * channels as usize;
        Ok(Self {
            width,
            height,
            channels,
            data: vec![0u8; len],
        })
    }

    pub(crate) fn size(&self) -> (i32, i32) {
        (self.width, self.height)
    }

    pub(crate) fn same_geometry(&self, other: &ImageU8) -> bool {
        self.width == other.width && self.height == other.height && self.channels == other.channels
    }
}

impl ImageF32 {
    pub(crate) fn new(width: i32, height: i32, channels: i32, data: Vec<f32>) -> OpResult<Self> {
        check_len(width, height, channels, data.len())?;
        Ok(Self {
            width,
            height,
            channels,
            data,
        })
    }

    pub(crate) fn zeros(width: i32, height: i32, channels: i32) -> OpResult<Self> {
        if width <= 0 || height <= 0 || channels <= 0 {
            return Err(format!(
                "invalid image geometry {width}x{height}x{channels}"
            ));
        }
        let len = width as usize * height as usize * channels as usize;
        Ok(Self {
            width,
            height,
            channels,
            data: vec![0.0f32; len],
        })
    }

    pub(crate) fn pixels(&self) -> usize {
        self.width as usize * self.height as usize
    }

    pub(crate) fn same_geometry(&self, other: &ImageF32) -> bool {
        self.width == other.width && self.height == other.height && self.channels == other.channels
    }
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum ImageRef<'a> {
    U8(&'a ImageU8),
    F32(&'a ImageF32),
}

#[derive(Clone, Debug)]
pub(crate) enum Image {
    U8(ImageU8),
    F32(ImageF32),
}

impl ImageRef<'_> {
    pub(crate) fn size(&self) -> (i32, i32) {
        match self {
            ImageRef::U8(i) => i.size(),
            ImageRef::F32(i) => (i.width, i.height),
        }
    }
}

impl Image {
    pub(crate) fn into_u8(self) -> OpResult<ImageU8> {
        match self {
            Image::U8(i) => Ok(i),
            Image::F32(_) => Err("expected an 8-bit image, got 32-bit float".to_string()),
        }
    }

    pub(crate) fn into_f32(self) -> OpResult<ImageF32> {
        match self {
            Image::F32(i) => Ok(i),
            Image::U8(_) => Err("expected a 32-bit float image, got 8-bit".to_string()),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Contour {
    pub points: Vec<(i32, i32)>,
    pub area: f64,
}
