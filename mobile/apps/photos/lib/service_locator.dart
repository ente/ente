import "package:dio/dio.dart";
import "package:ente_cast/ente_cast.dart";
import "package:ente_feature_flag/ente_feature_flag.dart";
import "package:ente_install_source/ente_install_source.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/gateways/billing/billing_gateway.dart";
import "package:photos/gateways/collections/collection_files_gateway.dart";
import "package:photos/gateways/collections/collection_share_gateway.dart";
import "package:photos/gateways/collections/collections_gateway.dart";
import "package:photos/gateways/emergency/emergency_gateway.dart";
import "package:photos/gateways/entity/entity_gateway.dart";
import "package:photos/gateways/files/file_data_gateway.dart";
import "package:photos/gateways/files/file_magic_gateway.dart";
import "package:photos/gateways/files/file_upload_gateway.dart";
import "package:photos/gateways/files/files_gateway.dart";
import "package:photos/gateways/push/push_gateway.dart";
import "package:photos/gateways/social/social_gateway.dart";
import "package:photos/gateways/trash/trash_gateway.dart";
import "package:photos/gateways/users/passkey_gateway.dart";
import "package:photos/gateways/users/users_gateway.dart";
import "package:photos/module/download/gallery_download_queue_service.dart";
import "package:photos/module/download/manager.dart";
import "package:photos/services/account/billing_service.dart";
import "package:photos/services/backup_preference_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/entity_service.dart";
import "package:photos/services/filedata/filedata_service.dart";
import "package:photos/services/location_service.dart";
import "package:photos/services/machine_learning/compute_controller.dart";
import "package:photos/services/machine_learning/face_ml/person/person_feedback_service.dart";
import "package:photos/services/magic_cache_service.dart";
import "package:photos/services/memories_cache_service.dart";
import "package:photos/services/permission/service.dart";
import "package:photos/services/rituals/rituals_service.dart";
import "package:photos/services/smart_albums_service.dart";
import "package:photos/services/smart_memories_service.dart";
import "package:photos/services/storage_bonus_service.dart";
import "package:photos/services/sync/trash_sync_service.dart";
import "package:photos/services/text_embeddings_cache_service.dart";
import "package:photos/services/update_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/services/wrapped/wrapped_cache_service.dart";
import "package:photos/services/wrapped/wrapped_service.dart";
import "package:photos/settings/backup_settings.dart";
import "package:photos/settings/local_settings.dart";
import "package:shared_preferences/shared_preferences.dart";

class ServiceLocator {
  late final SharedPreferences prefs;
  late final Dio enteDio;
  late final Dio nonEnteDio;
  late final Dio downloadDio;
  late final PackageInfo packageInfo;
  late final EndpointConfig endpointConfig;
  late final LocalSettings localSettings;
  late final BackupSettings backupSettings;
  late final EnteWakeLockService wakeLockService;

  // instance
  ServiceLocator._privateConstructor();

  static final ServiceLocator instance = ServiceLocator._privateConstructor();

  void init(
    SharedPreferences prefs,
    Dio enteDio,
    Dio nonEnteDio,
    Dio downloadDio,
    PackageInfo packageInfo,
  ) {
    this.prefs = prefs;
    this.enteDio = enteDio;
    this.nonEnteDio = nonEnteDio;
    this.downloadDio = downloadDio;
    this.packageInfo = packageInfo;
    endpointConfig = EndpointConfig(prefs);
    localSettings = LocalSettings(prefs);
    backupSettings = BackupSettings(prefs);
    wakeLockService = EnteWakeLockService(prefs);
  }
}

EndpointConfig get endpointConfig => ServiceLocator.instance.endpointConfig;

FlagService? _flagService;

FlagService get flagService {
  _flagService ??= FlagService(
    ServiceLocator.instance.prefs,
    ServiceLocator.instance.enteDio,
  );
  return _flagService!;
}

CastService? _castService;

CastService get castService {
  _castService ??= CastService();
  return _castService!;
}

LocalSettings get localSettings => ServiceLocator.instance.localSettings;

BackupSettings get backupSettings => ServiceLocator.instance.backupSettings;

EnteWakeLockService get wakeLockService =>
    ServiceLocator.instance.wakeLockService;

/// Whether the app is currently showing the no-account local gallery experience.
///
/// This does not mean the device is offline. It means the active gallery mode is
/// local-device focused rather than Ente-account focused.
bool get isLocalGalleryMode => localSettings.isLocalGalleryMode;

