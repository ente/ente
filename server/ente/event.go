package ente

const (
	EventInstall = "install"
	EventSignUp  = "sign_up"
	EventLogIn   = "log_in"
)

type EventRequest struct {
	ID       string                 `json:"id" binding:"required"`
	Event    string                 `json:"event" binding:"required"`
	App      string                 `json:"app" binding:"required"`
	Platform string                 `json:"platform" binding:"required"`
	Data     map[string]interface{} `json:"data" binding:"required"`
}
