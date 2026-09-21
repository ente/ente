use super::OpResult;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ImageU8 {
    pub width: i32,
    pub height: i32,
    pub channels: i32,
    pub data: Vec<u8>,
}

impl ImageU8 {
    pub(crate) fn new(width: i32, height: i32, channels: i32, data: Vec<u8>) -> OpResult<Self> {
        let expected = checked_length(width, height, channels)?;
        if data.len() != expected {
            return Err(format!(
                "image buffer length {} does not match {width}x{height}x{channels} ({expected})",
                data.len()
            ));
        }
        Ok(Self {
            width,
            height,
            channels,
            data,
        })
    }

    #[cfg(test)]
    pub(crate) fn zeros(width: i32, height: i32, channels: i32) -> OpResult<Self> {
        let length = checked_length(width, height, channels)?;
        let mut data = Vec::new();
        data.try_reserve_exact(length)
            .map_err(|error| format!("image allocation failed: {error}"))?;
        data.resize(length, 0);
        Ok(Self {
            width,
            height,
            channels,
            data,
        })
    }
}

fn checked_length(width: i32, height: i32, channels: i32) -> OpResult<usize> {
    if width <= 0 || height <= 0 || channels <= 0 {
        return Err(format!(
            "invalid image geometry {width}x{height}x{channels}"
        ));
    }
    (width as usize)
        .checked_mul(height as usize)
        .and_then(|n| n.checked_mul(channels as usize))
        .filter(|&n| n <= isize::MAX as usize)
        .ok_or_else(|| "image size overflow".to_owned())
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Contour {
    pub points: Vec<(i32, i32)>,
    pub area: f64,
    pub outer: bool,
}
