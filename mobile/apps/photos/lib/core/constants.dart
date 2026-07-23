import "package:flutter/foundation.dart";

const int thumbnailSmallSize = 256;
const int thumbnailQuality = 50;
const int thumbnailLargeSize = 512;
const int compressedThumbnailResolution = 1080;
const int thumbnailDataLimit = 100 * 1024;
const String sentryDSN =
    "https://2235e5c99219488ea93da34b9ac1cb68@sentry.ente.io/4";
const String sentryDebugDSN =
    "https://ca5e686dd7f149d9bf94e620564cceba@sentry.ente.io/3";
const String sentryTunnel = "https://sentry-reporter.ente.com";
const String githubDiscussionsUrl = "https://github.com/ente/ente/discussions";
const int microSecondsInDay = 86400000000;
const int android11SDKINT = 30;
const int jan011981Time = 347155200000000;
const int galleryLoadStartTime = -8000000000000000; // Wednesday, March 6, 1748
const int galleryLoadEndTime = 9223372036854775807; // 2^63 -1
const int batchSize = 1000;
const int batchSizeCopy = 100;
const photoGridSizeDefault = 4;
const photoGridSizeMin = 2;
const photoGridSizeMax = 6;
const subGalleryMultiplier = 10;

// used to identify which ente file are available in app cache
const String sharedMediaIdentifier = 'ente-shared-media://';

const galleryThumbnailDiskLoadDeferDuration = Duration(milliseconds: 80);
const galleryThumbnailServerLoadDeferDuration = Duration(milliseconds: 80);
const mediaManagementHintDismissDuration = Duration(days: 7);
const mediaManagementHintDeleteAttemptThreshold = 3;

// 256 bit key maps to 24 words
// https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki#Generating_the_mnemonic
const mnemonicKeyWordCount = 24;

// https://stackoverflow.com/a/61162219
const dragSensitivity = 8;

const supportEmail = 'support@ente.com';

// this is the chunk size of the un-encrypted file which is read and encrypted before uploading it as a single part.
const multipartPartSize = 20 * 1024 * 1024;

const kDefaultProductionEndpoint = 'https://api.ente.com';
const kLegacyProductionEndpoint = 'https://api.ente.io';
const kUploadProxyEndpoint = 'https://uploader.ente.com';
const kPhotosWebDomain = 'photos.ente.com';
const kFamilyUrl = 'https://family.ente.io';

const int intMaxValue = 9223372036854775807;

//Screen width of iPhone 14 pro max in points is taken as maximum
const double restrictedMaxWidth = 430;

const double mobileSmallThreshold = 336;

// Note: 0 indicates no device limit
const publicLinkDeviceLimits = [0, 50, 25, 10, 5, 2, 1];

const kilometersPerDegree = 111.16;

const defaultRadiusValues = <double>[1, 2, 10, 20, 40, 80, 200, 400, 1200];

const defaultRadiusValue = 40.0;

const defaultCityRadius = 10.0;

const galleryGridSpacing = 2.0;

const kSearchSectionLimit = 9;

const maxPickAssetLimit = 50;

const iOSGroupIDMemory = "group.io.ente.frame.EnteMemoryWidget";

const blackThumbnailBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEB'
    'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQ'
    'EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARC'
    'ACWASwDAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUF'
    'BAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk'
    '6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztL'
    'W2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAA'
    'AAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVY'
    'nLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImK'
    'kpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oAD'
    'AMBAAIRAxEAPwD/AD/6ACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA'
    'CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg'
    'AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKAC'
    'gAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo'
    'AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg'
    'AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg'
    'AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA'
    'CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA'
    'CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoA'
    'KACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg'
    'AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo'
    'AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA'
    'CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAK'
    'ACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoA'
    'KACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo'
    'AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo'
    'AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgD/9k=';

const uploadTempFilePrefix = "upload_file_";
final tempDirCleanUpInterval = kDebugMode
    ? const Duration(hours: 1).inMicroseconds
    : const Duration(hours: 6).inMicroseconds;

const kMaxAppbarFilters = 14;

const kLivePhotoHashSeparator = ':';
