// Cross-client wire bits; keep aligned with ml_versions.dart and never reuse them.
const mlIndexFlagRuntimeRust = 1 << 0;
const mlIndexFlagCoreML = 1 << 1;
const mlIndexFlagWebGPU = 1 << 2;

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
