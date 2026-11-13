package s3config

import (
	"sync"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestHotStorageFailover(t *testing.T) {
	for _, primary := range []string{dcB2EuropeCentral, dcWasabiEuropeCentral_v3} {
		t.Run(primary, func(t *testing.T) {
			config := failoverTestConfig(t, primary)
			_, secondary := config.GetHotDataCenters()
			require.True(t, config.CanFailoverHotStorage())
			require.True(t, config.FailoverHotStorage())
			require.False(t, config.FailoverHotStorage())
			require.Equal(t, secondary, config.GetHotDataCenter())
			active, fallback := config.GetHotDataCenters()
			require.Equal(t, secondary, active)
			require.Equal(t, primary, fallback)
			require.Equal(t, primary, config.GetBucketID(ente.PreviewVideo))
			require.Equal(t, primary, config.GetAttachmentBucketID("profile_picture"))
			restarted := NewS3Config()
			require.False(t, restarted.HasHotStorageFailedOver())
			require.Equal(t, primary, restarted.GetHotDataCenter())
		})
	}
}

func TestHotStorageFailoverRequiresConfiguredPair(t *testing.T) {
	for _, dc := range []string{dcB2EuropeCentral, dcWasabiEuropeCentral_v3} {
		for _, field := range []string{"key", "secret", "endpoint", "region", "bucket"} {
			t.Run(dc+"/missing_"+field, func(t *testing.T) {
				failoverTestConfig(t, dcB2EuropeCentral)
				viper.Set("s3."+dc+"."+field, "")
				config := NewS3Config()
				require.False(t, config.CanFailoverHotStorage())
				require.False(t, config.FailoverHotStorage())
				require.Equal(t, dcB2EuropeCentral, config.GetHotDataCenter())
			})
		}
	}
	for _, secondary := range []string{dcB2EuropeCentral, dcSCWEuropeFrance_v3} {
		t.Run(secondary, func(t *testing.T) {
			failoverTestConfig(t, dcB2EuropeCentral)
			viper.Set("s3.hot_storage.secondary", secondary)
			require.False(t, NewS3Config().CanFailoverHotStorage())
		})
	}
}

func TestHotStorageFailoverConcurrentSelection(t *testing.T) {
	config := failoverTestConfig(t, dcB2EuropeCentral)
	var wg sync.WaitGroup
	for range 20 {
		wg.Go(func() {
			for range 100 {
				primary, secondary := config.GetHotDataCenters()
				if primary == secondary {
					t.Errorf("selected the same bucket twice: %s", primary)
				}
				config.FailoverHotStorage()
			}
		})
	}
	wg.Wait()
	require.Equal(t, dcWasabiEuropeCentral_v3, config.GetHotDataCenter())
}

func failoverTestConfig(t *testing.T, primary string) *S3Config {
	t.Helper()
	viper.Reset()
	t.Cleanup(viper.Reset)
	secondary := dcWasabiEuropeCentral_v3
	if primary == secondary {
		secondary = dcB2EuropeCentral
	}
	viper.Set("s3.hot_storage.primary", primary)
	viper.Set("s3.hot_storage.secondary", secondary)
	for _, dc := range []string{primary, secondary} {
		for field, value := range map[string]string{
			"key": "test-key", "secret": "test-secret", "bucket": dc,
			"endpoint": "https://" + dc + ".example.test", "region": "us-east-1",
		} {
			viper.Set("s3."+dc+"."+field, value)
		}
	}
	return NewS3Config()
}
