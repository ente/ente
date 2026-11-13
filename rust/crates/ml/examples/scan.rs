use std::time::Instant;

use ente_ml::scan::{ColorMode, Point, Quad, ReprocessOptions, ScannerSession};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments.len() < 4 {
        return Err("usage: scan MODEL INPUT OUTPUT [PIXELS] [ROTATION] [color|gray] [x0,y0,x1,y1,x2,y2,x3,y3]".into());
    }
    let budget = arguments
        .get(4)
        .map(|v| v.parse::<u32>())
        .transpose()?
        .unwrap_or(2_000_000);
    let rotation = arguments
        .get(5)
        .map(|v| v.parse::<i32>())
        .transpose()?
        .unwrap_or(0);
    let mode = if arguments.get(6).is_some_and(|s| s == "gray") {
        ColorMode::Grayscale
    } else {
        ColorMode::Color
    };
    let start = Instant::now();
    let session = ScannerSession::new(&arguments[1])?;
    let load_ms = start.elapsed().as_secs_f64() * 1000.0;
    let bytes = std::fs::read(&arguments[2])?;
    let start = Instant::now();
    let result = if let Some(coordinates) = arguments.get(7) {
        let values = coordinates
            .split(',')
            .map(str::parse::<f64>)
            .collect::<Result<Vec<_>, _>>()?;
        if values.len() != 8 {
            return Err("quad requires eight coordinates".into());
        }
        let point = |i| Point {
            x: values[i],
            y: values[i + 1],
        };
        let quad = Quad {
            top_left: point(0),
            top_right: point(2),
            bottom_right: point(4),
            bottom_left: point(6),
        };
        session.reprocess(
            &bytes,
            &ReprocessOptions {
                quad,
                rotation_degrees: rotation,
                color_mode: mode,
                max_pixels: Some(budget),
            },
        )?
    } else {
        session.process_capture(&bytes, Some(budget))?
    };
    let process_ms = start.elapsed().as_secs_f64() * 1000.0;
    std::fs::write(&arguments[3], &result.processed_image)?;
    let quad = result.quad.map(|q| {
        vec![
            [q.top_left.x, q.top_left.y],
            [q.top_right.x, q.top_right.y],
            [q.bottom_right.x, q.bottom_right.y],
            [q.bottom_left.x, q.bottom_left.y],
        ]
    });
    println!(
        "{}",
        serde_json::json!({"source":[result.source_width,result.source_height],"output":[result.output_width,result.output_height],"mode":format!("{:?}",result.color_mode),"quad":quad,"bytes":result.processed_image.len(),"load_ms":load_ms,"process_ms":process_ms})
    );
    Ok(())
}
