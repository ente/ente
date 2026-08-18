pub(crate) fn average(values: impl Iterator<Item = f64>) -> f64 {
    let mut sum = 0.0;
    let mut count = 0usize;
    for v in values {
        sum += v;
        count += 1;
    }
    if count == 0 {
        f64::NAN
    } else {
        sum / count as f64
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

impl Point {
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }

    pub(crate) fn scaled(&self, scale_x: f64, scale_y: f64) -> Point {
        Point::new(self.x * scale_x, self.y * scale_y)
    }
}

pub(crate) fn norm(p1: Point, p2: Point) -> f64 {
    (p2.x - p1.x).hypot(p2.y - p1.y)
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct ImageSize {
    pub width: f64,
    pub height: f64,
}

impl ImageSize {
    pub(crate) fn new(width: f64, height: f64) -> Self {
        Self { width, height }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Quad {
    pub top_left: Point,
    pub top_right: Point,
    pub bottom_right: Point,
    pub bottom_left: Point,
}

impl Quad {
    pub fn corners(&self) -> [Point; 4] {
        [
            self.top_left,
            self.top_right,
            self.bottom_right,
            self.bottom_left,
        ]
    }

    pub(crate) fn edges(&self) -> [(Point, Point); 4] {
        [
            (self.top_left, self.top_right),
            (self.top_right, self.bottom_right),
            (self.bottom_right, self.bottom_left),
            (self.bottom_left, self.top_left),
        ]
    }

    pub(crate) fn rotate90(&self, iterations: i32, image_size: ImageSize) -> Quad {
        let rotate = |p: Point| -> Point {
            match iterations % 4 {
                1 => Point::new(image_size.height - p.y, p.x),
                2 => Point::new(image_size.width - p.x, image_size.height - p.y),
                3 => Point::new(p.y, image_size.width - p.x),
                _ => p,
            }
        };
        create_quad(&[
            rotate(self.top_left),
            rotate(self.top_right),
            rotate(self.bottom_right),
            rotate(self.bottom_left),
        ])
    }

    pub(crate) fn scaled_to(
        &self,
        from_width: f64,
        from_height: f64,
        to_width: f64,
        to_height: f64,
    ) -> Quad {
        let scale_x = to_width / from_width;
        let scale_y = to_height / from_height;
        Quad {
            top_left: self.top_left.scaled(scale_x, scale_y),
            top_right: self.top_right.scaled(scale_x, scale_y),
            bottom_right: self.bottom_right.scaled(scale_x, scale_y),
            bottom_left: self.bottom_left.scaled(scale_x, scale_y),
        }
    }
}

pub(crate) fn create_quad(vertices: &[Point]) -> Quad {
    assert_eq!(vertices.len(), 4, "create_quad requires exactly 4 vertices");
    let cx = average(vertices.iter().map(|p| p.x));
    let cy = average(vertices.iter().map(|p| p.y));

    let mut sorted = vertices.to_vec();
    sorted.sort_by(|a, b| {
        let aa = (a.y - cy).atan2(a.x - cx);
        let bb = (b.y - cy).atan2(b.x - cx);
        aa.total_cmp(&bb)
    });

    Quad {
        top_left: sorted[0],
        top_right: sorted[1],
        bottom_right: sorted[2],
        bottom_left: sorted[3],
    }
}

#[cfg(test)]
mod tests {
    use super::{ImageSize, Point, Quad, create_quad, norm};

    fn assert_close(a: f64, b: f64, eps: f64) {
        assert!((a - b).abs() <= eps, "expected {a} ~= {b} (eps {eps})");
    }

    #[test]
    fn create_quad_orders_corners_by_angle_from_centroid() {
        let vertices = vec![
            Point::new(100.0, 100.0),
            Point::new(0.0, 100.0),
            Point::new(0.0, 0.0),
            Point::new(100.0, 0.0),
        ];
        let quad = create_quad(&vertices);
        assert_eq!(quad.top_left, Point::new(0.0, 0.0));
        assert_eq!(quad.top_right, Point::new(100.0, 0.0));
        assert_eq!(quad.bottom_right, Point::new(100.0, 100.0));
        assert_eq!(quad.bottom_left, Point::new(0.0, 100.0));
    }

    #[test]
    fn create_quad_is_idempotent() {
        let quad = create_quad(&[
            Point::new(10.0, 12.0),
            Point::new(90.0, 8.0),
            Point::new(95.0, 70.0),
            Point::new(5.0, 74.0),
        ]);
        let again = create_quad(&quad.corners());
        assert_eq!(quad.top_left, again.top_left);
        assert_eq!(quad.top_right, again.top_right);
        assert_eq!(quad.bottom_right, again.bottom_right);
        assert_eq!(quad.bottom_left, again.bottom_left);
    }

    #[test]
    fn scaled_to_maps_mask_space_to_image_space() {
        let quad = Quad {
            top_left: Point::new(0.0, 0.0),
            top_right: Point::new(128.0, 0.0),
            bottom_right: Point::new(128.0, 256.0),
            bottom_left: Point::new(0.0, 256.0),
        };
        let scaled = quad.scaled_to(256.0, 256.0, 1024.0, 512.0);
        assert_close(scaled.top_right.x, 512.0, 1e-9);
        assert_close(scaled.bottom_right.y, 512.0, 1e-9);
    }

    #[test]
    fn norm_matches_hypot() {
        assert_close(norm(Point::new(0.0, 0.0), Point::new(3.0, 4.0)), 5.0, 1e-12);
    }

    #[test]
    fn image_size_keeps_doubles() {
        let size = ImageSize::new(1024.0, 768.0);
        assert_close(size.width, 1024.0, 0.0);
        assert_close(size.height, 768.0, 0.0);
    }
}
