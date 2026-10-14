// Package store keeps named counters in Postgres.
package store

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is a Postgres-backed counter store.
type Store struct{ pool *pgxpool.Pool }

// Open connects and makes sure the schema exists.
func Open(ctx context.Context, dsn string) (*Store, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, err
	}
	if _, err := pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS counters (name text PRIMARY KEY, n bigint NOT NULL)`); err != nil {
		pool.Close()
		return nil, err
	}
	return &Store{pool: pool}, nil
}

// Incr adds one to the named counter and returns the new value.
func (s *Store) Incr(ctx context.Context, name string) (int64, error) {
	var n int64
	err := s.pool.QueryRow(ctx, `INSERT INTO counters (name, n) VALUES ($1, 1)
		ON CONFLICT (name) DO UPDATE SET n = counters.n + 1 RETURNING n`, name).Scan(&n)
	return n, err
}

// Close releases the pool.
func (s *Store) Close() { s.pool.Close() }
