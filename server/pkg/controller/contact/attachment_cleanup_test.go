package contact

import (
	"testing"

	"github.com/ente/museum/ente"
	contactmodel "github.com/ente/museum/ente/contact"
	"github.com/stretchr/testify/require"
)

func TestAttachmentRegistrationCleanupState(t *testing.T) {
	for _, state := range []ente.TempObjectCleanupState{ente.TempObjectUploading, ente.TempObjectReleaseHold, ente.TempObjectDelete} {
		t.Run(string(state), func(t *testing.T) {
			ctrl, db, ctx, _ := setupContactControllerTest(t)
			mustInsertTestUser(t, db, 1)
			created := createContactForTest(t, db, ctrl, ctx, 41, "wrapped-key", "payload")
			upload, err := ctrl.GetAttachmentUploadURL(ctx, string(contactmodel.ProfilePicture), contactmodel.AttachmentUploadURLRequest{
				ContentLength: 128, ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
			})
			require.NoError(t, err)
			_, err = db.Exec(`UPDATE temp_objects SET cleanup_state = NULLIF($1, '')`, state)
			require.NoError(t, err)
			verified := false
			ctrl.verifyAttachmentFn = func(string, string, int64) error {
				verified = true
				return nil
			}
			_, err = ctrl.AttachContactAttachment(ctx, created.ID, string(contactmodel.ProfilePicture), contactmodel.CommitAttachmentRequest{
				AttachmentID: upload.AttachmentID, Size: 128,
			})
			allowed := state == ente.TempObjectUploading
			if allowed {
				require.NoError(t, err)
			} else {
				require.ErrorContains(t, err, "staged attachment upload not found")
				_, err = ctrl.Repo.AttachContactAttachment(ctx, 1, created.ID, contactmodel.ProfilePicture, upload.AttachmentID, 128)
				require.ErrorContains(t, err, "staged attachment upload not found")
			}
			require.Equal(t, allowed, verified)
			stored, err := ctrl.Repo.Get(ctx, 1, created.ID)
			require.NoError(t, err)
			require.Equal(t, allowed, stored.ProfilePictureAttachmentID != nil)
			var attached, staged bool
			require.NoError(t, db.QueryRow(`SELECT EXISTS (SELECT 1 FROM user_attachments),
				EXISTS (SELECT 1 FROM temp_objects)`).Scan(&attached, &staged))
			require.Equal(t, allowed, attached)
			require.Equal(t, !allowed, staged)
		})
	}
}
