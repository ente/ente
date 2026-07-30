package repo

import (
	"context"
	"database/sql"
	"encoding/json"

	"github.com/ente/stacktrace"
)

type EventRepository struct {
	DB *sql.DB
}

func (r *EventRepository) Insert(ctx context.Context, id string, event string, app string, platform string, data map[string]interface{}, userID *int64) error {
	payload, err := json.Marshal(data)
	if err != nil {
		return stacktrace.Propagate(err, "failed to marshal event data")
	}
	_, err = r.DB.ExecContext(ctx, `INSERT INTO events(id, event, app, platform, data, user_id)
		VALUES($1, $2, $3, $4, $5, $6)
		ON CONFLICT (id, event) DO NOTHING`, id, event, app, platform, string(payload), userID)
	return stacktrace.Propagate(err, "failed to insert event")
}

func (r *EventRepository) GetData(ctx context.Context, id string, event string) (map[string]interface{}, bool, error) {
	var raw []byte
	err := r.DB.QueryRowContext(ctx, `SELECT data FROM events WHERE id = $1 AND event = $2`, id, event).Scan(&raw)
	if err == sql.ErrNoRows {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "failed to fetch event data")
	}
	var data map[string]interface{}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &data); err != nil {
			return nil, false, stacktrace.Propagate(err, "failed to unmarshal event data")
		}
	}
	if data == nil {
		data = map[string]interface{}{}
	}
	return data, true, nil
}
