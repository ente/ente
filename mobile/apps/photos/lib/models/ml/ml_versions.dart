import "dart:io" show Platform;

const faceMlVersion = 1;
const clipMlVersion = 1;
const clusterMlVersion = 1;
const petMlVersion = 1;
const minimumClusterSize = 2;

/// Bits for the `flags` bitmask on RemoteFaceEmbedding / RemoteClipEmbedding.
/// Once shipped, a bit's meaning is immutable — only add new bits.
const int mlIndexFlagRuntimeRust = 1 << 0;
const int mlIndexFlagCoreML = 1 << 1;
const int mlIndexFlagWebGPU = 1 << 2;

const embeddingFetchLimit = 200;
final fileDownloadMlLimit = Platform.isIOS ? 5 : 10;
const maxFileDownloadSize = 100000000;
