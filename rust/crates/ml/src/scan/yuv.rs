//! Reproduces libyuv's limited-range BT.601 fixed-point arithmetic — not the
//! textbook full-range matrix — because that is what Android camera stacks
//! apply when converting frames to RGBA, so YUV and RGBA frames yield the
//! same quad.

use crate::cv;
use crate::cv::image::ImageU8;

const YG: i32 = 18997; // round(1.164 * 64 * 256 * 256 / 257)
const YGB: i32 = -1160; // 1.164 * 64 * -16 + 64 * 0.5 (rounding bias folded in)
const UB: i32 = -128; // max(-128, round(-2.018 * 64)): clamped to fit a signed byte
const UG: i32 = 25; // round(0.391 * 64)
const VG: i32 = 52; // round(0.813 * 64)
const VR: i32 = -102; // round(-1.596 * 64)

const BB: i32 = UB * 128 + YGB;
const BG: i32 = UG * 128 + VG * 128 + YGB;
const BR: i32 = VR * 128 + YGB;

fn ceil_half(value: i32) -> i32 {
    (value + 1) / 2
}

fn clamp_u8(value: i32) -> u8 {
    value.clamp(0, 255) as u8
}

#[inline]
pub(crate) fn yuv_to_bgr(y: u8, u: u8, v: u8) -> (u8, u8, u8) {
    let (y, u, v) = (y as i32, u as i32, v as i32);
    let y1 = ((y as u32 * 0x0101 * YG as u32) >> 16) as i32;
    let b = clamp_u8((-(u * UB) + y1 + BB) >> 6);
    let g = clamp_u8((-(u * UG + v * VG) + y1 + BG) >> 6);
    let r = clamp_u8((-(v * VR) + y1 + BR) >> 6);
    (b, g, r)
}

#[derive(Clone, Copy, Debug)]
pub struct PlaneLayout {
    pub width: i32,
    pub height: i32,
    pub y_row_stride: i32,
    pub uv_row_stride: i32,
    pub uv_pixel_stride: i32,
}

fn required_len(rows: i32, row_stride: i32, last_row_bytes: i32) -> usize {
    if rows <= 0 {
        return 0;
    }
    (rows - 1) as usize * row_stride as usize + last_row_bytes as usize
}

fn check_layout(
    y_plane: &[u8],
    u_plane: &[u8],
    v_plane: &[u8],
    layout: PlaneLayout,
) -> Result<(i32, i32), String> {
    let PlaneLayout {
        width,
        height,
        y_row_stride,
        uv_row_stride,
        uv_pixel_stride,
    } = layout;

    if width <= 0 || height <= 0 {
        return Err(format!("invalid frame size {width}x{height}"));
    }
    if uv_pixel_stride < 1 {
        return Err(format!("invalid uv pixel stride {uv_pixel_stride}"));
    }
    if y_row_stride < width {
        return Err(format!(
            "y row stride {y_row_stride} is smaller than the frame width {width}"
        ));
    }
    let cw = ceil_half(width);
    let ch = ceil_half(height);
    if uv_row_stride < (cw - 1) * uv_pixel_stride + 1 {
        return Err(format!(
            "uv row stride {uv_row_stride} is too small for {cw} chroma samples \
             at pixel stride {uv_pixel_stride}"
        ));
    }

    let need_y = required_len(height, y_row_stride, width);
    let need_uv = required_len(ch, uv_row_stride, (cw - 1) * uv_pixel_stride + 1);
    if y_plane.len() < need_y {
        return Err(format!(
            "y plane has {} bytes, needs {need_y}",
            y_plane.len()
        ));
    }
    if u_plane.len() < need_uv {
        return Err(format!(
            "u plane has {} bytes, needs {need_uv}",
            u_plane.len()
        ));
    }
    if v_plane.len() < need_uv {
        return Err(format!(
            "v plane has {} bytes, needs {need_uv}",
            v_plane.len()
        ));
    }
    Ok((cw, ch))
}

