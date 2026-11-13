package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/space/controller"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestCommentAPIRejectsUnsafeIDsBeforeStorage(t *testing.T) {
	handlers := &Handlers{Module: &controller.Module{Comments: &controller.CommentsController{}}}
	router := gin.New()
	router.POST("/discussions/:postID/comments", func(c *gin.Context) {
		handlers.CreateComment(c, &repo.SpaceRecord{SpaceID: "owner"})
	})
	for _, id := range []string{
		"../../../posts/42", `..\..\..\posts\42`, ".", "..",
		"%2e%2e%2fposts%2f42", "%252e%252e%252fposts%252f42",
		"comment/child", "comment?query=1", "comment#fragment",
		" comment", "comment ", "comment\n", "comment\x00", "cömment", strings.Repeat("a", 65),
	} {
		for _, field := range []string{"commentId", "replyToId"} {
			t.Run(field+"/"+id, func(t *testing.T) {
				body := map[string]string{"commentId": "comment-1", "cipher": "YWJj"}
				body[field] = id
				encoded, err := json.Marshal(body)
				require.NoError(t, err)
				request := httptest.NewRequest(http.MethodPost, "/discussions/42/comments", bytes.NewReader(encoded))
				request.Header.Set("Content-Type", "application/json")
				response := httptest.NewRecorder()
				router.ServeHTTP(response, request)
				require.Equal(t, http.StatusBadRequest, response.Code, response.Body.String())
			})
		}
	}
	t.Run("missing-comment-id", func(t *testing.T) {
		body, err := json.Marshal(models.CreateCommentRequest{Cipher: "YWJj"})
		require.NoError(t, err)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/discussions/42/comments", bytes.NewReader(body)))
		require.Equal(t, http.StatusBadRequest, response.Code)
	})
}
