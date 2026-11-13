package recover

import (
	"testing"
)

func TestInt64ToInt64RecoverWrapperConvertsPanicToError(t *testing.T) {
	err := Int64ToInt64RecoverWrapper(1, func(int64) (int64, error) {
		panic("panic err")
	}, nil)
	if err == nil {
		t.Fatal("expected panic to become an error")
	}
}
