package s3config

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestHotStorageFailoverRequiresSustainedActivity(t *testing.T) {
	for _, tc := range []struct {
		name     string
		interval time.Duration
		requests int
	}{
		{"brief burst", time.Second, 100},
		{"too few requests", 30 * time.Second, 10},
		{"idle gaps", 31 * time.Second, 30},
	} {
		t.Run(tc.name, func(t *testing.T) {
			config := failoverTestConfig(t, dcB2EuropeCentral)
			start := time.Now()
			for i := range tc.requests {
				config.RecordUploadActivity(start.Add(time.Duration(i) * tc.interval))
			}
			require.False(t, config.HasHotStorageFailedOver())
		})
	}
}

func TestHotStorageFailoverProgressResetsWindow(t *testing.T) {
	config := failoverTestConfig(t, dcB2EuropeCentral)
	start := time.Now()
	for i := range 20 {
		config.RecordUploadActivity(start.Add(time.Duration(i) * 6 * time.Second))
	}
	config.RecordUploadProgress(dcB2EuropeCentral)
	for i := 20; i < 40; i++ {
		config.RecordUploadActivity(start.Add(time.Duration(i) * 6 * time.Second))
		require.False(t, config.HasHotStorageFailedOver())
	}
	config.RecordUploadActivity(start.Add(4 * time.Minute))
	require.True(t, config.HasHotStorageFailedOver())
}