fn plane_to_image(
    plane: &[u8],
    width: i32,
    height: i32,
    row_stride: i32,
    pixel_stride: i32,
) -> Result<ImageU8, String> {
    let (w, h) = (width as usize, height as usize);
    let (row_stride, pixel_stride) = (row_stride as usize, pixel_stride as usize);
    if pixel_stride == 1 && row_stride == w {
        return ImageU8::new(width, height, 1, plane[..w * h].to_vec());
    }
    let mut out = vec![0u8; w * h];
    for (row, dst) in out.chunks_exact_mut(w).enumerate() {
        let base = row * row_stride;
        for (col, sample) in dst.iter_mut().enumerate() {
            *sample = plane[base + col * pixel_stride];
        }
    }
    ImageU8::new(width, height, 1, out)
}

pub(crate) fn yuv420_to_bgr(
    y_plane: &[u8],
    u_plane: &[u8],
    v_plane: &[u8],
    layout: PlaneLayout,
    width: i32,
    height: i32,
) -> Result<ImageU8, String> {
    let (cw, ch) = check_layout(y_plane, u_plane, v_plane, layout)?;

    let y = plane_to_image(y_plane, layout.width, layout.height, layout.y_row_stride, 1)?;
    let u = plane_to_image(
        u_plane,
        cw,
        ch,
        layout.uv_row_stride,
        layout.uv_pixel_stride,
    )?;
    let v = plane_to_image(
        v_plane,
        cw,
        ch,
        layout.uv_row_stride,
        layout.uv_pixel_stride,
    )?;

    let y = cv::resize_u8(&y, width, height, cv::Interp::Bilinear)?;
    let u = cv::resize_u8(&u, width, height, cv::Interp::Bilinear)?;
    let v = cv::resize_u8(&v, width, height, cv::Interp::Bilinear)?;

    let mut out = vec![0u8; width as usize * height as usize * 3];
    for (pixel, ((&y, &u), &v)) in out
        .as_chunks_mut::<3>()
        .0
        .iter_mut()
        .zip(y.data.iter().zip(u.data.iter()).zip(v.data.iter()))
    {
        let (b, g, r) = yuv_to_bgr(y, u, v);
        pixel[0] = b;
        pixel[1] = g;
        pixel[2] = r;
    }

    ImageU8::new(width, height, 3, out)
}

