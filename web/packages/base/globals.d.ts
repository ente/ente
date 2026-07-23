interface ErrorConstructor {
    /**
     * V8 stack trace hook available in Chromium-derived browsers and Electron.
     */
    captureStackTrace?(targetObject: object, constructorOpt?: unknown): void;
}
