import React from "react";

const messageURLPattern =
    /\bhttps?:\/\/[^\s<>"']+|(?<![\p{L}\p{M}\p{N}_@/.:+-])(?:[a-z\d](?:[a-z\d-]*[a-z\d])?\.)+[a-z]{2,}(?![\p{L}\p{M}\p{N}_@-]|\.[\p{L}\p{M}\p{N}_-])(?::\d+)?(?:[/?#][^\s<>"']*)?/giu;

export const SpaceMessageText: React.FC<{ text: string }> = ({ text }) => {
    const content: React.ReactNode[] = [];
    let offset = 0;

    for (const match of text.matchAll(messageURLPattern)) {
        let value = match[0];
        while (/[.,!?;:)\]}。，、！？；：…’”]$/.test(value)) {
            if (
                value.endsWith(")") &&
                value.split("(").length >= value.split(")").length
            )
                break;
            value = value.slice(0, -1);
        }

        const href = /^https?:\/\//i.test(value) ? value : `https://${value}`;
        try {
            new URL(href);
        } catch {
            continue;
        }

        content.push(
            text.slice(offset, match.index),
            <a
                key={match.index}
                href={href}
                target="_blank"
                rel="noopener noreferrer"
                style={{
                    color: "inherit",
                    textDecoration: "underline",
                    WebkitTouchCallout: "default",
                }}
            >
                {value}
            </a>,
        );
        offset = match.index + value.length;
    }

    content.push(text.slice(offset));
    return <>{content}</>;
};
