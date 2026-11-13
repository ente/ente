use ente_exif::{Limits, Mode};
use std::fs::File;
use std::io::{self, BufReader, Read, Seek, SeekFrom};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let (Some(input), Some(output), None) = (args.next(), args.next(), args.next()) else {
        return Err("usage: extract_motion INPUT OUTPUT.mp4".into());
    };
    let mut source = BufReader::with_capacity(16 * 1024, File::open(input)?);
    let metadata = ente_exif::read(&mut source, Mode::Summary, Limits::default())?;
    let video = metadata.motion_video.ok_or("no motion video detected")?;
    source.seek(SeekFrom::Start(video.start))?;
    let mut output = File::create_new(output)?;
    let copied = io::copy(&mut source.take(video.end - video.start), &mut output)?;
    println!(
        "copied {copied} bytes from [{}..{})",
        video.start, video.end
    );
    Ok(())
}
