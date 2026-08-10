CREATE TABLE pairings (
  id TEXT PRIMARY KEY,
  pairing_code TEXT NOT NULL UNIQUE,
  device_secret_hash TEXT NOT NULL,
  oauth_state_hash TEXT UNIQUE,
  oauth_state_used_at INTEGER,
  oauth_completed_at INTEGER,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX pairings_expiry ON pairings(expires_at);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  pairing_id TEXT NOT NULL UNIQUE,
  bearer_token_hash TEXT NOT NULL UNIQUE,
  token_ciphertext TEXT NOT NULL,
  token_iv TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  FOREIGN KEY(pairing_id) REFERENCES pairings(id)
);

CREATE INDEX sessions_bearer ON sessions(bearer_token_hash);

CREATE TABLE mutations (
  session_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(session_id, mutation_id),
  FOREIGN KEY(session_id) REFERENCES sessions(id)
);
