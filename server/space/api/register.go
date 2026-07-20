package api

import "github.com/gin-gonic/gin"

func Register(privateAPI, publicAPI gin.IRouter, handlers *Handlers) {
	privateAPI.GET("/account/space", handlers.ListSpaces)
	privateAPI.POST("/account/space", handlers.CreateSpace)

	spaceAPI := privateAPI.Group("/spaces/:spaceID", handlers.RequireSelectedSpace())
	selected := handlers.withSelectedSpace
	spaceAPI.POST("/profile", selected(handlers.UpdateSpaceProfile))
	spaceAPI.PUT("/slug", selected(handlers.UpdateSpaceSlug))
	spaceAPI.PATCH("/slug", selected(handlers.UpdateSpaceSlug))
	spaceAPI.POST("/uploads/presign", selected(handlers.PresignUpload))
	spaceAPI.GET("/unread", selected(handlers.GetUnreadStatus))
	spaceAPI.POST("/posts", selected(handlers.CreatePost))
	spaceAPI.GET("/feed", selected(handlers.ListFeed))
	spaceAPI.POST("/posts/:postID/caption", selected(handlers.UpdatePostCaption))
	spaceAPI.PATCH("/posts/:postID/caption", selected(handlers.UpdatePostCaption))
	spaceAPI.PUT("/posts/:postID/like", selected(handlers.LikePost))
	spaceAPI.DELETE("/posts/:postID/like", selected(handlers.UnlikePost))
	spaceAPI.POST("/posts/:postID/reply", selected(handlers.ReplyToPost))
	spaceAPI.DELETE("/posts/:postID", selected(handlers.DeletePost))
	spaceAPI.GET("/conversations", selected(handlers.ListConversations))
	spaceAPI.POST("/friends/:friendSpaceID/read", selected(handlers.MarkNotificationsRead))
	spaceAPI.GET("/friends/:friendSpaceID/messages", selected(handlers.ListMessageThread))
	spaceAPI.POST("/friends/:friendSpaceID/messages", selected(handlers.CreateMessage))
	spaceAPI.PUT("/messages/:messageID/like", selected(handlers.LikeMessage))
	spaceAPI.DELETE("/messages/:messageID/like", selected(handlers.UnlikeMessage))
	spaceAPI.DELETE("/messages/:messageID", selected(handlers.DeleteMessage))
	spaceAPI.POST("/friends/add", selected(handlers.AddFriend))
	spaceAPI.GET("/friends/requests", selected(handlers.ListFriendRequests))
	spaceAPI.POST("/friends/requests/:requestID/confirm", selected(handlers.ConfirmFriendRequest))
	spaceAPI.DELETE("/friends/requests/:requestID", selected(handlers.DeleteFriendRequest))
	spaceAPI.POST("/friends/unfriend", selected(handlers.Unfriend))
	spaceAPI.GET("/friends", selected(handlers.ListSpaceFriends))
	spaceAPI.GET("/friends/relationship", selected(handlers.FriendRelationship))
	spaceAPI.POST("/friends/shares/refresh", selected(handlers.RefreshFriendShares))
	spaceAPI.GET("/friends/shares", selected(handlers.ListFriendShares))

	publicAPI.GET("/spaces/:spaceID/profile", handlers.GetSpaceProfile)
	publicAPI.GET("/spaces/:spaceID/assets/redirect", handlers.AssetRedirect)
	publicAPI.GET("/spaces/:spaceID/posts", handlers.ListPosts)
	publicAPI.GET("/spaces/:spaceID/posts/:postID", handlers.GetPost)
	publicAPI.GET("/spaces/:spaceID/versions", handlers.ListSpaceKeyVersions)
	publicAPI.GET("/space/public/by-slug/:spaceSlug", handlers.LookupSpaceBySlug)
	publicAPI.GET("/space/public/slug-availability/:spaceSlug", handlers.SpaceSlugAvailability)
	publicAPI.POST("/account/space/sessions/bootstrap", handlers.BootstrapBrowserSession)
	publicAPI.DELETE("/account/space/sessions/current", handlers.DeleteBrowserSession)
}

func RegisterTokenSessionRoutes(privateAPI gin.IRoutes, handlers *Handlers) {
	privateAPI.POST("/account/space/sessions", handlers.CreateBrowserSession)
}
