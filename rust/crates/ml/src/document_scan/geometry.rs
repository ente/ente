//! Quad/point geometry. All arithmetic is f64.

/// Sequential mean; NaN for an empty iterator.
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

/// Four document corners in a fixed winding order.
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

    /// Rotates the four corners by `iterations` quarter turns inside
    /// `image_size` and re-sorts them through `create_quad`. A negative
    /// `iterations` falls into the identity branch (truncating `%`).
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

/// Sorts the four vertices by `atan2(y-cy, x-cx)` ascending with a stable
/// sort, then assigns them positionally. `total_cmp` keeps the total order
/// (-0.0 < 0.0) the original comparison used.
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
