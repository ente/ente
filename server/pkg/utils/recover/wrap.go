package recover

import (
	"fmt"

	stacktrace "github.com/ente/stacktrace"
)

type Int64ToInt64DataFn func(userID int64) (int64, error)

// Int64ToInt64RecoverWrapper is a helper method to wrap a function of Int64ToInt64DataFn syntax with recover.
// This wrapper helps us in avoiding boilerplate code for panic recovery while invoking the input fn in a new goroutine
func Int64ToInt64RecoverWrapper(
	input int64,
	fn Int64ToInt64DataFn,
	output *int64,
) (err error) {
	defer func() {
		if x := recover(); x != nil {
			// https://stackoverflow.com/questions/33167282/how-to-return-a-value-in-a-go-function-that-panics/33167433#33167433
			// we need to use named params if we want to return panic as err
			err = stacktrace.Propagate(fmt.Errorf("%+v", x), "panic during GoInt64ToInt64Data")
		}
	}()
	resp, err := fn(input)
	if err == nil {
		*output = resp
	}
	return err
}
