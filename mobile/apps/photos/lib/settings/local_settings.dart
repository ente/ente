import "dart:io";

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart' as hw;
import 'package:photos/app_mode.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/ui/viewer/gallery/component/group/type.dart';
import "package:photos/utils/ram_check_util.dart";
import 'package:shared_preferences/shared_preferences.dart';

enum AlbumSortKey { albumName, newestPhoto, lastUpdated }

enum AlbumSortDirection { ascending, descending }

enum AlbumViewType { grid, list }

enum PeopleSortKey { mostPhotos, name, lastUpdated }

/// Bit positions for per-widget-type "hide text" flags stored as a single
/// integer. The same integer is mirrored to the home_widget plugin's data
/// store so the native (Android/iOS) widget providers can read it directly.
/// IMPORTANT: Never reorder or remove values. Only append new values at the end.
enum WidgetHideTextFlag { memory, album, people }

/// Bit positions for local-gallery boolean flags stored as a single integer.
/// IMPORTANT: Never reorder or remove values. Only append new values at the end.
enum LocalGalleryFlag {
  mlConsent,
  mapEnabled,
  // Reserved: previously getStartedBannerDismissed. Kept to preserve bit
  // positions of subsequent flags in the stored bitmap.
  reservedGetStartedBannerDismissed,
  facesBannerDismissed,
  nameFaceBannerDismissed,
  seenMLEnablingBanner,
  mlProgressBannerDismissed,
  localGallerySettingsBannerDismissed,
}

enum DeletePreference {
  DeleteFromBoth("delete_from_both"),
  DeleteFromLocalOnly("delete_from_local_only"),
  DeleteFromRemoteOnly("delete_from_remote_only");

  const DeletePreference(this._serializedValue);

  final String _serializedValue;

  static DeletePreference? _fromSerializedValue(String? value) {
    return switch (value) {
      "delete_from_both" => DeleteFromBoth,
      "delete_from_local_only" => DeleteFromLocalOnly,
      "delete_from_remote_only" => DeleteFromRemoteOnly,
      _ => null,
    };
  }
}

class LocalSettings {
  static const kCollectionSortPref = "collection_sort_pref";
  static const kGalleryGroupType = "gallery_group_type";
  static const kPhotoGridSize = "photo_grid_size";
  static const _kisMLLocalIndexingEnabled = "ls.ml_local_indexing";
  static const _kLocalGalleryMLLocalIndexingEnabled =
      "ls.offline_ml_local_indexing";
  static const kRateUsShownCount = "rate_us_shown_count";
  static const kEnableMultiplePart = "ls.enable_multiple_part";
  static const kCuratedMemoriesEnabled = "ls.curated_memories_enabled";
  static const kOnThisDayNotificationsEnabled =
      "ls.on_this_day_notifications_enabled";
  static const kBirthdayNotificationsEnabled =
      "ls.birthday_notifications_enabled";
  static const kRateUsPromptThreshold = 2;
  static const shouldLoopVideoKey = "video.should_loop";
  static const onGuestViewKey = "on_guest_view";
  static const _hasConfiguredLinksInAppPermissionKey =
      "has_configured_links_in_app_permission";
  static const _hideSharedItemsFromHomeGalleryTag =
      "hide_shared_items_from_home_gallery";
  static const kCollectionViewType = "collection_view_type";
  static const kCollectionSortDirection = "collection_sort_direction";
  static const kPeopleSortKey = "people_sort_key";
  static const kPeopleSortNameAscending = "people_sort_name_ascending";
  static const kPeopleSortUpdatedAscending = "people_sort_updated_ascending";
  static const kPeopleSortPhotosAscending = "people_sort_photos_ascending";
  static const kPeopleSortSimilaritySelected =
      "people_sort_similarity_selected";
  static const kShowLocalIDOverThumbnails = "show_local_id_over_thumbnails";
  static const kEnableDatabaseLogging = "enable_db_logging";
  static const _kInternalUserDisabled = "ls.internal_user_disabled";
  static const _kBGDebugNotificationsEnabled =
      "ls.bg_debug_notifications_enabled";
  static const _kCFUploadProxyEnabled = "ls.cf_upload_proxy_enabled";
  static const _kSharedPhotoFeedCutoffTime = "ls.shared_photo_feed_cutoff_time";
  static const _kWrapped2025ResumeIndex = "ls.wrapped_2025_resume_index";
  static const _kWrapped2025Complete = "ls.wrapped_2025_complete";
  static const _memoryLaneSeenKey = "faces_timeline_seen_person_ids";
  static const _kChristmasBannerEnabled = "ls.christmas_banner_enabled";
  static const _kPetRecognitionEnabled = "ls.pet_recognition_enabled";
  static const _kAutoMergeThresholdOverride = "ml_debug.auto_merge_threshold";
  static const _kDefaultClusteringDistanceOverride =
      "ml_debug.default_clustering_distance";
  static const _kRunMLDuringInteractionOverride =
      "ml_debug.run_ml_during_interaction";
  static const _kSemanticSearchExactInRustEnabled =
      "ml_debug.semantic_search_exact_in_rust";
  static const _kAppMode = "ls.app_mode";
  static const _kShowLocalGalleryModeOption = "ls.show_offline_mode_option";
  static const _kDeletePreference = "delete_preference";
  static const _kMediaManagementHintDeleteAttempts =
      "media_management_hint_delete_attempts";
  static const _kMediaManagementHintDismissedAt =
      "media_management_hint_dismissed_at";
  static const _kIsFromLocalGalleryToEnte =
      "ls.pending_backup_selection_from_local_import";

