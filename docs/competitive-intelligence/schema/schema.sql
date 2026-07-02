-- Lancer Competitive Intelligence — SQLite schema (generated DB, gitignored)
-- Canonical source of truth is the JSONL under ../data/. This schema is regenerated
-- deterministically from that JSONL by tools/import. Do not hand-edit the .db file.

PRAGMA foreign_keys = ON;

-- ── competitors ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS competitors (
  id                 TEXT PRIMARY KEY,          -- stable kebab-case id, e.g. "omnara"
  name               TEXT NOT NULL,
  former_names       TEXT,                      -- JSON array
  category           TEXT NOT NULL,             -- direct | first-party-platform | adjacent | substitute | infra
  company            TEXT,
  product_urls       TEXT,                      -- JSON array
  repo_url           TEXT,
  app_store_id       TEXT,
  play_store_id      TEXT,
  oss_status         TEXT,                      -- closed | open-source | source-available | archived-oss
  license             TEXT,
  platforms          TEXT,                      -- JSON array
  supported_agents   TEXT,                      -- JSON array
  target_customer    TEXT,
  positioning        TEXT,
  pricing            TEXT,
  distribution_model TEXT,
  architecture       TEXT,
  security_model     TEXT,
  launch_date        TEXT,
  last_release_date  TEXT,
  status             TEXT,                      -- active | dormant | shut-down | pivoted | acquired
  threat_score       INTEGER,                   -- 1-5
  confidence         TEXT,                      -- strong | moderate | weak | inference
  first_observed     TEXT,
  last_checked       TEXT
);

-- ── sources ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sources (
  id               TEXT PRIMARY KEY,
  source_type      TEXT NOT NULL,               -- official-doc | app-store | play-store | github | hn | reddit | x | product-hunt | press | blog | forum
  url              TEXT,
  title            TEXT,
  author           TEXT,
  pub_date         TEXT,
  collected_date   TEXT NOT NULL,
  is_primary       INTEGER NOT NULL DEFAULT 0,  -- 1 = primary source
  region           TEXT,
  quality_score    INTEGER,                     -- 1-5
  content_hash     TEXT,
  competitor_id    TEXT REFERENCES competitors(id),
  notes            TEXT
);

-- ── features (normalized taxonomy) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS features (
  id          TEXT PRIMARY KEY,                 -- e.g. "governed-approvals"
  name        TEXT NOT NULL,
  category    TEXT NOT NULL,                    -- session | approvals | terminal | files | notifications | fleet | policy | audit | identity | security | monetization | integrations
  description TEXT
);

-- ── competitor_features (many-to-many with evidence) ────────────────────
CREATE TABLE IF NOT EXISTS competitor_features (
  competitor_id  TEXT NOT NULL REFERENCES competitors(id),
  feature_id     TEXT NOT NULL REFERENCES features(id),
  support_level  TEXT NOT NULL,                 -- full | partial | planned | absent | unknown
  evidence_source_id TEXT REFERENCES sources(id),
  notes          TEXT,
  last_verified  TEXT,
  confidence     TEXT,                          -- strong | moderate | weak | inference
  PRIMARY KEY (competitor_id, feature_id)
);

-- ── feedback (user quotes / observations, metadata + short excerpt only) ─
CREATE TABLE IF NOT EXISTS feedback (
  id                TEXT PRIMARY KEY,
  competitor_id     TEXT REFERENCES competitors(id),
  platform          TEXT,                       -- hn | reddit | x | app-store | play-store | product-hunt | github-issue | blog
  date              TEXT,
  engagement        TEXT,                       -- e.g. "HN front page", "32 ratings"
  sentiment         TEXT,                       -- positive | negative | neutral | mixed
  theme             TEXT,
  pain              TEXT,
  requested_feature TEXT,
  praise            TEXT,
  switching_behavior TEXT,
  willingness_to_pay TEXT,
  excerpt           TEXT,                       -- short excerpt only, not full text
  source_id         TEXT REFERENCES sources(id),
  is_verified_user  TEXT                        -- strong | moderate | weak | unknown
);

-- ── claims (every material statement in the reports) ────────────────────
CREATE TABLE IF NOT EXISTS claims (
  id                  TEXT PRIMARY KEY,
  claim_text          TEXT NOT NULL,
  supporting_sources   TEXT,                    -- JSON array of source ids
  contradicting_sources TEXT,                   -- JSON array of source ids
  confidence           TEXT NOT NULL,           -- strong | moderate | weak | inference
  last_verified        TEXT,
  claim_type            TEXT NOT NULL           -- fact | inference | hypothesis
);

-- ── opportunities ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS opportunities (
  id                    TEXT PRIMARY KEY,
  problem_statement     TEXT NOT NULL,
  user_segment          TEXT,
  evidence_count        INTEGER,
  evidence_quality       TEXT,
  pain_frequency         INTEGER,               -- 1-5
  pain_severity           INTEGER,              -- 1-5
  existing_workaround     TEXT,
  existing_competitors    TEXT,                 -- JSON array of competitor ids
  market_saturation       INTEGER,              -- 1-5 (5 = saturated)
  strategic_fit            INTEGER,             -- 1-5
  technical_fit             INTEGER,            -- 1-5 (existing-code leverage)
  differentiation_potential  INTEGER,           -- 1-5
  effort                     TEXT,              -- S | M | L | XL
  defensibility               INTEGER,          -- 1-5
  revenue_potential             INTEGER,        -- 1-5
  risks                         TEXT,
  overall_score                  REAL           -- computed, see tools/report scoring formula
);

-- ── research_runs ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS research_runs (
  id               TEXT PRIMARY KEY,
  started_at       TEXT NOT NULL,
  completed_at     TEXT,
  agents_used      TEXT,                        -- JSON array
  sources_queried  INTEGER,
  queries_used     TEXT,                        -- JSON array
  new_records      INTEGER,
  updated_records  INTEGER,
  failed_sources   TEXT,                        -- JSON array of {url, reason}
  validation_failures TEXT,
  report_version   TEXT
);

-- ── FTS indexes for quick recall ─────────────────────────────────────────
CREATE VIRTUAL TABLE IF NOT EXISTS feedback_fts USING fts5(
  excerpt, theme, pain, requested_feature, praise, content='feedback', content_rowid='rowid'
);

CREATE VIRTUAL TABLE IF NOT EXISTS claims_fts USING fts5(
  claim_text, content='claims', content_rowid='rowid'
);

CREATE INDEX IF NOT EXISTS idx_sources_competitor ON sources(competitor_id);
CREATE INDEX IF NOT EXISTS idx_feedback_competitor ON feedback(competitor_id);
CREATE INDEX IF NOT EXISTS idx_cf_competitor ON competitor_features(competitor_id);
CREATE INDEX IF NOT EXISTS idx_cf_feature ON competitor_features(feature_id);
