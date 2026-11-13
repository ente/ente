use ente_exif::{DateTimeKind, Ifd, Limits, Mode, TextEncoding};
use std::fs::File;
use std::io::BufReader;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1).peekable();
    let mode = if args.peek().is_some_and(|arg| arg == "--details") {
        args.next();
        Mode::Details
    } else {
        Mode::Summary
    };
    for path in args {
        let mut file = BufReader::with_capacity(16 * 1024, File::open(&path)?);
        let metadata = ente_exif::read(&mut file, mode, Limits::default())?;
        println!("{path}");
        println!("display dimensions: {:?}", metadata.display_dimensions());
        println!("capture date/time: {:?}", metadata.capture_date_time());
        println!(
            "stored dimensions: {:?} × {:?}",
            metadata.width(),
            metadata.height()
        );
        println!(
            "EXIF orientation: {:?}; native transforms: {:?}",
            metadata.orientation(),
            metadata.transforms
        );
        println!(
            "camera: {:?} {:?}; lens: {:?}",
            metadata.camera_make(),
            metadata.camera_model(),
            metadata.lens_model()
        );
        println!(
            "exposure seconds: {:?}; f-number: {:?}; focal length mm: {:?}; sensitivity: {:?}",
            metadata.exposure_time(),
            metadata.f_number(),
            metadata.focal_length(),
            metadata.iso_speed_ratings()
        );
        for kind in [
            DateTimeKind::Original,
            DateTimeKind::Digitized,
            DateTimeKind::Modified,
        ] {
            if let Some(date) = metadata.exif_date_time(kind) {
                println!(
                    "EXIF {kind:?}: {date}; epoch microseconds: {:?}",
                    date.unix_micros()
                );
            }
        }
        println!(
            "EXIF location: {:?}; XMP location: {:?}",
            metadata.exif_location(),
            metadata.xmp_location()
        );
        println!(
            "EXIF description: {:?}; XMP description: {:?}",
            metadata.exif_description(),
            metadata.xmp_description(None)
        );
        println!(
            "EXIF description as Latin-1: {:?}; IPTC caption (Windows-1252 fallback): {:?}",
            metadata
                .tag(Ifd::Image(0), 0x10e)
                .and_then(|t| t.value.text_with(TextEncoding::Latin1)),
            metadata.iptc_caption(TextEncoding::Windows1252)
        );
        println!("panorama: {}", metadata.is_panorama());
        if let Some(video) = metadata.motion_video {
            println!(
                "motion video: [{}..{}), {} bytes",
                video.start,
                video.end,
                video.end - video.start
            );
        } else {
            println!("motion video: none detected");
        }
        println!(
            "issues: {:?}; reads: {:?}",
            metadata.issues, metadata.statistics
        );
        if mode == Mode::Details {
            println!("{metadata:#?}");
        }
    }
    Ok(())
}
