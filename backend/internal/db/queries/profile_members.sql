-- name: ListProfileMembers :many
SELECT m.profile_id, m.user_id, m.role, m.created_at,
       u.email AS email, u.name AS name, u.oidc_sub AS oidc_sub
FROM profile_members m
JOIN users u ON u.id = m.user_id
WHERE m.profile_id = $1
ORDER BY u.email NULLS LAST, u.oidc_sub;

-- name: AddProfileMember :exec
INSERT INTO profile_members (profile_id, user_id, role)
VALUES ($1, $2, $3)
ON CONFLICT (profile_id, user_id) DO UPDATE SET role = EXCLUDED.role;

-- name: RemoveProfileMember :exec
DELETE FROM profile_members WHERE profile_id = $1 AND user_id = $2;
