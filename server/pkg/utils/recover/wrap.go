package recover

import (
	"fmt"

	stacktrace "github.com/ente/stacktrace"
)

type Int64ToInt64DataFn func(userID int64) (int64, error)

func Int64ToInt64RecoverWrapper(
	input int64,
	fn Int64ToInt64DataFn,
	output *int64,
) (err error) {
	defer func() {
		if x := recover(); x != nil {
			err = stacktrace.Propagate(fmt.Errorf("%+v", x), "panic during GoInt64ToInt64Data")
		}
	}()
	resp, err := fn(input)
	if err == nil {
		*output = resp
	}
	return err
}
