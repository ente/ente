package controller

import (
	baserepo "github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

type Module struct {
	Spaces     *SpacesController
	Posts      *PostsController
	Friends    *FriendsController
	Messages   *MessagesController
	Assets     *AssetsController
	Read       *ReadMarkersController
	Sessions   *SessionsController
	WebPush    *WebPushController
	Cleanup    *CleanupController
	Links      *LinksController
	UserTokens UserTokenTerminator
	auth       authDeps
}

type UserTokenTerminator interface {
	TerminateSession(userID int64, token string) error
}

func NewModule(
	repos *repo.Module,
	userAuthRepo *baserepo.UserAuthRepository,
	activityNotifier SpaceActivityNotifier,
	webPushConfig *SpaceWebPushConfig,
) *Module {
	authDeps := authDeps{
		UserAuthRepo: userAuthRepo,
		SpacesRepo:   repos.Spaces,
		FriendsRepo:  repos.Friends,
		SessionsRepo: repos.Sessions,
	}
	spaces := &SpacesController{SpacesRepo: repos.Spaces, AssetsRepo: repos.Assets, auth: authDeps}
	posts := &PostsController{PostsRepo: repos.Posts, SpacesRepo: repos.Spaces, AssetsRepo: repos.Assets, ActivityNotifier: activityNotifier, auth: authDeps}
	assets := &AssetsController{AssetsRepo: repos.Assets, SpacesRepo: repos.Spaces, auth: authDeps}
	links := &LinksController{LinksRepo: repos.Links, SpacesRepo: repos.Spaces, FriendsRepo: repos.Friends, Posts: posts, Assets: assets}
	return &Module{
		Spaces:   spaces,
		Posts:    posts,
		Friends:  &FriendsController{FriendsRepo: repos.Friends, SpacesRepo: repos.Spaces, ActivityNotifier: activityNotifier},
		Messages: &MessagesController{MessagesRepo: repos.Messages, PostsRepo: repos.Posts, SpacesRepo: repos.Spaces, FriendsRepo: repos.Friends, ReadMarkersRepo: repos.Read, ActivityNotifier: activityNotifier, auth: authDeps},
		Assets:   assets,
		Read:     &ReadMarkersController{ReadMarkersRepo: repos.Read},
		Sessions: &SessionsController{SessionsRepo: repos.Sessions},
		WebPush:  &WebPushController{webPushRepo: repos.WebPush, links: links, config: webPushConfig},
		Cleanup:  &CleanupController{AssetsRepo: repos.Assets},
		Links:    links,
		auth:     authDeps,
	}
}

func (m *Module) RequireSelectedSpace(c *gin.Context, rawSpaceID string) error {
	space, err := m.auth.requireSelectedSpace(c, rawSpaceID)
	if err != nil {
		return err
	}
	setSelectedSpace(c, space)
	return nil
}

func (m *Module) SelectedSpace(c *gin.Context) (*repo.SpaceRecord, error) {
	return selectedSpace(c)
}
