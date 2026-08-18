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
const String sharedMediaIdentifier = 'ente-shared-media://';

const int maxLivePhotoToastCount = 2;
const String livePhotoToastCounterKey = "show_live_photo_toast";

const thumbnailDiskLoadDeferDuration = Duration(milliseconds: 40);
const thumbnailServerLoadDeferDuration = Duration(milliseconds: 80);

// 256 bit key maps to 24 words
// https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki#Generating_the_mnemonic
const mnemonicKeyWordCount = 24;

class FFDefault {
  static const bool enableStripe = true;
  static const bool disableCFWorker = false;
}

const kDefaultProductionEndpoint = 'https://api.ente.com';