  static const _kWidgetHideTextFlags = "ls.widget_hide_text_flags";

  /// Key used by the native (Android/iOS) widget providers to read the
  /// mirrored copy of the widget hide-text bitmask from the home_widget
  /// data store. Must stay in sync with the native code.
  static const _kWidgetHideTextFlagsNativeKey = "widgetHideTitleFlags";

  static const _kLocalGalleryFlags = "ls.offline_flags";
  static const _kLocalGalleryMapEnabled = "ls.offline_map_enabled";
  static const _kLocalGalleryGetStartedBannerDismissedAt =
      "ls.offline_get_started_banner_dismissed_at";
  static const _kLocalGalleryGetStartedBannerDismissDuration = Duration(
    days: 7,
  );

  final SharedPreferences _prefs;

  AppMode? _cachedAppMode;

  /// True only for the session in which the user just enabled local-gallery
  /// mode during onboarding. Intentionally not persisted, so it resets to
  /// false on the next app launch. Used to defer the get-started banner to
  /// the second app open (after onboarding).
  bool localGalleryModeEnabledThisSession = false;

  /// Set after the first local-gallery import completes before an account is
  /// configured. When the user later signs in or signs up, the online flow
  /// replays first-import completion once so backup-folder selection can run
  /// against the imported local rows, then clears this marker.
  bool get isFromLocalGalleryToEnte =>
      _prefs.getBool(_kIsFromLocalGalleryToEnte) ?? false;

  Future<void> setIsFromLocalGalleryToEnte(bool value) async {
    await _prefs.setBool(_kIsFromLocalGalleryToEnte, value);
  }

  LocalSettings(this._prefs);

  bool _getFlag(LocalGalleryFlag flag) {
    final bitmap = _prefs.getInt(_kLocalGalleryFlags) ?? 0;
    return (bitmap & (1 << flag.index)) != 0;
  }

  Future<void> _setFlag(LocalGalleryFlag flag, bool value) {
    var bitmap = _prefs.getInt(_kLocalGalleryFlags) ?? 0;
    if (value) {
      bitmap |= (1 << flag.index);
    } else {
      bitmap &= ~(1 << flag.index);
    }
    return _prefs.setInt(_kLocalGalleryFlags, bitmap);
  }

