import { sendMessageToBackground } from "../utils/messaging";

// Content script: finds OTP inputs on the page and offers to fill them with the
// matching Ente Auth code. All secrets stay in the background worker; this
// script only ever receives a short-lived OTP for the current site.

const HOST_ID = "ente-auth-autofill-root";

export default defineContentScript({
    matches: ["<all_urls>"],
    runAt: "document_idle",
    allFrames: false,
    main(ctx) {
        let host: HTMLElement | undefined;
        let shadow: ShadowRoot | undefined;
        let chip: HTMLButtonElement | undefined;
        let activeField: HTMLInputElement | undefined;
        let hasMatch = false;

        const ensureUI = () => {
            if (host && shadow) return;
            host = document.createElement("div");
            host.id = HOST_ID;
            host.style.cssText =
                "all: initial; position: fixed; z-index: 2147483647; top: 0; left: 0;";
            shadow = host.attachShadow({ mode: "closed" });
            const style = document.createElement("style");
            style.textContent = `
                .ente-chip {
                    position: fixed;
                    display: none;
                    align-items: center;
                    gap: 6px;
                    font: 500 12px/1 system-ui, -apple-system, sans-serif;
                    color: #fff;
                    background: #1db954;
                    border: none;
                    border-radius: 8px;
                    padding: 6px 10px;
                    cursor: pointer;
                    box-shadow: 0 2px 8px rgba(0,0,0,.25);
                    white-space: nowrap;
                }
                .ente-chip:hover { filter: brightness(1.08); }
                .ente-chip .code { font-variant-numeric: tabular-nums; letter-spacing: 1px; }
            `;
            chip = document.createElement("button");
            chip.className = "ente-chip";
            chip.type = "button";
            chip.innerHTML = `<span>Ente</span>`;
            chip.addEventListener("click", (e) => {
                e.preventDefault();
                e.stopPropagation();
                void fill();
            });
            shadow.append(style, chip);
            document.documentElement.append(host);
        };

        const positionChip = () => {
            if (!chip || !activeField || !hasMatch) return;
            const rect = activeField.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0) {
                hideChip();
                return;
            }
            // Place the chip inside the field's right edge (like the browser's
            // own autofill affordance) so it is visible on full-width inputs,
            // and clamp it to the viewport.
            chip.style.display = "inline-flex";
            const cw = chip.offsetWidth;
            const ch = chip.offsetHeight;
            const viewportW = document.documentElement.clientWidth;
            let left = rect.right + window.scrollX - cw - 6;
            let top = rect.top + window.scrollY + (rect.height - ch) / 2;
            left = Math.max(
                window.scrollX + 4,
                Math.min(left, window.scrollX + viewportW - cw - 4),
            );
            top = Math.max(window.scrollY + 4, top);
            chip.style.left = `${Math.round(left)}px`;
            chip.style.top = `${Math.round(top)}px`;
        };

        const hideChip = () => {
            if (chip) chip.style.display = "none";
        };

        const setChipLabel = (label: string) => {
            if (chip) chip.innerHTML = label;
        };

        const fill = async () => {
            if (!activeField) return;
            setChipLabel(`<span>Ente</span> <span class="code">…</span>`);
            const { code } = await sendMessageToBackground({
                type: "requestCodeForHost",
                host: location.hostname,
            });
            if (!code) {
                hideChip();
                return;
            }
            writeValue(activeField, code.otp);
            setChipLabel(
                `<span>Filled</span> <span class="code">${code.otp}</span>`,
            );
            window.setTimeout(() => setChipLabel(`<span>Ente</span>`), 2500);
        };

        const onFocusIn = (e: FocusEvent) => {
            const target = e.target as Element | null;
            if (!(target instanceof HTMLInputElement)) return;
            if (!isOtpField(target)) return;
            activeField = target;
            void maybeShow();
        };

        const maybeShow = async () => {
            if (!activeField) return;
            const { match } = await sendMessageToBackground({
                type: "hasMatchForHost",
                host: location.hostname,
            });
            hasMatch = match;
            if (!match) {
                hideChip();
                return;
            }
            ensureUI();
            positionChip();
        };

        ctx.addEventListener(document, "focusin", onFocusIn);
        ctx.addEventListener(window, "scroll", () => positionChip());
        ctx.addEventListener(window, "resize", () => positionChip());

        // The field may already be focused (sites often auto-focus the OTP
        // input) before this script attaches.
        if (
            document.activeElement instanceof HTMLInputElement &&
            isOtpField(document.activeElement)
        ) {
            activeField = document.activeElement;
            void maybeShow();
        }

        // Re-check when the DOM changes (SPAs frequently swap the form out).
        const observer = new MutationObserver(() => {
            if (activeField && !activeField.isConnected) {
                activeField = undefined;
                hideChip();
            }
        });
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
        });
        ctx.onInvalidated(() => observer.disconnect());
    },
});

const isOtpField = (el: HTMLInputElement): boolean => {
    if (el.disabled || el.readOnly) return false;
    if (el.type === "password" || el.type === "hidden") return false;

    const haystack = [
        el.name,
        el.id,
        el.getAttribute("aria-label"),
        el.placeholder,
        el.getAttribute("data-testid"),
    ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

    // Unambiguous second-factor hints: trust these regardless of the input's
    // type/length, since many sites use a plain text field with no maxlength.
    const strong =
        el.autocomplete === "one-time-code" ||
        /(otp|one[\s_-]?time|2fa|two[\s_-]?factor|\bmfa\b|verification|verify|authenticat|security[\s_-]?code|passcode|token[\s_-]?code|auth[\s_-]?code|totp)/.test(
            haystack,
        );
    if (strong) return true;

    const numeric =
        el.inputMode === "numeric" ||
        el.type === "tel" ||
        el.type === "number" ||
        /numeric|digit/.test(haystack);

    // A one-character numeric box is one cell of a segmented code input.
    if (el.maxLength === 1 && numeric && segmentedGroup(el)) return true;

    // A bare "code" is too generic on its own (zip/postal/promo/coupon/country
    // code...), so only treat it as an OTP field when it also looks numeric or
    // short.
    const generic =
        /(zip|postal|promo|coupon|discount|country|area|phone|fax|sort)/;
    if (!/\bcode\b/.test(haystack) || generic.test(haystack)) return false;
    const short = el.maxLength > 0 && el.maxLength <= 12;
    return numeric || short;
};

// The sibling one-character inputs that make up a segmented code field, if any.
const segmentedGroup = (
    el: HTMLInputElement,
): HTMLInputElement[] | undefined => {
    const container = el.closest("form") ?? el.parentElement ?? document;
    const boxes = [...container.querySelectorAll("input")].filter(
        (i): i is HTMLInputElement =>
            i instanceof HTMLInputElement &&
            i.maxLength === 1 &&
            (i.inputMode === "numeric" ||
                i.type === "tel" ||
                i.type === "number"),
    );
    return boxes.length >= 4 ? boxes : undefined;
};

const setNativeValue = (input: HTMLInputElement, value: string) => {
    const descriptor = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        "value",
    );
    descriptor?.set?.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
};

const writeValue = (input: HTMLInputElement, value: string) => {
    // Segmented fields (one digit per box) need the code spread across boxes.
    if (input.maxLength === 1) {
        const boxes = segmentedGroup(input);
        if (boxes) {
            const digits = [...value];
            boxes.forEach((box, i) => setNativeValue(box, digits[i] ?? ""));
            const lastFilled = boxes[Math.min(digits.length, boxes.length) - 1];
            (lastFilled ?? input).focus();
            return;
        }
    }
    setNativeValue(input, value);
    input.focus();
};
