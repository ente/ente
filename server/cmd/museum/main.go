package main

import (
	"context"
	"database/sql"
	b64 "encoding/base64"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"path"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/ente/museum/pkg/controller/collections"
	publicCtrl "github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/repo/public"

	"github.com/ente/museum/ente/base"
	"github.com/ente/museum/pkg/controller/emergency"
	"github.com/ente/museum/pkg/controller/file_copy"
	"github.com/ente/museum/pkg/controller/filedata"
	legacykitctrl "github.com/ente/museum/pkg/controller/legacy_kit"
	emergencyRepo "github.com/ente/museum/pkg/repo/emergency"
	legacykitrepo "github.com/ente/museum/pkg/repo/legacy_kit"

	"github.com/ente/museum/pkg/repo/two_factor_recovery"

	"github.com/ente/museum/pkg/controller/cast"

	"github.com/ente/museum/pkg/controller/commonbilling"
	contactCtrl "github.com/ente/museum/pkg/controller/contact"

	cache2 "github.com/ente/museum/ente/cache"
	"github.com/ente/museum/pkg/controller/discord"
	discountCouponCtrl "github.com/ente/museum/pkg/controller/discountcoupon"
	"github.com/ente/museum/pkg/controller/offer"
	"github.com/ente/museum/pkg/controller/usercache"

	"github.com/dlmiddlecote/sqlstats"
	"github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/api"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/access"
	authenticatorCtrl "github.com/ente/museum/pkg/controller/authenticator"
	dataCleanupCtrl "github.com/ente/museum/pkg/controller/data_cleanup"
	"github.com/ente/museum/pkg/controller/email"
	embeddingCtrl "github.com/ente/museum/pkg/controller/embedding"
	"github.com/ente/museum/pkg/controller/family"
	"github.com/ente/museum/pkg/controller/lock"
	memoryShareCtrl "github.com/ente/museum/pkg/controller/memory_share"
	remoteStoreCtrl "github.com/ente/museum/pkg/controller/remotestore"
	socialcontroller "github.com/ente/museum/pkg/controller/social"
	"github.com/ente/museum/pkg/controller/storagebonus"
	"github.com/ente/museum/pkg/controller/user"
	userEntityCtrl "github.com/ente/museum/pkg/controller/userentity"
	"github.com/ente/museum/pkg/middleware"
	"github.com/ente/museum/pkg/repo"
	authenticatorRepo "github.com/ente/museum/pkg/repo/authenticator"
	castRepo "github.com/ente/museum/pkg/repo/cast"
	contactRepo "github.com/ente/museum/pkg/repo/contact"
	"github.com/ente/museum/pkg/repo/datacleanup"
	discountCouponRepo "github.com/ente/museum/pkg/repo/discountcoupon"
	"github.com/ente/museum/pkg/repo/embedding"
	fileDataRepo "github.com/ente/museum/pkg/repo/filedata"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/ente/museum/pkg/repo/remotestore"
	socialrepo "github.com/ente/museum/pkg/repo/social"
	storageBonusRepo "github.com/ente/museum/pkg/repo/storagebonus"
	userEntityRepo "github.com/ente/museum/pkg/repo/userentity"
	"github.com/ente/museum/pkg/utils/billing"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/s3config"
	timeUtil "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-contrib/gzip"
	"github.com/gin-contrib/requestid"
	"github.com/gin-contrib/timeout"
	"github.com/gin-gonic/gin"
	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "github.com/lib/pq"
	"github.com/patrickmn/go-cache"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/robfig/cron/v3"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	ginprometheus "github.com/zsais/go-gin-prometheus"
	"gopkg.in/natefinch/lumberjack.v2"
)

