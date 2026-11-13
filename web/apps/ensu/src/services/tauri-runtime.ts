type TauriGlobal = typeof globalThis & { isTauri?: unknown };

// Inlined variant of `isTauri` from @tauri-apps/api/core, so that we can
// detect the Tauri runtime without importing the entire package.
export const isTauriRuntime = () =>
    (globalThis as TauriGlobal).isTauri === true;
