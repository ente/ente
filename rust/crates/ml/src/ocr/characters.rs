use super::recognize::CharacterSpan;
use super::{CharacterBox, Orientation, Point};

const MIN_SPAN_LENGTH: f32 = 1e-4;

pub(crate) fn character_boxes(
    quad: &[Point; 4],
    spans: &[CharacterSpan],
    orientation: Orientation,
    rotated: bool,
) -> Vec<CharacterBox> {
    spans
        .iter()
        .filter_map(|span| {
            let (start, end) = span_range(span, rotated)?;
            Some(CharacterBox {
                text: span.text.clone(),
                confidence: span.confidence,
                points: span_polygon(quad, orientation, start, end),
            })
        })
        .collect()
}

fn span_range(span: &CharacterSpan, rotated: bool) -> Option<(f32, f32)> {
    let (start, end) = if rotated {
        (1.0 - span.end, 1.0 - span.start)
    } else {
        (span.start, span.end)
    };
    let start = start.clamp(0.0, 1.0);
    let end = end.clamp(start, 1.0);
    (end - start > MIN_SPAN_LENGTH).then_some((start, end))
}

fn span_polygon(quad: &[Point; 4], orientation: Orientation, start: f32, end: f32) -> [Point; 4] {
    let [tl, tr, br, bl] = *quad;
    match orientation {
        Orientation::Horizontal => [
            lerp(tl, tr, start),
            lerp(tl, tr, end),
            lerp(bl, br, end),
            lerp(bl, br, start),
        ],
        Orientation::Vertical => [
            lerp(tl, bl, start),
            lerp(tr, br, start),
            lerp(tr, br, end),
            lerp(tl, bl, end),
        ],
    }
}

fn lerp(from: Point, to: Point, ratio: f32) -> Point {
    from + (to - from) * ratio
}

#[cfg(test)]
mod tests {
    use super::*;

    fn span(text: &str, start: f32, end: f32) -> CharacterSpan {
        CharacterSpan {
            text: text.to_string(),
            confidence: 0.9,
            start,
            end,
        }
    }

    fn quad(points: [(f32, f32); 4]) -> [Point; 4] {
        points.map(|(x, y)| Point::new(x, y))
    }

    fn wide_quad() -> [Point; 4] {
        quad([(0.0, 0.0), (100.0, 0.0), (100.0, 10.0), (0.0, 10.0)])
    }

    fn tall_quad() -> [Point; 4] {
        quad([(0.0, 0.0), (10.0, 0.0), (10.0, 100.0), (0.0, 100.0)])
    }

    #[test]
    fn horizontal_spans_interpolate_along_the_top_and_bottom_edges() {
        let boxes = character_boxes(
            &wide_quad(),
            &[span("a", 0.25, 0.5), span("b", 0.5, 1.0)],
            Orientation::Horizontal,
            false,
        );
        assert_eq!(boxes.len(), 2);
        assert_eq!(boxes[0].text, "a");
        assert_eq!(boxes[0].confidence, 0.9);
        assert_eq!(
            boxes[0].points,
            quad([(25.0, 0.0), (50.0, 0.0), (50.0, 10.0), (25.0, 10.0)])
        );
        assert_eq!(
            boxes[1].points,
            quad([(50.0, 0.0), (100.0, 0.0), (100.0, 10.0), (50.0, 10.0)])
        );
    }

    #[test]
    fn sheared_quads_interpolate_each_edge_separately() {
        let sheared = quad([(10.0, 10.0), (50.0, 30.0), (40.0, 50.0), (0.0, 30.0)]);
        let boxes = character_boxes(
            &sheared,
            &[span("a", 0.5, 1.0)],
            Orientation::Horizontal,
            false,
        );
        assert_eq!(
            boxes[0].points,
            quad([(30.0, 20.0), (50.0, 30.0), (40.0, 50.0), (20.0, 40.0)])
        );
    }

    #[test]
    fn vertical_spans_interpolate_along_the_left_and_right_edges() {
        let boxes = character_boxes(
            &tall_quad(),
            &[span("a", 0.25, 0.5)],
            Orientation::Vertical,
            false,
        );
        assert_eq!(
            boxes[0].points,
            quad([(0.0, 25.0), (10.0, 25.0), (10.0, 50.0), (0.0, 50.0)])
        );
    }

    #[test]
    fn rotated_horizontal_spans_are_mirrored() {
        let boxes = character_boxes(
            &wide_quad(),
            &[span("a", 0.25, 0.5)],
            Orientation::Horizontal,
            true,
        );
        assert_eq!(
            boxes[0].points,
            quad([(50.0, 0.0), (75.0, 0.0), (75.0, 10.0), (50.0, 10.0)])
        );
    }

    #[test]
    fn rotated_vertical_spans_are_mirrored_bottom_to_top() {
        let boxes = character_boxes(
            &tall_quad(),
            &[span("a", 0.0, 0.25)],
            Orientation::Vertical,
            true,
        );
        assert_eq!(
            boxes[0].points,
            quad([(0.0, 75.0), (10.0, 75.0), (10.0, 100.0), (0.0, 100.0)])
        );
    }

    #[test]
    fn empty_and_out_of_range_spans_are_dropped() {
        let boxes = character_boxes(
            &wide_quad(),
            &[
                span("a", 0.5, 0.5),
                span("b", 0.7, 0.6),
                span("c", 1.2, 1.5),
                span("d", -0.5, 0.1),
            ],
            Orientation::Horizontal,
            false,
        );
        assert_eq!(boxes.len(), 1);
        assert_eq!(boxes[0].text, "d");
        assert_eq!(
            boxes[0].points,
            quad([(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)])
        );
    }
}
