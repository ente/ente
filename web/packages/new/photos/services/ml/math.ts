export const clamp = (value: number, min: number, max: number) =>
    Math.min(max, Math.max(min, value));

// ML callers use normalized embeddings, so this is cosine similarity there.
// Keep Float32Array and the simple loop; this runs on hot paths.
export const dotProduct = (v1: Float32Array, v2: Float32Array) => {
    if (v1.length != v2.length)
        throw new Error(`Length mismatch ${v1.length} ${v2.length}`);
    let d = 0;
    for (let i = 0; i < v1.length; i++) d += v1[i]! * v2[i]!;
    return d;
};