func main() {
	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		environment = "local"
	}

	err := config.ConfigureViper(environment)
	if err != nil {
		panic(err)
	}

	viper.SetDefault("apps.public-albums", "https://albums.ente.com")
	viper.SetDefault("apps.embed-albums", "https://embed.ente.com")
	viper.SetDefault("apps.custom-domain.cname", "my.ente.com")
	viper.SetDefault("apps.public-locker", "https://share.ente.com")
	viper.SetDefault("apps.public-paste", "https://paste.ente.com")
	viper.SetDefault("apps.public-memories", "https://memories.ente.com")
	viper.SetDefault("apps.accounts", "https://accounts.ente.com")
	viper.SetDefault("apps.accounts-legacy", "https://accounts.ente.io")
	viper.SetDefault("apps.cast", "https://cast.ente.com")
	viper.SetDefault("apps.family", "https://family.ente.io")

	setupLogger(environment)
	log.Infof("Booting up %s server with commit #%s", environment, os.Getenv("GIT_COMMIT"))

	secretEncryptionKey := viper.GetString("key.encryption")
	hashingKey := viper.GetString("key.hash")
	jwtSecret := viper.GetString("jwt.secret")

	secretEncryptionKeyBytes, err := b64.StdEncoding.DecodeString(secretEncryptionKey)
	if err != nil {
		log.Fatal("Could not decode email-encryption-key", err)
	}
	hashingKeyBytes, err := b64.StdEncoding.DecodeString(hashingKey)
	if err != nil {
		log.Fatal("Could not decode email-hash-key", err)
	}

	jwtSecretBytes, err := b64.URLEncoding.DecodeString(jwtSecret)
	if err != nil {
		log.Fatal("Could not decode jwt-secret ", err)
	}

	db := setupDatabase()
	defer db.Close()
	latencySensitiveDB := setupLatencySensitiveDatabase()
	defer latencySensitiveDB.Close()

	hostName, err := os.Hostname()
	if err != nil {
		log.Fatal("Could not get host name", err)
	}
	taskLockingRepo := &repo.TaskLockRepository{DB: db}
	lockController := &lock.LockController{
		TaskLockingRepo: taskLockingRepo,
		HostName:        hostName,
	}
	// Note: during boot-up, release any locks that might have been left behind.
	// This is a safety measure to ensure that no locks are left behind in case of a crash or restart.
	lockController.ReleaseHostLock()

	var latencyLogger = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "museum_method_latency",
		Help:    "The amount of time each method is taking to respond",
		Buckets: []float64{10, 50, 100, 200, 500, 1000, 10000, 30000, 60000, 120000, 600000},
	}, []string{"method"})

	s3Config := s3config.NewS3Config()
	passkeysRepo, err := passkey.NewRepository(db)
	if err != nil {
		panic(err)
	}

	storagBonusRepo := &storageBonusRepo.Repository{DB: db}
	castDb := castRepo.Repository{DB: db}
	userRepo := &repo.UserRepository{DB: db, SecretEncryptionKey: secretEncryptionKeyBytes, HashingKey: hashingKeyBytes, StorageBonusRepo: storagBonusRepo, PasskeysRepository: passkeysRepo}

	twoFactorRepo := &repo.TwoFactorRepository{DB: db, SecretEncryptionKey: secretEncryptionKeyBytes}
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	twoFactorRecoveryRepo := &two_factor_recovery.Repository{Db: db, SecretEncryptionKey: secretEncryptionKeyBytes}
	billingRepo := &repo.BillingRepository{DB: db}
	userEntityRepo := &userEntityRepo.Repository{DB: db}
	authRepo := &authenticatorRepo.Repository{DB: db}
	remoteStoreRepository := &remotestore.Repository{DB: db}
	dataCleanupRepository := &datacleanup.Repository{DB: db}
	emergencyContactRepository := &emergencyRepo.Repository{DB: db}
	legacyKitRepository := &legacykitrepo.Repository{DB: db}

	notificationHistoryRepo := &repo.NotificationHistoryRepository{DB: db}
	eventRepository := &repo.EventRepository{DB: db}
	queueRepo := &repo.QueueRepository{DB: db}
	objectRepo := &repo.ObjectRepository{DB: db, LatencySensitiveDB: latencySensitiveDB, QueueRepo: queueRepo}
	objectCleanupRepo := &repo.ObjectCleanupRepository{DB: db}
	contactRepository := &contactRepo.Repository{
		DB:                  db,
		ObjectCleanupRepo:   objectCleanupRepo,
		SecretEncryptionKey: secretEncryptionKeyBytes,
	}
	objectCopiesRepo := &repo.ObjectCopiesRepository{DB: db}
	usageRepo := &repo.UsageRepository{DB: db, UserRepo: userRepo}
	fileRepo := &repo.FileRepository{DB: db, S3Config: s3Config, QueueRepo: queueRepo,
		ObjectRepo: objectRepo, ObjectCleanupRepo: objectCleanupRepo,
		ObjectCopiesRepo: objectCopiesRepo, UsageRepo: usageRepo}
	fileLinkRepo := public.NewFileLinkRepo(db)
	pasteRepo := public.NewPasteRepository(db)
	fileDataRepo := &fileDataRepo.Repository{DB: db, ObjectCleanupRepo: objectCleanupRepo}
	familyRepo := &repo.FamilyRepository{DB: db}
	trashRepo := &repo.TrashRepository{DB: db, ObjectRepo: objectRepo, FileRepo: fileRepo, QueueRepo: queueRepo, FileLinkRepo: fileLinkRepo}
	collectionLinkRepo := public.NewCollectionLinkRepository(db, viper.GetString("apps.public-albums"))
	memoryShareRepo := repo.NewMemoryShareRepository(db)

	collectionRepo := &repo.CollectionRepository{DB: db, FileRepo: fileRepo, CollectionLinkRepo: collectionLinkRepo,
		TrashRepo: trashRepo, SecretEncryptionKey: secretEncryptionKeyBytes, QueueRepo: queueRepo, LatencyLogger: latencyLogger}
	accessCollectionLinkRepo := public.NewCollectionLinkRepository(latencySensitiveDB, viper.GetString("apps.public-albums"))
	accessCollectionRepo := &repo.CollectionRepository{DB: latencySensitiveDB, CollectionLinkRepo: accessCollectionLinkRepo}
	accessFileRepo := &repo.FileRepository{DB: latencySensitiveDB}
	pushRepo := &repo.PushTokenRepository{DB: db}
	collectionActionRepo := &repo.CollectionActionsRepository{
		DB: db,
	}

	embeddingRepo := &embedding.Repository{DB: db}

	authCache := cache.New(1*time.Minute, 15*time.Minute)
	accessTokenCache := cache.New(1*time.Minute, 15*time.Minute)
	discordController := discord.NewDiscordController(userRepo, hostName, environment)
	rateLimiter := middleware.NewRateLimitMiddleware(discordController, 1000, 1*time.Second)
	defer rateLimiter.Stop()

	emailNotificationCtrl := &email.EmailNotificationController{
		UserRepo:                userRepo,
		UsageRepo:               usageRepo,
		BillingRepo:             billingRepo,
		StorageBonusRepo:        storagBonusRepo,
		DiscordController:       discordController,
		LockController:          lockController,
		NotificationHistoryRepo: notificationHistoryRepo,
	}

	userCache := cache2.NewUserCache()
	userCacheCtrl := &usercache.Controller{UserCache: userCache, FileRepo: fileRepo,
		UsageRepo: usageRepo, TrashRepo: trashRepo,
		StoreBonusRepo: storagBonusRepo}
	offerController := offer.NewOfferController(*userRepo, discordController, storagBonusRepo, userCacheCtrl)
	plans := billing.GetPlans()
	defaultPlan := billing.GetDefaultPlans(plans)
	stripeClients := billing.GetStripeClients()
	commonBillController := commonbilling.NewController(emailNotificationCtrl, storagBonusRepo, userRepo, usageRepo, billingRepo)
	appStoreController := controller.NewAppStoreController(defaultPlan,
		billingRepo, fileRepo, userRepo, remoteStoreRepository, commonBillController, discordController)
	playStoreController := controller.NewPlayStoreController(defaultPlan,
		billingRepo, fileRepo, userRepo, storagBonusRepo, commonBillController)
	stripeController := controller.NewStripeController(plans, stripeClients,
		billingRepo, fileRepo, userRepo, storagBonusRepo, discordController, emailNotificationCtrl, offerController, commonBillController)
	billingController := controller.NewBillingController(plans,
		appStoreController, playStoreController, stripeController,
		discordController, emailNotificationCtrl,
		billingRepo, userRepo, usageRepo, storagBonusRepo, commonBillController)
	remoteStoreController := &remoteStoreCtrl.Controller{
		Repo:        remoteStoreRepository,
		BillingCtrl: billingController,
		UserRepo:    userRepo,
		FamilyRepo:  familyRepo,
	}

	pushController := controller.NewPushController(pushRepo, taskLockingRepo, hostName)
	mailingListsController := controller.NewMailingListsController(discordController)

	storageBonusCtrl := &storagebonus.Controller{
		UserRepo:                    userRepo,
		StorageBonus:                storagBonusRepo,
		LockController:              lockController,
		CronRunning:                 false,
		EmailNotificationController: emailNotificationCtrl,
	}

	objectController := &controller.ObjectController{
		S3Config:       s3Config,
		ObjectRepo:     objectRepo,
		QueueRepo:      queueRepo,
		LockController: lockController,
	}
	objectCleanupController := controller.NewObjectCleanupController(
		objectCleanupRepo,
		objectRepo,
		s3Config,
	)

	usageController := &controller.UsageController{
		BillingCtrl:       billingController,
		StorageBonusCtrl:  storageBonusCtrl,
		UserCacheCtrl:     userCacheCtrl,
		UsageRepo:         usageRepo,
		UserRepo:          userRepo,
		FamilyRepo:        familyRepo,
		FileRepo:          fileRepo,
		UploadResultCache: make(map[int64]bool),
	}

	accessCtrl := access.NewAccessController(accessCollectionRepo, accessFileRepo)
	commentsRepo := &socialrepo.CommentsRepository{DB: db}
	reactionsRepo := &socialrepo.ReactionsRepository{DB: db}
	anonUsersRepo := &socialrepo.AnonUsersRepository{DB: db}
	commentsController := &socialcontroller.CommentsController{
		Repo:           commentsRepo,
		CollectionRepo: collectionRepo,
		AccessCtrl:     accessCtrl,
	}
	reactionsController := &socialcontroller.ReactionsController{
		Repo:           reactionsRepo,
		CommentsRepo:   commentsRepo,
		CollectionRepo: collectionRepo,
		AccessCtrl:     accessCtrl,
	}
	socialController := &socialcontroller.Controller{
		CommentsRepo:   commentsRepo,
		ReactionsRepo:  reactionsRepo,
		CollectionRepo: collectionRepo,
		AccessCtrl:     accessCtrl,
		AnonUsersRepo:  anonUsersRepo,
	}
	fileDataCtrl := filedata.New(fileDataRepo, accessCtrl, objectCleanupController, s3Config, fileRepo, collectionRepo, discordController)

	fileController := &controller.FileController{
		FileRepo:              fileRepo,
		ObjectRepo:            objectRepo,
		ObjectCleanupRepo:     objectCleanupRepo,
		TrashRepository:       trashRepo,
		UserRepo:              userRepo,
		UsageCtrl:             usageController,
		AccessCtrl:            accessCtrl,
		CollectionRepo:        collectionRepo,
		TaskLockingRepo:       taskLockingRepo,
		DiscordController:     discordController,
		QueueRepo:             queueRepo,
		ObjectCleanupCtrl:     objectCleanupController,
		LockController:        lockController,
		EmailNotificationCtrl: emailNotificationCtrl,
		S3Config:              s3Config,
		HostName:              hostName,
	}

	replicationController3 := &controller.ReplicationController3{
		S3Config:          s3Config,
		ObjectRepo:        objectRepo,
		ObjectCopiesRepo:  objectCopiesRepo,
		DiscordController: discordController,
	}

	trashController := &controller.TrashController{
		TrashRepo:      trashRepo,
		FileRepo:       fileRepo,
		CollectionRepo: collectionRepo,
		QueueRepo:      queueRepo,
		TaskLockRepo:   taskLockingRepo,
		HostName:       hostName,
	}

	familyController := &family.Controller{
		FamilyRepo:      familyRepo,
		BillingCtrl:     billingController,
		UserRepo:        userRepo,
		UserCacheCtrl:   userCacheCtrl,
		UsageRepo:       usageRepo,
		RemoteStoreRepo: remoteStoreRepository,
	}

	collectionLinkCtrl := &publicCtrl.CollectionLinkController{
		FileController:        fileController,
		EmailNotificationCtrl: emailNotificationCtrl,
		CollectionLinkRepo:    collectionLinkRepo,
		FileLinkRepo:          fileLinkRepo,
		CollectionRepo:        collectionRepo,
		UserRepo:              userRepo,
		JwtSecret:             jwtSecretBytes,
	}
	publicCommentsCtrl := &publicCtrl.CommentsController{
		CommentCtrl:   commentsController,
		CommentsRepo:  commentsRepo,
		ReactionsRepo: reactionsRepo,
		UserRepo:      userRepo,
		UserAuthRepo:  userAuthRepo,
		AnonUsersRepo: anonUsersRepo,
		JwtSecret:     jwtSecretBytes,
	}
	publicReactionsCtrl := &publicCtrl.ReactionsController{
		ReactionCtrl:  reactionsController,
		ReactionsRepo: reactionsRepo,
		AnonUsersRepo: anonUsersRepo,
		UserAuthRepo:  userAuthRepo,
		JwtSecret:     jwtSecretBytes,
	}
	anonIdentityCtrl := &publicCtrl.AnonIdentityController{
		JwtSecret:     jwtSecretBytes,
		AnonUsersRepo: anonUsersRepo,
	}

	collectionController := &collections.CollectionController{
		CollectionRepo:        collectionRepo,
		EmailCtrl:             emailNotificationCtrl,
		AccessCtrl:            accessCtrl,
		CollectionLinkCtrl:    collectionLinkCtrl,
		UserRepo:              userRepo,
		FileRepo:              fileRepo,
		TrashRepo:             trashRepo,
		CastRepo:              &castDb,
		BillingCtrl:           billingController,
		QueueRepo:             queueRepo,
		TaskRepo:              taskLockingRepo,
		CollectionActionsRepo: collectionActionRepo,
		CommentsRepo:          commentsRepo,
		ReactionsRepo:         reactionsRepo,
	}

	// Pending actions' controller/handler
	collectionActionsController := &controller.CollectionActionsController{
		Repo: collectionActionRepo,
	}
	collectionActionsHandler := &api.CollectionActionsHandler{
		Controller: collectionActionsController,
	}

	userController := user.NewUserController(
		userRepo,
		usageRepo,
		userAuthRepo,
		twoFactorRepo,
		twoFactorRecoveryRepo,
		passkeysRepo,
		authRepo,
		storagBonusRepo,
		fileRepo,
		collectionController,
		collectionRepo,
		dataCleanupRepository,
		notificationHistoryRepo,
		billingRepo,
		secretEncryptionKeyBytes,
		hashingKeyBytes,
		authCache,
		jwtSecretBytes,
		billingController,
		familyController,
		discordController,
		mailingListsController,
		pushController,
		userCache,
		userCacheCtrl,
		contactRepository,
	)
	emailNotificationCtrl.UserAccessResetter = userController
	inactiveUserOrchestrator := user.NewInactiveUserOrchestrator(
		userRepo,
		notificationHistoryRepo,
		emergencyContactRepository,
		lockController,
		discordController,
		userController,
	)
	fileLinkCtrl := &publicCtrl.FileLinkController{
		FileController: fileController,
		FileLinkRepo:   fileLinkRepo,
		FileRepo:       fileRepo,
		JwtSecret:      jwtSecretBytes,
	}
	pasteCtrl := &publicCtrl.PasteController{
		PasteRepo:   pasteRepo,
		JwtSecret:   jwtSecretBytes,
		PasteOrigin: viper.GetString("apps.public-paste"),
	}

	memoryShareController := memoryShareCtrl.NewController(memoryShareRepo, fileRepo, accessCtrl)
	memorySharePublicController := publicCtrl.NewMemoryShareController(memoryShareRepo, fileRepo, collectionRepo, fileController)

	passkeyCtrl := &controller.PasskeyController{
		Repo:     passkeysRepo,
		UserRepo: userRepo,
	}
	legacyKitController := &legacykitctrl.Controller{
		Repo:              legacyKitRepository,
		UserRepo:          userRepo,
		UserCtrl:          userController,
		PasskeyController: passkeyCtrl,
	}

	authMiddleware := middleware.AuthMiddleware{UserAuthRepo: userAuthRepo, Cache: authCache, UserController: userController}
	collectionLinkMiddleware := middleware.CollectionLinkMiddleware{
		CollectionLinkRepo:   collectionLinkRepo,
		PublicCollectionCtrl: collectionLinkCtrl,
		CollectionRepo:       collectionRepo,
		AnonUsersRepo:        anonUsersRepo,
		Cache:                accessTokenCache,
		BillingCtrl:          billingController,
		DiscordController:    discordController,
		RemoteStoreRepo:      remoteStoreRepository,
		AnonIdentitySecret:   jwtSecretBytes,
	}
	fileLinkMiddleware := &middleware.FileLinkMiddleware{
		FileLinkRepo:      fileLinkRepo,
		FileLinkCtrl:      fileLinkCtrl,
		Cache:             accessTokenCache,
		BillingCtrl:       billingController,
		DiscordController: discordController,
	}
	memoryShareMiddleware := &middleware.MemoryShareMiddleware{
		Repo: memoryShareRepo,
	}

	if environment != "local" {
		gin.SetMode(gin.ReleaseMode)
	}
	server := gin.New()

	clientIPHeader := viper.GetString("internal.trusted-client-ip-header")
	if clientIPHeader != "" {
		server.TrustedPlatform = clientIPHeader
	}

	p := ginprometheus.NewPrometheus("museum")
	p.ReqCntURLLabelMappingFn = urlSanitizer
	server.Use(p.HandlerFunc())

	server.LoadHTMLGlob("web-templates/*")
	// note: the recover middleware must be in the last

	server.Use(requestid.New(
		requestid.Config{
			Generator: func() string {
				return base.ServerReqID()
			},
		}),
		middleware.Logger(urlSanitizer), cors(), cacheHeaders(),
		gzip.Gzip(gzip.DefaultCompression), middleware.PanicRecover())

	publicAPI := server.Group("/")
	publicAPI.Use(rateLimiter.GlobalRateLimiter(), rateLimiter.APIRateLimitMiddleware(urlSanitizer))

	privateAPI := server.Group("/")
	privateAPI.Use(rateLimiter.GlobalRateLimiter(), authMiddleware.TokenAuthMiddleware(nil), rateLimiter.APIRateLimitForUserMiddleware(urlSanitizer))
	storageAPI := privateAPI.Group("/")
	storageAPI.Use(middleware.RejectAuthApp())

	adminAPI := server.Group("/admin")
	adminAPI.Use(rateLimiter.GlobalRateLimiter(), authMiddleware.TokenAuthMiddleware(nil), authMiddleware.AdminAuthMiddleware())
	paymentJwtAuthAPI := server.Group("/")
	paymentJwtAuthAPI.Use(rateLimiter.GlobalRateLimiter(), authMiddleware.TokenAuthMiddleware(jwt.PAYMENT.Ptr()))

	familiesJwtAuthAPI := server.Group("/")
	//The middleware order matters. First, the userID must be set in the context, so that we can apply limit for user.
	familiesJwtAuthAPI.Use(rateLimiter.GlobalRateLimiter(), authMiddleware.TokenAuthMiddleware(jwt.FAMILIES.Ptr()), rateLimiter.APIRateLimitForUserMiddleware(urlSanitizer))

	publicCollectionAPI := server.Group("/public-collection")
	publicCollectionAPI.Use(
		rateLimiter.GlobalRateLimiter(),
		collectionLinkMiddleware.Authenticate(urlSanitizer),
		rateLimiter.APIRateLimitMiddleware(urlSanitizer),
	)
	fileLinkApi := server.Group("/file-link")
	fileLinkApi.Use(rateLimiter.GlobalRateLimiter(), fileLinkMiddleware.Authenticate(urlSanitizer))

	publicMemoryAPI := server.Group("/public-memory")
	publicMemoryAPI.Use(
		rateLimiter.GlobalRateLimiter(),
		memoryShareMiddleware.Authenticate(urlSanitizer),
		rateLimiter.APIRateLimitMiddleware(urlSanitizer),
	)

	healthCheckHandler := &api.HealthCheckHandler{
		DB: db,
	}
	publicAPI.GET("/ping", timeout.New(
		timeout.WithTimeout(5*time.Second),
		timeout.WithHandler(healthCheckHandler.Ping),
		timeout.WithResponse(timeOutResponse),
	))

	publicAPI.GET("/fire/db-m-ping", timeout.New(
		timeout.WithTimeout(5*time.Second),
		timeout.WithHandler(healthCheckHandler.PingDBStats),
		timeout.WithResponse(timeOutResponse),
	))
	eventHandler := &api.EventHandler{Repo: eventRepository}
	publicAPI.POST("/events", eventHandler.Create)
	privateAPI.POST("/events/user", eventHandler.CreateForUser)
	fileCopyCtrl := &file_copy.FileCopyController{
		FileController: fileController,
		CollectionCtrl: collectionController,
		S3Config:       s3Config,
		ObjectRepo:     objectRepo,
		FileRepo:       fileRepo,
	}

	fileHandler := &api.FileHandler{
		Controller:   fileController,
		FileCopyCtrl: fileCopyCtrl,
		FileDataCtrl: fileDataCtrl,
		FileUrlCtrl:  fileLinkCtrl,
	}
	pasteHandler := &api.PasteHandler{Controller: pasteCtrl}
	storageAPI.GET("/files/upload-eligibility", fileHandler.ValidateUploadEligibility)
	storageAPI.GET("/files/upload-urls", fileHandler.GetUploadURLs)
	storageAPI.GET("/files/multipart-upload-urls", fileHandler.GetMultipartUploadURLs)
	storageAPI.POST("/files/upload-url", fileHandler.GetUploadURLV2)
	storageAPI.POST("/files/multipart-upload-url", fileHandler.GetMultipartUploadURLV2)
	storageAPI.GET("/files/download/:fileID", fileHandler.Get)
	storageAPI.GET("/files/download/v2/:fileID", fileHandler.GetV2)
	storageAPI.GET("/files/preview/:fileID", fileHandler.GetThumbnail)
	storageAPI.GET("/files/preview/v2/:fileID", fileHandler.GetThumbnailV2)

	storageAPI.POST("/files/share-url", fileHandler.ShareUrl)
	storageAPI.GET("/files/share-url", fileHandler.GetUrls)
	storageAPI.PUT("/files/share-url", fileHandler.UpdateFileURL)
	storageAPI.DELETE("/files/share-url/:fileID", fileHandler.DisableUrl)
	storageAPI.GET("/files/share-urls/", fileHandler.GetUrls)

	storageAPI.PUT("/files/data", fileHandler.PutFileData)
	storageAPI.PUT("/files/video-data", fileHandler.PutVideoData)
	storageAPI.POST("/files/data/status-diff", fileHandler.FileDataStatusDiff)
	storageAPI.POST("/files/data/fetch", fileHandler.GetFilesData)
	storageAPI.GET("/files/data/fetch", fileHandler.GetFileData)
	storageAPI.GET("/files/data/preview-upload-url", fileHandler.GetPreviewUploadURL)
	storageAPI.GET("/files/data/preview", fileHandler.GetPreviewURL)

	storageAPI.POST("/files", fileHandler.CreateOrUpdate)
	storageAPI.POST("/files/meta", fileHandler.CreateMetaFile)
	storageAPI.POST("/files/copy", fileHandler.CopyFiles)
	storageAPI.PUT("/files/update", fileHandler.Update)
	storageAPI.POST("/files/trash", fileHandler.Trash)
	storageAPI.POST("/files/size", fileHandler.GetSize)
	storageAPI.POST("/files/info", fileHandler.GetInfo)
	storageAPI.GET("/files/duplicates", fileHandler.GetDuplicates)
	storageAPI.PUT("/files/thumbnail", fileHandler.UpdateThumbnail)
	storageAPI.PUT("/files/magic-metadata", fileHandler.UpdateMagicMetadata)
	storageAPI.PUT("/files/public-magic-metadata", fileHandler.UpdatePublicMagicMetadata)
	publicAPI.GET("/files/count", fileHandler.GetTotalFileCount)
	publicAPI.POST("/paste/create", pasteHandler.Create)
	publicAPI.POST("/paste/guard", pasteHandler.Guard)
	publicAPI.POST("/paste/consume", pasteHandler.Consume)

	trashHandler := &api.TrashHandler{
		Controller: trashController,
	}
	storageAPI.GET("/trash/diff", trashHandler.GetDiff)
	storageAPI.GET("/trash/v2/diff", trashHandler.GetDiffV2)
	storageAPI.POST("/trash/delete", trashHandler.Delete)
	storageAPI.POST("/trash/empty", trashHandler.Empty)
	commentsHandler := &api.CommentsHandler{Controller: commentsController}
	reactionsHandler := &api.ReactionsHandler{Controller: reactionsController}
	socialHandler := &api.SocialHandler{Controller: socialController}
	publicSocialHandler := &api.PublicCommentsHandler{
		CommentsCtrl:     publicCommentsCtrl,
		ReactionsCtrl:    publicReactionsCtrl,
		AnonIdentityCtrl: anonIdentityCtrl,
	}
	storageAPI.GET("/comments/diff", commentsHandler.Diff)
	storageAPI.POST("/comments", commentsHandler.Create)
	storageAPI.PUT("/comments/:commentID", commentsHandler.Update)
	storageAPI.DELETE("/comments/:commentID", commentsHandler.Delete)

	storageAPI.GET("/reactions/diff", reactionsHandler.Diff)
	storageAPI.PUT("/reactions", reactionsHandler.Upsert)
	storageAPI.DELETE("/reactions/:reactionID", reactionsHandler.Delete)

	storageAPI.GET("/social/diff", socialHandler.UnifiedDiff)
	storageAPI.GET("/social/anon-profiles", socialHandler.AnonProfiles)
	storageAPI.GET("/comments-reactions/counts", socialHandler.Counts)
	storageAPI.GET("/comments-reactions/updated-at", socialHandler.LatestUpdates)

	emergencyCtrl := &emergency.Controller{
		Repo:              emergencyContactRepository,
		UserRepo:          userRepo,
		UserCtrl:          userController,
		PasskeyController: passkeyCtrl,
		LockCtrl:          lockController,
	}
	userHandler := &api.UserHandler{
		UserController:      userController,
		EmergencyController: emergencyCtrl,
	}
	publicAPI.POST("/users/ott", userHandler.SendOTT)
	publicAPI.POST("/users/verify-email", userHandler.VerifyEmail)
	publicAPI.POST("/users/two-factor/verify", userHandler.VerifyTwoFactor)
	publicAPI.GET("/users/two-factor/recover", userHandler.RecoverTwoFactor)
	publicAPI.POST("/users/two-factor/remove", userHandler.RemoveTwoFactor)
	publicAPI.POST("/users/two-factor/passkeys/begin", userHandler.BeginPasskeyAuthenticationCeremony)
	publicAPI.POST("/users/two-factor/passkeys/finish", userHandler.FinishPasskeyAuthenticationCeremony)
	publicAPI.GET("/users/two-factor/passkeys/get-token", userHandler.GetTokenForPasskeySession)
	privateAPI.GET("/users/two-factor/recovery-status", userHandler.GetTwoFactorRecoveryStatus)
	privateAPI.POST("/users/two-factor/passkeys/configure-recovery", userHandler.ConfigurePasskeyRecovery)
	privateAPI.GET("/users/two-factor/status", userHandler.GetTwoFactorStatus)
	privateAPI.POST("/users/two-factor/setup", userHandler.SetupTwoFactor)
	privateAPI.POST("/users/two-factor/enable", userHandler.EnableTwoFactor)
	privateAPI.POST("/users/two-factor/disable", userHandler.DisableTwoFactor)
	privateAPI.PUT("/users/attributes", userHandler.SetAttributes)
	privateAPI.PUT("/users/email-mfa", userHandler.UpdateEmailMFA)
	privateAPI.POST("/users/srp/setup", userHandler.SetupSRP)
	privateAPI.POST("/users/srp/complete", userHandler.CompleteSRPSetup)
	privateAPI.POST("/users/srp/update", userHandler.UpdateSrpAndKeyAttributes)
	publicAPI.GET("/users/srp/attributes", userHandler.GetSRPAttributes)
	publicAPI.POST("/users/srp/verify-session", userHandler.VerifySRPSession)
	publicAPI.POST("/users/srp/create-session", userHandler.CreateSRPSession)
	privateAPI.PUT("/users/recovery-key", userHandler.SetRecoveryKey)
	privateAPI.GET("/users/public-key", userHandler.GetPublicKey)
	privateAPI.GET("/users/session-validity/v2", userHandler.GetSessionValidityV2)
	privateAPI.POST("/users/event", userHandler.ReportEvent)
	privateAPI.POST("/users/logout", userHandler.Logout)
	privateAPI.GET("/users/payment-token", userHandler.GetPaymentToken)
	privateAPI.GET("/users/families-token", userHandler.GetFamiliesToken)
	privateAPI.GET("/users/accounts-token", userHandler.GetAccountsToken)
	privateAPI.GET("/users/details/v2", userHandler.GetDetailsV2)
	privateAPI.GET("/users/deletion-summary", userHandler.GetAccountDeletionSummary)
	storageAPI.GET("/users/locker-usage", userHandler.GetLockerUsage)
	privateAPI.POST("/users/change-email", userHandler.ChangeEmail)
	privateAPI.GET("/users/sessions", userHandler.GetActiveSessions)
	privateAPI.DELETE("/users/session", userHandler.TerminateSession)
	privateAPI.GET("/users/delete-challenge", userHandler.GetDeleteChallenge)
	privateAPI.DELETE("/users/delete", userHandler.DeleteUser)
	publicAPI.GET("/users/recover-account", userHandler.SelfAccountRecovery)

	accountsJwtAuthAPI := server.Group("/")
	accountsJwtAuthAPI.Use(rateLimiter.GlobalRateLimiter(), authMiddleware.TokenAuthMiddleware(jwt.ACCOUNTS.Ptr()), rateLimiter.APIRateLimitForUserMiddleware(urlSanitizer))
	passkeysHandler := &api.PasskeyHandler{
		Controller: passkeyCtrl,
	}
	accountsJwtAuthAPI.GET("/passkeys", passkeysHandler.GetPasskeys)
	accountsJwtAuthAPI.PATCH("/passkeys/:passkeyID", passkeysHandler.RenamePasskey)
	accountsJwtAuthAPI.DELETE("/passkeys/:passkeyID", passkeysHandler.DeletePasskey)
	accountsJwtAuthAPI.POST("/passkeys/registration/begin", passkeysHandler.BeginRegistration)
	accountsJwtAuthAPI.POST("/passkeys/registration/finish", passkeysHandler.FinishRegistration)

	collectionHandler := &api.CollectionHandler{
		Controller: collectionController,
	}
	storageAPI.POST("/collections", collectionHandler.Create)
	// Collection actions (exposed for clients to fetch suggestions/removals)
	storageAPI.GET("/collection-actions/pending-remove", collectionActionsHandler.ListPendingRemove)
	storageAPI.GET("/collection-actions/delete-suggestions", collectionActionsHandler.ListDeleteSuggestions)
	storageAPI.POST("/collection-actions/reject-delete-suggestions", collectionActionsHandler.RejectDeleteSuggestions)

	storageAPI.GET("/collections/:collectionID", collectionHandler.GetCollectionByID)
	//lint:ignore SA1019 Deprecated API will be removed in the future
	storageAPI.GET("/collections", collectionHandler.Get)
	storageAPI.GET("/collections/v2", collectionHandler.GetV2)
	storageAPI.GET("/collections/v3", collectionHandler.GetWithLimit)
	storageAPI.POST("/collections/share", collectionHandler.Share)
	storageAPI.POST("/collections/join-link", collectionHandler.JoinLink)
	storageAPI.POST("/collections/share-url", collectionHandler.ShareURL)
	storageAPI.PUT("/collections/share-url", collectionHandler.UpdateShareURL)
	storageAPI.DELETE("/collections/share-url/:collectionID", collectionHandler.UnShareURL)
	storageAPI.POST("/collections/unshare", collectionHandler.UnShare)
	storageAPI.POST("/collections/leave/:collectionID", collectionHandler.Leave)
	storageAPI.POST("/collections/add-files", collectionHandler.AddFiles)
	storageAPI.POST("/collections/move-files", collectionHandler.MoveFiles)
	storageAPI.POST("/collections/restore-files", collectionHandler.RestoreFiles)

	storageAPI.POST("/collections/v3/remove-files", collectionHandler.RemoveFilesV3)
	storageAPI.POST("/collections/suggest-delete", collectionHandler.SuggestDeleteInSharedCollection)
	storageAPI.GET("/collections/v2/diff", collectionHandler.GetDiffV2)
	storageAPI.GET("/collections/file", collectionHandler.GetFile)
	storageAPI.GET("/collections/sharees", collectionHandler.GetSharees)
	storageAPI.DELETE("/collections/v3/:collectionID", collectionHandler.TrashV3)
	storageAPI.POST("/collections/rename", collectionHandler.Rename)
	storageAPI.PUT("/collections/magic-metadata", collectionHandler.PrivateMagicMetadataUpdate)
	storageAPI.PUT("/collections/public-magic-metadata", collectionHandler.PublicMagicMetadataUpdate)
	storageAPI.PUT("/collections/sharee-magic-metadata", collectionHandler.ShareeMagicMetadataUpdate)

	publicCollectionHandler := &api.PublicCollectionHandler{
		Controller:             collectionLinkCtrl,
		FileCtrl:               fileController,
		CollectionCtrl:         collectionController,
		FileDataCtrl:           fileDataCtrl,
		StorageBonusController: storageBonusCtrl,
	}
	fileLinkApi.GET("/info", fileHandler.LinkInfo)
	fileLinkApi.GET("/pass-info", fileHandler.PasswordInfo)
	fileLinkApi.GET("/thumbnail", fileHandler.LinkThumbnail)
	fileLinkApi.GET("/file", fileHandler.LinkFile)
	fileLinkApi.POST("/verify-password", fileHandler.VerifyPassword)

	publicCollectionAPI.GET("/files/preview/:fileID", publicCollectionHandler.GetThumbnail)
	publicCollectionAPI.GET("/files/download/:fileID", publicCollectionHandler.GetFile)
	publicCollectionAPI.GET("/files/data/fetch", publicCollectionHandler.GetFileData)
	publicCollectionAPI.GET("/files/data/preview", publicCollectionHandler.GetPreviewURL)
	publicCollectionAPI.GET("/diff", publicCollectionHandler.GetDiff)
	publicCollectionAPI.GET("/info", publicCollectionHandler.GetCollection)
	publicCollectionAPI.POST("/upload-url", publicCollectionHandler.GetUploadURLV2)
	publicCollectionAPI.POST("/multipart-upload-url", publicCollectionHandler.GetMultipartUploadURLV2)
	publicCollectionAPI.POST("/file", publicCollectionHandler.CreateFile)
	publicCollectionAPI.POST("/verify-password", publicCollectionHandler.VerifyPassword)
	publicCollectionAPI.GET("/social/diff", publicSocialHandler.SocialDiff)
	publicCollectionAPI.GET("/comments/diff", publicSocialHandler.CommentDiff)
	publicCollectionAPI.POST("/comments", publicSocialHandler.CreateComment)
	publicCollectionAPI.PUT("/comments/:commentID", publicSocialHandler.UpdateComment)
	publicCollectionAPI.DELETE("/comments/:commentID", publicSocialHandler.DeleteComment)
	publicCollectionAPI.GET("/reactions/diff", publicSocialHandler.ReactionDiff)
	publicCollectionAPI.POST("/reactions", publicSocialHandler.CreateReaction)
	publicCollectionAPI.DELETE("/reactions/:reactionID", publicSocialHandler.DeleteReaction)
	publicCollectionAPI.GET("/participants/masked-emails", publicSocialHandler.Participants)
	publicCollectionAPI.GET("/anon-profiles", publicSocialHandler.AnonProfiles)
	publicCollectionAPI.POST("/anon-identity", publicSocialHandler.CreateAnonIdentity)

	memoryShareHandler := &api.MemoryShareHandler{
		Controller: memoryShareController,
	}
	publicMemoryShareHandler := &api.PublicMemoryShareHandler{
		PublicCtrl:   memorySharePublicController,
		FileDataCtrl: fileDataCtrl,
	}

	storageAPI.POST("/memory-share", memoryShareHandler.Create)
	storageAPI.GET("/memory-share", memoryShareHandler.List)
	storageAPI.GET("/memory-share/:shareID", memoryShareHandler.GetByID)
	storageAPI.DELETE("/memory-share/:shareID", memoryShareHandler.Delete)

	publicMemoryAPI.GET("/info", publicMemoryShareHandler.GetInfo)
	publicMemoryAPI.GET("/files", publicMemoryShareHandler.GetFiles)
	publicMemoryAPI.GET("/files/preview/:fileID", publicMemoryShareHandler.GetThumbnail)
	publicMemoryAPI.GET("/files/download/:fileID", publicMemoryShareHandler.GetFile)
	publicMemoryAPI.GET("/file-data", publicMemoryShareHandler.GetFileData)
	publicMemoryAPI.GET("/files/data/preview", publicMemoryShareHandler.GetPreviewURL)

	castAPI := server.Group("/cast")

	castCtrl := cast.NewController(&castDb, accessCtrl)
	castMiddleware := middleware.CastMiddleware{CastCtrl: castCtrl, Cache: authCache}
	castAPI.Use(rateLimiter.GlobalRateLimiter(), castMiddleware.CastAuthMiddleware())

	castHandler := &api.CastHandler{
		CollectionCtrl: collectionController,
		FileCtrl:       fileController,
		Ctrl:           castCtrl,
	}

	publicAPI.POST("/cast/device-info", castHandler.RegisterDevice)
	storageAPI.GET("/cast/device-info", castHandler.GetAllDevices)
	storageAPI.DELETE("/cast/device-info/:deviceID", castHandler.DeleteDevice)
	// Deprecated Nov 2024. Remove in a few months.
	//
	// This (and below) are deprecated copy of endpoints with a trailing slash.
	// Kept around because existing desktop clients will not follow the 307
	// redirect because of CORS headers missing on the 307. Can be safely
	// removed in a few months after the desktop apps have updated.
	publicAPI.POST("/cast/device-info/", castHandler.RegisterDevice)
	storageAPI.GET("/cast/device-info/:deviceCode", castHandler.GetDeviceInfo)
	publicAPI.GET("/cast/cast-data/:deviceCode", castHandler.GetCastData)
	storageAPI.POST("/cast/cast-data", castHandler.InsertCastData)
	// Deprecated Nov 2024. Remove in a few months.
	storageAPI.POST("/cast/cast-data/", castHandler.InsertCastData)
	storageAPI.DELETE("/cast/revoke-all-tokens", castHandler.RevokeAllToken)
	// Deprecated Nov 2024. Remove in a few months.
	storageAPI.DELETE("/cast/revoke-all-tokens/", castHandler.RevokeAllToken)

	castAPI.GET("/files/preview/:fileID", castHandler.GetThumbnail)
	castAPI.GET("/files/download/:fileID", castHandler.GetFile)
	castAPI.GET("/diff", castHandler.GetDiff)
	castAPI.GET("/info", castHandler.GetCollection)
	familyHandler := &api.FamilyHandler{
		Controller: familyController,
	}

	publicAPI.GET("/family/invite-info/:token", familyHandler.GetInviteInfo)
	publicAPI.POST("/family/accept-invite", familyHandler.AcceptInvite)

	privateAPI.DELETE("/family/leave", familyHandler.Leave) // native/web app

	familiesJwtAuthAPI.POST("/family/create", familyHandler.CreateFamily)
	familiesJwtAuthAPI.POST("/family/add-member", familyHandler.InviteMember)
	familiesJwtAuthAPI.GET("/family/members", familyHandler.FetchMembers)
	familiesJwtAuthAPI.DELETE("/family/remove-member/:id", familyHandler.RemoveMember)
	familiesJwtAuthAPI.DELETE("/family/revoke-invite/:id", familyHandler.RevokeInvite)
	familiesJwtAuthAPI.POST("/family/modify-storage", familyHandler.ModifyStorageLimit)

	emergencyHandler := &api.EmergencyHandler{
		Controller: emergencyCtrl,
	}
	legacyKitHandler := &api.LegacyKitHandler{
		Controller: legacyKitController,
	}

	privateAPI.POST("/emergency-contacts/add", emergencyHandler.AddContact)
	privateAPI.GET("/emergency-contacts/info", emergencyHandler.GetInfo)
	privateAPI.POST("/emergency-contacts/update", emergencyHandler.UpdateContact)
	privateAPI.POST("/emergency-contacts/update-recovery-notice", emergencyHandler.UpdateRecoveryNotice)
	privateAPI.POST("/emergency-contacts/start-recovery", emergencyHandler.StartRecovery)
	privateAPI.POST("/emergency-contacts/stop-recovery", emergencyHandler.StopRecovery)
	privateAPI.POST("/emergency-contacts/reject-recovery", emergencyHandler.RejectRecovery)
	privateAPI.POST("/emergency-contacts/approve-recovery", emergencyHandler.ApproveRecovery)
	privateAPI.GET("/emergency-contacts/recovery-info/:id", emergencyHandler.GetRecoveryInfo)
	privateAPI.POST("/emergency-contacts/init-change-password", emergencyHandler.InitChangePassword)
	privateAPI.POST("/emergency-contacts/change-password", emergencyHandler.ChangePassword)
	privateAPI.POST("/legacy-kits", legacyKitHandler.Create)
	privateAPI.GET("/legacy-kits", legacyKitHandler.List)
	privateAPI.GET("/legacy-kits/:id/download", legacyKitHandler.DownloadContent)
	privateAPI.GET("/legacy-kits/:id/download-content", legacyKitHandler.DownloadContent)
	privateAPI.GET("/legacy-kits/:id/recovery-session", legacyKitHandler.OwnerRecoverySession)
	privateAPI.POST("/legacy-kits/update-recovery-notice", legacyKitHandler.UpdateRecoveryNotice)
	privateAPI.POST("/legacy-kits/block-recovery", legacyKitHandler.BlockRecovery)
	privateAPI.DELETE("/legacy-kits/:id", legacyKitHandler.Delete)
	publicAPI.POST("/legacy-kits/recovery/challenge", legacyKitHandler.CreateChallenge)
	publicAPI.POST("/legacy-kits/recovery/open", legacyKitHandler.OpenRecovery)
	publicAPI.POST("/legacy-kits/recovery/session", legacyKitHandler.Session)
	publicAPI.POST("/legacy-kits/recovery/info", legacyKitHandler.RecoveryInfo)
	publicAPI.POST("/legacy-kits/recovery/init-change-password", legacyKitHandler.InitChangePassword)
	publicAPI.POST("/legacy-kits/recovery/change-password", legacyKitHandler.ChangePassword)
	billingHandler := &api.BillingHandler{
		Controller:          billingController,
		AppStoreController:  appStoreController,
		PlayStoreController: playStoreController,
		StripeController:    stripeController,
	}
	publicAPI.GET("/billing/plans/v2", billingHandler.GetPlansV2)
	privateAPI.GET("/billing/user-plans", billingHandler.GetUserPlans)
	privateAPI.GET("/billing/usage", billingHandler.GetUsage)
	privateAPI.GET("/billing/subscription", billingHandler.GetSubscription)
	privateAPI.POST("/billing/verify-subscription", billingHandler.VerifySubscription)
	publicAPI.POST("/billing/notify/android", billingHandler.AndroidNotificationHandler)
	publicAPI.POST("/billing/notify/ios", billingHandler.IOSNotificationHandler)
	publicAPI.POST("/billing/notify/stripe", billingHandler.StripeINNotificationHandler)
	// after the StripeIN customers are completely migrated, we can change notify/stripe/us to notify/stripe and deprecate this endpoint
	publicAPI.POST("/billing/notify/stripe/us", billingHandler.StripeUSNotificationHandler)
	privateAPI.GET("/billing/stripe/customer-portal", billingHandler.GetStripeCustomerPortal)
	privateAPI.POST("/billing/stripe/cancel-subscription", billingHandler.StripeCancelSubscription)
	privateAPI.POST("/billing/stripe/activate-subscription", billingHandler.StripeActivateSubscription)
	paymentJwtAuthAPI.GET("/billing/stripe-account-country", billingHandler.GetStripeAccountCountry)
	paymentJwtAuthAPI.GET("/billing/stripe/checkout-session", billingHandler.GetCheckoutSession)
	paymentJwtAuthAPI.POST("/billing/stripe/update-subscription", billingHandler.StripeUpdateSubscription)

	storageBonusHandler := &api.StorageBonusHandler{
		Controller: storageBonusCtrl,
	}

	privateAPI.GET("/storage-bonus/details", storageBonusHandler.GetStorageBonusDetails)
	privateAPI.POST("/storage-bonus/change-code", storageBonusHandler.UpdateReferralCode)
	privateAPI.GET("/storage-bonus/referral-view", storageBonusHandler.GetReferralView)
	privateAPI.POST("/storage-bonus/referral-claim", storageBonusHandler.ClaimReferral)

	adminHandler := &api.AdminHandler{
		QueueRepo:              queueRepo,
		UserRepo:               userRepo,
		CollectionRepo:         collectionRepo,
		AuthenticatorRepo:      authRepo,
		UserAuthRepo:           userAuthRepo,
		UserController:         userController,
		FamilyController:       familyController,
		EmergencyController:    emergencyCtrl,
		RemoteStoreController:  remoteStoreController,
		FileRepo:               fileRepo,
		StorageBonusRepo:       storagBonusRepo,
		BillingRepo:            billingRepo,
		BillingController:      billingController,
		MailingListsController: mailingListsController,
		DiscordController:      discordController,
		HashingKey:             hashingKeyBytes,
		PasskeyController:      passkeyCtrl,
		StorageBonusCtl:        storageBonusCtrl,
	}
	adminAPI.POST("/mail", adminHandler.SendMail)
	adminAPI.POST("/mail/subscribe", adminHandler.SubscribeMail)
	adminAPI.POST("/mail/unsubscribe", adminHandler.UnsubscribeMail)
	adminAPI.GET("/listmonk/missing-subscribers/count", adminHandler.GetListmonkMissingSubscribersCount)
	adminAPI.GET("/users", adminHandler.GetUsers)
	adminAPI.GET("/user", adminHandler.GetUser)
	adminAPI.POST("/user/disable-2fa", adminHandler.DisableTwoFactor)
	adminAPI.POST("/user/update-referral", adminHandler.UpdateReferral)
	adminAPI.POST("/user/disable-passkeys", adminHandler.RemovePasskeys)
	adminAPI.POST("/user/update-email-mfa", adminHandler.UpdateEmailMFA)
	adminAPI.POST("/user/unblock-storage-warning-login", adminHandler.UnblockStorageWarningLogin)
	adminAPI.POST("/user/add-ott", adminHandler.AddOtt)
	adminAPI.POST("/user/terminate-session", adminHandler.TerminateSession)
	adminAPI.POST("/user/close-family", adminHandler.CloseFamily)
	adminAPI.PUT("/user/change-email", adminHandler.ChangeEmail)
	adminAPI.DELETE("/user/delete", adminHandler.DeleteUser)
	adminAPI.POST("/user/recover", adminHandler.RecoverAccount)
	adminAPI.POST("/user/update-flag", adminHandler.UpdateFeatureFlag)
	adminAPI.GET("/email-hash", adminHandler.GetEmailHash)
	adminAPI.POST("/emails-from-hashes", adminHandler.GetEmailsFromHashes)
	adminAPI.PUT("/user/subscription", adminHandler.UpdateSubscription)
	adminAPI.POST("/queue/re-queue", adminHandler.ReQueueItem)
	adminAPI.POST("/user/bonus", adminHandler.UpdateBonus)

	userEntityController := &userEntityCtrl.Controller{Repo: userEntityRepo}
	userEntityHandler := &api.UserEntityHandler{Controller: userEntityController}

	storageAPI.POST("/user-entity/key", userEntityHandler.CreateKey)
	storageAPI.GET("/user-entity/key", userEntityHandler.GetKey)
	storageAPI.POST("/user-entity/entity", userEntityHandler.CreateEntity)
	storageAPI.PUT("/user-entity/entity", userEntityHandler.UpdateEntity)
	storageAPI.DELETE("/user-entity/entity", userEntityHandler.DeleteEntity)
	storageAPI.GET("/user-entity/entity/diff", userEntityHandler.GetDiff)

	contactController := contactCtrl.New(contactRepository, objectCleanupController, s3Config)
	contactHandler := &api.ContactHandler{Controller: contactController}

	storageAPI.POST("/contacts", contactHandler.Create)
	storageAPI.GET("/contacts/:id", contactHandler.Get)
	storageAPI.GET("/contacts/diff", contactHandler.GetDiff)
	storageAPI.PUT("/contacts/:id", contactHandler.Update)
	storageAPI.DELETE("/contacts/:id", contactHandler.Delete)
	storageAPI.POST("/attachments/:type/upload-url", contactHandler.GetAttachmentUploadURL)
	storageAPI.GET("/attachments/:type/:attachmentID", contactHandler.GetAttachment)
	storageAPI.PUT("/contacts/:id/attachments/:type", contactHandler.AttachContactAttachment)
	storageAPI.GET("/contacts/:id/attachments/:type", contactHandler.GetCurrentContactAttachment)
	storageAPI.DELETE("/contacts/:id/attachments/:type", contactHandler.DeleteContactAttachment)
	storageAPI.POST("/contacts/:id/profile-picture/upload-url", contactHandler.GetProfilePictureUploadURL)
	storageAPI.PUT("/contacts/:id/profile-picture", contactHandler.AttachProfilePicture)
	storageAPI.GET("/contacts/:id/profile-picture", contactHandler.GetProfilePicture)
	storageAPI.DELETE("/contacts/:id/profile-picture", contactHandler.DeleteProfilePicture)

	authenticatorController := &authenticatorCtrl.Controller{Repo: authRepo, UserRepo: userRepo}
	authenticatorHandler := &api.AuthenticatorHandler{Controller: authenticatorController}

	privateAPI.POST("/authenticator/key", authenticatorHandler.CreateKey)
	privateAPI.GET("/authenticator/key", authenticatorHandler.GetKey)
	privateAPI.POST("/authenticator/entity", authenticatorHandler.CreateEntity)
	privateAPI.PUT("/authenticator/entity", authenticatorHandler.UpdateEntity)
	privateAPI.DELETE("/authenticator/entity", authenticatorHandler.DeleteEntity)
	privateAPI.GET("/authenticator/entity/diff", authenticatorHandler.GetDiff)

	dataCleanupController := &dataCleanupCtrl.DeleteUserCleanupController{
		Repo:           dataCleanupRepository,
		UserRepo:       userRepo,
		CollectionRepo: collectionRepo,
		TaskLockRepo:   taskLockingRepo,
		TrashRepo:      trashRepo,
		UsageRepo:      usageRepo,
		HostName:       hostName,
	}
	remoteStoreHandler := &api.RemoteStoreHandler{Controller: remoteStoreController}

	privateAPI.POST("/remote-store/update", remoteStoreHandler.InsertOrUpdate)
	privateAPI.DELETE("/remote-store/:key", remoteStoreHandler.RemoveKey)
	privateAPI.GET("/remote-store", remoteStoreHandler.GetKey)
	privateAPI.GET("/remote-store/feature-flags", remoteStoreHandler.GetFeatureFlags)
	publicAPI.GET("/custom-domain", remoteStoreHandler.CheckDomain)

	pushHandler := &api.PushHandler{PushController: pushController}
	privateAPI.POST("/push/token", pushHandler.AddToken)

	embeddingController := embeddingCtrl.New(embeddingRepo, objectCleanupController, queueRepo, taskLockingRepo, fileRepo, hostName)

	offerHandler := &api.OfferHandler{Controller: offerController}
	publicAPI.GET("/offers/black-friday", offerHandler.GetBlackFridayOffers)

	discountCouponRepository := &discountCouponRepo.Repository{DB: db}
	discountCouponController := &discountCouponCtrl.Controller{
		Repo:                  discountCouponRepository,
		UserRepo:              userRepo,
		BillingController:     billingController,
		EmailNotificationCtrl: emailNotificationCtrl,
		DiscordController:     discordController,
	}
	discountCouponHandler := &api.DiscountCouponHandler{Controller: discountCouponController}
	publicAPI.POST("/discount/claim", discountCouponHandler.ClaimCoupon)
	adminAPI.POST("/discount/add-coupons", discountCouponHandler.AddCoupons)

	setKnownAPIs(server.Routes())
	setupAndStartBackgroundJobs(objectCleanupController, replicationController3, fileDataCtrl, contactController)
	setupAndStartCrons(
		userAuthRepo, collectionLinkRepo, fileLinkRepo, pasteRepo, twoFactorRepo, passkeysRepo, fileController, taskLockingRepo, emailNotificationCtrl,
		trashController, pushController, objectController, dataCleanupController, storageBonusCtrl, emergencyCtrl,
		embeddingController, healthCheckHandler, castDb, inactiveUserOrchestrator)

	// Create new collectors, the names will be used as labels on the metrics
	primaryDBCollector := sqlstats.NewStatsCollector("prod_db", db)
	latencySensitiveDBCollector := sqlstats.NewStatsCollector("latency_sensitive_db", latencySensitiveDB)
	// Register them with Prometheus
	prometheus.MustRegister(primaryDBCollector, latencySensitiveDBCollector)

	http.Handle("/metrics", promhttp.Handler())
	go http.ListenAndServe(":2112", nil)
	go runServer(environment, server)
	discordController.NotifyStartup()
	log.Println("We have lift-off.")

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")
	discordController.NotifyShutdown()
}

