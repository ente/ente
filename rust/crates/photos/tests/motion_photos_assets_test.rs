use ente_photos::{
    extract_motion_video_file_from_path, extract_motion_video_from_path,
    get_motion_video_index_from_path,
};
use std::path::{Path, PathBuf};

// External fixtures live beside the repository unless overridden.
fn fixture_dir() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("ENTE_TEST_FIXTURES_DIR") {
        return Some(PathBuf::from(path).join("media/motion-photos/v1/files"));
    }

    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let repo_root = manifest_dir.parent()?.parent()?.parent()?;
    let parent_of_repo = repo_root.parent()?;
    Some(
        parent_of_repo
            .join("test-fixtures")
            .join("media/motion-photos/v1/files"),
    )
}

fn fixture(name: &str) -> Option<PathBuf> {
    let mut path = fixture_dir()?;
    path.push(name);
    if path.exists() { Some(path) } else { None }
}

#[test]
fn validates_known_motion_photo_indices_when_fixtures_present() {
    let Some(motion_jpg) = fixture("motionphoto.jpg") else {
        eprintln!("Skipping: external fixture motionphoto.jpg not present");
        return;
    };
    let Some(motion_heic) = fixture("motionphoto.heic") else {
        eprintln!("Skipping: external fixture motionphoto.heic not present");
        return;
    };
    let Some(pixel6) = fixture("pixel_6_small_video.jpg") else {
        eprintln!("Skipping: external fixture pixel_6_small_video.jpg not present");
        return;
    };
    let Some(pixel8) = fixture("pixel_8.jpg") else {
        eprintln!("Skipping: external fixture pixel_8.jpg not present");
        return;
    };
    let Some(normal) = fixture("normalphoto.jpg") else {
        eprintln!("Skipping: external fixture normalphoto.jpg not present");
        return;
    };

    let motion_jpg_index = get_motion_video_index_from_path(&motion_jpg)
        .expect("read motionphoto.jpg")
        .expect("motionphoto.jpg should have index");
    assert_eq!(motion_jpg_index.start, 3_366_251);
    assert_eq!(motion_jpg_index.end, 8_013_982);

    let motion_heic_index = get_motion_video_index_from_path(&motion_heic)
        .expect("read motionphoto.heic")
        .expect("motionphoto.heic should have index");
    assert_eq!(motion_heic_index.start, 1_455_411);
    assert_eq!(motion_heic_index.end, 3_649_069);

    let pixel6_index = get_motion_video_index_from_path(&pixel6)
        .expect("read pixel_6_small_video.jpg")
        .expect("pixel_6_small_video.jpg should have index");
    assert!(pixel6_index.start > 0);

    assert_eq!(
        get_motion_video_index_from_path(&pixel8).expect("read pixel_8.jpg"),
        None
    );
    assert_eq!(
        get_motion_video_index_from_path(&normal).expect("read normalphoto.jpg"),
        None
    );

    let motion_jpg_video = extract_motion_video_from_path(&motion_jpg, None)
        .expect("extract motionphoto.jpg video")
        .expect("video present");
    assert!(motion_jpg_video.len() > 1_000_000);

    let motion_heic_video = extract_motion_video_from_path(&motion_heic, None)
        .expect("extract motionphoto.heic video")
        .expect("video present");
    assert!(motion_heic_video.len() > 1_000_000);

    let Some(dual_mp4) = fixture("dual_mp4_video_last.jpg") else {
        eprintln!("Skipping: external fixture dual_mp4_video_last.jpg not present");
        return;
    };
    let dual_index = get_motion_video_index_from_path(&dual_mp4)
        .expect("read dual_mp4_video_last.jpg")
        .expect("dual_mp4_video_last.jpg should have index");
    assert_eq!(dual_index.start, 3_590_234);
    assert_eq!(dual_index.end, 7_638_778);

    let dual_video = extract_motion_video_from_path(&dual_mp4, None)
        .expect("extract dual_mp4_video_last.jpg video")
        .expect("video present");
    assert!(dual_video.len() > 1_000_000);

    let Some(dual_mp4_first) = fixture("dual_mp4_video_first.jpg") else {
        eprintln!("Skipping: external fixture dual_mp4_video_first.jpg not present");
        return;
    };
    let dual_first_index = get_motion_video_index_from_path(&dual_mp4_first)
        .expect("read dual_mp4_video_first.jpg")
        .expect("dual_mp4_video_first.jpg should have index");
    assert_eq!(dual_first_index.start, 2_708_585);
    assert_eq!(dual_first_index.end, 7_890_703);

    let dual_first_video = extract_motion_video_from_path(&dual_mp4_first, None)
        .expect("extract dual_mp4_video_first.jpg video")
        .expect("video present");
    assert!(dual_first_video.len() > 1_000_000);
}

#[test]
fn file_extraction_matches_video_bytes_when_fixtures_present() {
    let output_directory = tempfile::tempdir().expect("output directory");
    for name in [
        "motionphoto.jpg",
        "motionphoto.heic",
        "pixel_6_small_video.jpg",
        "dual_mp4_video_last.jpg",
        "dual_mp4_video_first.jpg",
    ] {
        let Some(path) = fixture(name) else {
            eprintln!("Skipping: external fixture {name} not present");
            return;
        };
        let source = std::fs::read(&path).expect("read fixture");
        let index = get_motion_video_index_from_path(&path)
            .expect("find video")
            .expect("video present");
        let expected = &source[index.start..index.end];

        for supplied_index in [None, Some(index)] {
            let video = extract_motion_video_from_path(&path, supplied_index.clone())
                .expect("extract bytes")
                .expect("video present");
            let output = extract_motion_video_file_from_path(
                &path,
                output_directory.path(),
                "clip.mp4",
                supplied_index,
            )
            .expect("extract file")
            .expect("video file present");

            assert_eq!(video, expected, "{name}");
            assert_eq!(std::fs::read(output).unwrap(), expected, "{name}");
        }
    }
}
