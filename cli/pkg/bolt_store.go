package pkg

import (
	"context"
	"fmt"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/utils/encoding"
)

func boltAEKey(entry *model.AlbumFileEntry) []byte {
	return fmt.Appendf(nil, "%d:%d", entry.AlbumID, entry.FileID)
}

func (c *ClICtrl) DeleteAlbumEntry(ctx context.Context, entry *model.AlbumFileEntry) error {
	return c.DeleteValue(ctx, model.RemoteAlbumEntries, boltAEKey(entry))
}

func (c *ClICtrl) UpsertAlbumEntry(ctx context.Context, entry *model.AlbumFileEntry) error {
	return c.PutValue(ctx, model.RemoteAlbumEntries, boltAEKey(entry), encoding.MustMarshalJSON(entry))
}
