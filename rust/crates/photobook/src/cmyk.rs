use std::sync::Arc;

use jpeg_encoder::{ColorType, Encoder, SamplingFactor};
use moxcms::{
    ColorProfile, DataColorSpace, Layout, RenderingIntent, Transform16BitExecutor, TransformOptions,
};

use crate::Error;

const JPEG_QUALITY: u8 = 98;

pub(crate) struct CmykJpegEncoder {
    transform: Arc<Transform16BitExecutor>,
}

impl CmykJpegEncoder {
    pub(crate) fn new(output: &ColorProfile) -> Result<Self, Error> {
        if output.color_space != DataColorSpace::Cmyk {
            return Err(Error::NotCmykProfile);
        }
        let options = TransformOptions {
            rendering_intent: RenderingIntent::Perceptual,
            ..TransformOptions::default()
        };
        let transform = ColorProfile::new_srgb()
            .create_transform_16bit(Layout::Rgb, output, Layout::Rgba, options)
            .map_err(Error::InvalidProfile)?;
        Ok(Self { transform })
    }

    pub(crate) fn encode(
        &self,
        mut srgb_rgba: Vec<u8>,
        width: u16,
        height: u16,
    ) -> Result<Vec<u8>, Error> {
        let expected_len = u64::from(width) * u64::from(height) * 4;
        if expected_len == 0 || srgb_rgba.len() as u64 != expected_len {
            return Err(Error::InvalidDimensions {
                width,
                height,
                len: srgb_rgba.len(),
            });
        }
        self.convert_in_place(&mut srgb_rgba, usize::from(width))?;
        let cmyk = srgb_rgba;

        let mut jpeg = Vec::new();
        let mut encoder = Encoder::new(&mut jpeg, JPEG_QUALITY);
        encoder.set_sampling_factor(SamplingFactor::F_1_1);
        encoder
            .encode(&cmyk, width, height, ColorType::Cmyk)
            .map_err(Error::Encode)?;
        Ok(jpeg)
    }

    fn convert_in_place(&self, pixels: &mut [u8], width: usize) -> Result<(), Error> {
        let mut rgb_row = vec![[0u16; 3]; width];
        let mut cmyk_row = vec![0u16; width * 4];
        for row in pixels.chunks_exact_mut(width * 4) {
            for (rgb, &[r, g, b, a]) in rgb_row.iter_mut().zip(row.as_chunks::<4>().0) {
                *rgb = [r, g, b].map(|value| over_white(value, u32::from(a)));
            }
            self.transform
                .transform(rgb_row.as_flattened(), &mut cmyk_row)
                .map_err(Error::Convert)?;
            for (byte, &value) in row.iter_mut().zip(&cmyk_row) {
                *byte = to_u8(value);
            }
        }
        Ok(())
    }
}

fn over_white(value: u8, alpha: u32) -> u16 {
    ((u32::from(value) * alpha * 257 + 65535 * (255 - alpha) + 127) / 255) as u16
}

fn to_u8(value: u16) -> u8 {
    ((u32::from(value) * 255 + 32767) / 65535) as u8
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_profile::key_only_profile;

    fn encoder() -> CmykJpegEncoder {
        CmykJpegEncoder::new(&ColorProfile::new_from_slice(&key_only_profile()).unwrap()).unwrap()
    }

    fn cmyk_of(pixels: &[[u8; 4]]) -> Vec<[u8; 4]> {
        let mut bytes = pixels.concat();
        encoder()
            .convert_in_place(&mut bytes, pixels.len())
            .unwrap();
        bytes.as_chunks::<4>().0.to_vec()
    }

    fn segments(jpeg: &[u8]) -> Vec<(u8, &[u8])> {
        assert_eq!(jpeg[..2], [0xFF, 0xD8]);
        let mut segments = Vec::new();
        let mut at = 2;
        loop {
            assert_eq!(jpeg[at], 0xFF);
            let marker = jpeg[at + 1];
            let len = usize::from(u16::from_be_bytes([jpeg[at + 2], jpeg[at + 3]]));
            segments.push((marker, &jpeg[at + 4..at + 2 + len]));
            if marker == 0xDA {
                break;
            }
            at += 2 + len;
        }
        assert_eq!(jpeg[jpeg.len() - 2..], [0xFF, 0xD9]);
        segments
    }

    #[test]
    fn converts_through_the_output_profile() {
        let cmyk = cmyk_of(&[[255, 255, 255, 255], [119, 119, 119, 255], [0, 0, 0, 255]]);
        let [white, gray, black] = cmyk[..] else {
            panic!("expected three pixels")
        };
        assert!(white.iter().all(|&ink| ink <= 2), "{white:?}");
        assert!(black[..3].iter().all(|&ink| ink <= 2), "{black:?}");
        assert!(black[3] >= 253, "{black:?}");
        assert!(
            gray[3] > white[3] + 64 && gray[3] < black[3] - 64,
            "{gray:?}"
        );
    }

    #[test]
    fn composites_transparency_over_white_paper() {
        let cmyk = cmyk_of(&[
            [255, 255, 255, 255],
            [0, 0, 0, 0],
            [0, 0, 0, 128],
            [0, 0, 0, 255],
        ]);
        assert_eq!(cmyk[1], cmyk[0]);
        assert!(cmyk[2][3] > cmyk[0][3] + 64 && cmyk[2][3] < cmyk[3][3] - 64);
    }

    #[test]
    fn writes_one_unsubsampled_adobe_cmyk_scan() {
        let jpeg = encoder().encode(vec![128; 3 * 2 * 4], 3, 2).unwrap();
        let segments = segments(&jpeg);
        assert_eq!(jpeg.windows(2).filter(|w| *w == [0xFF, 0xDA]).count(), 1);

        let scan = segments
            .iter()
            .find(|(marker, _)| *marker == 0xDA)
            .map(|(_, data)| data)
            .unwrap();
        assert_eq!(scan[0], 4);

        let adobe = segments
            .iter()
            .find(|(marker, data)| *marker == 0xEE && data.starts_with(b"Adobe"))
            .map(|(_, data)| data)
            .unwrap();
        assert_eq!(adobe[11], 0);

        let frame = segments
            .iter()
            .find(|(marker, _)| *marker == 0xC0)
            .map(|(_, data)| data)
            .unwrap();
        assert_eq!(frame[..6], [8, 0, 2, 0, 3, 4]);
        assert!(frame[6..].as_chunks::<3>().0.iter().all(|c| c[1] == 0x11));
    }

    #[test]
    fn rejects_non_cmyk_profiles() {
        assert!(matches!(
            CmykJpegEncoder::new(&ColorProfile::new_srgb()),
            Err(Error::NotCmykProfile)
        ));
    }

    #[test]
    fn rejects_mismatched_dimensions() {
        let encoder = encoder();
        for (len, width, height) in [(16, 2, 1), (0, 0, 0), (8, 0, 2)] {
            assert!(matches!(
                encoder.encode(vec![0; len], width, height),
                Err(Error::InvalidDimensions { .. })
            ));
        }
    }

    #[test]
    fn rejects_lengths_that_match_only_after_32_bit_wraparound() {
        let encoder = encoder();
        for (len, width, height) in [(0_u32, 32_768_u16, 32_768_u16), (131_072, 32_768, 32_769)] {
            let wrapped = u32::from(width)
                .wrapping_mul(u32::from(height))
                .wrapping_mul(4);
            assert_eq!(len, wrapped);
            assert!(matches!(
                encoder.encode(vec![0; len as usize], width, height),
                Err(Error::InvalidDimensions { .. })
            ));
        }
    }
}