  bool isWidgetTextHidden(WidgetHideTextFlag flag) {
    final bitmap = _prefs.getInt(_kWidgetHideTextFlags) ?? 0;
    return (bitmap & (1 << flag.index)) != 0;
  }

  Future<void> setWidgetTextHidden(WidgetHideTextFlag flag, bool value) async {
    var bitmap = _prefs.getInt(_kWidgetHideTextFlags) ?? 0;
    if (value) {
      bitmap |= (1 << flag.index);
    } else {
      bitmap &= ~(1 << flag.index);
    }
    await _prefs.setInt(_kWidgetHideTextFlags, bitmap);
    // Mirror into the home_widget data store so the native Android/iOS
    // widget providers can read the flag directly from their sandboxed
    // storage (widget SharedPreferences file / app-group UserDefaults).
    await hw.HomeWidget.saveWidgetData<int>(
      _kWidgetHideTextFlagsNativeKey,
      bitmap,
    );
  }

  AlbumSortKey albumSortKey() {
    return AlbumSortKey.values[_prefs.getInt(kCollectionSortPref) ?? 0];
  }

  Future<bool> setAlbumSortKey(AlbumSortKey key) {
    return _prefs.setInt(kCollectionSortPref, key.index);
  }

  Future<void> setAlbumViewType(AlbumViewType viewType) async {
    await _prefs.setInt(kCollectionViewType, viewType.index);
  }

  AlbumViewType albumViewType() {
    final index = _prefs.getInt(kCollectionViewType) ?? 0;
    return AlbumViewType.values[index];
  }

  AlbumSortDirection albumSortDirection() {
    return AlbumSortDirection.values[_prefs.getInt(kCollectionSortDirection) ??
        1];
  }

  Future<bool> setAlbumSortDirection(AlbumSortDirection direction) {
    return _prefs.setInt(kCollectionSortDirection, direction.index);
  }

  PeopleSortKey peopleSortKey() {
    final index = _prefs.getInt(kPeopleSortKey);
    if (index == null || index < 0 || index >= PeopleSortKey.values.length) {
      return PeopleSortKey.mostPhotos;
    }
    return PeopleSortKey.values[index];
  }

  Future<bool> setPeopleSortKey(PeopleSortKey key) {
    return _prefs.setInt(kPeopleSortKey, key.index);
  }

  bool get peopleNameSortAscending =>
      _prefs.getBool(kPeopleSortNameAscending) ?? true;

  Future<void> setPeopleNameSortAscending(bool value) async {
    await _prefs.setBool(kPeopleSortNameAscending, value);
  }

  bool get peopleUpdatedSortAscending =>
      _prefs.getBool(kPeopleSortUpdatedAscending) ?? false;

  Future<void> setPeopleUpdatedSortAscending(bool value) async {
    await _prefs.setBool(kPeopleSortUpdatedAscending, value);
  }

  bool get peoplePhotosSortAscending =>
      _prefs.getBool(kPeopleSortPhotosAscending) ?? false;

  Future<void> setPeoplePhotosSortAscending(bool value) async {
    await _prefs.setBool(kPeopleSortPhotosAscending, value);
  }

  bool get peopleSimilaritySortSelected =>
      _prefs.getBool(kPeopleSortSimilaritySelected) ?? true;

  Future<void> setPeopleSimilaritySortSelected(bool value) async {
    await _prefs.setBool(kPeopleSortSimilaritySelected, value);
  }

  GroupType getGalleryGroupType() {
    final groupTypeString = _prefs.getString(kGalleryGroupType);
    if (groupTypeString != null) {
      return GroupType.values.firstWhere(
        (type) => type.toString() == groupTypeString,
        orElse: () => GroupType.values[0],
      );
    }
    return GroupType.values[0];
  }

  Future<void> setGalleryGroupType(GroupType groupType) async {
    await _prefs.setString(kGalleryGroupType, groupType.toString());
  }

