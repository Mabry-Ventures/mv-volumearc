import { index, integer, jsonb, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

export const userProfile = pgTable('user_profile', {
  id: uuid('id').defaultRandom().primaryKey(),
  userKey: text('user_key').notNull().unique(),
  displayName: text('display_name'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});

export const workoutSyncOps = pgTable(
  'workout_sync_ops',
  {
    id: text('id').primaryKey(),
    userKey: text('user_key').notNull(),
    deviceId: text('device_id').notNull(),
    entityType: text('entity_type').notNull(),
    entityId: text('entity_id').notNull(),
    opType: text('op_type').notNull(),
    payload: jsonb('payload'),
    clientUpdatedAt: timestamp('client_updated_at', { withTimezone: true }).notNull(),
    serverReceivedAt: timestamp('server_received_at', { withTimezone: true }).defaultNow().notNull(),
  },
  table => ({
    userIdx: index('workout_sync_ops_user_idx').on(table.userKey),
    entityIdx: index('workout_sync_ops_entity_idx').on(table.entityType, table.entityId),
  })
);

export const workoutSyncConflicts = pgTable(
  'workout_sync_conflicts',
  {
    id: text('id').primaryKey(),
    userKey: text('user_key').notNull(),
    entityType: text('entity_type').notNull(),
    entityId: text('entity_id').notNull(),
    keptOperationId: text('kept_operation_id').notNull(),
    droppedOperationId: text('dropped_operation_id').notNull(),
    reason: text('reason').notNull(),
    resolvedAt: timestamp('resolved_at', { withTimezone: true }).defaultNow().notNull(),
  },
  table => ({
    userIdx: index('workout_sync_conflicts_user_idx').on(table.userKey),
    entityIdx: index('workout_sync_conflicts_entity_idx').on(table.entityType, table.entityId),
  })
);

export const workoutStateSnapshots = pgTable(
  'workout_state_snapshots',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    userKey: text('user_key').notNull(),
    cursor: integer('cursor').notNull(),
    state: jsonb('state').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  table => ({
    userCursorIdx: index('workout_state_snapshots_user_cursor_idx').on(table.userKey, table.cursor),
  })
);
