CREATE TABLE meta (
  key   TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE champions (
  champion_id INTEGER NOT NULL PRIMARY KEY,
  key         TEXT NOT NULL,
  changed     INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;

CREATE TABLE champion_flags (
  champion_id INTEGER NOT NULL,
  flag        TEXT NOT NULL,
  PRIMARY KEY (champion_id, flag)
) WITHOUT ROWID;

CREATE TABLE item_classes (
  item_id  INTEGER NOT NULL PRIMARY KEY,
  class    TEXT NOT NULL,
  antiheal INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;

CREATE TABLE champion_roles (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  games       INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role)
) WITHOUT ROWID;

CREATE TABLE champ_role_stats (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  kills       INTEGER NOT NULL,
  deaths      INTEGER NOT NULL,
  assists     INTEGER NOT NULL,
  cs          INTEGER NOT NULL,
  minutes     INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role)
) WITHOUT ROWID;

CREATE TABLE champ_ban_stats (
  champion_id INTEGER NOT NULL PRIMARY KEY,
  bans        INTEGER NOT NULL
) WITHOUT ROWID;

CREATE TABLE champion_profiles (
  champion_id  INTEGER NOT NULL,
  role         TEXT NOT NULL,
  phys_share   REAL NOT NULL,
  magic_share  REAL NOT NULL,
  true_share   REAL NOT NULL,
  dmg_per_min  REAL NOT NULL,
  tankiness    REAL NOT NULL,
  cc_score     REAL NOT NULL,
  tl_games     INTEGER NOT NULL,
  gold_diff_15 REAL,
  lvl6_s       INTEGER,
  item1_s      INTEGER,
  item2_s      INTEGER,
  item3_s      INTEGER,
  PRIMARY KEY (champion_id, role)
) WITHOUT ROWID;

CREATE TABLE duration_curves (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  bucket      TEXT NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, bucket)
) WITHOUT ROWID;

CREATE TABLE champ_vs_profile (
  champion_id   INTEGER NOT NULL,
  role          TEXT NOT NULL,
  enemy_profile TEXT NOT NULL,
  games         INTEGER NOT NULL,
  wins          INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_profile)
) WITHOUT ROWID;

CREATE TABLE matchup_stats (
  champion_id  INTEGER NOT NULL,
  role         TEXT NOT NULL,
  opp_id       INTEGER NOT NULL,
  games        INTEGER NOT NULL,
  wins         INTEGER NOT NULL,
  tl_games     INTEGER NOT NULL,
  gold_diff_15 REAL,
  cs_diff_15   REAL,
  PRIMARY KEY (champion_id, role, opp_id)
) WITHOUT ROWID;

CREATE TABLE synergy_stats (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  ally_id     INTEGER NOT NULL,
  ally_role   TEXT NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, ally_id, ally_role)
) WITHOUT ROWID;

CREATE TABLE vs_team_stats (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  enemy_id    INTEGER NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_id)
) WITHOUT ROWID;

CREATE TABLE rune_page_defs (
  page_id       INTEGER NOT NULL PRIMARY KEY,
  primary_style INTEGER NOT NULL,
  sub_style     INTEGER NOT NULL,
  perk1         INTEGER NOT NULL,
  perk2         INTEGER NOT NULL,
  perk3         INTEGER NOT NULL,
  perk4         INTEGER NOT NULL,
  perk5         INTEGER NOT NULL,
  perk6         INTEGER NOT NULL,
  shard_offense INTEGER NOT NULL,
  shard_flex    INTEGER NOT NULL,
  shard_defense INTEGER NOT NULL
);

CREATE TABLE rune_pages (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  opp_id      INTEGER NOT NULL,
  page_id     INTEGER NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, opp_id, page_id)
) WITHOUT ROWID;

CREATE TABLE rune_page_vs_profile (
  champion_id   INTEGER NOT NULL,
  role          TEXT NOT NULL,
  enemy_profile TEXT NOT NULL,
  page_id       INTEGER NOT NULL,
  games         INTEGER NOT NULL,
  wins          INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_profile, page_id)
) WITHOUT ROWID;

CREATE TABLE item_builds (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  opp_id      INTEGER NOT NULL,
  layer       TEXT NOT NULL,
  item1       INTEGER NOT NULL,
  item2       INTEGER NOT NULL,
  item3       INTEGER NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, opp_id, layer, item1, item2, item3)
) WITHOUT ROWID;

CREATE TABLE item_vs_profile (
  champion_id   INTEGER NOT NULL,
  role          TEXT NOT NULL,
  enemy_profile TEXT NOT NULL,
  item_id       INTEGER NOT NULL,
  games         INTEGER NOT NULL,
  wins          INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_profile, item_id)
) WITHOUT ROWID;

CREATE TABLE spell_pairs (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  opp_id      INTEGER NOT NULL,
  spell_a     INTEGER NOT NULL,
  spell_b     INTEGER NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, opp_id, spell_a, spell_b)
) WITHOUT ROWID;

CREATE TABLE skill_orders (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  max_order   TEXT NOT NULL,
  sequence    TEXT NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, max_order)
) WITHOUT ROWID;
