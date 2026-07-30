package ua

import (
	"errors"
	"sync"

	"github.com/slipros/devicedetector"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

var (
	errFailedToParseUserAgent = errors.New("failed to parse user agent")

	detectorOnce sync.Once
	detectorMu   sync.Mutex
	detector     *devicedetector.DeviceDetector
	detectorErr  error
)

// Returns the type of device based on the user agent.
// Example: Desktop, Mobile, Tablet, TV, etc.
// Returns empty string if the user agent is invalid or the device type is not found, or err is not nil.
func GetDeviceType(userAgent string) (string, error) {
	dd, err := getDetector()
	if err != nil {
		return "", err
	}

	detectorMu.Lock()
	info := dd.Parse(userAgent)
	detectorMu.Unlock()

	if info == nil {
		return "", errFailedToParseUserAgent
	}
	if info.Type == "" {
		return "", nil
	}
	titleCaser := cases.Title(language.English)
	return titleCaser.String(info.Type), nil
}

func getDetector() (*devicedetector.DeviceDetector, error) {
	detectorOnce.Do(func() {
		detector, detectorErr = devicedetector.NewDeviceDetector()
	})
	return detector, detectorErr
}
