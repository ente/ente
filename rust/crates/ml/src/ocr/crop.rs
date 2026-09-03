use super::Point;
use crate::cv;
use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};

const VERTICAL_ASPECT: f32 = 1.5;
const COUNTER_CLOCKWISE_DEGREES: i32 = 270;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Orientation {
    Horizontal,
    Vertical,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct TextCrop {
    pub(crate) image: ImageU8,
    pub(crate) orientation: Orientation,
}

pub(crate) fn crop_text(working: &ImageU8, quad: &[Point; 4]) -> MlResult<TextCrop> {
    let (width, height) = crop_size(quad);
    let warped = warp_to_rectangle(working, quad, width, height)?;
    if is_vertical(width, height) {
        Ok(TextCrop {
            image: rotate_counter_clockwise(&warped)?,
            orientation: Orientation::Vertical,
        })
    } else {
        Ok(TextCrop {
            image: warped,
            orientation: Orientation::Horizontal,
        })
    }
}

pub(crate) fn crop_size(quad: &[Point; 4]) -> (i32, i32) {
    let [tl, tr, br, bl] = *quad;
    let width = tl.distance(tr).max(bl.distance(br));
    let height = tl.distance(bl).max(tr.distance(br));
    (truncated_side(width), truncated_side(height))
}

fn truncated_side(length: f32) -> i32 {
    (length.trunc() as i32).max(1)
}

fn is_vertical(width: i32, height: i32) -> bool {
    height as f32 / width as f32 >= VERTICAL_ASPECT
}

fn warp_to_rectangle(
    working: &ImageU8,
    quad: &[Point; 4],
    width: i32,
    height: i32,
) -> MlResult<ImageU8> {
    let source_corners = quad.map(|p| (f64::from(p.x), f64::from(p.y)));
    let (w, h) = (f64::from(width), f64::from(height));
    let target_corners = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)];
    cv::warp_perspective(working, source_corners, target_corners, width, height)
        .map_err(MlError::Preprocess)
}

fn rotate_counter_clockwise(image: &ImageU8) -> MlResult<ImageU8> {
    cv::rotate_u8(image, COUNTER_CLOCKWISE_DEGREES).map_err(MlError::Preprocess)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn quad(points: [(f32, f32); 4]) -> [Point; 4] {
        points.map(|(x, y)| Point::new(x, y))
    }

    fn gradient_image(width: i32, height: i32) -> ImageU8 {
        let data = (0..height)
            .flat_map(|y| (0..width).flat_map(move |x| [x as u8, y as u8, (x + y) as u8]))
            .collect();
        ImageU8::new(width, height, 3, data).unwrap()
    }

    fn pixel(image: &ImageU8, x: i32, y: i32) -> [u8; 3] {
        let offset = ((y * image.width + x) * 3) as usize;
        [
            image.data[offset],
            image.data[offset + 1],
            image.data[offset + 2],
        ]
    }

    #[test]
    fn crop_size_truncates_the_longer_opposite_edges() {
        let size = crop_size(&quad([
            (10.0, 10.0),
            (110.7, 10.0),
            (110.7, 30.2),
            (10.0, 29.5),
        ]));
        assert_eq!(size, (100, 20));
    }

    #[test]
    fn crop_size_never_collapses_below_one_pixel() {
        let size = crop_size(&quad([(5.0, 5.0), (5.4, 5.0), (5.4, 5.3), (5.0, 5.3)]));
        assert_eq!(size, (1, 1));
    }

    #[test]
    fn axis_aligned_crop_reproduces_the_source_pixels() {
        let source = gradient_image(40, 30);
        let crop = crop_text(
            &source,
            &quad([(8.0, 5.0), (28.0, 5.0), (28.0, 17.0), (8.0, 17.0)]),
        )
        .unwrap();
        assert_eq!(crop.orientation, Orientation::Horizontal);
        assert_eq!((crop.image.width, crop.image.height), (20, 12));
        for y in 0..12 {
            for x in 0..20 {
                assert_eq!(
                    pixel(&crop.image, x, y),
                    pixel(&source, x + 8, y + 5),
                    "pixel ({x}, {y})"
                );
            }
        }
    }

    #[test]
    fn tall_crop_is_rotated_so_its_right_edge_becomes_the_top() {
        let source = gradient_image(40, 60);
        let crop = crop_text(
            &source,
            &quad([(4.0, 2.0), (6.0, 2.0), (6.0, 5.0), (4.0, 5.0)]),
        )
        .unwrap();
        assert_eq!(crop.orientation, Orientation::Vertical);
        assert_eq!((crop.image.width, crop.image.height), (3, 2));
        assert_eq!(pixel(&crop.image, 0, 0), pixel(&source, 5, 2));
        assert_eq!(pixel(&crop.image, 2, 0), pixel(&source, 5, 4));
        assert_eq!(pixel(&crop.image, 0, 1), pixel(&source, 4, 2));
        assert_eq!(pixel(&crop.image, 2, 1), pixel(&source, 4, 4));
    }

    #[test]
    fn aspect_of_exactly_one_and_a_half_counts_as_vertical() {
        assert!(is_vertical(2, 3));
        assert!(!is_vertical(3, 4));
        assert!(!is_vertical(1, 1));
    }

    #[test]
    fn counter_clockwise_rotation_moves_the_top_right_corner_to_the_top_left() {
        let [a, b, c, d, e, f] = [1u8, 2, 3, 4, 5, 6];
        let source = ImageU8::new(
            2,
            3,
            3,
            [a, b, c, d, e, f].iter().flat_map(|&v| [v, v, v]).collect(),
        )
        .unwrap();

        let rotated = rotate_counter_clockwise(&source).unwrap();

        assert_eq!((rotated.width, rotated.height), (3, 2));
        let values: Vec<u8> = rotated
            .data
            .as_chunks::<3>()
            .0
            .iter()
            .map(|px| px[0])
            .collect();
        assert_eq!(values, [b, d, f, a, c, e]);
    }
}
