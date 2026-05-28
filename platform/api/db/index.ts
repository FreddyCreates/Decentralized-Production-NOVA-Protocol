///
/// NOVA Cloud — Database Layer (SQLite)
///
/// Lightweight, sovereign, no external DB dependency for dev/single-node.
/// Production uses Postgres (already in docker-compose).
///

import Database from 'better-sqlite3';
import { resolve } from 'path';

const DB_PATH = process.env.NOVA_DB_PATH || resolve(process.cwd(), 'nova-cloud.db');

class NovaDB {
  private _db: Database.Database | null = null;

  get conn(): Database.Database {
    if (!this._db) {
      this._db = new Database(DB_PATH);
      this._db.pragma('journal_mode = WAL');
      this._db.pragma('foreign_keys = ON');
    }
    return this._db;
  }

  initialize() {
    this.conn.exec(`
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        name TEXT,
        org_id TEXT,
        api_token TEXT UNIQUE,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS organizations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        slug TEXT UNIQUE NOT NULL,
        type TEXT DEFAULT 'personal',
        created_at TEXT DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS apps (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        org_id TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        hostname TEXT,
        regions TEXT DEFAULT '[]',
        config TEXT DEFAULT '{}',
        current_release_id TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (org_id) REFERENCES organizations(id)
      );

      CREATE TABLE IF NOT EXISTS machines (
        id TEXT PRIMARY KEY,
        app_id TEXT NOT NULL,
        name TEXT NOT NULL,
        status TEXT DEFAULT 'created',
        region TEXT NOT NULL,
        instance_id TEXT,
        private_ip TEXT,
        image TEXT,
        cpus INTEGER DEFAULT 1,
        memory_mb INTEGER DEFAULT 256,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now')),
        events TEXT DEFAULT '[]',
        checks TEXT DEFAULT '[]',
        FOREIGN KEY (app_id) REFERENCES apps(id)
      );

      CREATE TABLE IF NOT EXISTS releases (
        id TEXT PRIMARY KEY,
        app_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        image TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        strategy TEXT DEFAULT 'rolling',
        deployed_by TEXT,
        reason TEXT,
        definition TEXT DEFAULT '{}',
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (app_id) REFERENCES apps(id)
      );

      CREATE TABLE IF NOT EXISTS secrets (
        id TEXT PRIMARY KEY,
        app_id TEXT NOT NULL,
        name TEXT NOT NULL,
        encrypted_value TEXT NOT NULL,
        digest TEXT NOT NULL,
        version INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (app_id) REFERENCES apps(id),
        UNIQUE(app_id, name)
      );

      CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_id TEXT NOT NULL,
        machine_id TEXT,
        region TEXT,
        level TEXT DEFAULT 'info',
        message TEXT NOT NULL,
        instance TEXT,
        timestamp TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (app_id) REFERENCES apps(id)
      );

      CREATE INDEX IF NOT EXISTS idx_apps_org ON apps(org_id);
      CREATE INDEX IF NOT EXISTS idx_machines_app ON machines(app_id);
      CREATE INDEX IF NOT EXISTS idx_releases_app ON releases(app_id);
      CREATE INDEX IF NOT EXISTS idx_secrets_app ON secrets(app_id);
      CREATE INDEX IF NOT EXISTS idx_logs_app ON logs(app_id);
      CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
    `);
  }
}

export const db = new NovaDB();
