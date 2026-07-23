package ua

import (
	"sync"
	"testing"
)

func TestGetDeviceType(t *testing.T) {
	deviceType, err := GetDeviceType("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
	if err != nil {
		t.Fatalf("GetDeviceType returned error: %v", err)
	}
	if deviceType != "Smartphone" {
		t.Fatalf("GetDeviceType = %q, want %q", deviceType, "Smartphone")
	}
}

func TestGetDeviceTypeReturnsErrorForUnparsableUserAgent(t *testing.T) {
	deviceType, err := GetDeviceType("")
	if err == nil {
		t.Fatal("GetDeviceType returned nil error")
	}
	if deviceType != "" {
		t.Fatalf("GetDeviceType = %q, want empty string", deviceType)
	}
}

func TestGetDeviceTypeConcurrent(t *testing.T) {
	const userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
	const workers = 16

	var wg sync.WaitGroup
	errs := make(chan string, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			deviceType, err := GetDeviceType(userAgent)
			if err != nil {
				errs <- err.Error()
				return
			}
			if deviceType != "Smartphone" {
				errs <- "unexpected device type"
			}
		}()
	}
	wg.Wait()
	close(errs)

	for err := range errs {
		t.Fatal(err)
	}
}
