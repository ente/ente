package ente

type CollectionParticipantRole string

const (
	VIEWER       CollectionParticipantRole = "VIEWER"
	OWNER        CollectionParticipantRole = "OWNER"
	COLLABORATOR CollectionParticipantRole = "COLLABORATOR"
	ADMIN        CollectionParticipantRole = "ADMIN"
	UNKNOWN      CollectionParticipantRole = "UNKNOWN"
)

func (c *CollectionParticipantRole) CanAdd() bool {
	if c == nil {
		return false
	}
	return *c == OWNER || *c == COLLABORATOR || *c == ADMIN
}

func (c *CollectionParticipantRole) CanRemoveAny() bool {
	if c == nil {
		return false
	}
	return *c == OWNER
}

func ConvertStringToCollectionParticipantRole(value string) CollectionParticipantRole {
	switch value {
	case "VIEWER":
		return VIEWER
	case "OWNER":
		return OWNER
	case "COLLABORATOR":
		return COLLABORATOR
	case "ADMIN":
		return ADMIN
	default:
		return UNKNOWN
	}
}

func (c *CollectionParticipantRole) IsValidShareRole() bool {
	if c == nil {
		return false
	}
	return *c == VIEWER || *c == COLLABORATOR || *c == ADMIN || *c == OWNER
}

func (c CollectionParticipantRole) roleRank() int {
	switch c {
	case VIEWER:
		return 1
	case COLLABORATOR:
		return 2
	case ADMIN:
		return 3
	case OWNER:
		return 4
	default:
		return 0
	}
}

func (c CollectionParticipantRole) Satisfies(min *CollectionParticipantRole) bool {
	if min == nil {
		return true
	}
	return c.roleRank() >= (*min).roleRank()
}
