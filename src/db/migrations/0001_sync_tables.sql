CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS user_profile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_key text NOT NULL UNIQUE,
  display_name text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workout_sync_ops (
  id text PRIMARY KEY,
  user_key text NOT NULL,
  device_id text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  op_type text NOT NULL,
  payload jsonb,
  client_updated_at timestamptz NOT NULL,
  server_received_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS workout_sync_ops_user_idx ON workout_sync_ops (user_key);
CREATE INDEX IF NOT EXISTS workout_sync_ops_entity_idx ON workout_sync_ops (entity_type, entity_id);

CREATE TABLE IF NOT EXISTS workout_sync_conflicts (
  id text PRIMARY KEY,
  user_key text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  kept_operation_id text NOT NULL,
  dropped_operation_id text NOT NULL,
  reason text NOT NULL,
  resolved_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS workout_sync_conflicts_user_idx ON workout_sync_conflicts (user_key);
CREATE INDEX IF NOT EXISTS workout_sync_conflicts_entity_idx ON workout_sync_conflicts (entity_type, entity_id);

CREATE TABLE IF NOT EXISTS workout_state_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_key text NOT NULL,
  cursor integer NOT NULL,
  state jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS workout_state_snapshots_user_cursor_idx
  ON workout_state_snapshots (user_key, cursor);
