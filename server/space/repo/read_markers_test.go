package repo

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestUnreadActivitiesAreScopedAndPaginated(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	alice, bob := notificationTestSpaces(t, module)
	charlieID := insertSpaceUser(t, module, "unread-stranger@example.com", "public")
	charlie, err := testCreateSpace(ctx, module, charlieID, "unread_stranger", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	_, err = module.Read.DB.ExecContext(ctx, `DELETE FROM space_notification_read_markers`)
	require.NoError(t, err)
	for _, item := range []struct {
		id        string
		sender    string
		recipient string
		createdAt int64
		likedAt   any
	}{
		{"incoming-a", bob.SpaceID, alice.SpaceID, 200, nil},
		{"incoming-b", bob.SpaceID, alice.SpaceID, 200, nil},
		{"outgoing-like", alice.SpaceID, bob.SpaceID, 100, int64(300)},
		{"outgoing", alice.SpaceID, bob.SpaceID, 400, nil},
		{"read", bob.SpaceID, alice.SpaceID, 100, nil},
		{"deleted", bob.SpaceID, alice.SpaceID, 400, nil},
		{"stranger", charlie.SpaceID, alice.SpaceID, 400, nil},
		{"other-recipient", bob.SpaceID, charlie.SpaceID, 400, nil},
	} {
		_, err = module.Messages.DB.ExecContext(ctx, `
			INSERT INTO space_messages (message_id, sender_space_id, recipient_space_id, kind,
				message_cipher, sender_encrypted_message_key, recipient_encrypted_message_key, created_at, recipient_liked_at)
			VALUES ($1, $2, $3, 'regular', $4, $5, $6, $7, $8)
		`, item.id, item.sender, item.recipient, []byte(item.id), []byte("sender-key"), []byte("recipient-key"), item.createdAt, item.likedAt)
		require.NoError(t, err)
	}
	_, err = module.Messages.DB.ExecContext(ctx, `UPDATE space_messages SET is_deleted = TRUE WHERE message_id = 'deleted'`)
	require.NoError(t, err)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, alice.SpaceID, bob.SpaceID, 100))
	first, cursor, err := module.Read.ListUnreadActivities(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Len(t, first, 2)
	require.Equal(t, "outgoing-like", first[0].MessageID)
	require.Equal(t, []byte("sender-key"), first[0].EncryptedMessageKey)
	require.Equal(t, "incoming-b", first[1].MessageID)
	require.Equal(t, []byte("recipient-key"), first[1].EncryptedMessageKey)
	require.Equal(t, []byte("incoming-b"), first[1].MessageCipher)
	require.NotEmpty(t, cursor)
	second, next, err := module.Read.ListUnreadActivities(ctx, alice.SpaceID, cursor, 2)
	require.NoError(t, err)
	require.Len(t, second, 1)
	require.Equal(t, "incoming-a", second[0].MessageID)
	require.Empty(t, next)
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, bob.OwnerID)
	require.NoError(t, err)
	hidden, _, err := module.Read.ListUnreadActivities(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Empty(t, hidden)
	require.NoError(t, module.Friends.DeleteFriendship(ctx, alice.SpaceID, bob.SpaceID))
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = '\x00'::bytea WHERE user_id = $1`, bob.OwnerID)
	require.NoError(t, err)
	hidden, _, err = module.Read.ListUnreadActivities(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Empty(t, hidden)
}
