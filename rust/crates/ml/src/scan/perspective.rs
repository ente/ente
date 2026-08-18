use super::geometry::{Point, Quad, norm};

#[derive(Clone, Copy, Debug)]
struct Vector3D {
    x: f64,
    y: f64,
    z: f64,
}

impl Vector3D {
    fn new(x: f64, y: f64, z: f64) -> Self {
        Self { x, y, z }
    }

    fn sub(self, other: Vector3D) -> Vector3D {
        Vector3D::new(self.x - other.x, self.y - other.y, self.z - other.z)
    }

    fn scale(self, t: f64) -> Vector3D {
        Vector3D::new(self.x * t, self.y * t, self.z * t)
    }

    fn dot(self, other: Vector3D) -> f64 {
        self.x * other.x + self.y * other.y + self.z * other.z
    }

    fn cross(self, other: Vector3D) -> Vector3D {
        Vector3D::new(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )
    }

    fn norm(self) -> f64 {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct EstimatedDimensions {
    pub(crate) width: f64,
    pub(crate) height: f64,
}

impl EstimatedDimensions {
    pub(crate) fn to_pixel_dimensions(self, quad: &Quad) -> (f64, f64) {
        let w =
            (norm(quad.top_left, quad.top_right) + norm(quad.bottom_left, quad.bottom_right)) / 2.0;
        let h =
            (norm(quad.top_left, quad.bottom_left) + norm(quad.top_right, quad.bottom_right)) / 2.0;
        let projected_area = w * h;

        let ratio = self.height / self.width;
        let target_width = (projected_area / ratio).sqrt();
        let target_height = target_width * ratio;
        (target_width, target_height)
    }
}

pub(crate) fn estimate_real_dimensions(
    quad: &Quad,
    image_width: i32,
    image_height: i32,
) -> EstimatedDimensions {
    let average_sides = || EstimatedDimensions {
        width: (norm(quad.top_left, quad.top_right) + norm(quad.bottom_left, quad.bottom_right))
            / 2.0,
        height: (norm(quad.top_left, quad.bottom_left) + norm(quad.top_right, quad.bottom_right))
            / 2.0,
    };

    let to_h = |p: Point| Vector3D::new(p.x, p.y, 1.0);
    let line_through = |p1: Point, p2: Point| to_h(p1).cross(to_h(p2));

    let v1h = line_through(quad.top_left, quad.top_right)
        .cross(line_through(quad.bottom_left, quad.bottom_right));
    let v2h = line_through(quad.top_left, quad.bottom_left)
        .cross(line_through(quad.top_right, quad.bottom_right));

    if v1h.z.abs() < 1e-6 || v2h.z.abs() < 1e-6 {
        return average_sides();
    }

    let cx = image_width as f64 / 2.0;
    let cy = image_height as f64 / 2.0;

    let v1 = Point::new(v1h.x / v1h.z - cx, v1h.y / v1h.z - cy);
    let v2 = Point::new(v2h.x / v2h.z - cx, v2h.y / v2h.z - cy);

    let f2 = -(v1.x * v2.x + v1.y * v2.y);
    if f2 <= 0.0 {
        return average_sides();
    }
    let f = f2.sqrt();

    if f > (image_width.max(image_height)) as f64 * 1.2 {
        return average_sides();
    }

    let d1 = Vector3D::new(v1.x, v1.y, f);
    let d2 = Vector3D::new(v2.x, v2.y, f);
    let n = d1.cross(d2);

    let ray = |p: Point| Vector3D::new((p.x - cx) / f, (p.y - cy) / f, 1.0);

    let corner3d = |p: Point| {
        let r = ray(p);
        r.scale(1.0 / n.dot(r))
    };

    let x_tl = corner3d(quad.top_left);
    let x_tr = corner3d(quad.top_right);
    let x_br = corner3d(quad.bottom_right);
    let x_bl = corner3d(quad.bottom_left);

    let real_w = (x_tr.sub(x_tl).norm() + x_br.sub(x_bl).norm()) / 2.0;
    let real_h = (x_bl.sub(x_tl).norm() + x_br.sub(x_tr).norm()) / 2.0;

    EstimatedDimensions {
        width: real_w,
        height: real_h,
    }
}

#[cfg(test)]
mod tests {
    use super::{EstimatedDimensions, estimate_real_dimensions};
    use crate::scan::geometry::{Point, Quad};

    fn assert_close(a: f64, b: f64, eps: f64) {
        assert!((a - b).abs() <= eps, "expected {a} ~= {b} (eps {eps})");
    }

    fn rect_quad(w: f64, h: f64) -> Quad {
        Quad {
            top_left: Point::new(0.0, 0.0),
            top_right: Point::new(w, 0.0),
            bottom_right: Point::new(w, h),
            bottom_left: Point::new(0.0, h),
        }
    }

    #[test]
    fn estimate_real_dimensions_falls_back_for_parallel_sides() {
        let quad = rect_quad(400.0, 300.0);
        let dims = estimate_real_dimensions(&quad, 1000, 800);
        assert_eq!(
            dims,
            EstimatedDimensions {
                width: 400.0,
                height: 300.0
            }
        );
    }

    #[test]
    fn estimate_real_dimensions_falls_back_for_weak_perspective() {
        let quad = Quad {
            top_left: Point::new(100.0, 100.0),
            top_right: Point::new(900.0, 100.0),
            bottom_right: Point::new(899.0, 700.0),
            bottom_left: Point::new(101.0, 700.0),
        };
        let dims = estimate_real_dimensions(&quad, 1000, 800);
        assert_close(dims.width, 799.0, 1e-9);
        assert_close(dims.height, 600.0008333, 1e-6);
    }

    #[test]
    fn to_pixel_dimensions_preserves_area_and_ratio() {
        let quad = rect_quad(400.0, 300.0);
        let dims = estimate_real_dimensions(&quad, 1000, 800);
        let (w, h) = dims.to_pixel_dimensions(&quad);
        assert_close(w * h, 400.0 * 300.0, 1e-6);
        assert_close(h / w, 300.0 / 400.0, 1e-12);
    }
}