func runServer(environment string, server *gin.Engine) {
	useTLS := viper.GetBool("http.use-tls")
	if useTLS {
		certPath, err := config.CredentialFilePath("tls.cert")
		if err != nil {
			log.Fatal(err)
		}

		keyPath, err := config.CredentialFilePath("tls.key")
		if err != nil {
			log.Fatal(err)
		}

		log.Fatal(server.RunTLS(":443", certPath, keyPath))
	} else {
		port := 8080
		if viper.IsSet("http.port") {
			port = viper.GetInt("http.port")
		}
		log.Infof("starting server on port %d", port)
		if server.TrustedPlatform != "" {
			log.Infof("trusted platform header: %s", server.TrustedPlatform)
		}
		server.Run(fmt.Sprintf(":%d", port))
	}
}

func setupLogger(environment string) {
	log.SetReportCaller(true)
	callerPrettyfier := func(f *runtime.Frame) (string, string) {
		s := strings.Split(f.Function, ".")
		funcName := s[len(s)-1]
		return funcName, fmt.Sprintf("%s:%d", path.Base(f.File), f.Line)
	}
	logFile := viper.GetString("log-file")
	if environment == "local" && logFile == "" {
		log.SetFormatter(&log.TextFormatter{
			CallerPrettyfier: callerPrettyfier,
			DisableQuote:     true,
			ForceColors:      true,
		})
	} else {
		log.SetFormatter(&log.JSONFormatter{
			CallerPrettyfier: callerPrettyfier,
			PrettyPrint:      false,
		})
		log.SetOutput(&lumberjack.Logger{
			Filename: logFile,
			MaxSize:  100,
			MaxAge:   30,
			Compress: true,
		})
	}
}

