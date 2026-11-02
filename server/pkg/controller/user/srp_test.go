package user

import (
	"math/big"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/go-srp"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestVerifySRPSessionRejectsAnotherAccountAndEnabledEmailMFA(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	controller := &UserController{
		UserAuthRepo: &repo.UserAuthRepository{DB: db},
		UserRepo: &repo.UserRepository{
			DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey(), HashingKey: testutil.HashingKey(),
			PasskeysRepository: &passkey.Repository{DB: db},
		},
	}
	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest(http.MethodPost, "/users/srp/verify-session", nil)

	params := srp.GetParams(Srp4096Params)
	secret := srp.GenKey()
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "srp-owner@example.com", CreationTime: 1})
	ownerSRPID := uuid.New()
	ownerVerifier := srp.ComputeVerifier(params, []byte("owner-salt"), ownerSRPID[:], []byte("owner-password"))
	ownerClient := srp.NewClient(params, []byte("owner-salt"), ownerSRPID[:], []byte("owner-password"), secret)
	require.NoError(t, controller.UserAuthRepo.InsertSRPAuth(ctx, ownerID, ownerSRPID, convertBytesToString(ownerVerifier), "owner-salt"))
	require.NoError(t, controller.UserAuthRepo.UpdateEmailMFA(ctx, ownerID, false))

	targetID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "srp-target@example.com", CreationTime: 1})
	targetSRPID := uuid.New()
	t.Cleanup(func() {
		_, err := db.Exec(`DELETE FROM srp_sessions WHERE srp_user_id IN ($1, $2)`, ownerSRPID, targetSRPID)
		require.NoError(t, err)
	})
	targetVerifier := srp.ComputeVerifier(params, []byte("target-salt"), targetSRPID[:], []byte("target-password"))
	targetClient := srp.NewClient(params, []byte("target-salt"), targetSRPID[:], []byte("target-password"), secret)
	require.NoError(t, controller.UserAuthRepo.InsertSRPAuth(ctx, targetID, targetSRPID, convertBytesToString(targetVerifier), "target-salt"))
	require.NoError(t, controller.UserAuthRepo.UpdateEmailMFA(ctx, targetID, true))

	_, err := controller.CreateSrpSession(ctx, ente.CreateSRPSessionRequest{
		SRPUserID: targetSRPID, SRPA: convertBytesToString(targetClient.ComputeA()),
	})
	var apiError *ente.ApiError
	require.ErrorAs(t, err, &apiError)
	require.Equal(t, ente.ErrorCode("EMAIL_MFA_ENABLED"), apiError.Code)

	session, err := controller.CreateSrpSession(ctx, ente.CreateSRPSessionRequest{
		SRPUserID: ownerSRPID, SRPA: convertBytesToString(ownerClient.ComputeA()),
	})
	require.NoError(t, err)
	b, err := convertStringToBytes(session.SRPB)
	require.NoError(t, err)
	ownerClient.SetB(b)

	// B_target = B_owner + k * (v_target - v_owner) mod N.
	verifierDifference := new(big.Int).Sub(new(big.Int).SetBytes(targetVerifier), new(big.Int).SetBytes(ownerVerifier))
	targetB := new(big.Int).Mul(targetClient.Multiplier, verifierDifference)
	targetB.Add(targetB, new(big.Int).SetBytes(b)).Mod(targetB, params.N)
	targetClient.SetB(targetB.FillBytes(make([]byte, params.NLengthBits/8)))
	storedSession, err := controller.UserAuthRepo.GetSrpSessionEntity(ctx, session.SessionID)
	require.NoError(t, err)
	serverKey, err := convertStringToBytes(storedSession.ServerKey)
	require.NoError(t, err)
	sessionA, err := convertStringToBytes(storedSession.SRP_A)
	require.NoError(t, err)
	targetServer := srp.NewServer(params, targetVerifier, serverKey)
	require.NotNil(t, targetServer)
	targetServer.SetA(sessionA)
	targetM1 := targetClient.ComputeM1()
	_, err = targetServer.CheckM1(targetM1)
	require.NoError(t, err)
	response, err := controller.VerifySRPSession(ctx, ente.VerifySRPSessionRequest{
		SessionID: session.SessionID, SRPUserID: targetSRPID, SRPM1: convertBytesToString(targetM1),
	})
	require.ErrorIs(t, err, ente.ErrInvalidPassword)
	require.Nil(t, response)
	storedSession, err = controller.UserAuthRepo.GetSrpSessionEntity(ctx, session.SessionID)
	require.NoError(t, err)
	require.False(t, storedSession.IsVerified)
	var tokens int
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM tokens WHERE user_id = $1`, targetID).Scan(&tokens))
	require.Zero(t, tokens)

	response, err = controller.VerifySRPSession(ctx, ente.VerifySRPSessionRequest{
		SessionID: session.SessionID, SRPUserID: ownerSRPID, SRPM1: convertBytesToString(ownerClient.ComputeM1()),
	})
	require.NoError(t, err)
	require.Equal(t, ownerID, response.ID)
	require.NotEmpty(t, response.Token)
	m2, err := convertStringToBytes(*response.SrpM2)
	require.NoError(t, err)
	require.NoError(t, ownerClient.CheckM2(m2))

	session, err = controller.CreateSrpSession(ctx, ente.CreateSRPSessionRequest{
		SRPUserID: ownerSRPID, SRPA: convertBytesToString(ownerClient.ComputeA()),
	})
	require.NoError(t, err)
	b, err = convertStringToBytes(session.SRPB)
	require.NoError(t, err)
	ownerClient.SetB(b)
	require.NoError(t, controller.UserAuthRepo.UpdateEmailMFA(ctx, ownerID, true))
	response, err = controller.VerifySRPSession(ctx, ente.VerifySRPSessionRequest{
		SessionID: session.SessionID, SRPUserID: ownerSRPID, SRPM1: convertBytesToString(ownerClient.ComputeM1()),
	})
	require.ErrorAs(t, err, &apiError)
	require.Equal(t, ente.ErrorCode("EMAIL_MFA_ENABLED"), apiError.Code)
	require.Nil(t, response)
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM tokens WHERE user_id = $1`, ownerID).Scan(&tokens))
	require.Equal(t, 1, tokens)
}

