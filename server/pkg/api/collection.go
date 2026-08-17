package api

import (
	"github.com/ente/museum/pkg/controller/collections"
	"net/http"
	"strconv"

	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
)

type CollectionHandler struct {
	Controller *collections.CollectionController
}

func (h *CollectionHandler) Create(c *gin.Context) {
	log.Info("Collection create")
	var collection ente.Collection
	if err := handler.BindJSON(c, &collection); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Could not bind request params"))
		return
	}

	collection.App = string(auth.GetApp(c))
	collection.UpdationTime = time.Microseconds()
	collection, err := h.Controller.Create(collection,
		auth.GetUserID(c.Request.Header))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Could not create collection"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"collection": collection,
	})
}

func (h *CollectionHandler) GetCollectionByID(c *gin.Context) {
	cID, err := strconv.ParseInt(c.Param("collectionID"), 10, 64)
	if err != nil {
		handler.Error(c, ente.ErrBadRequest)
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	collection, err := h.Controller.GetCollection(c, userID, cID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"collection": collection,
	})
}

// Deprecated: Remove once rps goes to 0.
func (h *CollectionHandler) Get(c *gin.Context) {
	h.GetV2(c)
}

func (h *CollectionHandler) GetV2(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	sinceTime, _ := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	app := auth.GetApp(c)
	ownedCollections, err := h.Controller.GetOwnedV2(userID, sinceTime, app, nil)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to get owned collections"))
		return
	}
	sharedCollections, err := h.Controller.GetSharedWith(userID, sinceTime, app, nil)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to get shared collections"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"collections": append(ownedCollections, sharedCollections...),
	})
}

func (h *CollectionHandler) GetWithLimit(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	sinceTime, _ := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	sharedSinceTime, _ := strconv.ParseInt(c.Query("sharedSinceTime"), 10, 64)
	limit := int64(1000)
	if c.Query("limit") != "" {
		limit, _ = strconv.ParseInt(c.Query("limit"), 10, 64)
		if limit > 1000 {
			limit = 1000
		}
	}
	app := auth.GetApp(c)
	ownedCollections, err := h.Controller.GetOwnedV2(userID, sinceTime, app, &limit)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to get owned collections"))
		return
	}
	sharedCollections, err := h.Controller.GetSharedWith(userID, sharedSinceTime, app, &limit)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to get shared collections"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"owned":  ownedCollections,
		"shared": sharedCollections,
	})
}

func (h *CollectionHandler) Share(c *gin.Context) {
	var request ente.AlterShareRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	resp, err := h.Controller.Share(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"sharees": resp,
	})
}

func (h *CollectionHandler) BulkShare(c *gin.Context) {
	var request ente.BulkCollectionShareRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	results, err := h.Controller.BulkShare(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"results": results})
}

func (h *CollectionHandler) JoinLink(c *gin.Context) {
	var request ente.JoinCollectionViaLinkRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.Controller.JoinViaLink(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *CollectionHandler) ShareURL(c *gin.Context) {
	var request ente.CreatePublicAccessTokenRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	response, err := h.Controller.ShareURL(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"result": response,
	})
}

func (h *CollectionHandler) UpdateShareURL(c *gin.Context) {
	var req ente.UpdatePublicAccessTokenRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	response, err := h.Controller.UpdateShareURL(c, auth.GetUserID(c.Request.Header), req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"result": response,
	})
}

func (h *CollectionHandler) UnShareURL(c *gin.Context) {
	cID, err := strconv.ParseInt(c.Param("collectionID"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, ""))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	err = h.Controller.DisableSharedURL(c, userID, cID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) UnShare(c *gin.Context) {
	var request ente.AlterShareRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	resp, err := h.Controller.UnShare(c, request.CollectionID, auth.GetUserID(c.Request.Header), request.Email)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"sharees": resp,
	})
}

func (h *CollectionHandler) BulkUnShare(c *gin.Context) {
	var request ente.BulkCollectionUnshareRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	results, err := h.Controller.BulkUnShare(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"results": results})
}

