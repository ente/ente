package api

import "github.com/ente/museum/space/controller"

type Handlers struct {
	Module *controller.Module
}

func NewHandlers(module *controller.Module) *Handlers {
	return &Handlers{Module: module}
}
