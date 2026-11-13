package remotestore

import "testing"

func TestReservedCustomDomainCanonicalization(t *testing.T) {
	if !isReservedCustomDomain("ｍｙ．ｅｎｔｅ．ｃｏｍ", "") {
		t.Error("width-mapped Ente domain was not reserved")
	}
}