bool get hasGrantedMLConsent {
  if (isLocalGalleryMode) {
    return localSettings.localGalleryMLConsent;
  }
  return flagService.hasGrantedMLConsent;
}

Future<void> setMLConsent(bool enabled) async {
  if (isLocalGalleryMode) {
    await localSettings.setLocalGalleryMLConsent(enabled);
    return;
  }
  await flagService.setMLConsent(enabled);
}

bool get mapEnabled {
  if (isLocalGalleryMode) {
    return localSettings.localGalleryMapEnabled;
  }
  return flagService.mapEnabled;
}

Future<void> setMapEnabled(bool enabled) async {
  if (isLocalGalleryMode) {
    await localSettings.setLocalGalleryMapEnabled(enabled);
    return;
  }
  await flagService.setMapEnabled(enabled);
}

BackupPreferenceService? _backupPreferenceService;
BackupPreferenceService get backupPreferenceService {
  _backupPreferenceService ??= BackupPreferenceService(
    ServiceLocator.instance.prefs,
  );
  return _backupPreferenceService!;
}

StorageBonusService? _storageBonusService;
StorageBonusService get storageBonusService {
  _storageBonusService ??= StorageBonusService(
    ServiceLocator.instance.prefs,
    ServiceLocator.instance.enteDio,
  );
  return _storageBonusService!;
}

UpdateService? _updateService;

UpdateService get updateService {
  _updateService ??= UpdateService(
    ServiceLocator.instance.prefs,
    ServiceLocator.instance.packageInfo,
  );
  return _updateService!;
}

EntityService? _entityService;

EntityService get entityService {
  _entityService ??= EntityService(
    ServiceLocator.instance.prefs,
    EntityGateway(ServiceLocator.instance.enteDio),
  );
  return _entityService!;
}

TrashSyncService? _trashSyncService;
TrashSyncService get trashSyncService {
  _trashSyncService ??= TrashSyncService(
    ServiceLocator.instance.prefs,
    trashGateway,
  );
  return _trashSyncService!;
}

LocationService? _locationService;
LocationService get locationService {
  _locationService ??= LocationService(ServiceLocator.instance.prefs);
  return _locationService!;
}

MagicCacheService? _magicCacheService;
MagicCacheService get magicCacheService {
  _magicCacheService ??= MagicCacheService(ServiceLocator.instance.prefs);
  return _magicCacheService!;
}

MemoriesCacheService? _memoriesCacheService;
MemoriesCacheService get memoriesCacheService {
  _memoriesCacheService ??= MemoriesCacheService(ServiceLocator.instance.prefs);
  return _memoriesCacheService!;
}

SmartMemoriesService? _smartMemoriesService;
SmartMemoriesService get smartMemoriesService {
  _smartMemoriesService ??= SmartMemoriesService();
  return _smartMemoriesService!;
}

TextEmbeddingsCacheService? _textEmbeddingsCacheService;
TextEmbeddingsCacheService get textEmbeddingsCacheService {
  _textEmbeddingsCacheService ??= TextEmbeddingsCacheService.instance;
  return _textEmbeddingsCacheService!;
}

BillingService? _billingService;
BillingService get billingService {
  _billingService ??= BillingService();
  return _billingService!;
}

ComputeController? _computeController;
ComputeController get computeController {
  _computeController ??= ComputeController(localSettings);
  return _computeController!;
}

PersonFeedbackService? _personFeedbackService;
PersonFeedbackService get personFeedbackService {
  _personFeedbackService ??= PersonFeedbackService();
  return _personFeedbackService!;
}

PermissionService? _permissionService;
PermissionService get permissionService {
  _permissionService ??= PermissionService(ServiceLocator.instance.prefs);
  return _permissionService!;
}

FileDataService? _fileDataService;
FileDataService get fileDataService {
  _fileDataService ??= FileDataService(
    ServiceLocator.instance.prefs,
    fileDataGateway,
  );
  return _fileDataService!;
}

DownloadManager? _downloadManager;
DownloadManager get downloadManager {
  _downloadManager ??= DownloadManager(ServiceLocator.instance.downloadDio);
  return _downloadManager!;
}

GalleryDownloadQueueService? _galleryDownloadQueueService;
GalleryDownloadQueueService get galleryDownloadQueueService {
  _galleryDownloadQueueService ??= GalleryDownloadQueueService.instance;
  return _galleryDownloadQueueService!;
}