func (h *CollectionHandler) Leave(c *gin.Context) {
	cID, err := strconv.ParseInt(c.Param("collectionID"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, ""))
		return
	}
	err = h.Controller.Leave(c, cID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) AddFiles(c *gin.Context) {
	var request ente.AddFilesRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if len(request.Files) > DefaultMaxBatchSize {
		handler.Error(c, stacktrace.Propagate(ente.ErrBatchSizeTooLarge, ""))
		return
	}

	if err := h.Controller.AddFiles(c, auth.GetUserID(c.Request.Header), request.Files, request.CollectionID); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) RestoreFiles(c *gin.Context) {
	var request ente.AddFilesRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	if len(request.Files) > DefaultMaxBatchSize {
		handler.Error(c, stacktrace.Propagate(ente.ErrBatchSizeTooLarge, ""))
		return
	}

	if err := h.Controller.RestoreFiles(c, auth.GetUserID(c.Request.Header), request.CollectionID, request.Files); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) MoveFiles(c *gin.Context) {
	var request ente.MoveFilesRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	if len(request.Files) > DefaultMaxBatchSize {
		handler.Error(c, stacktrace.Propagate(ente.ErrBatchSizeTooLarge, ""))
		return
	}
	if request.ToCollectionID == request.FromCollectionID {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "to and fromCollection should be different"))
		return
	}

	if err := h.Controller.MoveFiles(c, request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) RemoveFilesV3(c *gin.Context) {
	var request ente.RemoveFilesV3Request
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if len(request.FileIDs) > DefaultMaxBatchSize {
		handler.Error(c, stacktrace.Propagate(ente.ErrBatchSizeTooLarge, ""))
		return
	}
	actorUserID := auth.GetUserID(c.Request.Header)
	if err := h.Controller.RemoveFilesV3(c, actorUserID, request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) SuggestDeleteInSharedCollection(c *gin.Context) {
	var request ente.SuggestDeleteRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if len(request.FileIDs) > DefaultMaxBatchSize {
		handler.Error(c, stacktrace.Propagate(ente.ErrBatchSizeTooLarge, ""))
		return
	}
	if err := h.Controller.SuggestDeleteInSharedCollection(c, request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) GetDiffV2(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	cID, _ := strconv.ParseInt(c.Query("collectionID"), 10, 64)
	sinceTime, _ := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	files, hasMore, err := h.Controller.GetDiffV2(c, cID, userID, sinceTime)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"diff":    files,
		"hasMore": hasMore,
	})
}

func (h *CollectionHandler) GetFile(c *gin.Context) {
	cID, _ := strconv.ParseInt(c.Query("collectionID"), 10, 64)
	fileID, _ := strconv.ParseInt(c.Query("fileID"), 10, 64)
	file, err := h.Controller.GetFile(c, cID, fileID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"file": file,
	})
}

func (h *CollectionHandler) GetSharees(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	cID, _ := strconv.ParseInt(c.Query("collectionID"), 10, 64)
	sharees, err := h.Controller.GetSharees(c, cID, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"sharees": sharees,
	})
}

func (h *CollectionHandler) TrashV3(c *gin.Context) {
	var req ente.TrashCollectionV3Request
	if err := c.ShouldBindQuery(&req); err != nil {
		handler.Error(c,
			stacktrace.Propagate(ente.ErrBadRequest, "Request binding failed %s", err))
		return
	}

	err := h.Controller.TrashV3(c, req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) Rename(c *gin.Context) {
	var request ente.RenameRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if err := h.Controller.Rename(auth.GetUserID(c.Request.Header), request.CollectionID, request.EncryptedName, request.NameDecryptionNonce); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) PrivateMagicMetadataUpdate(c *gin.Context) {
	var request ente.UpdateCollectionMagicMetadata
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if err := h.Controller.UpdateMagicMetadata(c, request, false); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) PublicMagicMetadataUpdate(c *gin.Context) {
	var request ente.UpdateCollectionMagicMetadata
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if err := h.Controller.UpdateMagicMetadata(c, request, true); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *CollectionHandler) ShareeMagicMetadataUpdate(c *gin.Context) {
	var request ente.UpdateCollectionMagicMetadata
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.Controller.UpdateShareeMagicMetadata(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}
