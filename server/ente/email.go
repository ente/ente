package ente

type SendEmailRequest struct {
	To        []string `json:"to" binding:"required"`
	FromName  string   `json:"fromName" binding:"required"`
	FromEmail string   `json:"fromEmail" binding:"required"`
	Subject   string   `json:"subject" binding:"required"`
	Body      string   `json:"body" binding:"required"`
}