SmartAlbumsService? _smartAlbumsService;
SmartAlbumsService get smartAlbumsService {
  _smartAlbumsService ??= SmartAlbumsService();
  return _smartAlbumsService!;
}

RitualsService? _ritualsService;
RitualsService get ritualsService {
  _ritualsService ??= RitualsService.instance;
  return _ritualsService!;
}

CollectionsService? _collectionsService;
CollectionsService get collectionsService {
  _collectionsService ??= CollectionsService.instance;
  return _collectionsService!;
}

WrappedService? _wrappedService;
WrappedService get wrappedService {
  _wrappedService ??= WrappedService.instance;
  return _wrappedService!;
}

WrappedCacheService? _wrappedCacheService;
WrappedCacheService get wrappedCacheService {
  _wrappedCacheService ??= WrappedCacheService.instance;
  return _wrappedCacheService!;
}

InstallSourceService? _installSourceService;
InstallSourceService get installSourceService {
  _installSourceService ??= InstallSourceService(
    ServiceLocator.instance.enteDio,
    app: "photos",
    getToken: Configuration.instance.getToken,
  );
  return _installSourceService!;
}

// Gateways
PushGateway? _pushGateway;
PushGateway get pushGateway {
  _pushGateway ??= PushGateway(ServiceLocator.instance.enteDio);
  return _pushGateway!;
}

EmergencyGateway? _emergencyGateway;
EmergencyGateway get emergencyGateway {
  _emergencyGateway ??= EmergencyGateway(ServiceLocator.instance.enteDio);
  return _emergencyGateway!;
}

SocialGateway? _socialGateway;
SocialGateway get socialGateway {
  _socialGateway ??= SocialGateway(ServiceLocator.instance.enteDio);
  return _socialGateway!;
}

FilesGateway? _filesGateway;
FilesGateway get filesGateway {
  _filesGateway ??= FilesGateway(ServiceLocator.instance.enteDio);
  return _filesGateway!;
}

FileDataGateway? _fileDataGateway;
FileDataGateway get fileDataGateway {
  _fileDataGateway ??= FileDataGateway(ServiceLocator.instance.enteDio);
  return _fileDataGateway!;
}

FileMagicGateway? _fileMagicGateway;
FileMagicGateway get fileMagicGateway {
  _fileMagicGateway ??= FileMagicGateway(ServiceLocator.instance.enteDio);
  return _fileMagicGateway!;
}

FileUploadGateway? _fileUploadGateway;
FileUploadGateway get fileUploadGateway {
  _fileUploadGateway ??= FileUploadGateway(ServiceLocator.instance.enteDio);
  return _fileUploadGateway!;
}

TrashGateway? _trashGateway;
TrashGateway get trashGateway {
  _trashGateway ??= TrashGateway(ServiceLocator.instance.enteDio);
  return _trashGateway!;
}

CollectionFilesGateway? _collectionFilesGateway;
CollectionFilesGateway get collectionFilesGateway {
  _collectionFilesGateway ??= CollectionFilesGateway(
    ServiceLocator.instance.enteDio,
  );
  return _collectionFilesGateway!;
}

CollectionShareGateway? _collectionShareGateway;
CollectionShareGateway get collectionShareGateway {
  _collectionShareGateway ??= CollectionShareGateway(
    ServiceLocator.instance.enteDio,
  );
  return _collectionShareGateway!;
}

CollectionsGateway? _collectionsGateway;
CollectionsGateway get collectionsGateway {
  _collectionsGateway ??= CollectionsGateway(ServiceLocator.instance.enteDio);
  return _collectionsGateway!;
}

BillingGateway? _billingGateway;
BillingGateway get billingGateway {
  _billingGateway ??= BillingGateway(ServiceLocator.instance.enteDio);
  return _billingGateway!;
}

PasskeyGateway? _passkeyGateway;
PasskeyGateway get passkeyGateway {
  _passkeyGateway ??= PasskeyGateway(ServiceLocator.instance.enteDio);
  return _passkeyGateway!;
}

UsersGateway? _usersGateway;
UsersGateway get usersGateway {
  _usersGateway ??= UsersGateway(
    ServiceLocator.instance.enteDio,
    ServiceLocator.instance.nonEnteDio,
    endpointConfig,
  );
  return _usersGateway!;
}
