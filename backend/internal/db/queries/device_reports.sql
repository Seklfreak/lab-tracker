-- name: CreateDeviceReport :one
-- A saved, PDF-less report for one device reading. Returns no rows when this
-- reading already exists on the profile.
INSERT INTO lab_reports (profile_id, source, external_id, source_lab, collected_date, reported_date, status)
VALUES (sqlc.arg(profile_id), 'device', sqlc.arg(external_id), sqlc.arg(source_lab), sqlc.arg(collected_date), sqlc.arg(collected_date), 'saved')
ON CONFLICT (profile_id, source, external_id) DO NOTHING
RETURNING *;

-- name: ListDeviceReportsByExternalIDForUser :many
-- Device reports with any of the given external ids, on profiles the user owns
-- or that are shared with them. Other users' readings are never visible.
SELECT rep.id, rep.profile_id, rep.external_id
FROM lab_reports rep
JOIN profiles p ON p.id = rep.profile_id
WHERE rep.source = 'device'
  AND rep.external_id = ANY(sqlc.arg(external_ids)::text[])
  AND (
      p.owner_user_id = sqlc.arg(user_id)
      OR EXISTS (
          SELECT 1 FROM profile_members m
          WHERE m.profile_id = p.id AND m.user_id = sqlc.arg(user_id)
      )
  );
