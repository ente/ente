use image::{GrayImage, Luma};
use imageproc::drawing::draw_polygon_mut;
use imageproc::point::Point;

use super::saturate_u8_f64;
use crate::cv::OpResult;
use crate::cv::image::ImageU8;

pub(crate) fn fill_poly(
    width: i32,
    height: i32,
    polygon: &[(i32, i32)],
    value: f64,
) -> OpResult<ImageU8> {
    if width <= 0 || height <= 0 {
        return Err(format!("fill_poly: invalid mask size {width}x{height}"));
    }
    let mut canvas = GrayImage::new(width as u32, height as u32);
    let color = Luma([saturate_u8_f64(value)]);

    let mut pts: Vec<Point<i32>> = Vec::with_capacity(polygon.len());
    for &(x, y) in polygon {
        if pts.last() != Some(&Point::new(x, y)) {
            pts.push(Point::new(x, y));
        }
    }
    while pts.len() > 1 && pts.first() == pts.last() {
        pts.pop();
    }

    match pts.as_slice() {
        [] => {}
        [p] => {
            if (0..width).contains(&p.x) && (0..height).contains(&p.y) {
                canvas.put_pixel(p.x as u32, p.y as u32, color);
            }
        }
        [a, b] => imageproc::drawing::draw_line_segment_mut(
            &mut canvas,
            (a.x as f32, a.y as f32),
            (b.x as f32, b.y as f32),
            color,
        ),
        _ => draw_polygon_mut(&mut canvas, &pts, color),
    }
    ImageU8::new(width, height, 1, canvas.into_raw())
}