  int getPhotoGridSize() {
    if (_prefs.containsKey(kPhotoGridSize)) {
      return _prefs.getInt(kPhotoGridSize)!;
    } else {
      return photoGridSizeDefault;
    }
  }

  Future<void> setPhotoGridSize(int value) async {
    await _prefs.setInt(kPhotoGridSize, value);
  }

  int getRateUsShownCount() {
    if (_prefs.containsKey(kRateUsShownCount)) {
      return _prefs.getInt(kRateUsShownCount)!;
    } else {
      return 0;
    }
  }

  // getEstimatedInstallTimeInMs returns the time when the app was installed
  // The time is stored in shared preferences and will be reset on logout
  DateTime getInstallDateTime() {
    if (_prefs.containsKey('ls.install_time')) {
      return DateTime.fromMillisecondsSinceEpoch(
        _prefs.getInt('ls.install_time')!,
      );
    } else {
      final installTime = DateTime.now();
      _prefs.setInt('ls.install_time', installTime.millisecondsSinceEpoch);
      return installTime;
    }
  }

  Future<void> setRateUsShownCount(int value) async {
    await _prefs.setInt(kRateUsShownCount, value);
  }

  bool shouldPromptToRateUs() {
    return getRateUsShownCount() < kRateUsPromptThreshold;
  }

  bool get localGalleryMLConsent => _getFlag(LocalGalleryFlag.mlConsent);

  Future<void> setLocalGalleryMLConsent(bool value) =>
      _setFlag(LocalGalleryFlag.mlConsent, value);

  bool get localGalleryMapEnabled =>
      _prefs.getBool(_kLocalGalleryMapEnabled) ?? true;

  Future<void> setLocalGalleryMapEnabled(bool value) async {
    await _prefs.setBool(_kLocalGalleryMapEnabled, value);
    await _setFlag(LocalGalleryFlag.mapEnabled, value);
  }

  bool get isLocalGalleryMode => appMode == AppMode.localGallery;

  String get _mlLocalIndexingKey => isLocalGalleryMode
      ? _kLocalGalleryMLLocalIndexingEnabled
      : _kisMLLocalIndexingEnabled;

  bool get _defaultMLLocalIndexingEnabled => isLocalGalleryMode
      ? enoughRamForLocalGalleryLocalIndexing
      : enoughRamForLocalIndexing;

  bool get isMLLocalIndexingEnabled {
    return _prefs.getBool(_mlLocalIndexingKey) ??
        _defaultMLLocalIndexingEnabled;
  }

  bool get isSmartMemoriesEnabled =>
      _prefs.getBool(kCuratedMemoriesEnabled) ?? true;

  double? get autoMergeThresholdOverride =>
      _prefs.getDouble(_kAutoMergeThresholdOverride);

  Future<void> setAutoMergeThresholdOverride(double? value) async {
    if (value == null) {
      await _prefs.remove(_kAutoMergeThresholdOverride);
      return;
    }
    await _prefs.setDouble(_kAutoMergeThresholdOverride, value);
  }

  double? get defaultClusteringDistanceOverride =>
      _prefs.getDouble(_kDefaultClusteringDistanceOverride);

  Future<void> setDefaultClusteringDistanceOverride(double? value) async {
    if (value == null) {
      await _prefs.remove(_kDefaultClusteringDistanceOverride);
      return;
    }
    await _prefs.setDouble(_kDefaultClusteringDistanceOverride, value);
  }

  bool get petRecognitionEnabled =>
      _prefs.getBool(_kPetRecognitionEnabled) ?? false;

  Future<void> togglePetRecognition() async {
    await _prefs.setBool(_kPetRecognitionEnabled, !petRecognitionEnabled);
  }

  bool get runMLDuringInteractionOverride =>
      _prefs.getBool(_kRunMLDuringInteractionOverride) ?? isLocalGalleryMode;

  Future<void> setRunMLDuringInteractionOverride(bool value) async {
    await _prefs.setBool(_kRunMLDuringInteractionOverride, value);
  }

