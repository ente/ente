import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, test } from "vitest";
import { SpaceMessageText } from "../src/components/MessageText";

const renderMessage = (text: string) =>
    renderToStaticMarkup(createElement(SpaceMessageText, { text }));

test.each(["https://ente.io", "check this: https://ente.io"])(
    "web links open in a new tab: %s",
    (text) => {
        const html = renderMessage(text);
        expect(html).toContain('href="https://ente.io"');
        expect(html).toContain('target="_blank"');
        expect(html).toContain('rel="noopener noreferrer"');
        expect(html).toContain(">https://ente.io</a>");
        expect(html.startsWith(text.slice(0, text.indexOf("https")))).toBe(
            true,
        );
    },
);

test("multiple links preserve surrounding text, line breaks, and punctuation", () => {
    const html = renderMessage(
        "Look: https://ente.io/photos,\nthen (http://example.com). Done!",
    );
    expect(html).toMatch(/^Look: <a /);
    expect(html).toContain(">https://ente.io/photos</a>,\nthen (");
    expect(html).toContain('href="http://example.com"');
    expect(html).toMatch(/>http:\/\/example\.com<\/a>\)\. Done!$/);
});

test("bare web addresses use HTTPS", () => {
    const html = renderMessage("Try www.ente.io or ente.io/photos");
    expect(html).toContain('href="https://www.ente.io"');
    expect(html).toContain(">www.ente.io</a> or ");
    expect(html).toContain('href="https://ente.io/photos"');
});

test("URL paths, queries, fragments, and balanced parentheses stay intact", () => {
    const url = "https://example.com/a_(b)?first=1&second=2#section";
    const html = renderMessage(`See (${url}).`);
    expect(html).toContain(
        'href="https://example.com/a_(b)?first=1&amp;second=2#section"',
    );
    expect(html).toMatch(/<\/a>\)\.$/);
});

test("ordinary text, HTML, and non-web schemes stay as text", () => {
    const html = renderMessage(
        '<script>alert("hello")</script>\njavascript:alert(1) ftp://example.com user@example.com',
    );
    expect(html).not.toContain("<a ");
    expect(html).toContain(
        "&lt;script&gt;alert(&quot;hello&quot;)&lt;/script&gt;",
    );
    expect(html).toContain(
        "\njavascript:alert(1) ftp://example.com user@example.com",
    );
    expect(renderMessage("just a message\nwith another line")).toBe(
        "just a message\nwith another line",
    );
});

test.each([
    "https://%",
    "http://.",
    "javascript:example.com",
    "sftp://example.com",
    "user.name@example.com",
])("invalid URLs and non-web addresses stay as text: %s", (text) => {
    expect(renderMessage(text)).toBe(text);
});

test("punctuation around links stays outside the link", () => {
    const html = renderMessage("See (https://ente.io.), then ente.io!");
    expect(html).toContain(">https://ente.io</a>.), then ");
    expect(html).toMatch(/>ente\.io<\/a>!$/);
});

test.each([
    "bücher.de",
    "bu\u0308cher.de",
    "bücher.example.com",
    "example.cöm",
    "example.com.中国",
    "例example.com",
])("internationalized bare domains stay entirely unlinked: %s", (domain) => {
    const html = renderMessage(`See ${domain} or ente.io`);
    expect(html.startsWith(`See ${domain} or <a `)).toBe(true);
    expect(html).toContain('href="https://ente.io"');
});

test.each(["。", "，", "、", "！", "？", "；", "：", "…", "。”"])(
    "non-ASCII sentence punctuation stays outside links: %s",
    (punctuation) => {
        const html = renderMessage(
            `See https://example.com/path${punctuation}`,
        );
        expect(html).toContain('href="https://example.com/path"');
        expect(
            html.endsWith(`>https://example.com/path</a>${punctuation}`),
        ).toBe(true);
    },
);

test("explicit URLs preserve internationalized domains and Unicode paths", () => {
    const url = "https://bücher.de/資料/日本語?q=%E3%80%82";
    const html = renderMessage(url);
    expect(html).toContain(`href="${url}"`);
    expect(html).toContain(`>${url}</a>`);
});
