package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/pkg/middleware"
	"github.com/ente/museum/space/controller"
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/stretchr/testify/require"
)

func TestCreatePostJSONPreservesPayload(t *testing.T) {
	body := `{"encryptedPostKey":"a2V5","keyVersion":1,"unknown":true,"objects":[{"objectKey":"photo","metadataCipher":"bWV0YWRhdGE=","video":{"objectKey":"video","metadataCipher":"dmlkZW8=","unknown":true,"video":{},"video":null}},{"objectKey":"other","metadataCipher":"bWV0YWRhdGE=","position":1,"video":null}]}`
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest(http.MethodPost, "/posts", strings.NewReader(body))
	var req models.CreatePostRequest
	require.NoError(t, c.ShouldBindJSON(&req))
	require.Nil(t, req.Objects[0].Video.NestedVideo)
	encoded, err := json.Marshal(req)
	require.NoError(t, err)
	require.JSONEq(t, `{"encryptedPostKey":"a2V5","keyVersion":1,"objects":[{"objectKey":"photo","metadataCipher":"bWV0YWRhdGE=","video":{"objectKey":"video","metadataCipher":"dmlkZW8="}},{"objectKey":"other","metadataCipher":"bWV0YWRhdGE=","position":1}]}`, string(encoded))
}

func TestCreatePostJSONValidatesVideoSize(t *testing.T) {
	body := `{"encryptedPostKey":"a2V5","keyVersion":1,"objects":[{"objectKey":"photo","metadataCipher":"bWV0YWRhdGE=","video":{"objectKey":"video","metadataCipher":"dmlkZW8=","size":-1}}]}`
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest(http.MethodPost, "/posts", strings.NewReader(body))
	var req models.CreatePostRequest
	var validationErrors validator.ValidationErrors
	require.ErrorAs(t, c.ShouldBindJSON(&req), &validationErrors)
}

func TestCreatePostRejectsNestedVideo(t *testing.T) {
	router := gin.New()
	router.Use(middleware.LimitRequestBody())
	handlers := &Handlers{Module: &controller.Module{Posts: &controller.PostsController{}}}
	router.POST("/spaces/:spaceID/posts", func(c *gin.Context) {
		handlers.CreatePost(c, &spacerepo.SpaceRecord{})
	})
	for _, field := range []string{
		`"video":{}`,
		`"Video":{}`,
		`"\u0076ideo":{}`,
		`"video":` + strings.Repeat(`{"video":`, 9995) + `{}` + strings.Repeat("}", 9995),
	} {
		body := `{"encryptedPostKey":"a2V5","keyVersion":1,"objects":[{"objectKey":"photo","metadataCipher":"bWV0YWRhdGE=","video":{"objectKey":"video","metadataCipher":"dmlkZW8=",` + field + `}}]}`
		c, _ := gin.CreateTestContext(httptest.NewRecorder())
		c.Request = httptest.NewRequest(http.MethodPost, "/spaces/owner/posts", strings.NewReader(body))
		var req models.CreatePostRequest
		require.NoError(t, c.ShouldBindJSON(&req))
		require.NotNil(t, req.Objects[0].Video.NestedVideo)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/spaces/owner/posts", strings.NewReader(body)))
		require.Equal(t, http.StatusBadRequest, response.Code, response.Body.String())
		require.Equal(t, "no-store", response.Header().Get("Cache-Control"))
	}
}

func TestCreatePostValidationBoundsNestedVideoErrors(t *testing.T) {
	body := `{"encryptedPostKey":"a2V5","keyVersion":1,"objects":[` + strings.Repeat(`{"video":`, 1000) + `{}` + strings.Repeat("}", 1000) + `]}`
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest(http.MethodPost, "/posts", strings.NewReader(body))
	var req models.CreatePostRequest
	err := c.ShouldBindJSON(&req)
	var validationErrors validator.ValidationErrors
	require.ErrorAs(t, err, &validationErrors)
	require.Len(t, validationErrors, 4)
}
