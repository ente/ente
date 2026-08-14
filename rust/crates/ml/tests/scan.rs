//! Point `ENTE_DOC_SEGMENTATION_MODEL` at the model file; without it every
//! test skips.

use std::io::Cursor;

use ente_ml::scan::{ColorMode, PlaneLayout, Quad, ReprocessOptions, ScanOptions, ScannerSession};
use image::{ImageFormat, Rgb, RgbImage};

const MODEL_ENV: &str = "ENTE_DOC_SEGMENTATION_MODEL";

fn session() -> Option<ScannerSession> {
    let Ok(path) = std::env::var(MODEL_ENV) else {
        eprintln!("skipping: {MODEL_ENV} is not set");
        return None;
    };
    Some(ScannerSession::new(&path).expect("model should load"))
}

fn synthetic_document() -> RgbImage {
    let (width, height) = (640u32, 480u32);
    let mut img = RgbImage::from_pixel(width, height, Rgb([40, 45, 50]));
    let (x0, y0, x1, y1) = (120u32, 80u32, 520u32, 400u32);
    for y in y0..y1 {
        for x in x0..x1 {
            img.put_pixel(x, y, Rgb([235, 233, 228]));
        }
    }
    for line in 0..8u32 {
        let ly = y0 + 30 + line * 36;
        for y in ly..ly + 6 {
            for x in x0 + 30..x1 - 30 {
                img.put_pixel(x, y, Rgb([60, 60, 65]));
            }
        }
    }
    img
}

fn encode(img: &RgbImage, format: ImageFormat) -> Vec<u8> {
    let mut bytes = Cursor::new(Vec::new());
    img.write_to(&mut bytes, format).expect("encode");
    bytes.into_inner()
}

fn assert_document_result(result: &ente_ml::scan::ScanResult) {
    let quad = result.quad.expect("the synthetic document should be found");
    for p in quad.corners() {
        assert!(p.x >= 0.0 && p.x <= result.source_width as f64, "{quad:?}");
        assert!(p.y >= 0.0 && p.y <= result.source_height as f64, "{quad:?}");
    }
    assert_eq!(result.source_width, 640);
    assert_eq!(result.source_height, 480);
    assert!(result.output_width > 100 && result.output_height > 100);
    assert_jpeg(&result.processed_image);
}

fn assert_jpeg(bytes: &[u8]) {
    assert_eq!(
        image::guess_format(bytes).expect("recognizable output"),
        ImageFormat::Jpeg
    );
}

#[test]
fn processes_a_png_capture() {
    let Some(session) = session() else { return };
    let bytes = encode(&synthetic_document(), ImageFormat::Png);

    let result = session
        .process_capture(&bytes, &ScanOptions::default())
        .expect("process_capture");
    assert_document_result(&result);

    let decoded = image::load_from_memory(&result.processed_image).expect("valid JPEG output");
    assert_eq!(decoded.width(), result.output_width);
    assert_eq!(decoded.height(), result.output_height);
}

#[test]
fn processes_a_jpeg_capture_and_reprocesses_it() {
    let Some(session) = session() else { return };
    let bytes = encode(&synthetic_document(), ImageFormat::Jpeg);

    let result = session
        .process_capture(&bytes, &ScanOptions::default())
        .expect("process_capture");
    assert_document_result(&result);
    image::load_from_memory(&result.processed_image).expect("valid JPEG output");

    let reprocessed = session
        .reprocess(
            &bytes,
            &ReprocessOptions {
                quad: result.quad.expect("quad"),
                rotation_degrees: 90,
                color_mode: ColorMode::Grayscale,
                max_pixels: Some(500_000),
                jpeg_quality: Some(60),
            },
        )
        .expect("reprocess");
    assert_eq!(reprocessed.color_mode, ColorMode::Grayscale);
    assert_jpeg(&reprocessed.processed_image);
    assert!(reprocessed.output_width < reprocessed.output_height);
    image::load_from_memory(&reprocessed.processed_image).expect("valid JPEG output");
}

#[test]
fn live_detect_rgba_and_yuv_agree_on_a_grayscale_frame() {
    let Some(session) = session() else { return };
    let doc = synthetic_document();
    let (width, height) = (doc.width() as i32, doc.height() as i32);

    let mut rgba = Vec::with_capacity((width * height * 4) as usize);
    let mut y_plane = Vec::with_capacity((width * height) as usize);
    for px in doc.pixels() {
        // value = 1.164 * (y - 16), chroma neutral, so the limited-range YUV
        // round trip is exact.
        let y = 16 + (px.0[0] as i32 * 219 / 255) as u8;
        let value = (((y as i32 - 16) * 1164 + 500) / 1000).clamp(0, 255) as u8;
        rgba.extend_from_slice(&[value, value, value, 255]);
        y_plane.push(y);
    }
    let chroma_len = ((width + 1) / 2 * (height + 1) / 2) as usize;
    let u_plane = vec![128u8; chroma_len];
    let v_plane = vec![128u8; chroma_len];

    let from_rgba = session
        .live_detect_rgba(&rgba, width as u32, height as u32, 0)
        .expect("live_detect_rgba")
        .expect("quad from RGBA");
    let from_yuv = session
        .live_detect_yuv420(
            &y_plane,
            &u_plane,
            &v_plane,
            PlaneLayout {
                width,
                height,
                y_row_stride: width,
                uv_row_stride: (width + 1) / 2,
                uv_pixel_stride: 1,
            },
            0,
        )
        .expect("live_detect_yuv420")
        .expect("quad from YUV");

    let max_delta = quad_max_delta(&from_rgba, &from_yuv);
    assert!(
        max_delta < 2.0,
        "RGBA and YUV quads diverge by {max_delta} in mask space:\n{from_rgba:?}\n{from_yuv:?}"
    );

    let rotated = session
        .live_detect_rgba(&rgba, width as u32, height as u32, 180)
        .expect("live_detect_rgba rotated")
        .expect("quad");
    for p in rotated.corners() {
        assert!((0.0..=256.0).contains(&p.x) && (0.0..=256.0).contains(&p.y));
    }
}

#[test]
fn rejects_undecodable_bytes_with_a_codec_error() {
    let Some(session) = session() else { return };
    let error = session
        .process_capture(b"not an image", &ScanOptions::default())
        .expect_err("garbage must not decode");
    assert!(matches!(error, ente_ml::scan::ScanError::Codec(_)));
}

fn quad_max_delta(a: &Quad, b: &Quad) -> f64 {
    a.corners()
        .iter()
        .zip(b.corners())
        .map(|(p, q)| (p.x - q.x).hypot(p.y - q.y))
        .fold(0.0, f64::max)
}