func TestCompleteSRPSetupPreservesSessionBinding(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "srp-setup@example.com", CreationTime: 1})
	controller := &UserController{UserAuthRepo: &repo.UserAuthRepository{DB: db}}
	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest(http.MethodPost, "/users/srp/complete", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	params := srp.GetParams(Srp4096Params)
	srpUserID := uuid.New()
	t.Cleanup(func() {
		_, err := db.Exec(`DELETE FROM srp_sessions WHERE srp_user_id = $1`, srpUserID)
		require.NoError(t, err)
	})
	salt, password := []byte("setup-salt"), []byte("setup-password")
	client := srp.NewClient(params, salt, srpUserID[:], password, srp.GenKey())
	verifier := convertBytesToString(srp.ComputeVerifier(params, salt, srpUserID[:], password))
	setup, err := controller.SetupSRP(ctx, userID, ente.SetupSRPRequest{
		SrpUserID: srpUserID, SRPSalt: convertBytesToString(salt), SRPVerifier: verifier, SRPA: convertBytesToString(client.ComputeA()),
	})
	require.NoError(t, err)
	b, err := convertStringToBytes(setup.SRPB)
	require.NoError(t, err)
	client.SetB(b)
	response, err := controller.CompleteSRPSetup(ctx, ente.CompleteSRPSetupRequest{
		SetupID: setup.SetupID, SRPM1: convertBytesToString(client.ComputeM1()),
	})
	require.NoError(t, err)
	m2, err := convertStringToBytes(response.SRPM2)
	require.NoError(t, err)
	require.NoError(t, client.CheckM2(m2))
	storedAuth, err := controller.UserAuthRepo.GetSRPAuthEntity(ctx, userID)
	require.NoError(t, err)
	require.Equal(t, srpUserID, storedAuth.SRPUserID)
	require.Equal(t, verifier, storedAuth.Verifier)
}
