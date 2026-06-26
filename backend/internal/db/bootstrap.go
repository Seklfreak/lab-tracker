package db

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// BootstrapOwner ensures a user with the given OIDC sub exists and assigns it as
// the owner of any profiles that don't yet have one. This migrates pre-existing
// (owner-less) profiles to the admin/dev user when multi-user is first rolled
// out, and is a safe no-op once every profile has an owner. Idempotent.
//
// When fixedID is non-nil the user is created with that id (used for the fixed
// local dev user); otherwise the id is generated. If a user with this sub
// already exists, its id is reused regardless of fixedID.
func BootstrapOwner(ctx context.Context, pool *pgxpool.Pool, sub string, fixedID *uuid.UUID) error {
	if sub == "" {
		return nil
	}

	if fixedID != nil {
		if _, err := pool.Exec(ctx,
			`INSERT INTO users (id, oidc_sub) VALUES ($1, $2) ON CONFLICT (oidc_sub) DO NOTHING`,
			*fixedID, sub); err != nil {
			return fmt.Errorf("ensure user: %w", err)
		}
	} else {
		if _, err := pool.Exec(ctx,
			`INSERT INTO users (oidc_sub) VALUES ($1) ON CONFLICT (oidc_sub) DO NOTHING`,
			sub); err != nil {
			return fmt.Errorf("ensure user: %w", err)
		}
	}

	var id uuid.UUID
	if err := pool.QueryRow(ctx, `SELECT id FROM users WHERE oidc_sub = $1`, sub).Scan(&id); err != nil {
		return fmt.Errorf("load user id: %w", err)
	}

	if _, err := pool.Exec(ctx,
		`UPDATE profiles SET owner_user_id = $1 WHERE owner_user_id IS NULL`, id); err != nil {
		return fmt.Errorf("backfill profile owners: %w", err)
	}
	return nil
}
