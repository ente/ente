use super::*;

type TestResult = Result<(), Box<dyn std::error::Error>>;

#[tokio::test]
async fn shared_http_follows_redirects_and_resolves_declared_icons() -> TestResult {
    let mut server = mockito::Server::new_async().await;
    let page = server
        .mock("GET", "/")
        .with_status(302)
        .with_header("location", "/home")
        .create_async()
        .await;
    let html = server
        .mock("GET", "/home")
        .with_body("<head><base href=/assets/><link rel=icon href=logo.png></head>")
        .create_async()
        .await;
    let redirect = server
        .mock("GET", "/assets/logo.png")
        .with_status(302)
        .with_header("location", "/logo.png")
        .create_async()
        .await;
    let mut png = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgba8(image::RgbaImage::from_pixel(
        2,
        2,
        image::Rgba([10, 20, 30, 255]),
    ))
    .write_to(&mut png, image::ImageFormat::Png)?;
    let image = server
        .mock("GET", "/logo.png")
        .with_body(png.into_inner())
        .create_async()
        .await;
    let icon = Fetcher::new()?
        .fetch(&format!("{}/", server.url()))
        .await?
        .ok_or("missing icon")?;
    assert_eq!(icon.url.as_str(), format!("{}/logo.png", server.url()));
    assert_eq!(image::load_from_memory(&icon.data)?.width(), 2);
    page.assert_async().await;
    html.assert_async().await;
    redirect.assert_async().await;
    image.assert_async().await;
    Ok(())
}

#[test]
fn parent_fallback_respects_registration_boundaries() -> TestResult {
    for (input, expected) in [
        (
            "https://login.example.co.uk/signin?q=1",
            Some("https://example.co.uk/"),
        ),
        (
            "http://a.user.github.io:8080/login",
            Some("http://user.github.io:8080/"),
        ),
        (
            "https://user:secret@login.example.com/",
            Some("https://example.com/"),
        ),
        ("https://example.com/", None),
        ("https://gov.uk/", None),
        ("http://localhost/", None),
        ("http://127.0.0.1/", None),
    ] {
        let parent = parent_url(&Url::parse(input)?);
        assert_eq!(parent.as_ref().map(Url::as_str), expected, "{input}");
    }
    Ok(())
}

#[tokio::test]
async fn rejects_missing_urls_and_unsupported_schemes() -> TestResult {
    let fetcher = Fetcher::new()?;
    for input in [
        "",
        "example.com",
        "file:///tmp/icon.png",
        "data:image/png;base64,abc",
    ] {
        assert!(
            matches!(fetcher.fetch(input).await, Err(Error::InvalidUrl)),
            "{input}"
        );
    }
    Ok(())
}

#[tokio::test]
async fn bounds_streamed_bodies_without_trusting_content_length() -> TestResult {
    let mut server = mockito::Server::new_async().await;
    let response = server
        .mock("GET", "/body")
        .with_chunked_body(|writer| writer.write_all(&[b'a'; 20]))
        .expect(2)
        .create_async()
        .await;
    let http = Http::new()?;
    let url = format!("{}/body", server.url());
    let prefix = http.get(&url).send().await?.error_for_status()?;
    assert_eq!(body(prefix, 10, true).await?, vec![b'a'; 10]);
    let full = http.get(&url).send().await?.error_for_status()?;
    assert!(matches!(body(full, 10, false).await, Err(Error::TooLarge)));
    response.assert_async().await;
    Ok(())
}
