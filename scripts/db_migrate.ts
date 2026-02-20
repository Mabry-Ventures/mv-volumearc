import fs from 'node:fs';
import path from 'node:path';
import { Client } from 'pg';

const migrationDir = path.join(process.cwd(), 'src/db/migrations');

const main = async () => {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) {
    console.error('DATABASE_URL is required to run migrations.');
    process.exit(1);
  }

  if (!fs.existsSync(migrationDir)) {
    console.error(`Migration directory not found: ${migrationDir}`);
    process.exit(1);
  }

  const files = fs
    .readdirSync(migrationDir)
    .filter(file => file.endsWith('.sql'))
    .sort();

  if (files.length === 0) {
    console.log('No SQL migration files found. Nothing to apply.');
    return;
  }

  const client = new Client({ connectionString: databaseUrl });
  await client.connect();

  try {
    for (const file of files) {
      const filePath = path.join(migrationDir, file);
      const sql = fs.readFileSync(filePath, 'utf8');
      console.log(`Applying migration: ${file}`);
      await client.query(sql);
    }
    console.log(`Migration complete. Applied ${files.length} file(s).`);
  } finally {
    await client.end();
  }
};

main().catch(error => {
  console.error('Migration failed:', error);
  process.exit(1);
});

