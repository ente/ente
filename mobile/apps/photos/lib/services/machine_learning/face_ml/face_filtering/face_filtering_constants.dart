const kLaplacianHardThreshold = 10;
const kLaplacianSoftThreshold = 50;
const kLaplacianVerySoftThreshold = 200;

const kLapacianDefault = 10000.0;

const kMinFaceDetectionScore = 0.5;

const kMinimumFaceShowScore = 0.75;

const kMinimumQualityFaceScore = 0.80;
const kMediumQualityFaceScore = 0.85;
const kHighQualityFaceScore = 0.90;

bool isBadFaceForClustering({
  required double faceScore,
  required double blurValue,
  required bool isSideways,
}) =>
    faceScore < kMinimumQualityFaceScore ||
    blurValue < kLaplacianSoftThreshold ||
    (blurValue < kLaplacianVerySoftThreshold &&
        faceScore < kMediumQualityFaceScore) ||
    isSideways;

const kMinimumClusterSizeSearchResult = 10;

const kMinimumClusterSizeAllFaces = 1;
