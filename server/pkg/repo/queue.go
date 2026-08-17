package repo

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/sirupsen/logrus"
	"strconv"
	"strings"

	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
)

type QueueRepository struct {
	DB *sql.DB
}

// Negative delays make items immediately eligible.
var itemDeletionDelayInMinMap = map[string]int64{
	DropFileEncMedataQueue:    -1 * 24 * 60,
	DeleteObjectQueue:         45 * 24 * 60,
	DeleteEmbeddingsQueue:     -1 * 24 * 60,
	OutdatedObjectsQueue:      -1 * 24 * 60,
	DeleteOutdatedObjectQueue: 24 * 24 * 60, // old replaced objects may exist in compliance-protected replicas
	TrashCollectionQueueV3:    -1 * 24 * 60,
	TrashEmptyQueue:           -1 * 24 * 60,
	TrashEmptyLockerQueue:     -1 * 24 * 60,
	RemoveComplianceHoldQueue: -1 * 24 * 60,
}

const (
	DropFileEncMedataQueue    string = "dropFileEncMetata"
	DeleteObjectQueue         string = "deleteObject"
	DeleteEmbeddingsQueue     string = "deleteEmbedding"
	OutdatedObjectsQueue      string = "outdatedObject"
	DeleteOutdatedObjectQueue string = "deleteOutdatedObject"
	// Deprecated: Keeping it till we clean up items from the queue DB.
	TrashCollectionQueue      string = "trashCollection"
	TrashCollectionQueueV3    string = "trashCollectionV3"
	TrashEmptyQueue           string = "trashEmpty"
	TrashEmptyLockerQueue     string = "trashEmptyLocker"
	RemoveComplianceHoldQueue string = "removeComplianceHold"
	BatchSize                 int    = 30000
)

type QueueItem struct {
	Id   int64
	Item string
}

func (repo *QueueRepository) InsertItem(ctx context.Context, queueName string, item string) error {
	_, err := repo.DB.ExecContext(ctx, `INSERT INTO queue(queue_name, item) VALUES($1, $2)
		ON CONFLICT (queue_name, item) DO NOTHING`, queueName, item)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (repo *QueueRepository) UpdateItem(ctx context.Context, queueName string, queueID int64, item string) error {
	rows, err := repo.DB.ExecContext(ctx, `UPDATE queue SET item = $1 WHERE queue_name = $2 AND queue_id = $3 AND is_deleted=false`, item, queueName, queueID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	count, err := rows.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if count == 0 {
		return fmt.Errorf("no item found with queueID: %d for queue %s", queueID, queueName)
	}
	return nil
}

func (repo *QueueRepository) RequeueItem(ctx context.Context, queueName string, queueID int64) error {
	rows, err := repo.DB.ExecContext(ctx, `UPDATE queue SET is_deleted = false WHERE queue_name = $1 AND queue_id = $2`, queueName, queueID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	count, err := rows.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if count == 0 {
		return fmt.Errorf("no item found with queueID: %d for queue %s", queueID, queueName)
	}
	logrus.Infof("Re-queued %d item with queueID: %d for queue %s", count, queueID, queueName)
	return nil
}

func (repo *QueueRepository) AddItems(ctx context.Context, tx *sql.Tx, queueName string, items []string) error {
	if len(items) == 0 {
		return nil
	}
	lb := 0
	size := len(items)
	for lb < size {
		ub := min(lb+BatchSize, size)
		slicedList := items[lb:ub]
		query := "INSERT INTO queue(queue_name, item) VALUES "
		var inserts []string
		var params []interface{}
		for i, v := range slicedList {
			inserts = append(inserts, `($`+strconv.Itoa(2*i+1)+`,$`+strconv.Itoa(2*i+2)+`)`)
			params = append(params, queueName, v)
		}
		queryVals := strings.Join(inserts, ",")
		query = query + queryVals
		query = query + " ON CONFLICT (queue_name, item) DO NOTHING"
		_, err := tx.ExecContext(ctx, query, params...)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		lb += BatchSize
	}
	return nil
}

func (repo *QueueRepository) DeleteItem(queueName string, item string) error {
	_, err := repo.DB.Exec(`UPDATE queue SET is_deleted = $1 WHERE queue_name = $2 AND item=$3`, true, queueName, item)
	return stacktrace.Propagate(err, "")
}

func (repo *QueueRepository) GetItemsReadyForDeletion(queueName string, count int) ([]QueueItem, error) {
	delayInMin, ok := itemDeletionDelayInMinMap[queueName]
	if !ok {
		return nil, stacktrace.Propagate(fmt.Errorf("missing delay for %s", queueName), "")
	}
	rows, err := repo.DB.Query(`SELECT queue_id, item FROM queue WHERE
                                       queue_name=$1 and created_at <= $2 and is_deleted = false order by created_at ASC LIMIT $3`,
		queueName, time.MicrosecondsBeforeMinutes(delayInMin), count)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	defer rows.Close()
	items := make([]QueueItem, 0)

	for rows.Next() {
		var item QueueItem
		err = rows.Scan(&item.Id, &item.Item)
		if err != nil {
			return items, stacktrace.Propagate(err, "")
		}
		items = append(items, item)
	}
	return items, stacktrace.Propagate(err, "")
}
