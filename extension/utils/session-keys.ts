// `browser.storage.session` keys holding decrypted vault material. Kept in a
// wasm-free module so the background worker can read them without pulling in
// the crypto stack.
export const SESSION = {
    masterKey: "masterKey",
    codes: "codes",
    timeOffset: "timeOffset",
    pendingKek: "pendingKek",
    emailCodeLogin: "emailCodeLogin",
    // Raw credentials handed over by the `auth.ente.com` content script, kept
    // until the popup (the only context that can run the WASM crypto) unboxes
    // them.
    pendingWebLogin: "pendingWebLogin",
} as const;
