//! Real-dimension estimation from the quad's vanishing-point geometry,
//! optionally improved by camera intrinsics.

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

/// Camera intrinsics as the platform camera API reports them.
/// `focal_length_in_pixels` deliberately evaluates in f32 before widening.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CameraIntrinsics {
    pub focal_length_mm: f32,
    pub sensor_width_mm: f32,
}

impl CameraIntrinsics {
    pub(crate) fn focal_length_in_pixels(&self, image_width_in_pixels: i32) -> f32 {
        self.focal_length_mm / self.sensor_width_mm * image_width_in_pixels as f32
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct OpticalMeasures {
    pub camera_intrinsics: CameraIntrinsics,
    /// Millimetres; `None` when the capture carries no calibrated distance.
    pub subject_distance_mm: Option<f32>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum EstimatedDimensions {
    Physical { width_mm: f64, height_mm: f64 },
    Ratio { width: f64, height: f64 },
}

/// Standard paper formats, in this exact match order.
const PAPER_FORMATS: [(f64, f64); 5] = [
    (210.0, 297.0), // A4
    (215.9, 279.4), // Letter
    (215.9, 355.6), // Legal
    (148.0, 210.0), // A5
    (297.0, 420.0), // A3
];

impl EstimatedDimensions {
    pub(crate) fn aspect_ratio(&self) -> f64 {
        match *self {
            EstimatedDimensions::Physical {
                width_mm,
                height_mm,
            } => height_mm / width_mm,
            EstimatedDimensions::Ratio { width, height } => height / width,
        }
    }

    /// Returns `self` unchanged for `Ratio`.
    pub(crate) fn snap_to_standard_format(self) -> EstimatedDimensions {
        self.snap_to_standard_format_with(0.04, 0.20)
    }

    pub(crate) fn snap_to_standard_format_with(
        self,
        ratio_tolerance: f64,
        dimension_tolerance: f64,
    ) -> EstimatedDimensions {
        let (width_mm, height_mm) = match self {
            EstimatedDimensions::Physical {
                width_mm,
                height_mm,
            } => (width_mm, height_mm),
            EstimatedDimensions::Ratio { .. } => return self,
        };

        let (w, h) = if width_mm <= height_mm {
            (width_mm, height_mm)
        } else {
            (height_mm, width_mm)
        };
        let portrait = width_mm <= height_mm;

        for (fw, fh) in PAPER_FORMATS {
            let ratio_error = ((h / w) - (fh / fw)).abs() / (fh / fw);
            let dim_error = ((w - fw).abs() / fw).max((h - fh).abs() / fh);
            if ratio_error < ratio_tolerance && dim_error < dimension_tolerance {
                return if portrait {
                    EstimatedDimensions::Physical {
                        width_mm: fw,
                        height_mm: fh,
                    }
                } else {
                    EstimatedDimensions::Physical {
                        width_mm: fh,
                        height_mm: fw,
                    }
                };
            }
        }

        self
    }

    pub(crate) fn to_pixel_dimensions(self, quad: &Quad) -> (f64, f64) {
        let w =
            (norm(quad.top_left, quad.top_right) + norm(quad.bottom_left, quad.bottom_right)) / 2.0;
        let h =
            (norm(quad.top_left, quad.bottom_left) + norm(quad.top_right, quad.bottom_right)) / 2.0;
        let projected_area = w * h;

        let ratio = self.aspect_ratio();
        let target_width = (projected_area / ratio).sqrt();
        let target_height = target_width * ratio;
        (target_width, target_height)
    }
}

pub(crate) fn estimate_real_dimensions(
    quad: &Quad,
    image_width: i32,
    image_height: i32,
    optical_measures: Option<OpticalMeasures>,
) -> EstimatedDimensions {
    let average_sides = || EstimatedDimensions::Ratio {
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

    let f = match optical_measures {
        Some(measures) => measures
            .camera_intrinsics
            .focal_length_in_pixels(image_width.max(image_height)) as f64,
        None => {
            let f2 = -(v1.x * v2.x + v1.y * v2.y);
            if f2 <= 0.0 {
                return average_sides();
            }
            f2.sqrt()
        }
    };

    if f > (image_width.max(image_height)) as f64 * 1.2 {
        return average_sides();
    }

    let d1 = Vector3D::new(v1.x, v1.y, f);
    let d2 = Vector3D::new(v2.x, v2.y, f);
    let n = d1.cross(d2);

    let ray = |p: Point| Vector3D::new((p.x - cx) / f, (p.y - cy) / f, 1.0);

    let subject_distance = optical_measures.and_then(|m| m.subject_distance_mm);
    let scale: Option<f64> = match subject_distance {
        Some(distance) => {
            let center_x =
                (quad.top_left.x + quad.top_right.x + quad.bottom_left.x + quad.bottom_right.x)
                    / 4.0;
            let center_y =
                (quad.top_left.y + quad.top_right.y + quad.bottom_left.y + quad.bottom_right.y)
                    / 4.0;
            let raw = ray(Point::new(center_x, center_y));
            let center_ray = raw.scale(1.0 / raw.norm());
            let cos_angle = center_ray.dot(n).abs();
            if cos_angle < 0.1 {
                None
            } else {
                Some(distance as f64 * cos_angle)
            }
        }
        None => None,
    };

    let corner3d = |p: Point| {
        let r = ray(p);
        let t = match scale {
            Some(s) => s / n.dot(r),
            None => 1.0 / n.dot(r),
        };
        r.scale(t)
    };

    let x_tl = corner3d(quad.top_left);
    let x_tr = corner3d(quad.top_right);
    let x_br = corner3d(quad.bottom_right);
    let x_bl = corner3d(quad.bottom_left);

    let real_w = (x_tr.sub(x_tl).norm() + x_br.sub(x_bl).norm()) / 2.0;
    let real_h = (x_bl.sub(x_tl).norm() + x_br.sub(x_tr).norm()) / 2.0;

    if optical_measures.is_some() && scale.is_some() {
        EstimatedDimensions::Physical {
            width_mm: real_w,
            height_mm: real_h,
        }
    } else {
        EstimatedDimensions::Ratio {
            width: real_w,
            height: real_h,
        }
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
        // A perfect rectangle has both vanishing points at infinity, so the
        // average-sides fallback applies.
        let quad = rect_quad(400.0, 300.0);
        let dims = estimate_real_dimensions(&quad, 1000, 800, None);
        assert_eq!(
            dims,
            EstimatedDimensions::Ratio {
                width: 400.0,
                height: 300.0
            }
        );
    }

    #[test]
    fn estimate_real_dimensions_falls_back_for_weak_perspective() {
        // Barely trapezoidal: f exceeds max(w,h)*1.2, so the fallback applies.
        let quad = Quad {
            top_left: Point::new(100.0, 100.0),
            top_right: Point::new(900.0, 100.0),
            bottom_right: Point::new(899.0, 700.0),
            bottom_left: Point::new(101.0, 700.0),
        };
        let dims = estimate_real_dimensions(&quad, 1000, 800, None);
        match dims {
            EstimatedDimensions::Ratio { width, height } => {
                assert_close(width, 799.0, 1e-9);
                assert_close(height, 600.0008333, 1e-6);
            }
            other => panic!("expected Ratio, got {other:?}"),
        }
    }

    #[test]
    fn snap_to_standard_format_is_a_noop_for_ratio() {
        let dims = EstimatedDimensions::Ratio {
            width: 210.0,
            height: 297.0,
        };
        assert_eq!(dims.snap_to_standard_format(), dims);
    }

    #[test]
    fn snap_to_standard_format_snaps_physical_to_a4() {
        let dims = EstimatedDimensions::Physical {
            width_mm: 208.0,
            height_mm: 294.0,
        };
        assert_eq!(
            dims.snap_to_standard_format(),
            EstimatedDimensions::Physical {
                width_mm: 210.0,
                height_mm: 297.0
            }
        );
    }

    #[test]
    fn to_pixel_dimensions_preserves_area_and_ratio() {
        let quad = rect_quad(400.0, 300.0);
        let dims = estimate_real_dimensions(&quad, 1000, 800, None).snap_to_standard_format();
        let (w, h) = dims.to_pixel_dimensions(&quad);
        assert_close(w * h, 400.0 * 300.0, 1e-6);
        assert_close(h / w, 300.0 / 400.0, 1e-12);
    }
}
