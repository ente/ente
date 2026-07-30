package s3config

import (
	"fmt"
	"slices"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/ente"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

// S3Config is the file which abstracts away s3 related configs for clients.
//
// Objects are replicated in multiple "data centers". Each data center is an
// S3-compatible provider, and has an associated "bucket".
//
// The list of data centers are not arbitrarily configurable - while we pick the
// exact credentials, endpoint and the bucket from the runtime configuration
// file, the code has specific logic to deal with the quirks of specific data
// centers. So as such, the constants used to specify these data centers in the
// YAML configuration matter.
type S3Config struct {
	// A map from data centers to the name of the bucket used in that DC.
	buckets map[string]string
	// Primary (hot) data center
	hotDC string
	// Secondary (hot) data center
	secondaryHotDC string
	//Derived data data center for derived files like ml embeddings & preview files
	derivedStorageDC string
	// A map from data centers to S3 configurations
	s3Configs map[string]*aws.Config
	// A map from data centers to pre-created S3 clients
	s3Clients map[string]s3.S3
	// Indicates if compliance is enabled for the Wasabi DC.
	isWasabiComplianceEnabled bool
	// Indicates if local minio buckets are being used. Enables various
	// debugging workarounds; not tested/intended for production.
	areLocalBuckets bool

	// FileDataConfig is the configuration for various file data.
	// If for particular object type, the bucket is not specified, it will
	// default to hotDC as the bucket with no replicas. Initially, this config won't support
	// existing objectType (file, thumbnail) and will be used for new objectTypes. In the future,
	// we can migrate existing objectTypes to this config.
	fileDataConfig FileDataConfig
	// attachmentConfig is the configuration for contact and future user attachments.
	// If no explicit config is present, attachments default to hot storage with no replicas.
	attachmentConfig AttachmentConfig
}

// # Datacenters
// Note: We are now renaming datacenter names to bucketID. Till the migration is completed, you will see usage of both
// terminology.
// Below are some high level details about the three replicas ("data centers")
// that are in use. There are a few other legacy ones too.
//
// # Backblaze (dcB2EuropeCentral)
//
//   - Primary hot storage
//   - Versioned, but with extra code that undoes all overwrites
//
// # Wasabi (dcWasabiEuropeCentral_v3)
//
//   - Secondary hot storage
//   - Objects stay under compliance, which prevents them from being
//     deleted/updated for 21 days.
//   - Not versioned (versioning is not needed since objects cannot be overwritten)
//   - When an user (permanently) deletes an object, we remove the compliance
//     retention. It can then be deleted normally when the scheduled
//     cleanup happens (as long as it happens after 21 days).
//
// # Scaleway (dcSCWEuropeFrance_v3)
//
//   - Cold storage
//   - Specify type GLACIER in API requests

var (
	dcB2EuropeCentral                 string = "b2-eu-cen"
	dcSCWEuropeFranceDeprecated       string = "scw-eu-fr"
	dcSCWEuropeFranceLockedDeprecated string = "scw-eu-fr-locked"
	dcWasabiEuropeCentralDeprecated   string = "wasabi-eu-central-2"
	dcWasabiEuropeCentral_v3          string = "wasabi-eu-central-2-v3"
	dcSCWEuropeFrance_v3              string = "scw-eu-fr-v3"
	dcWasabiEuropeCentralDerived      string = "wasabi-eu-central-2-derived"
	spaceBucket1                      string = "space-b1"
	bucket5                           string = "b5"
	bucket6                           string = "b6"
)

// Number of days that the wasabi bucket is configured to retain objects.
// We must wait at least these many days after removing the conditional hold
// before we can delete the object.
const WasabiObjectConditionalHoldDays = 21

func NewS3Config() *S3Config {
	s3Config := new(S3Config)
	s3Config.initialize()
	return s3Config
}

func (config *S3Config) initialize() {
	dcs := []string{
		dcB2EuropeCentral, dcSCWEuropeFranceLockedDeprecated, dcWasabiEuropeCentralDeprecated,
		dcWasabiEuropeCentral_v3, dcSCWEuropeFrance_v3, dcWasabiEuropeCentralDerived, spaceBucket1, bucket5, bucket6}

	config.hotDC = dcB2EuropeCentral
	config.secondaryHotDC = dcWasabiEuropeCentral_v3
	hs1 := viper.GetString("s3.hot_storage.primary")
	hs2 := viper.GetString("s3.hot_storage.secondary")
	if hs1 != "" && hs2 != "" && slices.Contains(dcs, hs1) && slices.Contains(dcs, hs2) {
		config.hotDC = hs1
		config.secondaryHotDC = hs2
		log.Infof("Hot storage: %s (secondary: %s)", hs1, hs2)
	}
	config.derivedStorageDC = config.hotDC
	embeddingsDC := viper.GetString("s3.derived-storage")
	if embeddingsDC != "" && slices.Contains(dcs, embeddingsDC) {
		config.derivedStorageDC = embeddingsDC
		log.Infof("Embeddings bucket: %s", embeddingsDC)
	}

	config.buckets = make(map[string]string)
	config.s3Configs = make(map[string]*aws.Config)
	config.s3Clients = make(map[string]s3.S3)

	usePathStyleURLs := viper.GetBool("s3.use_path_style_urls")
	areLocalBuckets := viper.GetBool("s3.are_local_buckets")
	config.areLocalBuckets = areLocalBuckets

	for _, dc := range dcs {
		config.buckets[dc] = viper.GetString("s3." + dc + ".bucket")
		s3Config := aws.Config{
			Credentials: credentials.NewStaticCredentials(viper.GetString("s3."+dc+".key"),
				viper.GetString("s3."+dc+".secret"), ""),
			Endpoint: aws.String(viper.GetString("s3." + dc + ".endpoint")),
			Region:   aws.String(viper.GetString("s3." + dc + ".region")),
		}
		if usePathStyleURLs || viper.GetBool("s3."+dc+".use_path_style_urls") || areLocalBuckets {
			s3Config.S3ForcePathStyle = aws.Bool(true)
		}
		if areLocalBuckets || viper.GetBool("s3."+dc+".disable_ssl") {
			s3Config.DisableSSL = aws.Bool(true)
		}
		s3Session, err := session.NewSession(&s3Config)
		if err != nil {
			log.Fatal("Could not create session for " + dc)
		}
		s3Client := *s3.New(s3Session)
		config.s3Configs[dc] = &s3Config
		config.s3Clients[dc] = s3Client
		if dc == dcWasabiEuropeCentral_v3 {
			config.isWasabiComplianceEnabled = viper.GetBool("s3." + dc + ".compliance")
		}
	}

	if err := viper.Sub("s3").Unmarshal(&config.fileDataConfig); err != nil {
		log.Fatalf("Unable to decode into struct: %v\n", err)
		return
	}
	if err := viper.Sub("s3").Unmarshal(&config.attachmentConfig); err != nil {
		log.Fatalf("Unable to decode into struct: %v\n", err)
		return
	}

}

func (config *S3Config) GetBucket(dcOrBucketID string) *string {
	bucket := config.buckets[dcOrBucketID]
	return &bucket
}

// GetBucketID returns the bucket ID for the given object type. Note: existing dc are renamed as bucketID
func (config *S3Config) GetBucketID(oType ente.ObjectType) string {
	if config.fileDataConfig.HasConfig(oType) {
		return config.fileDataConfig.GetPrimaryBucketID(oType)
	}
	if oType == ente.MlData || oType == ente.PreviewVideo || oType == ente.PreviewImage {
		return config.derivedStorageDC
	}
	panic(fmt.Sprintf("ops not supported for type: %s", oType))
}
func (config *S3Config) GetReplicatedBuckets(oType ente.ObjectType) []string {
	if config.fileDataConfig.HasConfig(oType) {
		return config.fileDataConfig.GetReplicaBuckets(oType)
	}
	if oType == ente.MlData || oType == ente.PreviewVideo || oType == ente.PreviewImage {
		return []string{}
	}
	panic(fmt.Sprintf("ops not supported for object type: %s", oType))
}

func (config *S3Config) GetAttachmentBucketID(attachmentType string) string {
	if config.attachmentConfig.HasConfig(attachmentType) {
		return config.attachmentConfig.GetPrimaryBucketID(attachmentType)
	}
	return config.hotDC
}

func (config *S3Config) GetReplicatedAttachmentBuckets(attachmentType string) []string {
	if config.attachmentConfig.HasConfig(attachmentType) {
		return config.attachmentConfig.GetReplicaBuckets(attachmentType)
	}
	return []string{}
}

func (config *S3Config) IsBucketActive(bucketID string) bool {
	return config.buckets[bucketID] != ""
}

func (config *S3Config) GetS3Config(dcOrBucketID string) *aws.Config {
	return config.s3Configs[dcOrBucketID]
}

func (config *S3Config) GetS3Client(dcOrBucketID string) s3.S3 {
	return config.s3Clients[dcOrBucketID]
}

func (config *S3Config) GetHotDataCenter() string {
	return config.hotDC
}

func (config *S3Config) GetSecondaryHotDataCenter() string {
	return config.secondaryHotDC
}

func (config *S3Config) GetHotBucket() *string {
	return config.GetBucket(config.hotDC)
}

func (config *S3Config) GetHotS3Config() *aws.Config {
	return config.GetS3Config(config.hotDC)
}

func (config *S3Config) GetHotS3Client() *s3.S3 {
	s3Client := config.GetS3Client(config.hotDC)
	return &s3Client
}

func (config *S3Config) GetDerivedStorageDataCenter() string {
	return config.derivedStorageDC
}
func (config *S3Config) GetDerivedStorageBucket() *string {
	return config.GetBucket(config.derivedStorageDC)
}

func (config *S3Config) GetDerivedStorageS3Client() *s3.S3 {
	s3Client := config.GetS3Client(config.derivedStorageDC)
	return &s3Client
}

// Return the name of the hot Backblaze data center
func (config *S3Config) GetHotBackblazeDC() string {
	return dcB2EuropeCentral
}

// Return the name of the hot Wasabi data center
func (config *S3Config) GetHotWasabiDC() string {
	return dcWasabiEuropeCentral_v3
}

func (config *S3Config) GetWasabiDerivedDC() string {
	return dcWasabiEuropeCentralDerived
}

// Return the name of the cold Scaleway data center
func (config *S3Config) GetColdScalewayDC() string {
	return dcSCWEuropeFrance_v3
}

// ShouldDeleteFromDataCenter returns true if objects should be deleted from the
// given data center when permanently deleting these objects.
//
// There are some legacy / deprecated data center values which are no longer
// being used, and it returns false for such data centers.
func (config *S3Config) ShouldDeleteFromDataCenter(dc string) bool {
	return dc != dcSCWEuropeFranceDeprecated && dc != dcSCWEuropeFranceLockedDeprecated && dc != dcWasabiEuropeCentralDeprecated
}

// Return the name of the Wasabi DC if objects in that DC are kept under the
// Wasabi compliance lock. Otherwise return the empty string.
func (config *S3Config) WasabiComplianceDC() string {
	if config.isWasabiComplianceEnabled {
		return dcWasabiEuropeCentral_v3
	}
	return ""
}

// Return true if we're using local minio buckets. This can then be used to add
// various workarounds for debugging locally; not meant for production use.
func (config *S3Config) AreLocalBuckets() bool {
	return config.areLocalBuckets
}
