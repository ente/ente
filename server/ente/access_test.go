package ente

import "testing"

func TestCollectionParticipantRoleStringNilSafe(t *testing.T) {
	var nilRole *CollectionParticipantRole
	if got := nilRole.String(); got != "none" {
		t.Fatalf("nilRole.String() = %q, want %q", got, "none")
	}

	admin := ADMIN
	if got := admin.String(); got != "ADMIN" {
		t.Fatalf("admin.String() = %q, want %q", got, "ADMIN")
	}
}