  bool get semanticSearchExactInRustEnabled =>
      _prefs.getBool(_kSemanticSearchExactInRustEnabled) ?? false;

  Future<void> setSemanticSearchExactInRustEnabled(bool value) async {
    await _prefs.setBool(_kSemanticSearchExactInRustEnabled, value);
  }

  Future<bool> setSmartMemories(bool value) async {
    await _prefs.setBool(kCuratedMemoriesEnabled, value);
    return value;
  }

  bool get isOnThisDayNotificationsEnabled =>
      _prefs.getBool(kOnThisDayNotificationsEnabled) ?? true;

  Future<bool> setOnThisDayNotificationsEnabled(bool value) async {
    await _prefs.setBool(kOnThisDayNotificationsEnabled, value);
    return value;
  }

  bool get birthdayNotificationsEnabled =>
      _prefs.getBool(kBirthdayNotificationsEnabled) ?? true;

  Future<bool> setBirthdayNotificationsEnabled(bool value) async {
    await _prefs.setBool(kBirthdayNotificationsEnabled, value);
    return value;
  }

  bool get userEnabledMultiplePart =>
      _prefs.getBool(kEnableMultiplePart) ?? true;

  Future<bool> setUserEnabledMultiplePart(bool value) async {
    await _prefs.setBool(kEnableMultiplePart, value);
    return value;
  }

  /// toggleFaceIndexing toggles the face indexing setting and returns the new value
  Future<bool> toggleLocalMLIndexing() async {
    final nextValue =
        !(_prefs.getBool(_mlLocalIndexingKey) ??
            _defaultMLLocalIndexingEnabled);
    await _prefs.setBool(_mlLocalIndexingKey, nextValue);
    return nextValue;
  }

  bool get hasSeenMLEnablingBanner =>
      _getFlag(LocalGalleryFlag.seenMLEnablingBanner);
  Future<void> setHasSeenMLEnablingBanner() =>
      _setFlag(LocalGalleryFlag.seenMLEnablingBanner, true);

  bool hasSeenMemoryLane(String personId) {
    final seenIds = _prefs.getStringList(_memoryLaneSeenKey);
    if (seenIds == null || seenIds.isEmpty) {
      return false;
    }
    return seenIds.contains(personId);
  }

  Future<void> markMemoryLaneSeen(String personId) async {
    final List<String> seenIds = List<String>.from(
      _prefs.getStringList(_memoryLaneSeenKey) ?? [],
    );
    if (seenIds.contains(personId)) {
      return;
    }
    seenIds.add(personId);
    await _prefs.setStringList(_memoryLaneSeenKey, seenIds);
  }

  //#region todo:(NG) remove this section, only needed for internal testing to see
  // if the OS stops the app during indexing
  bool get remoteFetchEnabled => _prefs.getBool("remoteFetchEnabled") ?? true;
  Future<void> toggleRemoteFetch() async {
    await _prefs.setBool("remoteFetchEnabled", !remoteFetchEnabled);
  }
  //#endregion

  Future<void> setShouldLoopVideo(bool value) async {
    await _prefs.setBool(shouldLoopVideoKey, value);
  }

  bool shouldLoopVideo() {
    return _prefs.getBool(shouldLoopVideoKey) ?? true;
  }

  Future<void> setOnGuestView(bool value) {
    return _prefs.setBool(onGuestViewKey, value);
  }

  bool isOnGuestView() {
    return _prefs.getBool(onGuestViewKey) ?? false;
  }

  Future<void> setConfiguredLinksInAppPermissions(bool value) async {
    await _prefs.setBool(_hasConfiguredLinksInAppPermissionKey, value);
  }

  /// This is only relevant for fdorid and independent builds since in them,
  /// user has to manually allow the app to open public links in-app
  bool hasConfiguredInAppLinkPermissions() {
    final result = _prefs.getBool(_hasConfiguredLinksInAppPermissionKey);
    return result ?? false;
  }

