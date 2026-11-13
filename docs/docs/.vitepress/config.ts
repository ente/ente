import { defineConfig } from "vitepress";
import { sidebar } from "./sidebar";

const docsBaseUrl = "https://ente.com/help";

const noindexPages = new Set<string>();

export default defineConfig({
    base: "/help/",
    title: "Ente Help",
    description: "Documentation and help for Ente's products",
    head: [
        ["link", { rel: "icon", type: "image/png", href: "/help/favicon.png" }],
    ],
    cleanUrls: true,
    ignoreDeadLinks: "localhostLinks",
    sitemap: {
        hostname: `${docsBaseUrl}/`,
        transformItems: (items) => {
            const seen = new Set();
            return items
                .map((item) => ({
                    ...item,
                    url: item.url.replace(/\/$/, ""),
                }))
                .filter((item) => {
                    const path = item.url.replace(/\/$/, "");
                    if (noindexPages.has(path)) {
                        return false;
                    }
                    if (seen.has(item.url)) {
                        return false;
                    }
                    seen.add(item.url);
                    return true;
                });
        },
    },
    transformPageData(pageData) {
        const head = pageData.frontmatter.head;
        if (Array.isArray(head)) {
            for (const tag of head) {
                if (
                    Array.isArray(tag) &&
                    tag[0] === "meta" &&
                    tag[1]?.name === "robots" &&
                    tag[1]?.content?.includes("noindex")
                ) {
                    const path = pageData.relativePath
                        .replace(/index\.md$/, "")
                        .replace(/\.md$/, "");
                    noindexPages.add(path);
                    break;
                }
            }
        }

        const canonicalUrl = `${docsBaseUrl}/${pageData.relativePath}`
            .replace(/index\.md$/, "")
            .replace(/\.md$/, "");
        pageData.frontmatter.canonicalUrl = canonicalUrl;
    },
    async transformHead({ pageData }) {
        const head: any[] = [];
        const canonicalUrl =
            pageData.frontmatter.canonicalUrl || `${docsBaseUrl}/`;
        const title =
            pageData.frontmatter.title || pageData.title || "Ente Help";
        const description =
            pageData.frontmatter.description ||
            "Documentation and help for Ente's products";
        const ogImage = `${docsBaseUrl}/og-image.png`;

        head.push(["link", { rel: "canonical", href: canonicalUrl }]);

        head.push(["meta", { property: "og:type", content: "website" }]);
        head.push(["meta", { property: "og:title", content: title }]);
        head.push([
            "meta",
            { property: "og:description", content: description },
        ]);
        head.push(["meta", { property: "og:url", content: canonicalUrl }]);
        head.push(["meta", { property: "og:image", content: ogImage }]);
        head.push(["meta", { property: "og:site_name", content: "Ente Help" }]);

        head.push([
            "meta",
            { name: "twitter:card", content: "summary_large_image" },
        ]);
        head.push(["meta", { name: "twitter:site", content: "@enteio" }]);
        head.push(["meta", { name: "twitter:title", content: title }]);
        head.push([
            "meta",
            { name: "twitter:description", content: description },
        ]);
        head.push(["meta", { name: "twitter:image", content: ogImage }]);

        head.push(["meta", { name: "description", content: description }]);

        if (
            pageData.relativePath.includes("/faq/") &&
            pageData.relativePath !== "photos/faq/index.md"
        ) {
            const faqSchema = await generateFAQSchema(pageData);
            if (faqSchema) {
                head.push([
                    "script",
                    { type: "application/ld+json" },
                    JSON.stringify(faqSchema),
                ]);
            }
        }

        const breadcrumbSchema = generateBreadcrumbSchema(pageData);
        if (breadcrumbSchema) {
            head.push([
                "script",
                { type: "application/ld+json" },
                JSON.stringify(breadcrumbSchema),
            ]);
        }

        return head;
    },
    themeConfig: {
        logo: "/logo.png",
        externalLinkIcon: true,
        editLink: {
            pattern: "https://github.com/ente/ente/edit/main/docs/docs/:path",
        },
        search: {
            provider: "local",
            options: {
                detailedView: true,
            },
        },
        sidebar: sidebar,
        outline: {
            level: [2, 3],
        },
        socialLinks: [
            { icon: "github", link: "https://github.com/ente/ente/" },
            { icon: "twitter", link: "https://twitter.com/enteio" },
            { icon: "discord", link: "https://discord.gg/z2YVKkycX3" },
        ],
    },
});

async function generateFAQSchema(pageData: any) {
    try {
        const { readFile } = await import("fs/promises");
        const { join } = await import("path");

        const filePath = join(process.cwd(), "docs", pageData.relativePath);
        const content = await readFile(filePath, "utf-8");

        const questions: any[] = [];

        // FAQ entries use ### Question {#id} headings.
        const questionRegex =
            /###\s+(.+?)\s+\{#[^}]+\}\s*\n+([\s\S]*?)(?=\n###\s|\n##\s|$)/g;
        let match;

        while ((match = questionRegex.exec(content)) !== null) {
            const question = match[1].trim();
            let answer = match[2]
                .trim()
                .replace(/\*\*([^*]+)\*\*/g, "$1")
                .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
                .replace(/`([^`]+)`/g, "$1")
                .replace(
                    /^\s*>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/gim,
                    "",
                )
                .replace(/^\s*>\s?/gm, "")
                .replace(/^[-*]\s+/gm, "")
                .replace(/\n+/g, " ")
                .replace(/\s+/g, " ")
                .trim();

            if (answer.length > 500) {
                answer = answer.substring(0, 500);
                const lastPeriod = answer.lastIndexOf(".");
                if (lastPeriod > 300) {
                    answer = answer.substring(0, lastPeriod + 1);
                }
            }

            if (question && answer && answer.length > 20) {
                questions.push({
                    "@type": "Question",
                    name: question,
                    acceptedAnswer: {
                        "@type": "Answer",
                        text: answer,
                    },
                });
            }
        }

        if (questions.length === 0) {
            return null;
        }

        return {
            "@context": "https://schema.org",
            "@type": "FAQPage",
            mainEntity: questions,
        };
    } catch (error) {
        console.error(
            `Error generating FAQ schema for ${pageData.relativePath}:`,
            error,
        );
        return null;
    }
}

function generateBreadcrumbSchema(pageData: any) {
    const path = pageData.relativePath
        .replace(/\.md$/, "")
        .replace(/\/index$/, "");
    if (!path || path === "index") return null;

    const parts = path.split("/").filter(Boolean);
    const items = [
        {
            "@type": "ListItem",
            position: 1,
            name: "Home",
            item: `${docsBaseUrl}/`,
        },
    ];

    let currentPath = docsBaseUrl;
    parts.forEach((part, index) => {
        currentPath += `/${part}`;
        items.push({
            "@type": "ListItem",
            position: index + 2,
            name:
                part.charAt(0).toUpperCase() + part.slice(1).replace(/-/g, " "),
            item: currentPath,
        });
    });

    return {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        itemListElement: items,
    };
}