func setupDatabase() *sql.DB {
	log.Println("Setting up db")
	db, err := sql.Open("postgres", config.GetPGInfo())

	if err != nil {
		log.Panic(err)
		panic(err)
	}
	log.Println("Connected to DB")
	err = db.Ping()
	if err != nil {
		panic(err)
	}
	log.Println("Pinged DB")

	driver, _ := postgres.WithInstance(db, &postgres.Config{})
	m, err := migrate.NewWithDatabaseInstance(
		"file://migrations", "postgres", driver)
	if err != nil {
		log.Panic(err)
		panic(err)
	}
	log.Println("Loaded migration scripts")
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		log.Panic(err)
		panic(err)
	}

	db.SetMaxIdleConns(30)
	db.SetMaxOpenConns(60)
	db.SetConnMaxLifetime(30 * time.Minute)
	db.SetConnMaxIdleTime(10 * time.Minute)

	log.Println("Database was configured successfully.")

	return db
}

func setupLatencySensitiveDatabase() *sql.DB {
	log.Println("Setting up latency sensitive db")
	db, err := sql.Open("postgres", config.GetPGInfo())

	if err != nil {
		log.Panic(err)
		panic(err)
	}
	log.Println("Connected to latency sensitive DB")
	err = db.Ping()
	if err != nil {
		panic(err)
	}
	log.Println("Pinged latency sensitive DB")

	db.SetMaxIdleConns(50)
	db.SetMaxOpenConns(100)
	db.SetConnMaxLifetime(30 * time.Minute)
	db.SetConnMaxIdleTime(10 * time.Minute)

	log.Println("Latency sensitive database was configured successfully.")

	return db
}

