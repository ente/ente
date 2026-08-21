package ente

import "testing"

func TestFilterPublicURLsForRole(t *testing.T) {
	viewer := VIEWER
	collaborator := COLLABORATOR

	urls := []PublicURL{
		{URL: "unrestricted"},
		{URL: "viewer-only", MinRole: &viewer},
		{URL: "collaborator-only", MinRole: &collaborator},
	}

	tests := []struct {
		name     string
		role     CollectionParticipantRole
		expected []string
	}{
		{
			name:     "viewer gets unrestricted and viewer urls",
			role:     VIEWER,
			expected: []string{"unrestricted", "viewer-only"},
		},
		{
			name:     "collaborator gets all urls",
			role:     COLLABORATOR,
			expected: []string{"unrestricted", "viewer-only", "collaborator-only"},
		},
		{
			name:     "unknown treated as viewer",
			role:     UNKNOWN,
			expected: []string{"unrestricted", "viewer-only"},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			filtered := FilterPublicURLsForRole(urls, tc.role)
			if len(filtered) != len(tc.expected) {
				t.Fatalf("expected %d urls, got %d", len(tc.expected), len(filtered))
			}
			for i := range filtered {
				if filtered[i].URL != tc.expected[i] {
					t.Fatalf("expected url %s at index %d, got %s", tc.expected[i], i, filtered[i].URL)
				}
			}
		})
	}
}
