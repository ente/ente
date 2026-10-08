use std::collections::HashSet;

use scraper::{ElementRef, Html};
use url::Url;

const MAX_CANDIDATES: usize = 8;
const PREFERRED_SIZE: u32 = 128;

pub(crate) fn icon_urls(html: &str, page: &Url) -> Vec<Url> {
    let document = Html::parse_document(html);
    let Some(head) = document
        .root_element()
        .descendants()
        .filter_map(ElementRef::wrap)
        .find(|element| element.value().name() == "head")
    else {
        return Vec::new();
    };
    let base = head
        .descendants()
        .filter_map(ElementRef::wrap)
        .find(|element| element.value().name() == "base" && element.attr("href").is_some())
        .and_then(|element| page.join(element.attr("href")?.trim()).ok())
        .unwrap_or_else(|| page.clone());

    let mut candidates = Vec::new();
    for element in head.descendants().filter_map(ElementRef::wrap) {
        if element.value().name() != "link" {
            continue;
        }
        let Some(rel) = element.attr("rel") else {
            continue;
        };
        let icon = rel
            .split_ascii_whitespace()
            .any(|token| token.eq_ignore_ascii_case("icon"));
        let touch = rel.split_ascii_whitespace().any(|token| {
            token.eq_ignore_ascii_case("apple-touch-icon")
                || token.eq_ignore_ascii_case("apple-touch-icon-precomposed")
        });
        if !icon && !touch {
            continue;
        }
        let Some(href) = element
            .attr("href")
            .map(str::trim)
            .filter(|href| !href.is_empty())
        else {
            continue;
        };
        let Ok(mut url) = base.join(href) else {
            continue;
        };
        if !matches!(url.scheme(), "http" | "https") {
            continue;
        }
        url.set_fragment(None);
        let svg = element
            .attr("type")
            .is_some_and(|kind| kind.trim().eq_ignore_ascii_case("image/svg+xml"))
            || url
                .path()
                .rsplit_once('.')
                .is_some_and(|(_, extension)| extension.eq_ignore_ascii_case("svg"));
        let rank = (svg, size_rank(element.attr("sizes").unwrap_or("")), !icon);
        candidates.push((rank, url));
    }
    candidates.sort_by_key(|(rank, _)| *rank);
    let mut seen = HashSet::new();
    candidates
        .into_iter()
        .map(|(_, url)| url)
        .filter(|url| seen.insert(url.clone()))
        .take(MAX_CANDIDATES)
        .collect()
}

fn size_rank(sizes: &str) -> (u8, u32) {
    sizes
        .split_ascii_whitespace()
        .filter_map(|size| {
            let (width, height) = size.split_once(['x', 'X'])?;
            let width: u32 = width.parse().ok()?;
            let height: u32 = height.parse().ok()?;
            (width > 0 && width == height).then_some((
                u8::from(width < PREFERRED_SIZE),
                width.abs_diff(PREFERRED_SIZE),
            ))
        })
        .min()
        .unwrap_or((2, 0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_base_relative_and_cdn_links_and_orders_sizes() -> Result<(), url::ParseError> {
        let html = r#"<!doctype html><head>
            <link rel=ICON sizes=16x16 href=/small.png>
            <link rel="shortcut icon" sizes=128x128 href="best.png?a=1&amp;b=2">
            <base href="/assets/">
            <link rel=icon sizes=256x256 href=large.png>
            <link rel=apple-touch-icon href="//cdn.example.com/touch.png">
            <link rel=icon sizes=128x128 href="best.png?a=1&amp;b=2#duplicate">
            <link rel=stylesheet href=style.css>
            <link rel=icon href="http://cdn.example.com/plain.png">
            <link rel=icon href="data:image/png;base64,abc">
        </head><body><link rel=icon href=body.png>"#;
        let urls = icon_urls(html, &Url::parse("https://www.example.com/new/page")?);
        let urls: Vec<_> = urls.iter().map(Url::as_str).collect();
        assert_eq!(
            urls,
            [
                "https://www.example.com/assets/best.png?a=1&b=2",
                "https://www.example.com/assets/large.png",
                "https://www.example.com/small.png",
                "http://cdn.example.com/plain.png",
                "https://cdn.example.com/touch.png",
            ]
        );
        Ok(())
    }

    #[test]
    fn excludes_script_text_and_limits_candidate_requests() -> Result<(), url::ParseError> {
        let links: String = (0..20)
            .map(|i| format!("<link rel=icon href=/{i}.ico>"))
            .collect();
        let html = format!("<head><script>'<link rel=icon href=/fake.ico>'</script>{links}</head>");
        let urls = icon_urls(&html, &Url::parse("https://example.com")?);
        assert_eq!(urls.len(), MAX_CANDIDATES);
        assert_eq!(urls[0].path(), "/0.ico");
        Ok(())
    }

    #[test]
    fn declared_svgs_do_not_crowd_out_a_raster_candidate() -> Result<(), url::ParseError> {
        let mut html = "<head>".to_owned();
        for i in 0..MAX_CANDIDATES {
            html.push_str(&format!(
                "<link rel=icon type='image/svg+xml' sizes=any href=/{i}.svg>"
            ));
        }
        html.push_str("<link rel=icon sizes=128x128 href=/icon.png></head>");
        let urls = icon_urls(&html, &Url::parse("https://example.com/")?);
        assert_eq!(urls[0], Url::parse("https://example.com/icon.png")?);
        assert_eq!(urls.len(), MAX_CANDIDATES);
        Ok(())
    }

    #[test]
    fn prefers_sharp_rasters_including_touch_icons() -> Result<(), url::ParseError> {
        let html = "<head>
            <link rel=icon sizes=any href=/scalable.ico>
            <link rel=icon sizes=32x32 href=/small.png>
            <link rel=apple-touch-icon sizes=180x180 href=/touch.png>
            <link rel=apple-touch-icon sizes=128x128 href=/touch-128.png>
            <link rel=icon sizes='16x16 128x128' href=/icon.png>
        </head>";
        let urls = icon_urls(html, &Url::parse("https://example.com/")?);
        let paths: Vec<_> = urls.iter().map(Url::path).collect();
        assert_eq!(
            paths,
            [
                "/icon.png",
                "/touch-128.png",
                "/touch.png",
                "/small.png",
                "/scalable.ico"
            ]
        );
        Ok(())
    }

    #[test]
    fn accepts_http_and_https_links_with_custom_ports() -> Result<(), url::ParseError> {
        let page = Url::parse("https://example.com/")?;
        let html = "<head>
            <link rel=icon href=https://cdn.example.com:443/icon.png>
            <link rel=icon href=http://cdn.example.com:80/icon.png>
            <link rel=icon href=https://cdn.example.com:8443/icon.png>
            <link rel=icon href=http://cdn.example.com:8080/icon.png>
        </head>";
        let urls = icon_urls(html, &page);
        let urls: Vec<_> = urls.iter().map(Url::as_str).collect();
        assert_eq!(
            urls,
            [
                "https://cdn.example.com/icon.png",
                "http://cdn.example.com/icon.png",
                "https://cdn.example.com:8443/icon.png",
                "http://cdn.example.com:8080/icon.png"
            ]
        );
        assert_eq!(
            icon_urls(
                "<head><base href=https://cdn.example.com:8443/><link rel=icon href=icon.png></head>",
                &page,
            ),
            [Url::parse("https://cdn.example.com:8443/icon.png")?]
        );
        Ok(())
    }
}
