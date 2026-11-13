package ente

type App string

const (
	Photos App = "photos"
	Auth   App = "auth"
	Locker App = "locker"
)

func (a App) IsValid() bool {
	switch a {
	case Photos, Auth, Locker:
		return true
	}
	return false
}

func (a App) IsValidForCollection() bool {
	switch a {
	case Photos, Locker:
		return true
	}
	return false
}
