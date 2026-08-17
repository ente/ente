import "dart:io" show Platform;

const faceMlVersion = 1;
const clipMlVersion = 1;
const clusterMlVersion = 1;
const petMlVersion = 1;
const minimumClusterSize = 2;

// Remote embedding flag bits are immutable. Add new bits; never reuse old ones.
const int mlIndexFlagRuntimeRust = 1 << 0;
const int mlIndexFlagCoreML = 1 << 1;
const int mlIndexFlagWebGPU = 1 << 2;

const embeddingFetchLimit = 200;
final fileDownloadMlLimit = Platform.isIOS ? 5 : 10;
const maxFileDownloadSize = 100000000;