func setupAndStartBackgroundJobs(
	objectCleanupController *controller.ObjectCleanupController,
	replicationController3 *controller.ReplicationController3,
	fileDataCtrl *filedata.Controller,
	contactController *contactCtrl.Controller,
) {
	isReplicationEnabled := viper.GetBool("replication.enabled")
	if isReplicationEnabled {
		err := replicationController3.StartReplication()
		if err != nil {
			log.Warnf("Could not start replication v3: %s", err)
		}
		err = fileDataCtrl.StartReplication()
		if err != nil {
			log.Warnf("Could not start fileData replication: %s", err)
		}
		err = contactController.StartReplication()
		if err != nil {
			log.Warnf("Could not start contact attachment replication: %s", err)
		}
	} else {
		log.Info("Skipping Replication as replication is disabled")
	}

	if viper.GetBool("jobs.cron.skip") {
		log.Info("Skipping background cleanup jobs")
		return
	}

	fileDataCtrl.StartDataDeletion() // Start data deletion for file data;
	contactController.StartDataDeletion()
	objectCleanupController.StartRemovingUnreportedObjects()
}

func setupAndStartCrons(userAuthRepo *repo.UserAuthRepository, collectionLinkRepo *public.CollectionLinkRepo,
	fileLinkRepo *public.FileLinkRepository,
	pasteRepo *public.PasteRepository,
	twoFactorRepo *repo.TwoFactorRepository, passkeysRepo *passkey.Repository, fileController *controller.FileController,
	taskRepo *repo.TaskLockRepository, emailNotificationCtrl *email.EmailNotificationController,
	trashController *controller.TrashController, pushController *controller.PushController,
	objectController *controller.ObjectController,
	dataCleanupCtrl *dataCleanupCtrl.DeleteUserCleanupController,
	storageBonusCtrl *storagebonus.Controller,
	emergencyCtrl *emergency.Controller,
	embeddingCtrl *embeddingCtrl.Controller,
	healthCheckHandler *api.HealthCheckHandler,
	castDb castRepo.Repository,
	inactiveUserOrchestrator *user.InactiveUserOrchestrator) {
	if viper.GetBool("jobs.cron.skip") {
		log.Info("Skipping cron jobs")
		return
	}

	const deletedTokenRetentionDays = 427 // 13-month deletion window (395 days) + 32-day safety buffer

	c := cron.New()
	schedule(c, "@every 1m", func() {
		_ = userAuthRepo.RemoveExpiredOTTs()
	})

	schedule(c, "@every 24h", func() {
		_ = userAuthRepo.RemoveDeletedTokens(timeUtil.MicrosecondsBeforeDays(deletedTokenRetentionDays))
		_ = castDb.DeleteOldSessions(context.Background(), timeUtil.MicrosecondsBeforeDays(7))
		_ = collectionLinkRepo.CleanupAccessHistory(context.Background())
		_ = fileLinkRepo.CleanupAccessHistory(context.Background())
	})

	schedule(c, "@every 30m", func() {
		_ = pasteRepo.CleanupExpired(context.Background())
	})

	schedule(c, "@every 1m", func() {
		_ = twoFactorRepo.RemoveExpiredTwoFactorSessions()
		// Clean up used OTP codes older than 90 seconds
		_ = twoFactorRepo.RemoveExpiredUsedOTPCodes(90 * 1000 * 1000) // 90 seconds in microseconds
	})
	schedule(c, "@every 1m", func() {
		_ = twoFactorRepo.RemoveExpiredTempTwoFactorSecrets()
	})

	schedule(c, "@every 1m", func() {
		_ = passkeysRepo.RemoveExpiredPasskeySessions()
	})
	schedule(c, "@every 1m", func() {
		healthCheckHandler.PerformHealthCheck()
	})

	scheduleAndRun(c, "@every 60m", func() {
		emergencyCtrl.SendRecoveryReminder()
		err := taskRepo.CleanupExpiredLocks()
		if err != nil {
			log.Printf("Error while cleaning up lock table, %s", err)
		}
	})

	schedule(c, "@every 8m", func() {
		fileController.CleanupDeletedFiles()
	})
	schedule(c, "@every 13m", func() {
		fileController.CleanupOutdatedObjects()
	})
	schedule(c, "@every 101s", func() {
		embeddingCtrl.CleanupDeletedEmbeddings()
	})

	schedule(c, "@every 17m", func() {
		trashController.DropFileMetadataCron()
	})

	schedule(c, "@every 90s", func() {
		objectController.RemoveComplianceHolds()
	})

	schedule(c, "@every 1m", func() {
		trashController.CleanupTrashedCollections()
	})

	// 101s to avoid running too many cron at same time
	schedule(c, "@every 101s", func() {
		trashController.DeleteAgedTrashedFiles()
	})

	schedule(c, "@every 63s", func() {
		storageBonusCtrl.PaymentUpgradeOrDowngradeCron()
	})

	// 67s to avoid running too many cron at same time
	schedule(c, "@every 67s", func() {
		trashController.ProcessEmptyTrashRequests()
	})

	schedule(c, "@every 45m", func() {
		// delete unclaimed codes older than 60 minutes
		_ = castDb.DeleteUnclaimedCodes(context.Background(), timeUtil.MicrosecondsBeforeMinutes(60))
		dataCleanupCtrl.DeleteDataCron()
	})

	schedule(c, "@every 24h", func() {
		emailNotificationCtrl.SendStorageLimitExceededMails()
	})

	scheduleAndRun(c, "@every 24h", func() {
		emailNotificationCtrl.SayHelloToCustomers()
	})

	scheduleAndRun(c, "@every 24h", func() {
		emailNotificationCtrl.NudgePaidSubscriberForFamily()
		deleted, err := userAuthRepo.CleanupOldFakeSessions(context.Background())
		if err != nil {
			log.WithError(err).Error("Failed to cleanup old fake SRP sessions")
		} else if deleted > 0 {
			log.WithField("count", deleted).Info("Cleaned up old fake SRP sessions")
		}
	})

	scheduleAndRun(c, "@every 24h", func() {
		inactiveUserOrchestrator.ProcessInactiveUsers()
	})

	scheduleAndRun(c, "@every 24h", func() {
		emailNotificationCtrl.SendStorageWarningMails()
	})

	schedule(c, "@every 1m", func() {
		pushController.SendPushes()
	})

	schedule(c, "@every 24h", func() {
		pushController.ClearExpiredTokens()
	})

	c.Start()
}

