package repo_test

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"errors"
	"fmt"
	"io"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/embedding"
	"github.com/ente/museum/pkg/repo/emergency"
	"github.com/ente/museum/pkg/repo/filedata"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type securityTestRows struct {
	columns  []string
	values   [][]driver.Value
	queryErr error
	nextErr  error
	next     int
	closed   bool
}

func securityRows(values []driver.Value, nextErr error) *securityTestRows {
	columns := make([]string, len(values))
	for i := range columns {
		columns[i] = fmt.Sprintf("column_%d", i)
	}
	return &securityTestRows{columns: columns, nextErr: nextErr}
}

func (r *securityTestRows) Columns() []string { return r.columns }
func (r *securityTestRows) Close() error {
	r.closed = true
	return nil
}
func (r *securityTestRows) Next(dest []driver.Value) error {
	if r.next < len(r.values) {
		copy(dest, r.values[r.next])
		r.next++
		return nil
	}
	if r.nextErr != nil {
		return r.nextErr
	}
	return io.EOF
}

type securityTestDB struct {
	queries []*securityTestRows
	execs   int
	execErr error
}

type securityTestDriver struct{}

func (securityTestDriver) Open(string) (driver.Conn, error) {
	return nil, errors.New("use the test connector")
}
func (d *securityTestDB) Connect(context.Context) (driver.Conn, error) { return d, nil }
func (d *securityTestDB) Driver() driver.Driver                        { return securityTestDriver{} }
func (d *securityTestDB) Prepare(string) (driver.Stmt, error) {
	return nil, errors.New("unexpected prepare")
}
func (d *securityTestDB) Begin() (driver.Tx, error) {
	return nil, errors.New("unexpected transaction")
}
func (d *securityTestDB) Close() error { return nil }
func (d *securityTestDB) QueryContext(context.Context, string, []driver.NamedValue) (driver.Rows, error) {
	if len(d.queries) == 0 {
		return nil, errors.New("unexpected query")
	}
	rows := d.queries[0]
	d.queries = d.queries[1:]
	if rows.queryErr != nil {
		return nil, rows.queryErr
	}
	return rows, nil
}
func (d *securityTestDB) ExecContext(context.Context, string, []driver.NamedValue) (driver.Result, error) {
	d.execs++
	if d.execErr != nil {
		return nil, d.execErr
	}
	return driver.RowsAffected(1), nil
}
func (d *securityTestDB) open(t *testing.T) *sql.DB {
	t.Helper()
	db := sql.OpenDB(d)
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func TestSecurityReadsHandleRowFailures(t *testing.T) {
	ctx := context.Background()
	readErr := errors.New("interrupted security query")
	tests := []struct {
		name   string
		values []driver.Value
		read   func(*sql.DB) (any, error)
	}{
		{"ownership", []driver.Value{int64(1), int64(10)}, func(db *sql.DB) (any, error) {
			return (&repo.FileRepository{DB: db}).GetOwnerToFileIDsMap(ctx, []int64{10, 11})
		}},
		{"collection shares", []driver.Value{int64(10), int64(2), int64(1)}, func(db *sql.DB) (any, error) {
			return (&repo.CollectionRepository{DB: db}).GetAllSharedCollections(ctx, 1)
		}},
		{"public links", []driver.Value{int64(10)}, func(db *sql.DB) (any, error) {
			return (&public.CollectionLinkRepo{DB: db}).GetActivePublicTokenForUser(ctx, 1)
		}},
		{"emergency contacts", []driver.Value{int64(1), int64(2), string(ente.ContactAccepted), int64(24), "encrypted-key"}, func(db *sql.DB) (any, error) {
			return (&emergency.Repository{DB: db}).GetActiveContactForUser(ctx, 1)
		}},
		{"passkeys", []driver.Value{uuid.New().String(), int64(1), "security key", int64(1)}, func(db *sql.DB) (any, error) {
			return (&passkey.Repository{DB: db}).GetUserPasskeys(1)
		}},
		{"passkey credentials", []driver.Value{uuid.New().String(), "Y3JlZGVudGlhbA==", "accounts.example.com", "a2V5", "none", "internal", "{}", `{"AAGUID":"AAAAAAAAAAAAAAAAAAAAAA==","SignCount":0,"CloneWarning":false,"Attachment":""}`, int64(1)}, func(db *sql.DB) (any, error) {
			return (&passkey.Repository{DB: db}).GetUserPasskeyCredentials(1, "accounts.example.com")
		}},
		{"embedding locations", []driver.Value{"{b2}"}, func(db *sql.DB) (any, error) {
			return (&embedding.Repository{DB: db}).GetDatacenters(ctx, 10)
		}},
		{"file data statuses", []driver.Value{int64(10), int64(1), string(ente.MlData), int64(5), false, nil, nil, int64(1)}, func(db *sql.DB) (any, error) {
			return (&filedata.Repository{DB: db}).GetFDForUser(ctx, 1, 0, 10)
		}},
		{"file data", []driver.Value{int64(10), int64(1), string(ente.MlData), int64(5), "b2", "{}", "{}", "{}", false, false, int64(0), int64(1), int64(1), nil, nil, nil}, func(db *sql.DB) (any, error) {
			return (&filedata.Repository{DB: db}).GetFilesData(ctx, ente.MlData, []int64{10})
		}},
		{"metadata deletion batch", []driver.Value{int64(10), int64(1)}, func(db *sql.DB) (any, error) {
			return (&repo.TrashRepository{DB: db}).GetFileIdsForDroppingMetadata(0)
		}},
		{"token information", []driver.Value{int64(1), int64(1), "test-agent", false, string(ente.Photos)}, func(db *sql.DB) (any, error) {
			return (&repo.UserAuthRepository{DB: db}).GetUserTokenInfo(1)
		}},
		{"active sessions", []driver.Value{[]byte("hash"), int64(1), "127.0.0.1", "test-agent", int64(1)}, func(db *sql.DB) (any, error) {
			return (&repo.UserAuthRepository{DB: db}).GetActiveSessions(1, ente.Photos)
		}},
	}
	for _, test := range tests {
		for _, failure := range []string{"before first row", "after first row", "scan"} {
			t.Run(test.name+"/"+failure, func(t *testing.T) {
				rows := securityRows(test.values, readErr)
				if failure != "before first row" {
					rows.values = [][]driver.Value{test.values}
				}
				if failure == "scan" {
					rows.nextErr = nil
					rows.columns = append(rows.columns, "unexpected_column")
				}
				db := (&securityTestDB{queries: []*securityTestRows{rows}}).open(t)
				_, err := test.read(db)
				if failure == "scan" && err == nil {
					t.Fatal("expected scan error")
				}
				if failure != "scan" && !errors.Is(err, readErr) {
					t.Fatalf("expected iteration error, got %v", err)
				}
				if !rows.closed || db.Stats().InUse != 0 {
					t.Fatal("query did not release its connection")
				}
			})
		}
	}
}

func TestDropFilesMetadataDoesNotWriteAfterReadFailure(t *testing.T) {
	readErr := errors.New("remaining object check failed")
	rows := securityRows([]driver.Value{int64(10)}, readErr)
	state := &securityTestDB{queries: []*securityTestRows{rows}}
	err := (&repo.FileRepository{DB: state.open(t)}).DropFilesMetadata(context.Background(), []int64{10})
	if !errors.Is(err, readErr) {
		t.Fatalf("expected read error, got %v", err)
	}
	if state.execs != 0 {
		t.Fatal("metadata was scrubbed after the object check failed")
	}
}

func TestCanAccessFileRejectsIncompleteOwnership(t *testing.T) {
	for _, partial := range []bool{false, true} {
		t.Run(fmt.Sprintf("partial=%t", partial), func(t *testing.T) {
			rows := securityRows([]driver.Value{int64(1), int64(10)}, nil)
			if partial {
				rows.values = [][]driver.Value{{int64(1), int64(10)}}
			}
			db := (&securityTestDB{queries: []*securityTestRows{rows}}).open(t)
			controller := access.NewAccessController(nil, &repo.FileRepository{DB: db})
			ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
			err := controller.CanAccessFile(ctx, &access.CanAccessFileParams{ActorUserID: 1, FileIDs: []int64{10, 11}})
			if !errors.Is(err, ente.ErrPermissionDenied) {
				t.Fatalf("expected permission denied, got %v", err)
			}
		})
	}
}

func TestReleaseHostLockHandlesDatabaseFailure(t *testing.T) {
	state := &securityTestDB{execErr: errors.New("lock deletion failed")}
	controller := &lock.LockController{TaskLockingRepo: &repo.TaskLockRepository{DB: state.open(t)}, HostName: "test-host"}
	controller.ReleaseHostLock()
}
