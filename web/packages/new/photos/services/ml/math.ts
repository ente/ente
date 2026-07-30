/**
 * Clamp {@link value} to between {@link min} and {@link max}, inclusive.
 */
export const clamp = (value: number, min: number, max: number) =>
    Math.min(max, Math.max(min, value));

/**
 * Return the dot-product of two vectors.
 *
 * Dot product is the component-wise product of the corresponding elements of
 * the two given vectors.
 *
 * Precondition: The two vectors must be of the same length.
 *
 * ---
 *
 * [Note: Dot product is cosine similarity for normalized vectors]
 *
 * The cosine similarity of two vectors is defined as
 *
 *     dotProduct(v1, v2) / (norm(v1) * norm(v2));
 *
 * In particular, when both the vectors are normalized, this is equal to the dot
 * product. When we're computing dot products in a hot loop, skipping over that
 * unnecessary renormalization matters.
 *
 * When comparing embeddings we usually want is the cosine similarity, but if
 * both the embeddings involved are already normalized, we can save the norm
 * calculations and directly do their `dotProduct`.
 *
 * Such code is often on the hot path, so these optimizations help.
 *
 * ---
 *
 * [Note: Cosine similarity and cosine distance]
 *
 * The cosine similarity of two vectors is [-1, 1] (inclusive), indicating how
 * similar (1), orthogonal (0) and dissimilar (1) the two vectors are in
 * direction. A related concept is cosine distance, which is defined as
 *
 *     1 - cosine similarity
 *
 * in an attempt to convert it into a (pseudo) distance metric.
 *
 * ---
 *
 * [Note: Dot product performance]
 *
 * In theory, Wasm SIMD instructions should give us a huge boost for computing
 * dot products. In practice, we can get to roughly around the same performance
 * by using Float32Arrays instead of number[], and letting the JS JIT do the
 * optimizations for us (This assertion was made on Chrome on macOS on Sep 2023,
 * and may not hold in the future).
 *
 * We can get a further 2x speedup over this by using some library that directly
 * uses the SIMD intrinsics provided by the architecture instead of limiting
 * itself to Wasm's set. But that'll require bundling native code, so as a
 * tradeoff to avoid complexity we currently leave that 1x on the table.
 */
export const dotProduct = (v1: Float32Array, v2: Float32Array) => {
    if (v1.length != v2.length)
        throw new Error(`Length mismatch ${v1.length} ${v2.length}`);
    let d = 0;
    for (let i = 0; i < v1.length; i++) d += v1[i]! * v2[i]!;
    return d;
};
