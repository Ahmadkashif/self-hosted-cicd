//go:build integration

package store

import (
	"context"
	"os"
	"testing"
	"time"
)

// Runs against a real Postgres (CI: the `postgres` service container). DATABASE_URL is required.
func TestIncrAgainstPostgres(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL is not set (integration tests need Postgres)")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	s, err := Open(ctx, dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer s.Close()
	name := "it-" + time.Now().Format("150405.000000000")
	for want := int64(1); want <= 3; want++ {
		got, err := s.Incr(ctx, name)
		if err != nil || got != want {
			t.Fatalf("Incr #%d = %d, %v", want, got, err)
		}
	}
}
