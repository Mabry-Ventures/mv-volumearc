import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import * as schema from '@/db/schema';

const connectionString = process.env.DATABASE_URL?.trim();
const isConfigured = Boolean(connectionString);

let pool: Pool | null = null;
let dbInstance: ReturnType<typeof drizzle<typeof schema>> | null = null;

if (isConfigured && connectionString) {
  pool = new Pool({
    connectionString,
    max: 5,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
  dbInstance = drizzle(pool, { schema });
}

export const database = dbInstance;
export const hasDatabase = isConfigured;

