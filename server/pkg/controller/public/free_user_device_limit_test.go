package public

import "testing"

func TestIsAllowedFreeUserDeviceLimit(t *testing.T) {
	if FreeUserDeviceLimit != 10 {
		t.Fatalf("free user device limit = %d, want 10", FreeUserDeviceLimit)
	}

	for _, deviceLimit := range []int{FreeUserDeviceLimit, 5} {
		if !IsAllowedFreeUserDeviceLimit(deviceLimit) {
			t.Fatalf("device limit %d should be allowed for free users", deviceLimit)
		}
	}

	for _, deviceLimit := range []int{0, 1, 2, 25, 50} {
		if IsAllowedFreeUserDeviceLimit(deviceLimit) {
			t.Fatalf("device limit %d should not be allowed for free users", deviceLimit)
		}
	}
}
