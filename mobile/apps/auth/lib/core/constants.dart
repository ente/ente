const int thumbnailSmallSize = 256;
const int thumbnailQuality = 50;
const int thumbnailLargeSize = 512;
const int compressedThumbnailResolution = 1080;
const int thumbnailDataLimit = 100 * 1024;
const String sentryDSN =
    "https://ed4ddd6309b847ba8849935e26e9b648@sentry.ente.io/9";

final Uri githubFeatureRequestUri = Uri.https(
  "github.com",
  "/ente/ente/discussions/categories/enhancements",
  {"discussions_q": "is:open label:\"- auth\" sort:top"},
);
const int microSecondsInDay = 86400000000;
const int android11SDKINT = 30;
const int galleryLoadStartTime = -8000000000000000; // Wednesday, March 6, 1748
const int galleryLoadEndTime = 9223372036854775807; // 2^63 -1

// used to identify which ente file are available in app cache
// todo: 6Jun22: delete old media identifier after 3 months
const String oldSharedMediaIdentifier = 'ente-shared://';
const String sharedMediaIdentifier = 'ente-shared-media://';

const int maxLivePhotoToastCount = 2;
const String livePhotoToastCounterKey = "show_live_photo_toast";

const thumbnailDiskLoadDeferDuration = Duration(milliseconds: 40);
const thumbnailServerLoadDeferDuration = Duration(milliseconds: 80);

// 256 bit key maps to 24 words
// https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki#Generating_the_mnemonic
const mnemonicKeyWordCount = 24;

// https://stackoverflow.com/a/61162219
const dragSensitivity = 8;

// Default values for various feature flags
class FFDefault {
  static const bool enableStripe = true;
  static const bool disableCFWorker = false;
}

const kDefaultProductionEndpoint = 'https://api.ente.com';