pub(crate) fn bgra_to_bgr(
    bgra: &[u8],
    row_stride: i32,
    width: i32,
    height: i32,
) -> Result<ImageU8, String> {
    if width <= 0 || height <= 0 {
        return Err(format!("invalid frame size {width}x{height}"));
    }
    let row_bytes = width as usize * 4;
    if row_stride < 0 || (row_stride as usize) < row_bytes {
        return Err(format!(
            "row stride {row_stride} is smaller than {row_bytes} bytes per row"
        ));
    }
    let row_stride = row_stride as usize;
    let needed = required_len(height, row_stride as i32, row_bytes as i32);
    if bgra.len() < needed {
        return Err(format!(
            "BGRA buffer has {} bytes, needs {needed}",
            bgra.len()
        ));
    }

    let mut out = vec![0u8; width as usize * height as usize * 3];
    for (row, dst_row) in out.chunks_exact_mut(width as usize * 3).enumerate() {
        let src_row = &bgra[row * row_stride..row * row_stride + row_bytes];
        for (dst, src) in dst_row
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .zip(src_row.as_chunks::<4>().0.iter())
        {
            dst[0] = src[0];
            dst[1] = src[1];
            dst[2] = src[2];
        }
    }
    ImageU8::new(width, height, 3, out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reference_yuv_to_bgr(y: u8, u: u8, v: u8, ub: f64) -> (u8, u8, u8) {
        let yf = (y as f64 - 16.0) * 1.164;
        let uf = u as f64 - 128.0;
        let vf = v as f64 - 128.0;
        let r = yf + 1.596 * vf;
        let g = yf - 0.391 * uf - 0.813 * vf;
        let b = yf - ub * uf;
        let to_u8 = |v: f64| v.round().clamp(0.0, 255.0) as u8;
        (to_u8(b), to_u8(g), to_u8(r))
    }

    fn worst_deviation(triples: impl Iterator<Item = (u8, u8, u8)>, ub: f64) -> [i32; 3] {
        let mut worst = [0i32; 3];
        for (y, u, v) in triples {
            let got = yuv_to_bgr(y, u, v);
            let want = reference_yuv_to_bgr(y, u, v, ub);
            let pairs = [(got.0, want.0), (got.1, want.1), (got.2, want.2)];
            for (i, (a, b)) in pairs.iter().enumerate() {
                worst[i] = worst[i].max((*a as i32 - *b as i32).abs());
            }
        }
        worst
    }

    fn all_triples() -> impl Iterator<Item = (u8, u8, u8)> {
        (0..=255u8)
            .flat_map(|y| (0..=255u8).map(move |u| (y, u)))
            .flat_map(|(y, u)| (0..=255u8).map(move |v| (y, u, v)))
    }

    fn strided_triples() -> impl Iterator<Item = (u8, u8, u8)> {
        let axis = |step: usize| (0..=255u8).step_by(step).chain(std::iter::once(255));
        axis(6).flat_map(move |y| axis(7).flat_map(move |u| axis(11).map(move |v| (y, u, v))))
    }

    struct Rng(u64);

    impl Rng {
        fn next_u8(&mut self) -> u8 {
            let mut x = self.0;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            self.0 = x;
            (x.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 33) as u8
        }
    }

    #[test]
    fn anchor_values_match_the_reference_matrix() {
        assert_eq!(yuv_to_bgr(16, 128, 128), (0, 0, 0));
        assert_eq!(yuv_to_bgr(235, 128, 128), (255, 255, 255));
        assert_eq!(yuv_to_bgr(0, 128, 128), (0, 0, 0));
        assert_eq!(yuv_to_bgr(255, 128, 128), (255, 255, 255));
        let (b, g, r) = yuv_to_bgr(126, 128, 128);
        assert_eq!((b, g, r), (128, 128, 128));
    }

    #[test]
    fn fixed_point_matches_the_effective_matrix_on_a_subsample() {
        let worst = worst_deviation(strided_triples(), -2.0);
        assert!(
            worst[0] == 0 && worst[1] <= 1 && worst[2] <= 1,
            "B/G/R deviation from the effective matrix changed: {worst:?}"
        );
    }

    #[test]
    #[ignore = "exhaustive 2^24 sweep; run explicitly"]
    fn fixed_point_matches_the_effective_matrix_exhaustively() {
        let worst = worst_deviation(all_triples(), -2.0);
        assert_eq!(
            worst,
            [0, 1, 1],
            "B/G/R deviation from the effective matrix changed"
        );
    }

    #[test]
    #[ignore = "exhaustive 2^24 sweep; run explicitly"]
    fn documented_matrix_differs_only_in_blue_by_the_ub_clamp() {
        let worst = worst_deviation(all_triples(), -2.018);
        assert_eq!(
            worst,
            [3, 1, 1],
            "B/G/R deviation from the documented matrix changed"
        );
    }

    #[test]
    fn grey_ramp_is_monotonic_and_neutral() {
        let mut previous = 0u8;
        for y in 16..=235u8 {
            let (b, g, r) = yuv_to_bgr(y, 128, 128);
            assert_eq!(b, g, "neutral chroma must stay grey at Y={y}");
            assert_eq!(g, r, "neutral chroma must stay grey at Y={y}");
            assert!(b >= previous, "luma ramp must be monotonic at Y={y}");
            previous = b;
        }
    }

    fn planes_from_pixels(
        width: i32,
        height: i32,
        pixel: impl Fn(i32, i32) -> (u8, u8, u8),
    ) -> (Vec<u8>, Vec<u8>, Vec<u8>) {
        let cw = ceil_half(width);
        let ch = ceil_half(height);
        let mut y = vec![0u8; (width * height) as usize];
        let mut u = vec![0u8; (cw * ch) as usize];
        let mut v = vec![0u8; (cw * ch) as usize];
        for row in 0..height {
            for col in 0..width {
                y[(row * width + col) as usize] = pixel(col, row).0;
            }
        }
        for row in 0..ch {
            for col in 0..cw {
                let (_, cu, cv) = pixel(col * 2, row * 2);
                u[(row * cw + col) as usize] = cu;
                v[(row * cw + col) as usize] = cv;
            }
        }
        (y, u, v)
    }

    #[test]
    fn planar_and_interleaved_layouts_agree() {
        let (width, height) = (37, 21);
        let mut rng = Rng(0xC0FF_EE00_1234_5677);
        let samples: Vec<(u8, u8, u8)> = (0..(width * height))
            .map(|_| (rng.next_u8(), rng.next_u8(), rng.next_u8()))
            .collect();
        let pixel = |x: i32, y: i32| samples[(y * width + x) as usize];

        let (y_plane, u_plane, v_plane) = planes_from_pixels(width, height, pixel);
        let planar = yuv420_to_bgr(
            &y_plane,
            &u_plane,
            &v_plane,
            PlaneLayout {
                width,
                height,
                y_row_stride: width,
                uv_row_stride: ceil_half(width),
                uv_pixel_stride: 1,
            },
            width,
            height,
        )
        .expect("planar conversion");

        let cw = ceil_half(width);
        let ch = ceil_half(height);
        let mut vu = vec![0u8; (cw * ch * 2) as usize];
        for i in 0..(cw * ch) as usize {
            vu[i * 2] = v_plane[i];
            vu[i * 2 + 1] = u_plane[i];
        }
        let interleaved = yuv420_to_bgr(
            &y_plane,
            &vu[1..],
            &vu,
            PlaneLayout {
                width,
                height,
                y_row_stride: width,
                uv_row_stride: cw * 2,
                uv_pixel_stride: 2,
            },
            width,
            height,
        )
        .expect("interleaved conversion");
        assert_eq!(planar, interleaved);

        let mut uv = vec![0u8; (cw * ch * 2) as usize];
        for i in 0..(cw * ch) as usize {
            uv[i * 2] = u_plane[i];
            uv[i * 2 + 1] = v_plane[i];
        }
        let nv12 = yuv420_to_bgr(
            &y_plane,
            &uv,
            &uv[1..],
            PlaneLayout {
                width,
                height,
                y_row_stride: width,
                uv_row_stride: cw * 2,
                uv_pixel_stride: 2,
            },
            width,
            height,
        )
        .expect("nv12 conversion");
        assert_eq!(planar, nv12);
    }

    #[test]
    fn row_padding_is_honoured() {
        let (width, height) = (10, 6);
        let mut rng = Rng(0x1234_5678_9ABC_DEF1);
        let samples: Vec<(u8, u8, u8)> = (0..(width * height))
            .map(|_| (rng.next_u8(), rng.next_u8(), rng.next_u8()))
            .collect();
        let pixel = |x: i32, y: i32| samples[(y * width + x) as usize];
        let (y_tight, u_tight, v_tight) = planes_from_pixels(width, height, pixel);

        let tight = yuv420_to_bgr(
            &y_tight,
            &u_tight,
            &v_tight,
            PlaneLayout {
                width,
                height,
                y_row_stride: width,
                uv_row_stride: ceil_half(width),
                uv_pixel_stride: 1,
            },
            width,
            height,
        )
        .expect("tight conversion");

        let (y_stride, uv_stride) = (width + 7, ceil_half(width) + 3);
        let cw = ceil_half(width);
        let ch = ceil_half(height);
        let mut y_pad = vec![0xA5u8; (y_stride * height) as usize];
        let mut u_pad = vec![0x5Au8; (uv_stride * ch) as usize];
        let mut v_pad = vec![0x3Cu8; (uv_stride * ch) as usize];
        for row in 0..height {
            for col in 0..width {
                y_pad[(row * y_stride + col) as usize] = y_tight[(row * width + col) as usize];
            }
        }
        for row in 0..ch {
            for col in 0..cw {
                u_pad[(row * uv_stride + col) as usize] = u_tight[(row * cw + col) as usize];
                v_pad[(row * uv_stride + col) as usize] = v_tight[(row * cw + col) as usize];
            }
        }
        let padded = yuv420_to_bgr(
            &y_pad,
            &u_pad,
            &v_pad,
            PlaneLayout {
                width,
                height,
                y_row_stride: y_stride,
                uv_row_stride: uv_stride,
                uv_pixel_stride: 1,
            },
            width,
            height,
        )
        .expect("padded conversion");
        assert_eq!(tight, padded);
    }

    #[test]
    fn odd_sizes_and_short_planes_are_rejected_not_panicked() {
        let layout = PlaneLayout {
            width: 8,
            height: 8,
            y_row_stride: 8,
            uv_row_stride: 4,
            uv_pixel_stride: 1,
        };
        assert!(yuv420_to_bgr(&[0u8; 63], &[0u8; 16], &[0u8; 16], layout, 8, 8).is_err());
        assert!(yuv420_to_bgr(&[0u8; 64], &[0u8; 15], &[0u8; 16], layout, 8, 8).is_err());
        assert!(yuv420_to_bgr(&[0u8; 64], &[0u8; 16], &[0u8; 15], layout, 8, 8).is_err());
        assert!(
            yuv420_to_bgr(
                &[0u8; 64],
                &[0u8; 16],
                &[0u8; 16],
                PlaneLayout {
                    y_row_stride: 4,
                    ..layout
                },
                8,
                8
            )
            .is_err()
        );
        assert!(
            yuv420_to_bgr(
                &[128u8],
                &[128u8],
                &[128u8],
                PlaneLayout {
                    width: 1,
                    height: 1,
                    y_row_stride: 1,
                    uv_row_stride: 1,
                    uv_pixel_stride: 1,
                },
                1,
                1
            )
            .is_ok()
        );
    }

    #[test]
    fn bgra_to_bgr_honours_row_padding_and_rejects_bad_geometry() {
        let stride = 2 * 4 + 4;
        let mut padded = vec![0xAAu8; stride * 2];
        let rows = [
            [[1u8, 2, 3, 255], [10, 20, 30, 0]],
            [[40u8, 50, 60, 255], [70, 80, 90, 128]],
        ];
        for (row, pixels) in rows.iter().enumerate() {
            for (col, px) in pixels.iter().enumerate() {
                padded[row * stride + col * 4..row * stride + col * 4 + 4].copy_from_slice(px);
            }
        }

        let bgr = bgra_to_bgr(&padded, stride as i32, 2, 2).expect("conversion");
        assert_eq!(bgr.data, vec![1, 2, 3, 10, 20, 30, 40, 50, 60, 70, 80, 90]);

        let needed = stride + 2 * 4;
        assert!(bgra_to_bgr(&padded[..needed], stride as i32, 2, 2).is_ok());
        assert!(bgra_to_bgr(&padded[..needed - 1], stride as i32, 2, 2).is_err());
        assert!(bgra_to_bgr(&padded, 7, 2, 2).is_err());
        assert!(bgra_to_bgr(&padded, -8, 2, 2).is_err());
        assert!(bgra_to_bgr(&padded, stride as i32, 0, 2).is_err());
    }
}
