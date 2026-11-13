package filedata

import (
	"fmt"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/base"
)

// File data is fully deleted only when no objects remain under this prefix.
func BasePrefix(fileID int64, ownerID int64) string {
	return fmt.Sprintf("%d/file-data/%d/", ownerID, fileID)
}

func AllObjects(fileID int64, ownerID int64, oType ente.ObjectType) []string {
	switch oType {
	case ente.MlData:
		return []string{derivedMetaPath(fileID, ownerID)}

	default:
		panic(fmt.Sprintf("object type %s is not supported", oType))
	}
}

func ObjectKey(fileID int64, ownerID int64, oType ente.ObjectType, id *string) string {
	switch oType {
	case ente.PreviewVideo:
		return fmt.Sprintf("%s%s/%s", BasePrefix(fileID, ownerID), string(oType), *id)
	case ente.PreviewImage:
		return fmt.Sprintf("%s%s/%s", BasePrefix(fileID, ownerID), string(oType), *id)
	default:
		panic(fmt.Sprintf("object type %s is not supported", oType))
	}
}

func ObjectMetadataKey(fileID int64, ownerID int64, oType ente.ObjectType, id *string) string {
	switch oType {
	case ente.PreviewVideo:
		return fmt.Sprintf("%s_playlist", ObjectKey(fileID, ownerID, oType, id))
	case ente.MlData:
		return fmt.Sprintf("%s%s", BasePrefix(fileID, ownerID), string(oType))
	default:
		panic(fmt.Sprintf("ObjectMetadata not supported for type %s", string(oType)))
	}
}

func DeletePrefix(fileID int64, ownerID int64, oType ente.ObjectType) string {
	return fmt.Sprintf("%s%s/", BasePrefix(fileID, ownerID), string(oType))
}

func NewUploadID(oType ente.ObjectType) string {
	if oType == ente.PreviewVideo {
		return base.MustNewID("pv")
	} else if oType == ente.PreviewImage {
		return base.MustNewID("pi")
	}
	panic(fmt.Sprintf("object type %s is not supported", oType))
}

func derivedMetaPath(fileID int64, ownerID int64) string {
	return fmt.Sprintf("%s%s", BasePrefix(fileID, ownerID), string(ente.MlData))
}
