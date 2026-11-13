package user

import (
	"context"
	"database/sql"
	"encoding/base64"
	"errors"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/controller/family"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/cast"
	publicrepo "github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	timeutil "github.com/ente/museum/pkg/utils/time"
	spacecontroller "github.com/ente/museum/space/controller"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/require"
)

type spaceAccessResetterWithCallback struct {
	*spacerepo.Module
	afterReset func()
}

func (r *spaceAccessResetterWithCallback) ResetUserAccess(ctx context.Context, userID int64) error {
	if err := r.Module.ResetUserAccess(ctx, userID); err != nil {
		return err
	}
	r.afterReset()
	return nil
}

func (r *spaceAccessResetterWithCallback) ResetAccountDeletionAccess(ctx context.Context, userID int64) error {
	if err := r.Module.ResetAccountDeletionAccess(ctx, userID); err != nil {
		return err
	}
	r.afterReset()
	return nil
}

func TestResetUserAccessRevokesSpaceSessionCreatedDuringReset(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	gin.SetMode(gin.TestMode)

	for _, accountDeletion := range []bool{false, true} {
		name := "access reset"
		if accountDeletion {
			name = "account deletion"
		}
		t.Run(name, func(t *testing.T) {
			testutil.ResetTables(t, db)
			t.Cleanup(func() { testutil.ResetTables(t, db) })
			userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "space-reset@example.com", CreationTime: 1})
			userAuthRepo := &repo.UserAuthRepository{DB: db}
			photosToken := "space-reset-photos-token"
			remainingToken := "space-reset-remaining-token"
			for _, token := range []string{photosToken, remainingToken} {
				require.NoError(t, userAuthRepo.AddToken(userID, ente.Photos, token, "127.0.0.1", "test"))
			}
			spaceRepos := spacerepo.NewModule(db, nil)
			sessions := &spacecontroller.SessionsController{SessionsRepo: spaceRepos.Sessions}
			ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
			ctx.Request = httptest.NewRequest("POST", "/account/space/sessions", nil)
			wrapKey := base64.StdEncoding.EncodeToString(make([]byte, 32))
			existingHash := auth.HashToken("existing-space-session")
			require.NoError(t, spaceRepos.Sessions.CreateBrowserSession(ctx, existingHash[:], userID, wrapKey, timeutil.NDaysFromNow(365)))
			var created *spacecontroller.CreatedBrowserSession
			resetter := &spaceAccessResetterWithCallback{
				Module: spaceRepos,
				afterReset: func() {
					_, err := spaceRepos.Sessions.GetBrowserSession(ctx, existingHash[:])
					require.ErrorIs(t, err, sql.ErrNoRows)
					created, err = sessions.CreateBrowserSession(ctx, userID, photosToken, wrapKey)
					require.NoError(t, err)
					_, err = sessions.ValidateBrowserSession(ctx, created.Response.SessionToken)
					require.NoError(t, err)
				},
			}
			controller := &UserController{
				UserAuthRepo:        userAuthRepo,
				Cache:               cache.New(time.Minute, time.Minute),
				SpaceAccessResetter: resetter,
				CollectionCtrl: &collections.CollectionController{
					CollectionRepo: &repo.CollectionRepository{DB: db},
					CastRepo:       &cast.Repository{DB: db},
					CollectionLinkCtrl: &public.CollectionLinkController{
						CollectionLinkRepo: &publicrepo.CollectionLinkRepo{DB: db},
						FileLinkRepo:       &publicrepo.FileLinkRepository{DB: db},
						MemoryShareRepo:    repo.NewMemoryShareRepository(db),
					},
				},
				FamilyController: &family.Controller{
					UserRepo:   &repo.UserRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey()},
					FamilyRepo: &repo.FamilyRepository{DB: db},
				},
			}

			require.NoError(t, controller.resetUserAccess(ctx, userID, logrus.NewEntry(logrus.New()), accountDeletion))
			require.NotNil(t, created)
			_, err := sessions.ValidateBrowserSession(ctx, created.Response.SessionToken)
			require.ErrorIs(t, err, ente.ErrAuthenticationRequired)
			_, err = sessions.CreateBrowserSession(ctx, userID, remainingToken, wrapKey)
			require.ErrorIs(t, err, ente.ErrAuthenticationRequired)
		})
	}
}

type failingSpaceSessionRevoker struct {
	*spacerepo.Module
	err error
}

func (r *failingSpaceSessionRevoker) RevokeBrowserSessions(context.Context, int64) error {
	return r.err
}

func TestResetUserAccessReturnsSpaceSessionSweepError(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "space-reset-failure@example.com", CreationTime: 1})
	sweepErr := errors.New("space session sweep failed")
	controller := &UserController{
		UserAuthRepo: &repo.UserAuthRepository{DB: db},
		Cache:        cache.New(time.Minute, time.Minute),
		SpaceAccessResetter: &failingSpaceSessionRevoker{
			Module: spacerepo.NewModule(db, nil),
			err:    sweepErr,
		},
	}

	err := controller.ResetUserAccess(context.Background(), userID, logrus.NewEntry(logrus.New()))
	require.ErrorIs(t, err, sweepErr)
}