  Future<void> setHideSharedItemsFromHomeGallery(bool value) async {
    await _prefs.setBool(_hideSharedItemsFromHomeGalleryTag, value);
  }

  bool get hideSharedItemsFromHomeGallery =>
      _prefs.getBool(_hideSharedItemsFromHomeGalleryTag) ?? false;

  bool get showLocalIDOverThumbnails =>
      _prefs.getBool(kShowLocalIDOverThumbnails) ?? false;

  Future<void> setShowLocalIDOverThumbnails(bool value) async {
    await _prefs.setBool(kShowLocalIDOverThumbnails, value);
  }

  bool get enableDatabaseLogging =>
      _prefs.getBool(kEnableDatabaseLogging) ?? kDebugMode;

  Future<void> setEnableDatabaseLogging(bool value) async {
    await _prefs.setBool(kEnableDatabaseLogging, value);
  }

  bool get isInternalUserDisabled =>
      _prefs.getBool(_kInternalUserDisabled) ?? false;

  Future<void> setInternalUserDisabled(bool value) async {
    await _prefs.setBool(_kInternalUserDisabled, value);
  }

  bool get isBGDebugNotificationsEnabled =>
      _prefs.getBool(_kBGDebugNotificationsEnabled) ??
      (Platform.isAndroid ? false : true);

  Future<void> setBGDebugNotificationsEnabled(bool value) async {
    await _prefs.setBool(_kBGDebugNotificationsEnabled, value);
  }

  /// User's explicit override for the Cloudflare upload proxy toggle.
  /// `null` means the user has not chosen — callers should fall back to
  /// `flagService.cloudflareUploadWorker` (the rollout default).
  bool? get cfUploadProxyEnabled => _prefs.getBool(_kCFUploadProxyEnabled);

  Future<void> setCFUploadProxyEnabled(bool value) async {
    await _prefs.setBool(_kCFUploadProxyEnabled, value);
  }

  int getOrCreateSharedPhotoFeedCutoffTime() {
    final existingCutoff = _prefs.getInt(_kSharedPhotoFeedCutoffTime);
    if (existingCutoff != null) {
      return existingCutoff;
    }

    // files.added_time is stored in microseconds since epoch.
    final cutoff = DateTime.now().microsecondsSinceEpoch;
    _prefs.setInt(_kSharedPhotoFeedCutoffTime, cutoff).ignore();
    return cutoff;
  }

  int wrapped2025ResumeIndex() {
    return _prefs.getInt(_kWrapped2025ResumeIndex) ?? 0;
  }

  Future<void> setWrapped2025ResumeIndex(int index) async {
    await _prefs.setInt(_kWrapped2025ResumeIndex, index);
  }

  bool wrapped2025Complete() {
    return _prefs.getBool(_kWrapped2025Complete) ?? false;
  }

  Future<void> setWrapped2025Complete() async {
    await _prefs.setBool(_kWrapped2025Complete, true);
  }

  Future<void> resetWrapped2025Complete() async {
    await _prefs.setBool(_kWrapped2025Complete, false);
  }

  bool get isChristmasBannerEnabled =>
      _prefs.getBool(_kChristmasBannerEnabled) ?? true;

  Future<void> setChristmasBannerEnabled(bool value) async {
    await _prefs.setBool(_kChristmasBannerEnabled, value);
  }

  AppMode get appMode {
    if (_cachedAppMode != null) return _cachedAppMode!;

    final savedIndex = _prefs.getInt(_kAppMode);
    if (savedIndex != null &&
        savedIndex >= 0 &&
        savedIndex < AppMode.values.length) {
      _cachedAppMode = AppMode.values[savedIndex];
      return _cachedAppMode!;
    }

    _cachedAppMode = AppMode.enteGallery;
    return _cachedAppMode!;
  }

  bool get isAppModeSet => _prefs.containsKey(_kAppMode);

  Future<void> setAppMode(AppMode mode) async {
    await _prefs.setInt(_kAppMode, mode.index);
    _cachedAppMode = mode;
  }

