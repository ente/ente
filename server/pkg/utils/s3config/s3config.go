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

// Bucket IDs are fixed because provider-specific code depends on their exact
// values. Credentials, endpoints, and bucket names remain configurable.
type S3Config struct {
	buckets                   map[string]string
	hotDC                     string
	secondaryHotDC            string
	derivedStorageDC          string
	s3Configs                 map[string]*aws.Config
	s3Clients                 map[string]s3.S3
	isWasabiComplianceEnabled bool
	// Indicates if local minio buckets are being used. Enables various
	// debugging workarounds; not tested/intended for production.
	areLocalBuckets bool

	fileDataConfig   FileDataConfig
	attachmentConfig AttachmentConfig
}

// The primary object-replication path uses three provider-specific roles:
//
// Backblaze is primary hot storage. It is versioned, and the server rolls back
// client overwrites by deleting the newest object version.
//
// Wasabi is secondary hot storage. Compliance prevents overwrites and deletion
// for 21 days. Permanent deletion releases the hold before scheduled cleanup.
//
// Scaleway is cold storage. Replication uploads use the GLACIER storage class.
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

func (config *S3Config) GetHotBackblazeDC() string {
	return dcB2EuropeCentral
}

func (config *S3Config) GetHotWasabiDC() string {
	return dcWasabiEuropeCentral_v3
}

func (config *S3Config) GetWasabiDerivedDC() string {
	return dcWasabiEuropeCentralDerived
}

func (config *S3Config) GetColdScalewayDC() string {
	return dcSCWEuropeFrance_v3
}

func (config *S3Config) ShouldDeleteFromDataCenter(dc string) bool {
	return dc != dcSCWEuropeFranceDeprecated && dc != dcSCWEuropeFranceLockedDeprecated && dc != dcWasabiEuropeCentralDeprecated
}

func (config *S3Config) WasabiComplianceDC() string {
	if config.isWasabiComplianceEnabled {
		return dcWasabiEuropeCentral_v3
	}
	return ""
}

func (config *S3Config) AreLocalBuckets() bool {
	return config.areLocalBuckets
}
