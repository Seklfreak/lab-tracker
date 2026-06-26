DROP TABLE IF EXISTS profile_members;
DROP INDEX IF EXISTS idx_profiles_owner;
ALTER TABLE profiles DROP COLUMN IF EXISTS owner_user_id;
DROP TABLE IF EXISTS users;