  bool get showLocalGalleryModeOption =>
      _prefs.getBool(_kShowLocalGalleryModeOption) ?? true;

  Future<void> setShowLocalGalleryModeOption(bool value) async {
    await _prefs.setBool(_kShowLocalGalleryModeOption, value);
  }

  bool get isLocalGalleryGetStartedBannerDismissed {
    final dismissedAtMs =
        _prefs.getInt(_kLocalGalleryGetStartedBannerDismissedAt) ?? 0;
    if (dismissedAtMs == 0) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - dismissedAtMs;
    return elapsed >= 0 &&
        elapsed < _kLocalGalleryGetStartedBannerDismissDuration.inMilliseconds;
  }

  Future<void> setLocalGalleryGetStartedBannerDismissed(bool value) {
    if (value) {
      return _prefs.setInt(
        _kLocalGalleryGetStartedBannerDismissedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    return _prefs.remove(_kLocalGalleryGetStartedBannerDismissedAt);
  }

  bool get isMLProgressBannerDismissed =>
      _getFlag(LocalGalleryFlag.mlProgressBannerDismissed);

  Future<void> setMLProgressBannerDismissed(bool value) =>
      _setFlag(LocalGalleryFlag.mlProgressBannerDismissed, value);

  bool get isLocalGalleryFacesBannerDismissed =>
      _getFlag(LocalGalleryFlag.facesBannerDismissed);

  Future<void> setLocalGalleryFacesBannerDismissed(bool value) =>
      _setFlag(LocalGalleryFlag.facesBannerDismissed, value);

  bool get isLocalGalleryNameFaceBannerDismissed =>
      _getFlag(LocalGalleryFlag.nameFaceBannerDismissed);

  Future<void> setLocalGalleryNameFaceBannerDismissed(bool value) =>
      _setFlag(LocalGalleryFlag.nameFaceBannerDismissed, value);

  bool get isLocalGallerySettingsBannerDismissed =>
      _getFlag(LocalGalleryFlag.localGallerySettingsBannerDismissed);

  Future<void> setLocalGallerySettingsBannerDismissed(bool value) =>
      _setFlag(LocalGalleryFlag.localGallerySettingsBannerDismissed, value);

  int get _mediaManagementHintDeleteAttempts =>
      _prefs.getInt(_kMediaManagementHintDeleteAttempts) ?? 0;

  bool hasMediaManagementHintDeleteAttemptsReached() {
    return _mediaManagementHintDeleteAttempts >=
        mediaManagementHintDeleteAttemptThreshold;
  }

  bool get isMediaManagementHintDismissed {
    final dismissedAtMs = _prefs.getInt(_kMediaManagementHintDismissedAt) ?? 0;
    if (dismissedAtMs == 0) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - dismissedAtMs;
    return elapsed >= 0 &&
        elapsed < mediaManagementHintDismissDuration.inMilliseconds;
  }

  Future<void> incrementMediaManagementHintDeleteAttempts() async {
    await _prefs.setInt(
      _kMediaManagementHintDeleteAttempts,
      _mediaManagementHintDeleteAttempts + 1,
    );
  }

  Future<void> resetMediaManagementHintDeleteAttempts() async {
    await _prefs.setInt(_kMediaManagementHintDeleteAttempts, 0);
  }

  Future<void> setMediaManagementHintDismissed() async {
    await _prefs.setInt(
      _kMediaManagementHintDismissedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  DeletePreference? getDeletePreference() {
    if (!_prefs.containsKey(_kDeletePreference)) {
      return null;
    }
    return DeletePreference._fromSerializedValue(
      _prefs.getString(_kDeletePreference),
    );
  }

  Future<void> setDeletePreference(DeletePreference? preference) async {
    if (preference == null) {
      await _prefs.remove(_kDeletePreference);
    } else {
      await _prefs.setString(_kDeletePreference, preference._serializedValue);
    }
  }
}
