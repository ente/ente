/**
 * Bits for the `flags` bitmask stored on remote face and CLIP indexes.
 *
 * These values are part of the cross-client wire format and must stay aligned
 * with `ml_versions.dart`. Once shipped, a bit's meaning is immutable.
 */
const mlIndexFlagRuntimeRust = 1 << 0;
const mlIndexFlagCoreML = 1 << 1;
const mlIndexFlagWebGPU = 1 << 2;

/** Flags describing the runtime that produced a Rust analysis result. */
export const mlIndexFlagsForRustResult = ({
    usedCoreml,
    usedWebgpu,
}: {
    usedCoreml: boolean;
    usedWebgpu: boolean;
}) =>
    mlIndexFlagRuntimeRust |
    (usedCoreml ? mlIndexFlagCoreML : 0) |
    (usedWebgpu ? mlIndexFlagWebGPU : 0);