func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", c.GetHeader("Origin"))
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, X-Auth-Token, X-Auth-Access-Token, X-Cast-Access-Token, X-Auth-Access-Token-JWT, X-Auth-Link-Device-Token, X-Client-Package, X-Client-Version, X-Paste-Consume, Authorization, accept, origin, Cache-Control, X-Requested-With, upgrade-insecure-requests, Range")
		c.Writer.Header().Set("Access-Control-Expose-Headers", "X-Request-Id, X-Ente-Link-Device-Token")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, PATCH, DELETE")
		c.Writer.Header().Set("Access-Control-Max-Age", "1728000")

		if c.Request.Method == http.MethodOptions {
			// While 204 No Content is more appropriate, Safari intermittently
			// (intermittently!) fails CORS if we return 204 instead of 200 OK.
			c.Status(http.StatusOK)
			return
		}
		c.Next()
	}
}

func cacheHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Add "Cache-Control: no-store" to HTTP GET API responses.
		if c.Request.Method == http.MethodGet {
			reqPath := urlSanitizer(c)
			if reqPath == "/files/preview/:fileID" ||
				reqPath == "/files/download/:fileID" ||
				reqPath == "/public-collection/files/preview/:fileID" ||
				reqPath == "/public-collection/files/download/:fileID" ||
				reqPath == "/public-memory/files/preview/:fileID" ||
				reqPath == "/public-memory/files/download/:fileID" ||
				reqPath == "/cast/files/preview/:fileID" ||
				reqPath == "/cast/files/download/:fileID" {
				// Exclude those that redirect to S3 for file downloads.
			} else {
				c.Writer.Header().Set("Cache-Control", "no-store")
			}
		}

		c.Next()
	}
}

var knownAPIs = make(map[string]bool)

func urlSanitizer(c *gin.Context) string {
	if c.Request.Method == http.MethodOptions {
		return "/options"
	}
	u := *c.Request.URL
	u.RawQuery = ""
	uri := u.RequestURI()
	for _, p := range c.Params {
		uri = strings.Replace(uri, p.Value, fmt.Sprintf(":%s", p.Key), 1)
	}
	if !knownAPIs[uri] {
		log.Warn("Unknown API: " + uri)
		return "/unknown-api"
	}
	return uri
}

func timeOutResponse(c *gin.Context) {
	c.JSON(http.StatusRequestTimeout, gin.H{"handler": true})
}

func setKnownAPIs(routes []gin.RouteInfo) {
	for _, route := range routes {
		knownAPIs[route.Path] = true
	}
}

// Schedule a cron job
func schedule(c *cron.Cron, spec string, cmd func()) (cron.EntryID, error) {
	return c.AddFunc(spec, cmd)
}

// Schedule a cron job, and run it once immediately too.
func scheduleAndRun(c *cron.Cron, spec string, cmd func()) (cron.EntryID, error) {
	go cmd()
	return schedule(c, spec, cmd)
}
