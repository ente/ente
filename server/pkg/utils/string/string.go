package string

func EmptyIfNil(sp *string) string {
	if sp == nil {
		return ""
	}
	return *sp
}
