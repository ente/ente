package ua

import (
	"errors"

	"github.com/slipros/devicedetector"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

// Returns the type of device based on the user agent.
// Example: Desktop, Mobile, Tablet, TV, etc.
// Returns empty string if the user agent is invalid or the device type is not found, or err is not nil.
func GetDeviceType(ua string) (string, error) {
	dd, dderr := devicedetector.NewDeviceDetector()
	if dderr != nil {
		return "", dderr
	}
	info := dd.Parse(ua)
	if info == nil {
		return "", errors.New("failed to parse user agent")
	}
	if info.Type == "" {
		return "", nil
	}
	titleCaser := cases.Title(language.English)
	return titleCaser.String(info.Type), nil
}
