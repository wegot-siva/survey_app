-- Survey app — Supabase schema (Phase 2: CONNECT ONLY, no sync yet).
--
-- Mirrors the local SQLite model defined in lib/services/app_database.dart so a
-- later slice can sync 1:1. Run this in the Supabase dashboard SQL editor.
-- Re-runnable (idempotent).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.sites (
  id   text primary key,
  name text not null
);

create table if not exists public.blocks (
  id       bigint generated always as identity primary key,
  site_id  text not null references public.sites (id) on delete cascade,
  position integer not null,
  label    text not null
);

create index if not exists blocks_site_id_idx on public.blocks (site_id);

create table if not exists public.client_inputs (
  site_id                        text primary key references public.sites (id) on delete cascade,
  site_name                      text,
  information_source             text,    -- enum name: physicalSurvey | drawing
  client_poc_name                text,
  client_poc_contact             text,
  goal_of_installation           text,
  water_sources                  text,    -- comma-separated enum names (mirrors SQLite)
  oht_hns                        text,    -- enum name: oht | hns | both
  finalised_plumbing_drawings    boolean,
  points_identified              integer,
  max_and_continuous_pressure    text,
  pressure_boosters              boolean,
  materials_and_brand_guidelines text,
  rework_required                boolean,
  rework_details                 text,
  age_of_plumbing_lines          text,
  aesthetic_guidelines           boolean,
  aesthetic_details              text
);

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- RLS is enabled. The policies below are PERMISSIVE, DEV-ONLY placeholders so
-- the in-app "Test connection" check works before any auth exists.
-- !! TIGHTEN THESE before real sync/auth (scope by authenticated user/org). !!
-- ---------------------------------------------------------------------------

alter table public.sites         enable row level security;
alter table public.blocks        enable row level security;
alter table public.client_inputs enable row level security;

drop policy if exists "dev all - sites" on public.sites;
create policy "dev all - sites" on public.sites
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "dev all - blocks" on public.blocks;
create policy "dev all - blocks" on public.blocks
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "dev all - client_inputs" on public.client_inputs;
create policy "dev all - client_inputs" on public.client_inputs
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Source points + inlet points (slice 1c). Mirror the local sqflite models.
-- Booleans are native (null = unanswered); enums stored as their `.name`.
-- ---------------------------------------------------------------------------

create table if not exists public.source_points (
  id                                text primary key,
  site_id                           text not null references public.sites (id) on delete cascade,
  block                             text,
  apartment                         text,
  inlet_description                 text,
  sensor_size                       text,
  sensor_od                         text,
  pipe_size                         text,
  pipe_type                         text,
  qty                               integer,
  sensor_type                       text,
  rework                            boolean,
  rework_details                    text,
  flow_direction                    text,
  clearance_10x                     boolean,
  pipe_full                         boolean,
  valve_downstream                  boolean,
  reducer_spec                      boolean,
  reducer_spec_details              text,
  downstream_outlet_above_pipe_fig1 boolean,
  air_vent_needed_fig2              boolean,
  reverse_flow                      boolean,
  distance_from_motor_pump_fig3     boolean,
  no_flexible_pipe_within_20x       boolean,
  max_and_continuous_pressure_bar   double precision,
  strainer_screen_filter            boolean,
  chamber_installation              boolean,
  antenna_required                  boolean,
  transmitting_part_open_to_air     boolean,
  nrv_feasibility                   boolean
);

create index if not exists source_points_site_id_idx
  on public.source_points (site_id);

create table if not exists public.inlet_points (
  id                              text primary key,
  site_id                         text not null references public.sites (id) on delete cascade,
  block                           text,
  apartment_bhk                   text,
  sensor_size                     text,
  series                          text,
  sensor_od                       text,
  pipe_size                       text,
  pipe_type                       text,
  qty                             integer,
  sensor_type                     text,
  rework                          boolean,
  rework_details                  text,
  linear_distance_clearance_10x   boolean,
  reverse_flow                    boolean,
  oht_hns                         text,
  distance_from_motor_pump        boolean,
  max_and_continuous_pressure_bar double precision,
  strainer_screen_filter          boolean,
  flow_direction                  text,
  access_mode                     text,
  cable_run_length                text,
  conduit_clamping                boolean,
  civil_work_needed               boolean,
  civil_work_details              text
);

create index if not exists inlet_points_site_id_idx
  on public.inlet_points (site_id);

alter table public.source_points enable row level security;
alter table public.inlet_points  enable row level security;

drop policy if exists "dev all - source_points" on public.source_points;
create policy "dev all - source_points" on public.source_points
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "dev all - inlet_points" on public.inlet_points;
create policy "dev all - inlet_points" on public.inlet_points
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Phase 2: Duct LoRa, Gateway, Footer + reserved assignment columns on sites.
-- Mirrors the local sqflite v4 schema. Booleans native; enums stored as
-- `.name`; multi-select sets (series_served, blocks_covered) are
-- comma-separated text (mirrors water_sources). Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- Reserved for a future assignment workflow — unused for now.
alter table public.sites add column if not exists status      text;
alter table public.sites add column if not exists assigned_to text;

create table if not exists public.duct_loras (
  id                             text primary key,
  site_id                        text not null references public.sites (id) on delete cascade,
  block                          text,
  series_served                  text,    -- comma-separated series tokens
  accessible_for_service         boolean,
  rssi_if_tcl                    double precision,
  power_point_available_shielded boolean,
  separate_mcb_for_series        boolean,
  ups_power_supply               boolean,
  cable_length                   double precision
);

create index if not exists duct_loras_site_id_idx
  on public.duct_loras (site_id);

create table if not exists public.gateways (
  id                         text primary key,
  site_id                    text not null references public.sites (id) on delete cascade,
  placement                  text,    -- enum name: indoor | outdoor
  location_description       text,
  blocks_covered             text,    -- comma-separated block labels
  quantity                   integer,
  uplink_type                text,    -- enum name: sim | router | both
  wifi_interference_check    boolean,
  wifi_interference_details  text,
  sim_coverage               text,    -- enum name: airtel | jio | both | none
  uninterrupted_power_source boolean,
  mounting_hardware_needed   text
);

create index if not exists gateways_site_id_idx
  on public.gateways (site_id);

create table if not exists public.footers (
  site_id             text primary key references public.sites (id) on delete cascade,
  tds_ppm             double precision,
  tss_ppm             double precision,
  tcl_service         boolean,
  tcl_service_details text,
  general_remarks     text,
  survey_date         text,    -- ISO-8601 string (mirrors SQLite TEXT storage)
  surveyor_name       text
);

alter table public.duct_loras enable row level security;
alter table public.gateways   enable row level security;
alter table public.footers    enable row level security;

drop policy if exists "dev all - duct_loras" on public.duct_loras;
create policy "dev all - duct_loras" on public.duct_loras
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "dev all - gateways" on public.gateways;
create policy "dev all - gateways" on public.gateways
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "dev all - footers" on public.footers;
create policy "dev all - footers" on public.footers
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Material Master + BoM phase. Admin-editable reference data — NOT site-scoped
-- (no FK to sites). The on-device BoM engine reads every quantity from this
-- table at generation time; it starts empty and is populated via the
-- Material Master admin screen in the app. Mirrors the local sqflite v5 schema.
-- ---------------------------------------------------------------------------

create table if not exists public.material_master_items (
  id                   text primary key,
  group_code           text not null,              -- enum name: a..g
  material_name        text not null,
  sku                  text,                        -- optional SKU / part code
  item_label           text,                        -- optional short label, distinct from material_name (Lumax export)
  unit                 text not null,
  behavior_type        text not null,              -- enum name: fixed | derived | variable
  sensor_size          text,                        -- enum name; null = any size
  sensor_type          text,                        -- enum name; null = any type
  quantity_per_sensor  double precision not null default 0,
  derived_formula      text,                        -- enum name; e.g. ceilWiredSensorsDividedByDivisor
  formula_divisor      double precision,
  variable_source      text,                        -- enum name; e.g. ductLoraCableLength
  notes                text,
  material_type        text,                        -- e.g. 'uPVC', 'CPVC'; only set on group C's plumbing catalog
  category              text,                        -- e.g. 'Elbow 90°', 'Tee', 'Coupler'
  variant               text,                        -- e.g. 'SCH40', 'SCH80', 'Brass Threaded'
  size_mm               double precision,            -- nominal DN in mm; sort/join field only, never shown directly
  size_display          text,                        -- human-readable size, e.g. '1¼"' or '1¼" x 1"' for a reducer
  deleted_at            text                         -- unused; superseded, see the migration note below
);

alter table public.material_master_items enable row level security;

drop policy if exists "dev all - material_master_items" on public.material_master_items;
create policy "dev all - material_master_items" on public.material_master_items
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Photo capture slice 1 — Duct LoRa placement photo.
--
-- Adds the remote object-key column on duct_loras (the device-local file path
-- is never pushed), plus a Storage bucket + dev-only policies so the app can
-- upload captured photos. Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.duct_loras
  add column if not exists placement_photo_remote_path text;

-- Storage bucket for survey photos. `on conflict do nothing` makes re-runs safe.
insert into storage.buckets (id, name, public)
values ('survey-photos', 'survey-photos', true)
on conflict (id) do nothing;

-- DEV-ONLY storage policies: allow anon + authenticated to read/write objects
-- in the survey-photos bucket. !! TIGHTEN before production (scope by auth). !!
drop policy if exists "dev all - survey-photos read" on storage.objects;
create policy "dev all - survey-photos read" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'survey-photos');

drop policy if exists "dev all - survey-photos write" on storage.objects;
create policy "dev all - survey-photos write" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'survey-photos');

drop policy if exists "dev all - survey-photos update" on storage.objects;
create policy "dev all - survey-photos update" on storage.objects
  for update to anon, authenticated
  using (bucket_id = 'survey-photos')
  with check (bucket_id = 'survey-photos');

-- ---------------------------------------------------------------------------
-- Photo capture slice 2 — generic polymorphic photos table serving the
-- source/inlet/gateway/footer photo fields. (owner_type, owner_id) is a
-- polymorphic link (no FK); slot names the field; footer site media uses many
-- rows in one slot, ordered by position. Files upload to the same survey-photos
-- bucket under photos/<id>.jpg. The device-local path is never pushed.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

create table if not exists public.photos (
  id          text primary key,
  owner_type  text not null,   -- source_point | inlet_point | gateway | footer | duct_lora | client_inputs
  owner_id    text not null,
  slot        text not null,   -- e.g. inlet_marked, shaft_access, site_media
  position    integer not null default 0,
  remote_path text             -- Storage object key; local path never pushed
);

create index if not exists photos_owner_idx on public.photos (owner_type, owner_id);

alter table public.photos enable row level security;

drop policy if exists "dev all - photos" on public.photos;
create policy "dev all - photos" on public.photos
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Admin role slice — SKU on Material Master + its change log.
--
-- `alter table add column if not exists` covers projects that already ran the
-- material_master_items block above before this column existed; the
-- `create table` above already includes it for fresh setups. The audit table
-- is NOT FK'd to material_master_items — a delete's own audit entry (and any
-- earlier edits) must survive the row's removal. Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.material_master_items
  add column if not exists sku text;

create table if not exists public.material_master_audit (
  id              text primary key,
  material_row_id text not null,
  field_changed   text not null,   -- field name, or '(created)' / '(deleted)'
  old_value       text,
  new_value       text,
  changed_by_role text not null,   -- role label, e.g. "Admin" (shared login)
  changed_at      text not null    -- ISO-8601 string (mirrors SQLite TEXT storage)
);

create index if not exists material_master_audit_row_idx
  on public.material_master_audit (material_row_id);

alter table public.material_master_audit enable row level security;

drop policy if exists "dev all - material_master_audit" on public.material_master_audit;
create policy "dev all - material_master_audit" on public.material_master_audit
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- D/E/G "Add materials" picker — manual BoM entries (mechanics only; not
-- wired into snapshot/finalize logic yet, never read by the BoM engine).
--
-- FK'd to sites (cascade delete) — genuinely survey-scoped, unlike Material
-- Master. Not linked to any material_master_items row by id: name/sku/unit
-- are copied at the moment the picker's dropdown selection is made, so an
-- entry survives that catalog row later changing or being deleted.
-- `group_code` avoids "group" (a reserved word in Postgres) but, unlike
-- material_master_items.group_code (lowercase enum name), stores the literal
-- 'D' / 'E' / 'G' — the app restricts it to just those three.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

create table if not exists public.bom_manual_entries (
  id            text primary key,
  survey_id     text not null references public.sites (id) on delete cascade,
  material_name text not null,
  sku           text,
  item_label    text,            -- optional short label (Lumax export)
  sensor_size   text,            -- enum name; usually null (D/E/G items rarely have a variant)
  sensor_type   text,            -- enum name; usually null
  unit          text not null,
  qty           double precision not null,
  group_code    text not null,   -- literal: 'D' | 'E' | 'G'
  added_by      text not null,   -- role label, e.g. "Engineer" (shared login)
  added_at      text not null    -- ISO-8601 string (mirrors SQLite TEXT storage)
);

create index if not exists bom_manual_entries_survey_idx
  on public.bom_manual_entries (survey_id);

alter table public.bom_manual_entries enable row level security;

drop policy if exists "dev all - bom_manual_entries" on public.bom_manual_entries;
create policy "dev all - bom_manual_entries" on public.bom_manual_entries
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Finalize — freezes the current BoM as an immutable version-1 snapshot.
--
-- `bom_locked` defaults to false, so every existing survey stays unlocked
-- until explicitly finalized. bom_snapshots is one row per survey in this
-- slice (version always 1; no revisions/re-finalize flow yet), FK'd to sites.
-- bom_snapshot_lines is NOT linked to material_master_items or
-- bom_manual_entries by id — sku/item/unit/qty/group are copied in at
-- finalize time, so editing either later cannot alter an existing snapshot.
-- `group_code` stores the literal 'A'..'G' (see the matching comment on
-- bom_manual_entries above for why this differs from
-- material_master_items.group_code); `source` stores literal 'auto'|'manual'.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.sites
  add column if not exists bom_locked boolean not null default false;

create table if not exists public.bom_snapshots (
  id            text primary key,
  survey_id     text not null references public.sites (id) on delete cascade,
  version       integer not null default 1,
  status        text not null,   -- literal: 'final' (no other status exists yet)
  finalized_by  text not null,   -- role label, e.g. "Engineer" (shared login)
  finalized_at  text not null    -- ISO-8601 string (mirrors SQLite TEXT storage)
);

create index if not exists bom_snapshots_survey_idx
  on public.bom_snapshots (survey_id);

create table if not exists public.bom_snapshot_lines (
  id            text primary key,
  snapshot_id   text not null references public.bom_snapshots (id) on delete cascade,
  sku           text,
  item          text not null,
  material_name text,            -- plain name, no variant suffix (Lumax "Materials")
  item_label    text,            -- short label (Lumax "Item")
  sensor_size   text,            -- enum name; frozen from the source at finalize time
  sensor_type   text,            -- enum name
  unit          text not null,
  qty           double precision not null,
  group_code    text not null,   -- literal: 'A'..'G'
  source        text not null    -- literal: 'auto' | 'manual'
);

create index if not exists bom_snapshot_lines_snapshot_idx
  on public.bom_snapshot_lines (snapshot_id);

alter table public.bom_snapshots      enable row level security;
alter table public.bom_snapshot_lines enable row level security;

drop policy if exists "dev all - bom_snapshots" on public.bom_snapshots;
create policy "dev all - bom_snapshots" on public.bom_snapshots
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "dev all - bom_snapshot_lines" on public.bom_snapshot_lines;
create policy "dev all - bom_snapshot_lines" on public.bom_snapshot_lines
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- BoM revisions — additive delta layers (version 2+) on top of a survey's
-- locked v1 snapshot.
--
-- A revision's own row and its lines never change after creation — a later
-- correction is a NEW revision, not an edit. Like bom_snapshot_lines,
-- bom_revision_lines is NOT linked to material_master_items by id — sku/item/
-- unit are copied in when the picker's dropdown selection is made.
-- `qty_delta` may be negative (reduces the running total for that sku/item).
-- `group_code` stores the literal 'A'..'G' — a revision line is not
-- restricted to D/E/G like bom_manual_entries. The running total itself
-- (v1 snapshot lines + every revision's deltas) is computed on read only;
-- no per-version total is stored anywhere.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

create table if not exists public.bom_revisions (
  id          text primary key,
  survey_id   text not null references public.sites (id) on delete cascade,
  version     integer not null,   -- 2, 3, 4, ... (v1 is bom_snapshots, not this table)
  reason      text not null,      -- required: why this change was made
  created_by  text not null,      -- role label, e.g. "Engineer" (shared login)
  created_at  text not null       -- ISO-8601 string (mirrors SQLite TEXT storage)
);

create index if not exists bom_revisions_survey_idx
  on public.bom_revisions (survey_id);

create table if not exists public.bom_revision_lines (
  id            text primary key,
  revision_id   text not null references public.bom_revisions (id) on delete cascade,
  sku           text,
  item          text not null,
  material_name text,            -- plain name, no variant suffix (Lumax "Materials")
  item_label    text,            -- short label (Lumax "Item")
  sensor_size   text,            -- enum name; frozen from the source at pick time
  sensor_type   text,            -- enum name
  unit          text not null,
  qty_delta     double precision not null,
  group_code    text not null   -- literal: 'A'..'G'
);

create index if not exists bom_revision_lines_revision_idx
  on public.bom_revision_lines (revision_id);

alter table public.bom_revisions      enable row level security;
alter table public.bom_revision_lines enable row level security;

drop policy if exists "dev all - bom_revisions" on public.bom_revisions;
create policy "dev all - bom_revisions" on public.bom_revisions
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "dev all - bom_revision_lines" on public.bom_revision_lines;
create policy "dev all - bom_revision_lines" on public.bom_revision_lines
  for all to anon, authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Lumax export format — Item (short label, distinct from the full
-- descriptive name) and the frozen sensor variant on every line that can
-- feed an export, so sheet-per-variant grouping and the Item/Materials/Size
-- columns don't need to guess at a string split.
--
-- `alter table add column if not exists` covers projects that already ran
-- the blocks above before these columns existed; the `create table`
-- statements above already include them for fresh setups. All nullable, so
-- existing rows are unaffected. Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.material_master_items
  add column if not exists item_label text;

alter table public.bom_manual_entries
  add column if not exists item_label  text,
  add column if not exists sensor_size text,
  add column if not exists sensor_type text;

alter table public.bom_snapshot_lines
  add column if not exists material_name text,
  add column if not exists item_label    text,
  add column if not exists sensor_size   text,
  add column if not exists sensor_type   text;

alter table public.bom_revision_lines
  add column if not exists material_name text,
  add column if not exists item_label    text,
  add column if not exists sensor_size   text,
  add column if not exists sensor_type   text;

-- ---------------------------------------------------------------------------
-- Group C plumbing catalog (uPVC/CPVC fittings) — five columns to drive a
-- 4-level cascading picker (Material Type -> Category -> Variant -> Size) in
-- the "Add materials" screen, instead of the flat single-dropdown every other
-- group still uses.
--
-- `alter table add column if not exists` covers projects that already ran the
-- material_master_items block above before these columns existed; the
-- `create table` above already includes them for fresh setups. All nullable
-- and unset on every existing row (D/E/F/G, and any C row from the earlier
-- Lumax-derived seed) — those keep using the flat picker unaffected.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.material_master_items
  add column if not exists material_type text,
  add column if not exists category      text,
  add column if not exists variant       text,
  add column if not exists size_mm       double precision,
  add column if not exists size_display  text;

-- ---------------------------------------------------------------------------
-- Material Master soft-delete, first attempt (superseded — see the app's
-- deleteMaterialMasterItem / pending_delete handling for the actual
-- mechanism now in place; a real row delete propagates both ways via a
-- genuine `delete`, not this column). Column kept, unused, rather than
-- reversing an already-applied additive migration; safe to ignore.
--
-- `alter table add column if not exists` covers projects that already ran
-- the material_master_items block above before this column existed; the
-- `create table` above already includes it for fresh setups. Nullable and
-- unset on every existing row. Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.material_master_items
  add column if not exists deleted_at text;

-- ---------------------------------------------------------------------------
-- Group A direct material selection — source/inlet point sensor entry
-- becomes a reference to a specific active Group A material_master_items
-- row (by id) instead of abstract sensor_size + sensor_type matching.
-- `on delete set null`: if the referenced material is later hard-deleted,
-- the point reverts to unassigned rather than a dangling id — the app's
-- BomEngine already treats a null/unresolved material_id as needing
-- re-selection before Finalize. sensor_size/sensor_type columns are
-- unchanged: they stay as auto-populated snapshots of the selected
-- material's own values, still read by the generic FIXED-row filter and the
-- wired-sensor DERIVED aggregate, both unrelated to material_id.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.source_points
  add column if not exists material_id text references public.material_master_items (id) on delete set null;

alter table public.inlet_points
  add column if not exists material_id text references public.material_master_items (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 1a: backend foundation only.
--
-- One row per real Supabase Auth user, one-to-one with auth.users (id IS the
-- auth user's id, not a separate identity) and carrying the same 4-role model
-- the app already has (UserRole.name values — see lib/models/user_role.dart).
-- Nothing in the app reads this table yet; that's Slice 1b onward.
--
-- RLS is deliberately NOT enabled/policied here — out of scope for this
-- slice by explicit instruction (see the project's RLS slice, still pending).
-- !! No real employee gets a real account until that slice lands — this table
-- is currently reachable by the anon key with no restriction at all. Only
-- the 1-2 manually-created test accounts from this slice should exist until
-- then. !!
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null,
  role       text not null check (role in ('sales', 'engineer', 'approver', 'admin')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- Auto-creates a profiles row whenever a new auth.users row is inserted (i.e.
-- every time an account is created via the Dashboard's Auth panel), so a
-- fresh Auth user is never left without a matching profile. full_name/role
-- are read from the new user's metadata; otherwise full_name falls back to
-- the email and role to 'engineer' so the insert can never fail the NOT
-- NULL/check constraints above — a failing trigger would abort the
-- auth.users insert itself, since both run in the same transaction.
--
-- WHICH metadata matters, and is a security boundary (Slice 0): `role` is
-- read ONLY from raw_app_meta_data, which a client cannot set. The
-- Dashboard's "User Metadata" box writes raw_user_meta_data and is
-- therefore NO LONGER a way to grant a role — filling it in produces an
-- inactive account, exactly as leaving it blank does. Setting a role by
-- hand now means writing app_metadata (Admin API, or
-- `update auth.users set raw_app_meta_data = ...` in the SQL Editor), or
-- simply correcting profiles.role/active afterwards in the Table Editor as
-- before. The in-app approval flow removes the need for either.
--
-- active defaults to false whenever role metadata wasn't actually supplied
-- (Slice 2c fix — was unconditionally true). Before this, a forgotten
-- "User Metadata" field silently produced a fully active account under the
-- 'engineer' fallback role rather than failing loudly — exactly what
-- happened to the first sales/approver test accounts, which sat as live
-- (if narrowly-scoped) engineer accounts until Slice 2c's own RLS
-- verification caught the mismatch by accident. Now that same mistake
-- makes the account inert instead: _resolveProfile (SupabaseAuthRepository)
-- already rejects an inactive account at sign-in, so a misconfigured
-- account fails to sign in at all rather than silently working under the
-- wrong role. An account created *with* role metadata is unaffected —
-- still active immediately, no new step for the normal path. Whatever an
-- incomplete account lands on, an Admin can always correct full_name/role/
-- active afterwards directly in the Table Editor.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  -- SLICE 0 (security): role is read from raw_APP_meta_data, never from
  -- raw_USER_meta_data.
  --
  -- raw_user_meta_data is populated verbatim from the `data` field of a
  -- client's signUp call, so it is attacker-controlled. Reading `role` from
  -- it meant anyone holding the anon key -- which ships inside the APK, and
  -- with public sign-up enabled -- could create a fully ACTIVE ADMIN by
  -- calling signUp(email, password, data: {'role': 'admin'}). No invite, no
  -- approval, no manual step. That was live.
  --
  -- raw_app_meta_data cannot be set by a client: GoTrue only accepts it via
  -- the Admin API (service_role) or a direct database write, both of which
  -- are already trusted. Moving one word closes the hole without touching
  -- any policy or any other trigger.
  --
  -- full_name deliberately still comes from raw_user_meta_data: it is a
  -- display string, carries no privilege, and letting a user state their own
  -- name is the point.
  meta_role text := new.raw_app_meta_data ->> 'role';
begin
  insert into public.profiles (id, full_name, role, active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email),
    coalesce(meta_role, 'engineer'),
    -- Unchanged, and still the point: no TRUSTED role means the account is
    -- created inactive and cannot sign in (SupabaseAuthRepository
    -- ._resolveProfile rejects it). Hardening the source of `role` makes
    -- this fail-closed default apply to attackers too, not just to an admin
    -- who forgot the metadata field.
    meta_role is not null
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 1c: real account references for assignment.
--
-- assigned_to (the display-name string, above) stays as a denormalized
-- cache; assigned_to_user_id is the real source of truth going forward. Must
-- come after the profiles table above — the FK target has to already exist.
-- `on delete set null`: if an engineer's account is ever hard-deleted, the
-- site reverts to unassigned-by-id rather than leaving a dangling
-- reference; assigned_to (the name snapshot) is untouched either way, same
-- reasoning as material_id's on-delete behavior on source_points/
-- inlet_points. Re-runnable / idempotent.
--
-- survey_assignment_audit is NOT included here — it's local-only (never
-- synced to Supabase, same as the now-retired `engineers` roster table —
-- see SqfliteSurveyRepository's pull-reconcile helper's doc comment for the
-- full list of push-only/local-only tables), so its matching
-- old_assignee_user_id/new_assignee_user_id columns live only in
-- app_database.dart, not here.
-- ---------------------------------------------------------------------------

alter table public.sites
  add column if not exists assigned_to_user_id uuid references public.profiles (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 1d: real account references for attribution.
--
-- The remaining "who did this" fields — who changed a Material Master row,
-- finalized a BoM, added a revision, or added a manual BoM line (not who a
-- survey is assigned to/from — that was 1c's assigned_to_user_id). Each
-- existing label/name column (changed_by_role, finalized_by, created_by,
-- added_by) stays as the denormalized display snapshot; each new
-- *_user_id column is the real source of truth going forward. Same
-- `on delete set null` reasoning as assigned_to_user_id above. Must come
-- after the profiles table — the FK target has to already exist.
--
-- survey_assignment_audit.changed_by_user_id is NOT included here — that
-- table is local-only, same as its 1c-era *_assignee_user_id columns (see
-- the comment on assigned_to_user_id above); it lives only in
-- app_database.dart. Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.material_master_audit
  add column if not exists changed_by_user_id uuid references public.profiles (id) on delete set null;

alter table public.bom_manual_entries
  add column if not exists added_by_user_id uuid references public.profiles (id) on delete set null;

alter table public.bom_snapshots
  add column if not exists finalized_by_user_id uuid references public.profiles (id) on delete set null;

alter table public.bom_revisions
  add column if not exists created_by_user_id uuid references public.profiles (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 2b: lock down profiles RLS.
--
-- profiles has had ZERO RLS policies since Slice 1a (deliberately deferred,
-- with an explicit "!! no real employee gets a real account until this
-- lands !!" warning on that table's own comment block) — meaning any
-- authenticated caller could read every profile and, worse, update ANY
-- profile's role/active columns, including their own (a live privilege-
-- escalation hole). This closes it.
--
-- is_admin() is SECURITY DEFINER, so its internal lookup runs as the
-- function owner and bypasses RLS entirely — this sidesteps the classic
-- self-referential-RLS foot-gun (a policy on `profiles` that subqueries
-- `profiles` to check the caller's own role can work via a plain subquery
-- too, since the "select own row" policy would let that subquery see the
-- caller's own row regardless — but that only holds as long as nobody later
-- tightens the "own row" policy to depend on something else, which would
-- silently break the admin check). A SECURITY DEFINER function has no such
-- fragility, and is reusable by every later RLS slice (2c onward) that also
-- needs an "is this caller an admin / what site can they see" check.
-- `stable` lets the planner cache one evaluation per query instead of
-- re-running it per row. `set search_path = public` matches the same
-- hardening already applied to handle_new_user() — prevents a
-- search_path-hijacking attack against a SECURITY DEFINER function.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- SLICE 1 (security): is this caller a currently-ACTIVE account?
--
-- Before this, `active` was enforced nowhere in the database. It appeared in
-- exactly one policy — "select engineer roster" — and there it filtered WHICH
-- ROWS were listed, not whether the viewer was permitted to act. Every access
-- helper checked `role` alone. Deactivation was therefore a client-side
-- courtesy: SupabaseAuthRepository._resolveProfile signs an inactive user out
-- at login, but a caller that ignores the app and talks to PostgREST directly
-- kept every privilege of its role. A deactivated admin was still an admin to
-- the database.
--
-- SECURITY DEFINER, so the read below bypasses RLS on profiles and cannot
-- recurse when a profiles policy calls it — the same pattern is_admin() has
-- always used in "admin selects any profile".
create or replace function public.is_active_user()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and active
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    -- Slice 1: `and active` — a deactivated admin is not an admin.
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and active
  );
$$;

-- ---------------------------------------------------------------------------
-- ADMIN AND APPROVER ARE DELIBERATELY EQUIVALENT FOR DAY-TO-DAY OPERATIONS.
--
-- Slice 5 final decision by the project owner: the two roles keep separate
-- labels, but there is to be no Admin-vs-Approver capability difference in
-- the operational surface — invite codes, the review queue and its history,
-- Material Master, and BoM revisions. Anywhere an Admin can act on the
-- running application, an Approver can too.
--
-- Its OWN helper rather than reusing is_signup_reviewer() or can_edit_bom(),
-- which happen to cover the same two roles today. Same reasoning that gave
-- is_signup_reviewer() its own function: coupling them means a future change
-- to who may review signups silently changes who may edit Material Master.
-- These are different questions that currently share an answer.
--
-- SECURITY IMPLICATION, stated plainly because it is the whole point:
-- an Approver is now, in practice, an Admin. Combined with the widened
-- may_approve_role() (Approver may grant all four roles, admin included) and
-- read/write access to invite codes, an Approver can mint an invite code,
-- have a request submitted against it, approve that request, and grant it
-- admin — entirely unassisted. The earlier "Approver cannot obtain a code"
-- limit, previously the last structural check on the role, is GONE by
-- deliberate choice. Treat an Approver account as exactly as sensitive as an
-- Admin one when deciding who gets it.
--
-- ONE ASYMMETRY REMAINS, and it is intentional: profiles.role/active can
-- still only be rewritten directly by an Admin ("update own or any as admin"
-- plus prevent_self_role_escalation). No in-app screen uses that path — it
-- exists for Dashboard/SQL-editor administration — so it is not part of the
-- operational surface this helper governs. Widening it would additionally
-- let an Approver re-role or deactivate EXISTING users, which approval flow
-- cannot do.
-- ---------------------------------------------------------------------------
create or replace function public.is_operational_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'approver') and active
  );
$$;

revoke all on function public.is_operational_admin() from public, anon;
grant execute on function public.is_operational_admin() to authenticated, service_role;

alter table public.profiles enable row level security;

-- SELECT: three independent PERMISSIVE policies for the same command, which
-- Postgres OR's together — a caller sees the union of (their own row) OR
-- (any active engineer row — the assign/reassign picker's roster; role and
-- active are the fields that matter for that, and the table's only other
-- columns today are id/full_name/created_at, none of which are sensitive
-- enough to warrant a separate column-restricted view) OR (every row, if
-- they're an admin).
drop policy if exists "select own profile" on public.profiles;
create policy "select own profile" on public.profiles
  for select to authenticated
  using (id = auth.uid());

drop policy if exists "select engineer roster" on public.profiles;
create policy "select engineer roster" on public.profiles
  for select to authenticated
  -- Slice 1: `active = true` here filters WHICH ROWS are listed; it never
  -- said anything about the viewer. Without is_active_user() a deactivated
  -- account could still enumerate every active engineer's name.
  using (role = 'engineer' and active = true and public.is_active_user());

drop policy if exists "admin selects any profile" on public.profiles;
create policy "admin selects any profile" on public.profiles
  for select to authenticated
  using (public.is_operational_admin());

-- UPDATE: row-level gate only (own row, or admin on any row) — RLS
-- USING/WITH CHECK clauses can't restrict which *columns* an UPDATE touches,
-- only which *rows* it's allowed to target. Column-level restriction (a
-- non-admin may change full_name but never role/active, even on their own
-- row) is enforced below by prevent_self_role_escalation, a trigger — the
-- only mechanism that can actually inspect NEW vs OLD per column. (Postgres
-- does support column-level GRANTs, e.g. `grant update (full_name)`, but
-- those apply per Postgres *role* — every human user here shares the same
-- `authenticated` role, so a GRANT can't distinguish "this authenticated
-- user is admin" from "this one isn't"; only a row-aware check like this
-- trigger can.)
drop policy if exists "update own or any as admin" on public.profiles;
create policy "update own or any as admin" on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

create or replace function public.prevent_self_role_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null outside a real PostgREST-authenticated request — the
  -- SQL Editor, Table Editor, a migration script, or any other direct
  -- connection (all of which already bypass RLS entirely as the table
  -- owner/superuser; a trigger doesn't inherit that bypass automatically,
  -- since triggers always fire regardless of RLS bypass status, so it needs
  -- its own explicit check here). This rule only ever means to constrain a
  -- real signed-in non-admin's own app requests, never trusted direct DB
  -- access — without this, correcting a test account's role via Table
  -- Editor would trip the same exception below.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.role is distinct from old.role or new.active is distinct from old.active then
    raise exception 'Only an admin can change role or active.';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_self_role_escalation on public.profiles;
create trigger prevent_self_role_escalation
  before update on public.profiles
  for each row execute function public.prevent_self_role_escalation();

-- INSERT / DELETE: no policy for either — RLS default-denies a command with
-- no matching permissive policy, for every role. This is intentional, not
-- an oversight:
--   INSERT: the only current path that creates a profiles row is
--   handle_new_user() (Slice 1a), a SECURITY DEFINER trigger on auth.users
--   that runs as its owner and so bypasses RLS on profiles entirely — it
--   keeps working unaffected. No app code inserts into profiles directly.
--   DELETE: the app never deletes a profile. Deactivate via `active = false`
--   instead (already enforced as admin-only above), consistent with the
--   pending_delete/tombstone convention used everywhere else in this
--   schema. An actual account removal happens by deleting the auth.users
--   row via the Dashboard (service_role, bypasses RLS) or the future
--   Edge-Function-based admin flow — the `on delete cascade` FK already
--   removes the matching profiles row automatically when that happens.
--
-- anon is deliberately not granted on any of the policies above — the app
-- only ever queries Supabase after a real sign-in, so every legitimate
-- request already carries an authenticated session; anon access here would
-- just mean anyone holding the publishable key (baked into the APK) could
-- read/write profiles with no session at all.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 2c: real RLS for sites, blocks, client_inputs.
--
-- Replaces every "dev all" placeholder on these three tables with the
-- actual permission model: Engineer sees/edits only their own assigned
-- site; Sales, Approver, and Admin all see and edit every site (Sales has
-- no created_by column to scope by, and isn't getting one — confirmed
-- decision; Approver gets edit rights here too, not view-only — also a
-- confirmed decision, distinct from the app UI's own separate readOnly
-- flag on Approver's review screen, which is unaffected by this and still
-- applies at the UI layer).
--
-- is_site_manager() bundles the three full-access roles into one reusable
-- check (SECURITY DEFINER, same reasoning as is_admin() in Slice 2b — its
-- internal profiles lookup bypasses RLS entirely, so no self-referential
-- fragility). can_access_site(id) bundles "is a site manager, OR is the
-- engineer this specific site is assigned to" — this is the exact rule
-- blocks/client_inputs need to inherit from their parent site via EXISTS,
-- and is written now so Slice 2d's five site-cascading tables
-- (source_points, inlet_points, duct_loras, gateways, footers) can reuse it
-- unchanged rather than re-deriving the same join.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

create or replace function public.is_site_manager()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    -- Slice 1: `and active` — a deactivated manager is not a manager.
    select 1 from public.profiles
    where id = auth.uid() and role in ('sales', 'approver', 'admin')
      and active
  );
$$;

create or replace function public.can_access_site(target_site_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    -- Slice 1: is_active_user() gates BOTH branches. The
    -- assigned_to_user_id one compares auth.uid() directly and so never
    -- passed through is_site_manager()'s new `active` check.
    select 1 from public.sites
    where id = target_site_id
      and public.is_active_user()
      and (assigned_to_user_id = auth.uid() or public.is_site_manager())
  );
$$;

-- ---- sites ------------------------------------------------------------

drop policy if exists "dev all - sites" on public.sites;

drop policy if exists "engineer selects own assigned sites" on public.sites;
create policy "engineer selects own assigned sites" on public.sites
  for select to authenticated
  -- Slice 1: compares auth.uid() directly, so it never touched any role
  -- helper and an inactive engineer kept reading their assigned sites.
  using (assigned_to_user_id = auth.uid() and public.is_active_user());

drop policy if exists "site managers select all sites" on public.sites;
create policy "site managers select all sites" on public.sites
  for select to authenticated
  using (public.is_site_manager());

-- Row-level gate only: an engineer may UPDATE a row iff it's currently
-- assigned to them (`using`) AND it's still assigned to them afterward
-- (`with check`) — which already blocks them from reassigning a site away
-- from themselves (assigned_to_user_id changing would fail `with check`
-- for anyone who isn't a site manager). It does NOT stop them changing
-- `name` or the display-string `assigned_to` while leaving
-- `assigned_to_user_id` untouched, though — column-level restriction needs
-- the trigger below, same reasoning as profiles' role/active in Slice 2b.
drop policy if exists "update sites" on public.sites;
create policy "update sites" on public.sites
  for update to authenticated
  -- Slice 1: the is_active_user() conjunct is OUTSIDE the parentheses so it
  -- gates both branches. Written as `A and (B or C)`, never `A and B or C`,
  -- which Postgres would read as `(A and B) or C` and leave the manager
  -- branch ungated.
  using (public.is_active_user()
         and (assigned_to_user_id = auth.uid() or public.is_site_manager()))
  with check (public.is_active_user()
              and (assigned_to_user_id = auth.uid()
                   or public.is_site_manager()));

create or replace function public.prevent_engineer_site_reassignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null outside a real PostgREST-authenticated request — see
  -- the matching guard/comment on prevent_self_role_escalation (Slice 2b)
  -- for why this needs its own explicit check: without it, any direct SQL
  -- Editor/Table Editor write to sites (e.g. test setup, ad-hoc admin
  -- fixes) trips the exception below even though it's trusted, not-an-
  -- engineer access.
  if auth.uid() is null or public.is_site_manager() then
    return new;
  end if;
  -- Engineer: only status/bom_locked (survey progress — set by the app's
  -- own "start work"/"submit"/finalize actions) may change on their own
  -- assigned site. name/assigned_to/assigned_to_user_id stay Sales/
  -- Approver/Admin-only, even though row-level ownership above already let
  -- the UPDATE reach this row at all.
  if new.name is distinct from old.name
      or new.assigned_to is distinct from old.assigned_to
      or new.assigned_to_user_id is distinct from old.assigned_to_user_id then
    raise exception 'Engineers may only update survey progress fields on their own site, not its identity or assignment.';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_engineer_site_reassignment on public.sites;
create trigger prevent_engineer_site_reassignment
  before update on public.sites
  for each row execute function public.prevent_engineer_site_reassignment();

-- INSERT: Sales/Approver/Admin only — an Engineer never creates a survey,
-- only works an already-assigned one.
drop policy if exists "site managers insert sites" on public.sites;
create policy "site managers insert sites" on public.sites
  for insert to authenticated
  with check (public.is_site_manager());

-- DELETE: no policy at all, for anyone — RLS default-denies with no
-- matching permissive policy. The app never hard-deletes a site; Sales'
-- "Delete site" sets the `archived` flag (a normal synced column as of
-- Full sync Group 1 — see below), so there is no legitimate DELETE to
-- allow here.

-- ---- blocks, client_inputs ---------------------------------------------
--
-- Both inherit sites' access exactly via can_access_site(site_id), and both
-- use `for all` (not just SELECT/UPDATE) because of how the app actually
-- writes them: blocks has no stable per-row id in the domain model, so
-- every edit deletes the site's full block set and reinserts it (needs
-- DELETE + INSERT, not UPDATE at all); client_inputs is upserted
-- (`site_id` is its primary key), which PostgREST/Postgres can resolve as
-- either an INSERT or an UPDATE per row depending on whether it already
-- exists, so both policies are needed for a single upsert() call to work
-- regardless of which path Postgres takes. Neither table has an identity/
-- assignment column of its own, so — unlike sites — no additional
-- column-level trigger is needed: every field on both tables is exactly
-- the kind of "survey progress" data an assigned Engineer should be able
-- to freely read and write.

drop policy if exists "dev all - blocks" on public.blocks;
drop policy if exists "access blocks via site" on public.blocks;
create policy "access blocks via site" on public.blocks
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "dev all - client_inputs" on public.client_inputs;
drop policy if exists "access client_inputs via site" on public.client_inputs;
create policy "access client_inputs via site" on public.client_inputs
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

-- anon is deliberately not granted anywhere above — same reasoning as
-- Slice 2b's profiles policies.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 2d: real RLS for source_points, inlet_points,
-- duct_loras, gateways, footers.
--
-- All five cascade from sites via site_id (footers' site_id is its own
-- primary key, same shape as client_inputs; the other four are a regular
-- FK column) — same access rule as Slice 2c's blocks/client_inputs,
-- reusing can_access_site(site_id) unchanged rather than re-deriving it.
-- `for all` (not just SELECT/UPDATE/INSERT) for the same reason blocks
-- needed it in 2c: source_points/inlet_points/duct_loras/gateways delete
-- via the pending_delete tombstone convention (an UPDATE to set the flag,
-- then a real DELETE once sync confirms the remote side is gone —
-- see SqfliteSurveyRepository's deleteSourcePoint/deleteInletPoint/
-- deleteDuctLora/deleteGateway and SyncService.pushAll's matching
-- getPendingDeleteXIds/hardDeleteX pairs), so DELETE needs to be permitted
-- too, not just the three read/write operations. footers has no delete
-- feature at all, but including it costs nothing and keeps all five
-- tables' policies identical rather than special-casing one.
--
-- duct_loras/gateways' delete-propagation (tombstone, not a bare local
-- hard-delete) was flagged as a gap earlier this session but is already
-- fixed — confirmed directly against current code, not assumed: both
-- deleteDuctLora/deleteGateway already set pending_delete/dirty exactly
-- like deleteSourcePoint/deleteInletPoint, and pushAll already has the
-- matching getPendingDeleteDuctLoraIds/hardDeleteDuctLora and
-- getPendingDeleteGatewayIds/hardDeleteGateway pairs. Nothing new needed
-- here beyond RLS.
--
-- reconcileDeletes on all five tables' pull already defaults to false
-- (Slice 2b-prereq) — confirmed none of their upsertXFromRemote callers
-- pass true, so absence-based local deletion is already off; this slice
-- doesn't need to touch that.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

drop policy if exists "dev all - source_points" on public.source_points;
drop policy if exists "access source_points via site" on public.source_points;
create policy "access source_points via site" on public.source_points
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "dev all - inlet_points" on public.inlet_points;
drop policy if exists "access inlet_points via site" on public.inlet_points;
create policy "access inlet_points via site" on public.inlet_points
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "dev all - duct_loras" on public.duct_loras;
drop policy if exists "access duct_loras via site" on public.duct_loras;
create policy "access duct_loras via site" on public.duct_loras
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "dev all - gateways" on public.gateways;
drop policy if exists "access gateways via site" on public.gateways;
create policy "access gateways via site" on public.gateways
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "dev all - footers" on public.footers;
drop policy if exists "access footers via site" on public.footers;
create policy "access footers via site" on public.footers
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

-- anon is deliberately not granted anywhere above — same reasoning as
-- Slice 2b's profiles policies.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 2e: real RLS for photos.
--
-- photos has no direct site reference — only a polymorphic (owner_type,
-- owner_id) link (source_point | inlet_point | gateway | footer |
-- duct_lora | client_inputs), so a correct RLS policy would otherwise need
-- to branch per owner_type and, for four of the six, join through that
-- owner's own table to reach site_id. Denormalizing a direct site_id
-- column instead (same reasoning already used for sites.assigned_to_user_id
-- and every attribution field) keeps this table on the exact same
-- can_access_site(site_id) rule as every other site-cascading table, no
-- special-casing. client_inputs/footer already use the site's own id as
-- owner_id, so their site_id is that value directly; the other four need
-- one hop through their own table. Backfills every existing row; a photo
-- whose owner no longer exists (should be rare — every delete path already
-- removes its own photos transactionally) is left with a null site_id
-- rather than guessed at — such a row becomes invisible under RLS to
-- everyone, including Admin, until reconciled by hand. `on delete cascade`
-- matches every other child-of-sites table here (source_points,
-- inlet_points, ...), not the `on delete set null` used for
-- assigned_to_user_id/attribution fields — those reference profiles
-- (an account going away shouldn't take a site with it), this references
-- sites itself (a site going away should take its photos with it, same as
-- every other child row already does).
--
-- Every write site already has the owning Site in scope (every photo-
-- capturing form receives a [Site]), so this is always set going forward
-- — see SurveyPhoto.siteId / app_database.dart's local v25->v26 migration
-- for the matching local-side backfill.
--
-- Only SELECT/INSERT/UPDATE get policies, not `for all` like the other
-- site-cascading tables in Slices 2c/2d — confirmed directly against
-- current code that no app path ever issues a remote DELETE on photos, so
-- there's nothing legitimate for a DELETE policy to allow; RLS
-- default-denies a command with no matching permissive policy.
--
-- The survey-photos Storage bucket itself (where the actual image bytes
-- live) is explicitly out of scope here — its own "dev all" policies are
-- Slice 2h, which depends on this table's site_id being correct first.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.photos
  add column if not exists site_id text references public.sites (id) on delete cascade;

update public.photos set site_id = owner_id
where owner_type in ('client_inputs', 'footer') and site_id is null;

update public.photos set site_id = source_points.site_id
from public.source_points
where photos.owner_type = 'source_point'
  and photos.owner_id = source_points.id
  and photos.site_id is null;

update public.photos set site_id = inlet_points.site_id
from public.inlet_points
where photos.owner_type = 'inlet_point'
  and photos.owner_id = inlet_points.id
  and photos.site_id is null;

update public.photos set site_id = gateways.site_id
from public.gateways
where photos.owner_type = 'gateway'
  and photos.owner_id = gateways.id
  and photos.site_id is null;

update public.photos set site_id = duct_loras.site_id
from public.duct_loras
where photos.owner_type = 'duct_lora'
  and photos.owner_id = duct_loras.id
  and photos.site_id is null;

drop policy if exists "dev all - photos" on public.photos;

drop policy if exists "select photos via site" on public.photos;
create policy "select photos via site" on public.photos
  for select to authenticated
  using (public.can_access_site(site_id));

drop policy if exists "insert photos via site" on public.photos;
create policy "insert photos via site" on public.photos
  for insert to authenticated
  with check (public.can_access_site(site_id));

drop policy if exists "update photos via site" on public.photos;
create policy "update photos via site" on public.photos
  for update to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

-- DELETE: no policy at all — see the doc block above for why.

-- anon is deliberately not granted anywhere above — same reasoning as
-- Slice 2b's profiles policies.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 2f: real RLS for BoM data, plus the missing
-- bom_manual_edit_snapshots / bom_manual_edit_snapshot_lines tables.
--
-- bom_manual_edit_snapshots and bom_manual_edit_snapshot_lines never existed
-- remotely — every "Edit BoM" action (see BomPreviewScreen.canEditBom,
-- restricted in the app to Admin/Approver) has been syncing to nowhere since
-- that feature shipped: SyncService already pushes both tables and
-- SupabaseSurveyDataSource already has pushBomManualEditSnapshot(Line), all
-- silently failing per-row (relation does not exist) every sync. Column sets
-- below are copied exactly from app_database.dart's
-- _createBomManualEditSnapshotsTable / _createBomManualEditSnapshotLinesTable
-- (minus the local-only `dirty` column) — this is a wire-format contract
-- with SupabaseSurveyDataSource's _bomManualEditSnapshot(Line)ToRemoteRow,
-- not a free design choice. Note there's no edited_by_user_id (unlike
-- finalized_by_user_id / created_by_user_id on the other BoM tables) —
-- the local schema and Dart model never grew one, so real-user attribution
-- for manual edits is a pre-existing gap, not something this slice
-- introduces or is scoped to fix.
--
-- Access model for all 7 tables (5 pre-existing + 2 new):
--   * SELECT: can_access_site() via survey_id (or two-hop through the
--     parent row for the three line/child tables) — Engineer sees their own
--     site, Sales/Approver/Admin see everything. Same shape as every
--     site-cascading table since Slice 2c.
--   * INSERT/UPDATE on bom_manual_entries, bom_snapshots, bom_snapshot_lines:
--     same can_access_site() — no narrower rule requested for these; an
--     Engineer building/finalizing their own site's BoM is exactly the
--     existing app flow.
--   * INSERT/UPDATE on bom_revisions, bom_revision_lines: narrower —
--     can_create_bom_revision() — only the survey's assigned Engineer or
--     Admin (D6: not Sales, not Approver, even though they can SELECT/view).
--   * INSERT/UPDATE on bom_manual_edit_snapshots,
--     bom_manual_edit_snapshot_lines: narrower still — can_edit_bom() —
--     only Admin/Approver, matching canEditBom in the app (site_hub_screen.
--     dart / approver_review_screen.dart). No site-membership check beyond
--     the role itself: Admin/Approver already have blanket site access via
--     is_site_manager(), same as everywhere else.
--   * UPDATE is granted with the same predicate as INSERT on every one of
--     these tables even though the app treats each row as immutable after
--     creation (never edits content) — every push goes through .upsert(),
--     so a sync interrupted after the remote insert succeeded but before the
--     local dirty flag cleared retries as an UPDATE (ON CONFLICT DO UPDATE)
--     of byte-identical content next time. Without an UPDATE policy that
--     retry would fail forever. This mirrors the "for all" grants every
--     earlier slice used for the same reason — it's not a new allowance for
--     genuine edits.
--   * DELETE: bom_manual_entries is the one table here with a real delete
--     path (BomGroupManualSectionScreen — removing a manual line before
--     finalize; confirmed via SupabaseSurveyDataSource.deleteBomManualEntry
--     and its pending_delete tombstone push in SyncService) — scoped the
--     same as its other commands. The other 6 tables have no delete
--     anywhere in the app (confirmed: SupabaseSurveyDataSource defines no
--     delete method for any of them) — no DELETE policy at all, reflecting
--     that immutability directly instead of leaving it as an unenforced
--     convention.
--
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

create table if not exists public.bom_manual_edit_snapshots (
  id               text primary key,
  survey_id        text not null references public.sites (id) on delete cascade,
  version          integer not null,
  based_on_version integer not null,
  edited_by        text not null,
  edited_at        text not null,
  reason           text
);

create index if not exists bom_manual_edit_snapshots_survey_idx
  on public.bom_manual_edit_snapshots (survey_id);

create table if not exists public.bom_manual_edit_snapshot_lines (
  id          text primary key,
  snapshot_id text not null references public.bom_manual_edit_snapshots (id) on delete cascade,
  sku         text,
  item_name   text not null,
  description text,
  unit        text not null,
  qty         double precision not null,
  group_code  text not null
);

create index if not exists bom_manual_edit_snapshot_lines_snapshot_idx
  on public.bom_manual_edit_snapshot_lines (snapshot_id);

alter table public.bom_manual_edit_snapshots      enable row level security;
alter table public.bom_manual_edit_snapshot_lines enable row level security;

-- ---- helper functions ------------------------------------------------

-- Two-hop visibility: a bom_snapshot_lines/bom_revision_lines/
-- bom_manual_edit_snapshot_lines row is visible iff its parent row's own
-- site is. SECURITY DEFINER so the lookup on the parent table runs
-- independent of (and isn't circularly gated by) that table's own RLS.
create or replace function public.can_access_bom_snapshot(target_snapshot_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.bom_snapshots
    where id = target_snapshot_id
      and public.can_access_site(survey_id)
  );
$$;

create or replace function public.can_access_bom_revision(target_revision_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.bom_revisions
    where id = target_revision_id
      and public.can_access_site(survey_id)
  );
$$;

create or replace function public.can_access_bom_manual_edit_snapshot(target_snapshot_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.bom_manual_edit_snapshots
    where id = target_snapshot_id
      and public.can_access_site(survey_id)
  );
$$;

-- D6: a bom_revision may only be created by the survey's assigned Engineer
-- or Admin — narrower than can_access_site() (which also passes for
-- Sales/Approver, who may SELECT revisions but not create them).
create or replace function public.can_create_bom_revision(target_site_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    -- Slice 1: same reasoning as can_access_site — the assigned_to_user_id
    -- branch compares auth.uid() directly and so bypasses the role helper's
    -- own `active` check, hence the explicit is_active_user() conjunct.
    --
    -- Slice 5: was is_admin(); widened to is_operational_admin() so Approver
    -- matches Admin. This also FIXED a live mismatch — BomPreviewScreen's
    -- "Add revision" FAB is gated on `locked` only, never on role, so an
    -- Approver was already being offered the action while the database
    -- refused the write.
    select 1 from public.sites
    where id = target_site_id
      and public.is_active_user()
      and (assigned_to_user_id = auth.uid() or public.is_operational_admin())
  );
$$;

-- Same D6 rule, one hop down for bom_revision_lines — the revision's own
-- creator (or Admin), not just anyone who can see the revision.
create or replace function public.can_create_bom_revision_line(target_revision_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.bom_revisions
    where id = target_revision_id
      and public.can_create_bom_revision(survey_id)
  );
$$;

-- "Edit BoM" (bom_manual_edit_snapshots/lines) is Admin/Approver only in the
-- app (BomPreviewScreen.canEditBom) — both roles already have blanket site
-- access via is_site_manager(), so this is a role check alone, no site_id
-- parameter needed.
create or replace function public.can_edit_bom()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    -- Slice 1: `and active`.
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'approver') and active
  );
$$;

-- ---- bom_manual_entries ------------------------------------------------

drop policy if exists "dev all - bom_manual_entries" on public.bom_manual_entries;

drop policy if exists "select bom_manual_entries via site" on public.bom_manual_entries;
create policy "select bom_manual_entries via site" on public.bom_manual_entries
  for select to authenticated
  using (public.can_access_site(survey_id));

drop policy if exists "insert bom_manual_entries via site" on public.bom_manual_entries;
create policy "insert bom_manual_entries via site" on public.bom_manual_entries
  for insert to authenticated
  with check (public.can_access_site(survey_id));

drop policy if exists "update bom_manual_entries via site" on public.bom_manual_entries;
create policy "update bom_manual_entries via site" on public.bom_manual_entries
  for update to authenticated
  using (public.can_access_site(survey_id))
  with check (public.can_access_site(survey_id));

drop policy if exists "delete bom_manual_entries via site" on public.bom_manual_entries;
create policy "delete bom_manual_entries via site" on public.bom_manual_entries
  for delete to authenticated
  using (public.can_access_site(survey_id));

-- ---- bom_snapshots / bom_snapshot_lines (no DELETE — see doc block) ----

drop policy if exists "dev all - bom_snapshots" on public.bom_snapshots;

drop policy if exists "select bom_snapshots via site" on public.bom_snapshots;
create policy "select bom_snapshots via site" on public.bom_snapshots
  for select to authenticated
  using (public.can_access_site(survey_id));

drop policy if exists "insert bom_snapshots via site" on public.bom_snapshots;
create policy "insert bom_snapshots via site" on public.bom_snapshots
  for insert to authenticated
  with check (public.can_access_site(survey_id));

drop policy if exists "update bom_snapshots via site" on public.bom_snapshots;
create policy "update bom_snapshots via site" on public.bom_snapshots
  for update to authenticated
  using (public.can_access_site(survey_id))
  with check (public.can_access_site(survey_id));

drop policy if exists "dev all - bom_snapshot_lines" on public.bom_snapshot_lines;

drop policy if exists "select bom_snapshot_lines via snapshot" on public.bom_snapshot_lines;
create policy "select bom_snapshot_lines via snapshot" on public.bom_snapshot_lines
  for select to authenticated
  using (public.can_access_bom_snapshot(snapshot_id));

drop policy if exists "insert bom_snapshot_lines via snapshot" on public.bom_snapshot_lines;
create policy "insert bom_snapshot_lines via snapshot" on public.bom_snapshot_lines
  for insert to authenticated
  with check (public.can_access_bom_snapshot(snapshot_id));

drop policy if exists "update bom_snapshot_lines via snapshot" on public.bom_snapshot_lines;
create policy "update bom_snapshot_lines via snapshot" on public.bom_snapshot_lines
  for update to authenticated
  using (public.can_access_bom_snapshot(snapshot_id))
  with check (public.can_access_bom_snapshot(snapshot_id));

-- ---- bom_revisions / bom_revision_lines (D6 narrower INSERT/UPDATE) ----

drop policy if exists "dev all - bom_revisions" on public.bom_revisions;

drop policy if exists "select bom_revisions via site" on public.bom_revisions;
create policy "select bom_revisions via site" on public.bom_revisions
  for select to authenticated
  using (public.can_access_site(survey_id));

drop policy if exists "insert bom_revisions by assigned engineer" on public.bom_revisions;
create policy "insert bom_revisions by assigned engineer" on public.bom_revisions
  for insert to authenticated
  with check (public.can_create_bom_revision(survey_id));

drop policy if exists "update bom_revisions by assigned engineer" on public.bom_revisions;
create policy "update bom_revisions by assigned engineer" on public.bom_revisions
  for update to authenticated
  using (public.can_create_bom_revision(survey_id))
  with check (public.can_create_bom_revision(survey_id));

drop policy if exists "dev all - bom_revision_lines" on public.bom_revision_lines;

drop policy if exists "select bom_revision_lines via revision" on public.bom_revision_lines;
create policy "select bom_revision_lines via revision" on public.bom_revision_lines
  for select to authenticated
  using (public.can_access_bom_revision(revision_id));

drop policy if exists "insert bom_revision_lines by assigned engineer" on public.bom_revision_lines;
create policy "insert bom_revision_lines by assigned engineer" on public.bom_revision_lines
  for insert to authenticated
  with check (public.can_create_bom_revision_line(revision_id));

drop policy if exists "update bom_revision_lines by assigned engineer" on public.bom_revision_lines;
create policy "update bom_revision_lines by assigned engineer" on public.bom_revision_lines
  for update to authenticated
  using (public.can_create_bom_revision_line(revision_id))
  with check (public.can_create_bom_revision_line(revision_id));

-- ---- bom_manual_edit_snapshots / _lines (Admin/Approver-only write) ----

drop policy if exists "select bom_manual_edit_snapshots via site" on public.bom_manual_edit_snapshots;
create policy "select bom_manual_edit_snapshots via site" on public.bom_manual_edit_snapshots
  for select to authenticated
  using (public.can_access_site(survey_id));

drop policy if exists "insert bom_manual_edit_snapshots by editor" on public.bom_manual_edit_snapshots;
create policy "insert bom_manual_edit_snapshots by editor" on public.bom_manual_edit_snapshots
  for insert to authenticated
  with check (public.can_edit_bom());

drop policy if exists "update bom_manual_edit_snapshots by editor" on public.bom_manual_edit_snapshots;
create policy "update bom_manual_edit_snapshots by editor" on public.bom_manual_edit_snapshots
  for update to authenticated
  using (public.can_edit_bom())
  with check (public.can_edit_bom());

drop policy if exists "select bom_manual_edit_snapshot_lines via snapshot" on public.bom_manual_edit_snapshot_lines;
create policy "select bom_manual_edit_snapshot_lines via snapshot" on public.bom_manual_edit_snapshot_lines
  for select to authenticated
  using (public.can_access_bom_manual_edit_snapshot(snapshot_id));

drop policy if exists "insert bom_manual_edit_snapshot_lines by editor" on public.bom_manual_edit_snapshot_lines;
create policy "insert bom_manual_edit_snapshot_lines by editor" on public.bom_manual_edit_snapshot_lines
  for insert to authenticated
  with check (public.can_edit_bom());

drop policy if exists "update bom_manual_edit_snapshot_lines by editor" on public.bom_manual_edit_snapshot_lines;
create policy "update bom_manual_edit_snapshot_lines by editor" on public.bom_manual_edit_snapshot_lines
  for update to authenticated
  using (public.can_edit_bom())
  with check (public.can_edit_bom());

-- anon is deliberately not granted anywhere above — same reasoning as
-- Slice 2b's profiles policies.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 2g: real RLS for material_master_items and
-- material_master_audit.
--
-- material_master_items is the one table in this whole schema where SELECT
-- stays unconditional for every authenticated role, not scoped by site or
-- role: every device needs the complete active catalog for on-device BoM
-- generation (auto Group A matching, cascade/flat pickers —
-- BomEngine/pickers themselves untouched by this slice). It's also the one
-- table whose pull (SqfliteSurveyRepository.upsertMaterialMasterItemsFromRemote,
-- confirmed NOT routed through the shared _pullAndReconcile helper and its
-- reconcileDeletes flag — it's unconditional there by design) treats a row
-- absent from the fetch as deleted and removes it locally. That reconcile
-- logic depends on the fetch being genuinely complete for whoever runs it —
-- narrowing SELECT for any role here would make Material Master rows
-- silently vanish from that role's device on next sync. This slice leaves
-- that pull code untouched and keeps SELECT unconditional specifically so
-- reconcileDeletes stays correct; it isn't a gap to close.
--
-- Write access is Admin-only for both tables — confirmed against the app,
-- not assumed: home_screen.dart only shows the "Material Master" menu entry
-- `if (widget.session.currentRole == UserRole.admin)`, so it's the sole
-- entry point that can ever create/edit/delete a material_master_items row
-- or, as a side effect of those same repository calls
-- (SqfliteSurveyRepository's _writeMaterialMasterAudit, called from the
-- create/update/delete paths directly, not a DB trigger), write a
-- material_master_audit row. Both tables' delete path is a genuine SQL
-- DELETE (deleteMaterialMasterItem) via the same pending_delete tombstone
-- convention as every other table — material_master_items.deleted_at is
-- dead/unused (see its own column comment above).
--
-- material_master_audit gets no UPDATE policy at all, unlike every other
-- "immutable" table in this schema (bom_revisions, bom_snapshots, ...) —
-- those got a same-predicate UPDATE policy purely so a sync retry's
-- ON CONFLICT DO UPDATE (from .upsert()) doesn't fail forever after a crash
-- between the remote insert succeeding and the local dirty flag clearing.
-- material_master_audit is pushed via pushMaterialMasterAuditEntry, which
-- also .upsert()s, so it has the exact same retry gap: an interrupted sync
-- would leave that one row permanently failing (shown as a skipped row on
-- every future sync, retried and rejected each time) rather than
-- self-healing like the BoM tables do. That's a deliberate tradeoff, not an
-- oversight — an audit log gains real integrity value from being
-- mechanically un-updatable by anyone, including its own writer, and this
-- retry gap is a rare, non-destructive edge case (a stuck row, not data
-- loss) rather than a correctness bug.
--
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

drop policy if exists "dev all - material_master_items" on public.material_master_items;

drop policy if exists "select material_master_items for everyone" on public.material_master_items;
create policy "select material_master_items for everyone" on public.material_master_items
  for select to authenticated
  -- Slice 1: was `using (true)`, so ANY authenticated caller — including a
  -- deactivated or not-yet-approved account — could read the entire
  -- catalogue. "Everyone" now means every ACTIVE user; the intent (no
  -- role/site scoping) is unchanged.
  using (public.is_active_user());

drop policy if exists "insert material_master_items by admin" on public.material_master_items;
create policy "insert material_master_items by admin" on public.material_master_items
  for insert to authenticated
  with check (public.is_operational_admin());

drop policy if exists "update material_master_items by admin" on public.material_master_items;
create policy "update material_master_items by admin" on public.material_master_items
  for update to authenticated
  using (public.is_operational_admin())
  with check (public.is_operational_admin());

drop policy if exists "delete material_master_items by admin" on public.material_master_items;
create policy "delete material_master_items by admin" on public.material_master_items
  for delete to authenticated
  using (public.is_operational_admin());

drop policy if exists "dev all - material_master_audit" on public.material_master_audit;

drop policy if exists "select material_master_audit by admin" on public.material_master_audit;
create policy "select material_master_audit by admin" on public.material_master_audit
  for select to authenticated
  using (public.is_operational_admin());

drop policy if exists "insert material_master_audit by admin" on public.material_master_audit;
create policy "insert material_master_audit by admin" on public.material_master_audit
  for insert to authenticated
  with check (public.is_operational_admin());

-- No UPDATE, no DELETE on material_master_audit — see the doc block above.

-- anon is deliberately not granted anywhere above — same reasoning as
-- Slice 2b's profiles policies.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Per-user auth — Slice 2h: real RLS for storage.objects (survey-photos
-- bucket) — the last wide-open surface.
--
-- Join key: an object's name IS the photos table's remote_path for that row
-- — set to the deterministic `photos/<photo.id>.jpg` the moment a photo is
-- pushed (see SyncService._pushGenericPhoto and
-- SupabaseSurveyDataSource.uploadPhoto's caller) — so
-- can_access_photo_object(name) below just looks up the one photos row
-- with remote_path = name and defers to that row's own site_id via
-- can_access_site(), exactly like every other Slice 2e/2f/2g helper.
--
-- Ordering dependency this slice depends on: _pushGenericPhoto now pushes
-- the photos metadata row (already carrying remote_path and site_id)
-- *before* the actual Storage upload, not after like it used to. The object
-- key is deterministic and known upfront, so this reorder is safe — but
-- it's required: with the old order (upload first, metadata row second),
-- can_access_photo_object(name) would find no matching row yet at upload
-- time and reject every photo's very first upload.
--
-- The bucket itself is flipped from public to private here
-- (update storage.buckets ... public = false) — this is not optional
-- alongside the RLS below. A Supabase Storage bucket with public = true
-- serves every object via an unauthenticated /object/public/... URL that
-- completely bypasses storage.objects RLS; leaving it public would make
-- every policy below pure theater; anyone with (or able to guess) an
-- object's URL could still fetch it directly. Confirmed via a full grep of
-- lib/ that the app never actually fetches a photo back from Storage today
-- (no getPublicUrl / createSignedUrl / Image.network anywhere — every photo
-- view in the app reads SurveyPhoto.localPath, the on-device file) — so
-- this flip has no visible effect on current app behavior. Any future
-- feature that displays a remote photo (e.g. Sales/Approver viewing one
-- without the originating device) will need an authenticated download or a
-- signed URL, not a public link.
--
-- Only SELECT and INSERT get policies — confirmed via grep that the app's
-- only Storage call anywhere is the single .storage.from(photoBucket).upload
-- in SupabaseSurveyDataSource.uploadPhoto (no .remove()/.update()/.move()),
-- consistent with the "no delete feature" finding from Slice 2e. Also
-- confirmed survey-photos is the only bucket referenced anywhere in this
-- schema or the app.
--
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

update storage.buckets set public = false where id = 'survey-photos';

create or replace function public.can_access_photo_object(object_name text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.photos
    where remote_path = object_name
      and public.can_access_site(site_id)
  );
$$;

drop policy if exists "dev all - survey-photos read" on storage.objects;
drop policy if exists "dev all - survey-photos write" on storage.objects;
drop policy if exists "dev all - survey-photos update" on storage.objects;

drop policy if exists "select survey-photos via site" on storage.objects;
create policy "select survey-photos via site" on storage.objects
  for select to authenticated
  using (bucket_id = 'survey-photos' and public.can_access_photo_object(name));

drop policy if exists "insert survey-photos via site" on storage.objects;
create policy "insert survey-photos via site" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'survey-photos' and public.can_access_photo_object(name));

-- No UPDATE, no DELETE — see the doc block above.

-- anon is deliberately not granted anywhere above — same reasoning as
-- Slice 2b's profiles policies.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Full sync Group 1 — sites.archived becomes a real synced column.
--
-- "Delete site" has only ever set this locally (see the DELETE-policy
-- comment on sites above, and SqfliteSurveyRepository's pull-reconcile doc —
-- both now stale, kept only as history of why sites had no DELETE policy in
-- the first place: there is still no genuine row delete to allow, archived
-- just becomes a normal synced field like any other on the row). No RLS
-- change needed: sites' existing UPDATE policy (site-scoped via
-- can_access_site/is_site_manager) and prevent_engineer_site_reassignment
-- trigger (which only restricts name/assigned_to/assigned_to_user_id)
-- already cover this column with no amendment — and in the app, "Delete
-- site" is gated to Sales/Admin/Approver only (home_screen.dart's
-- _canManageSites), so this was never reachable by Engineer in practice
-- anyway.
--
-- No tombstone here — archived hides a site, it never deletes the row, so
-- there's nothing for a reconcile pull to detect via absence in the first
-- place; this is a plain field like bom_locked.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.sites
  add column if not exists archived boolean not null default false;

-- ---------------------------------------------------------------------------
-- Full sync Group 1 (continued) — blocks push/pull rework: real per-row
-- identity instead of delete-all-and-reinsert.
--
-- Root cause (confirmed with logged/SQL evidence, not inferred — see the
-- blocks-push investigation): the old strategy had no stable id shared
-- between local storage and Supabase, so it couldn't tell a genuinely
-- unchanged block from a deleted-then-recreated one. That single defect
-- produced two symptoms: a block-only edit's push could fail/get skipped
-- as a whole, and — sharper — whenever a site's blocks got swept into a
-- push for ANY reason, the whole current local list, including a block
-- another device had already deleted remotely but this device never
-- learned about, got blindly resent, resurrecting it.
--
-- blocks.id changes from a server-generated `bigint identity` to a
-- client-provided `text` (same shape as every other table's id), which
-- can't be done as an in-place ALTER (existing numeric ids can't become
-- meaningful client uuids). This DROPS and recreates the table rather than
-- attempting a data-preserving type migration — deliberate, not an
-- oversight: the old id was never something the app tracked (push never
-- sent it, pull never read it), so there's nothing worth preserving under
-- it, and every device already has the current correct block content
-- locally, which the matching local migration (app_database.dart's
-- v27 -> v28) marks dirty=1 so it re-pushes under the new stable ids on
-- each device's next sync. Safe specifically because this is a small
-- dev/test dataset with every row reconstructible from a device — not a
-- general-purpose pattern for a production table with irreplaceable data.
--
-- RLS is unchanged in shape (still can_access_site(site_id), still no
-- DELETE-by-absence anywhere) — recreated here only because dropping the
-- table drops its policies with it.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

drop table if exists public.blocks;

create table public.blocks (
  id       text primary key,
  site_id  text not null references public.sites (id) on delete cascade,
  position integer not null,
  label    text not null
);

create index if not exists blocks_site_id_idx on public.blocks (site_id);

alter table public.blocks enable row level security;

drop policy if exists "access blocks via site" on public.blocks;
create policy "access blocks via site" on public.blocks
  for all to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

-- anon is deliberately not granted — same reasoning as every other
-- site-scoped table since Slice 2c.

-- ---------------------------------------------------------------------------
-- Blocks explicit delete tombstone — deleted_at, replacing the real DELETE
-- the previous section still allowed (via "for all").
--
-- Absence-based delete detection was ruled unsafe for every RLS-scoped
-- table back in the sync-safety work (a legitimately narrower fetch — RLS
-- hiding a row this caller was never meant to see — is indistinguishable
-- from a real deletion once you're only looking at what came back). The
-- fix isn't "leave deletes unsynced downward" forever, though — it's an
-- EXPLICIT marker every caller can see on the row itself, checked directly,
-- never inferred from the row's absence. blocks is the first table this
-- session actually builds that for (every other per-row-deletable table —
-- source_points, inlet_points, duct_loras, gateways, bom_manual_entries —
-- still only propagates deletes upward, one direction, exactly as before;
-- extending them the same way is separate, future work, not implied by
-- this change).
--
-- deleted_at is nullable, set once, never cleared — a block is "deleted"
-- the moment this is non-null, full stop. RLS SELECT does NOT filter on it
-- (must not: pull-reconcile needs to see a tombstoned row to act on it —
-- filtering it out here would silently break the exact mechanism this
-- exists to provide, the same rule already documented for every other
-- tombstoned table). Local display/read paths are what hide a deleted row
-- from the UI, same as the local pending_delete convention everywhere else.
--
-- DELETE is removed from the policy entirely (the "for all" above is
-- superseded by the three commands below) — not just "the app doesn't
-- currently call it," but genuinely disallowed at the database level, so
-- nobody (including a future code path, including direct SQL Editor use)
-- can bypass the tombstone by hard-deleting a row out from under pull
-- reconciliation. "Delete" a block by setting deleted_at via UPDATE, which
-- the existing can_access_site(site_id)-scoped UPDATE policy already
-- permits — no new grant needed for that half.
--
-- can_access_site(site_id) on every command means a caller can only ever
-- see, insert, update, or tombstone a block belonging to a site they can
-- access in the first place — a block for an inaccessible site is invisible
-- end to end, never returned, never reconciled, never touched.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.blocks
  add column if not exists deleted_at timestamptz;

drop policy if exists "access blocks via site" on public.blocks;

drop policy if exists "select blocks via site" on public.blocks;
create policy "select blocks via site" on public.blocks
  for select to authenticated
  using (public.can_access_site(site_id));

drop policy if exists "insert blocks via site" on public.blocks;
create policy "insert blocks via site" on public.blocks
  for insert to authenticated
  with check (public.can_access_site(site_id));

drop policy if exists "update blocks via site" on public.blocks;
create policy "update blocks via site" on public.blocks
  for update to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

-- No DELETE policy — see the doc block above for why this is deliberate,
-- not an oversight.

-- ---------------------------------------------------------------------------
-- Full sync Group 2 (Slice 3c) — delete tombstones for source_points,
-- inlet_points, duct_loras, gateways, extending the exact mechanism blocks
-- proved out in the section above.
--
-- These four already had pull-sync, but upsert-only: a row deleted on one
-- device was pushed as a real remote DELETE and therefore vanished from
-- every later fetch — and absence is precisely the signal pull reconcile is
-- (correctly) forbidden to act on for an RLS-scoped table, since a
-- role-narrowed fetch looks identical to a deletion. So the delete
-- propagated upward and stopped there: other devices kept the row forever.
-- Same fix as blocks — an EXPLICIT marker on the row itself, checked
-- directly, never inferred from absence.
--
-- deleted_at is nullable, set once, never cleared. RLS SELECT does NOT
-- filter on it, and must never be changed to: pull reconcile can only act
-- on a tombstone it can actually see, so filtering here would silently
-- re-break the propagation this exists to provide. Hiding a deleted row
-- from the UI is the local read path's job, same as the pending_delete
-- convention used everywhere else.
--
-- DELETE is removed from all four policies. The previous "for all" grant
-- (Slice 2c) covered it; the three commands below supersede that, so a
-- hard delete is now genuinely refused at the database level rather than
-- merely unused by current code — nobody, including a future code path or
-- direct SQL Editor use, can bypass the tombstone out from under pull
-- reconciliation. "Delete" a row by setting deleted_at via UPDATE, which
-- the same can_access_site(site_id) scope already permits.
--
-- photos gains deleted_at for the cascade: each of these four owns photos
-- rows via the polymorphic (owner_type, owner_id) link, and the local
-- delete path already hard-deletes them on-device (see
-- SqfliteSurveyRepository.deleteSourcePoint) while nothing ever removed
-- them remotely — a pre-existing orphan gap this closes. photos needs no
-- policy change: it already has select/insert/update and deliberately no
-- DELETE policy (Slice 2f), so an UPDATE tombstone is already permitted
-- and a hard delete already refused.
--
-- Photos' own pull path is Group 4 — this slice only guarantees the
-- cascade write happens, so the tombstones are already correct in the
-- database by the time that pull is built on top of them.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.source_points add column if not exists deleted_at timestamptz;
alter table public.inlet_points  add column if not exists deleted_at timestamptz;
alter table public.duct_loras    add column if not exists deleted_at timestamptz;
alter table public.gateways      add column if not exists deleted_at timestamptz;
alter table public.photos        add column if not exists deleted_at timestamptz;

drop policy if exists "access source_points via site" on public.source_points;

drop policy if exists "select source_points via site" on public.source_points;
create policy "select source_points via site" on public.source_points
  for select to authenticated
  using (public.can_access_site(site_id));

drop policy if exists "insert source_points via site" on public.source_points;
create policy "insert source_points via site" on public.source_points
  for insert to authenticated
  with check (public.can_access_site(site_id));

drop policy if exists "update source_points via site" on public.source_points;
create policy "update source_points via site" on public.source_points
  for update to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "access inlet_points via site" on public.inlet_points;

drop policy if exists "select inlet_points via site" on public.inlet_points;
create policy "select inlet_points via site" on public.inlet_points
  for select to authenticated
  using (public.can_access_site(site_id));

drop policy if exists "insert inlet_points via site" on public.inlet_points;
create policy "insert inlet_points via site" on public.inlet_points
  for insert to authenticated
  with check (public.can_access_site(site_id));

drop policy if exists "update inlet_points via site" on public.inlet_points;
create policy "update inlet_points via site" on public.inlet_points
  for update to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "access duct_loras via site" on public.duct_loras;

drop policy if exists "select duct_loras via site" on public.duct_loras;
create policy "select duct_loras via site" on public.duct_loras
  for select to authenticated
  using (public.can_access_site(site_id));

drop policy if exists "insert duct_loras via site" on public.duct_loras;
create policy "insert duct_loras via site" on public.duct_loras
  for insert to authenticated
  with check (public.can_access_site(site_id));

drop policy if exists "update duct_loras via site" on public.duct_loras;
create policy "update duct_loras via site" on public.duct_loras
  for update to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

drop policy if exists "access gateways via site" on public.gateways;

drop policy if exists "select gateways via site" on public.gateways;
create policy "select gateways via site" on public.gateways
  for select to authenticated
  using (public.can_access_site(site_id));

drop policy if exists "insert gateways via site" on public.gateways;
create policy "insert gateways via site" on public.gateways
  for insert to authenticated
  with check (public.can_access_site(site_id));

drop policy if exists "update gateways via site" on public.gateways;
create policy "update gateways via site" on public.gateways
  for update to authenticated
  using (public.can_access_site(site_id))
  with check (public.can_access_site(site_id));

-- No DELETE policy on any of the four (or on photos) — deliberate, see the
-- doc block above.

-- ---------------------------------------------------------------------------
-- Full sync Group 3 (Slice 3d) — bom_manual_entries delete tombstone, and
-- pull-sync for the six immutable BoM tables.
--
-- Part 1: bom_manual_entries gets the same deleted_at tombstone as Group 2
-- (source_points/inlet_points/duct_loras/gateways), for the same reason — it
-- is the one BoM table with a real delete path (removing a manual line
-- before finalize, BomGroupManualSectionScreen), and that delete was pushed
-- as a real remote DELETE, so it propagated upward and stopped there while
-- every other device kept the row forever. DELETE is dropped from its
-- policy set, so a hard delete is refused at the database level rather than
-- merely unused. RLS SELECT does NOT filter deleted_at, and must never be
-- changed to: reconcile can only act on a tombstone it can see.
--
-- Unlike Group 2's four tables, bom_manual_entries owns NO photos — there is
-- no PhotoOwner token for it (see survey_photo.dart: the six owner types are
-- source_point, inlet_point, gateway, footer, duct_lora, client_inputs), no
-- app path creates one, and its local delete path does not touch the photos
-- table at all (unlike deleteSourcePoint et al, which each delete their own
-- photos transactionally). So there is deliberately no photos cascade here —
-- adding one would be inventing an ownership relationship the app does not
-- have.
--
-- Part 2: the six immutable BoM tables (bom_snapshots, bom_snapshot_lines,
-- bom_revisions, bom_revision_lines, bom_manual_edit_snapshots,
-- bom_manual_edit_snapshot_lines) get NO schema change at all — they need
-- none. Their pull is new app-side code only; the SELECT policies they need
-- already exist (Slice 2g), including the two-hop can_access_bom_snapshot /
-- can_access_bom_revision / can_access_bom_manual_edit_snapshot helpers that
-- scope the three line tables through their parent's survey_id. They are
-- immutable by design — no delete path anywhere in the app, and already no
-- DELETE policy — so they get no deleted_at column and no tombstone logic.
-- Absence-based reconcile stays off for them as for every RLS-scoped table.
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

alter table public.bom_manual_entries add column if not exists deleted_at timestamptz;

-- Supersedes the Slice 2g DELETE grant — "delete" is now an UPDATE that sets
-- deleted_at, which the existing update policy above already permits.
drop policy if exists "delete bom_manual_entries via site" on public.bom_manual_entries;

-- No DELETE policy on bom_manual_entries, and none on any of the six
-- immutable BoM tables — deliberate, see the doc block above.

-- ---------------------------------------------------------------------------
-- Scheduled purge of expired photo tombstones (Storage cleanup).
--
-- WHERE THIS LIVES: nowhere in the Flutter app. This is server-side
-- infrastructure — a pg_cron job calling the function below. A maintainer
-- reading lib/ will find no trace of it, which is exactly why it is
-- documented here at length. If photos start disappearing from Storage,
-- this is what did it.
--
-- WHY SERVER-SIDE: the app cannot do this. Slice 2h grants storage.objects
-- SELECT and INSERT only, so a client DELETE is refused (verified: HTTP 403
-- AccessDenied). That is deliberate and must stay — it is what stops a
-- compromised or buggy client destroying survey evidence. Cleanup therefore
-- runs with the service role, which only the database has.
--
-- WHY NOT PURE SQL: deleting a row from storage.objects does NOT free the
-- underlying file — Supabase Storage keeps metadata in Postgres and the
-- bytes in object storage, and only the Storage API removes both. A SQL-only
-- job would orphan every file permanently AND destroy the metadata needed to
-- ever find them again. So the object deletion goes over HTTP via pg_net.
--
-- THE 90-DAY GRACE (see `grace` below): a tombstone is how other devices
-- learn a photo was deleted. Purging the photos row immediately would mean a
-- device that happened to be offline never sees the tombstone and keeps its
-- local copy forever. 90 days is the window a field device has to come back
-- online and reconcile. A device offline LONGER than that will keep its
-- local copy indefinitely — an accepted edge case, not an oversight.
--
-- TWO PHASES, and why the retry requirement needs no error handling:
--
--   Phase A fires a Storage DELETE for every expired tombstone whose object
--           still exists.
--   Phase B hard-deletes the photos row only for expired tombstones whose
--           object is already GONE.
--
-- The presence of the storage.objects row is itself the success signal, so
-- a failed delete simply leaves the object in place, Phase B skips that
-- photo, and Phase A retries on the next run. That sidesteps pg_net being
-- asynchronous (it returns a request id, not a result) — no response
-- correlation, no two-phase commit, no partial-failure states.
--
-- ORDER MATTERS: object first, row second, never the reverse.
-- can_access_photo_object() resolves an object's site by looking up the
-- photos row; once that row is gone the object is invisible to everyone
-- including Admin, and unreachable for cleanup. Phase B's condition
-- guarantees the row only ever goes after the object already has.
--
-- SECRETS: the service role key is read from Supabase Vault at call time and
-- never appears in this file, the repo, or the app binary (the client only
-- ever gets the anon key, via --dart-define-from-file=.env). Create both
-- secrets once per project, in Dashboard -> Project Settings -> Vault:
--
--     service_role_key  = the project's service_role JWT
--     project_url       = https://<project-ref>.supabase.co   (no trailing /)
--
-- project_url is a secret only for convenience — it keeps this file
-- environment-agnostic so the same schema.sql can be applied to staging.
--
-- APPLYING THIS: run the statements below as SEPARATE SQL Editor
-- executions, not as one pasted block. The editor wraps an execution in a
-- transaction, so a failure in the cron statements at the bottom silently
-- rolls back the function at the top — it reports success and leaves you
-- with nothing. That happened twice while this was first deployed; the
-- symptom is `42883: function ... does not exist` right after a "successful"
-- run.
--
-- REQUIRES pg_net (the HTTP call) and pg_cron (the schedule). Create them
-- explicitly and one at a time — the Dashboard's Extensions toggle silently
-- failed to take during deployment, and `create extension` at least errors
-- loudly. Verify with:
--     select extname, extversion from pg_extension
--      where extname in ('pg_net', 'pg_cron');
-- pg_cron installs only in the `postgres` database. pg_net must be 0.7+ for
-- net.http_delete to exist (deployed against 0.20.3).
-- Re-runnable / idempotent.
-- ---------------------------------------------------------------------------

create extension if not exists pg_net;

create extension if not exists pg_cron;

create or replace function public.purge_expired_photo_tombstones(
  grace               interval default interval '90 days',
  max_deletes_per_run integer  default 500
)
returns table (storage_deletes_fired integer, rows_purged integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  service_key text;
  base_url    text;
  fired       integer := 0;
  purged      integer := 0;
  rec         record;
begin
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'service_role_key';
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'project_url';

  -- Fail loudly rather than firing unauthenticated requests that would 403
  -- forever while looking like the job "ran".
  if service_key is null or base_url is null then
    raise exception 'purge_expired_photo_tombstones: missing Vault secret'
      using hint = 'Create Vault secrets named service_role_key and '
                   'project_url — see the doc block in schema.sql.';
  end if;

  -- ---- Phase A: delete the Storage object -------------------------------
  -- Capped per run so a large backlog drains over several nights instead of
  -- queueing thousands of concurrent HTTP requests in pg_net. Oldest first,
  -- so nothing can be starved indefinitely.
  for rec in
    select p.remote_path
      from public.photos p
      join storage.objects o
        on o.bucket_id = 'survey-photos'
       and o.name = p.remote_path
     where p.deleted_at is not null
       and p.deleted_at < now() - grace
     order by p.deleted_at
     limit max_deletes_per_run
  loop
    perform net.http_delete(
      url     := base_url || '/storage/v1/object/survey-photos/' || rec.remote_path,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || service_key,
        'apikey',        service_key
      )
    );
    fired := fired + 1;
  end loop;

  -- ---- Phase B: purge the row, only once its object is gone -------------
  -- A null/blank remote_path means the photo was removed before it ever
  -- uploaded — there is no object, so nothing to wait for.
  with purgeable as (
    select p.id
      from public.photos p
     where p.deleted_at is not null
       and p.deleted_at < now() - grace
       and (
         p.remote_path is null
         or p.remote_path = ''
         or not exists (
           select 1 from storage.objects o
            where o.bucket_id = 'survey-photos'
              and o.name = p.remote_path
         )
       )
  )
  delete from public.photos p
   using purgeable
   where p.id = purgeable.id;
  get diagnostics purged = row_count;

  return query select fired, purged;
end;
$$;

-- SECURITY DEFINER + reads Vault, so it must not be callable by app roles.
-- Postgres grants EXECUTE to PUBLIC on new functions by default; revoke it
-- so only the cron job's owner (postgres) can run this. Without this line
-- any authenticated user could trigger a purge via PostgREST RPC.
revoke all on function public.purge_expired_photo_tombstones(interval, integer)
  from public, anon, authenticated;

-- Daily at 03:17 UTC — off-peak, and an odd minute so it doesn't pile up
-- with every other cron job in the world scheduled on the hour.
select cron.unschedule('purge-expired-photo-tombstones')
 where exists (
   select 1 from cron.job where jobname = 'purge-expired-photo-tombstones'
 );

select cron.schedule(
  'purge-expired-photo-tombstones',
  '17 3 * * *',
  $job$ select public.purge_expired_photo_tombstones(); $job$
);

-- ---------------------------------------------------------------------------
-- SLICE 2 — Invite codes for in-app signup
--
-- Distribution is a direct APK, so the anon key is in every attacker's hands.
-- Signup therefore has to be gated by something they cannot obtain, and the
-- gate cannot live in the client. Codes are generated server-side, stored
-- here, and checked by a SECURITY DEFINER function — the table itself is
-- never readable by an unauthenticated caller.
--
-- Single-use with an expiry, per the agreed design. `max_uses` exists so a
-- future "invite the whole team" case does not need a migration, but every
-- code this app issues defaults to 1.
-- ---------------------------------------------------------------------------

create table if not exists public.signup_invites (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  -- Must match profiles.role's check constraint, or approving a request
  -- created from this code would fail at the last step. Deliberately allows
  -- admin/approver: an Admin can invite anyone, and Slice 4 is what decides
  -- who may APPROVE such a request.
  role_allowed text not null check (role_allowed in ('sales', 'engineer', 'approver', 'admin')),
  created_by   uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz,
  max_uses     integer not null default 1 check (max_uses > 0),
  uses         integer not null default 0 check (uses >= 0),
  revoked_at   timestamptz
);

create index if not exists signup_invites_code_idx on public.signup_invites (code);

alter table public.signup_invites enable row level security;

-- SELECT: Admin AND Approver (is_operational_admin()).
--
-- HISTORY, because this reversed twice and the reasoning matters more than
-- the current value:
--
--   Originally Admin-only, specifically to stop an Approver from both
--   issuing an invite and approving the account it produced. When
--   may_approve_role() was widened so an Approver could grant all four
--   roles, this policy briefly became the last structural check on the role
--   — an Approver could grant admin, but could not obtain a code to start
--   the process with.
--
--   Slice 5's final decision removed that check ON PURPOSE: Admin and
--   Approver are to be operationally equivalent (see is_operational_admin()
--   for the full statement). So an Approver can now mint a code, have a
--   request submitted against it, approve it, and grant admin — unassisted.
--
-- That is the accepted consequence, not an oversight. The control that
-- remains is WHO YOU GIVE AN APPROVER ACCOUNT TO: it is now exactly as
-- powerful as an Admin account. Engineer and Sales are unaffected and still
-- see nothing here.
--
-- anon gets nothing, which is the point: RLS default-denies a command with no
-- matching policy, so an unauthenticated caller cannot read a single row.
drop policy if exists "admin selects signup_invites" on public.signup_invites;
create policy "admin selects signup_invites" on public.signup_invites
  for select to authenticated
  using (public.is_operational_admin());

-- No INSERT/UPDATE/DELETE policy exists, for ANY role, on purpose. Every
-- write goes through the SECURITY DEFINER functions below, so a code cannot
-- be minted, edited or un-revoked by a direct table write — not even by an
-- Admin, who could otherwise reset `uses` to defeat single-use.

-- ---------------------------------------------------------------------------
-- Generation — Admin only, server-side.
--
-- Never generated client-side: the APK is inspectable, and an attacker who
-- knows the algorithm can mint their own codes. Randomness comes from
-- gen_random_uuid(), which is PG13+ built-in (no pgcrypto dependency, so no
-- search_path exposure to a non-trusted schema).
--
-- 20 hex characters drawn from two v4 UUIDs. Each UUID carries ~122 bits from
-- the server CSPRNG, so any 20-hex-char slice is comfortably over 70 bits of
-- entropy — brute-forcing it through validate_signup_invite() is not
-- feasible, which matters because that function is callable by anon.
-- ---------------------------------------------------------------------------
create or replace function public.create_signup_invite(
  p_role_allowed text,
  p_expires_at   timestamptz default null,
  p_max_uses     integer default 1
)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_code text;
  v_attempt int := 0;
begin
  -- Admin OR Approver: the two roles are operationally equivalent by
  -- deliberate decision (see is_operational_admin()). Engineer and Sales are
  -- still refused here, server-side, regardless of what any UI offers.
  if not public.is_operational_admin() then
    raise exception 'Only an admin or approver can create an invite code.'
      using errcode = 'insufficient_privilege';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := upper(substring(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
      from 1 for 20));
    begin
      insert into public.signup_invites
        (code, role_allowed, created_by, expires_at, max_uses)
      values
        (v_code, p_role_allowed, auth.uid(), p_expires_at,
         coalesce(p_max_uses, 1));
      return v_code;
    exception when unique_violation then
      -- Astronomically unlikely at this entropy; retry rather than fail.
      if v_attempt >= 5 then raise; end if;
    end;
  end loop;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Revocation — Admin only. Sets revoked_at and nothing else, so the audit
-- trail (who created it, when, how many times it was used) stays intact.
-- Idempotent: revoking an already-revoked code keeps the original timestamp.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_signup_invite(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_rows int;
begin
  if not public.is_operational_admin() then
    raise exception 'Only an admin or approver can revoke an invite code.'
      using errcode = 'insufficient_privilege';
  end if;

  update public.signup_invites
     set revoked_at = now()
   where id = p_id and revoked_at is null;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Validation — callable by anon, because Slice 3's signup screen has no
-- session yet.
--
-- Returns ONLY (valid, role_allowed). It must never become an enumeration
-- oracle, so every failure — unknown code, expired, revoked, exhausted —
-- produces the identical result: valid = false, role_allowed = null. No
-- error, no message, nothing that distinguishes "wrong code" from "expired
-- code". The row itself is never returned.
--
-- Read-only: it does NOT consume a use. Consumption belongs with the request
-- that actually uses the code (Slice 3), so that merely checking a code
-- cannot burn it — and so a user who mistypes their name afterwards is not
-- locked out by their own retry.
--
-- Input is normalised (case, spaces, dashes) so a code can be read aloud or
-- copied with formatting without failing.
-- ---------------------------------------------------------------------------
create or replace function public.validate_signup_invite(p_code text)
returns table (valid boolean, role_allowed text)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_norm text;
  v_role text;
begin
  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  select i.role_allowed into v_role
  from public.signup_invites i
  where i.code = v_norm
    and i.revoked_at is null
    and (i.expires_at is null or i.expires_at > now())
    and i.uses < i.max_uses
  limit 1;

  if v_role is null then
    -- Single indistinguishable failure for every reason.
    return query select false, null::text;
  else
    return query select true, v_role;
  end if;
end;
$fn$;

-- Explicit grants. Admin-gated functions are still executable by any signed-in
-- user — they check is_admin() internally and raise otherwise — but anon must
-- never reach them. Only validation is exposed to anon.
revoke all on function public.create_signup_invite(text, timestamptz, integer) from public, anon;
revoke all on function public.revoke_signup_invite(uuid) from public, anon;
revoke all on function public.validate_signup_invite(text) from public;
grant execute on function public.create_signup_invite(text, timestamptz, integer) to authenticated;
grant execute on function public.revoke_signup_invite(uuid) to authenticated;
grant execute on function public.validate_signup_invite(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- SLICE 3 — Signup requests
--
-- A request is NOT an account. Deliberately its own table rather than a status
-- column on profiles: a pending or rejected request has no auth.users row and
-- no profiles row, so there is nothing to authenticate with and nothing for
-- is_admin() or can_access_site() to match. Pending users are inert by
-- construction, not by every future policy remembering to filter them.
--
-- The Auth account is created only at approval (Slice 4), via the Admin API.
--
-- There is NO password column, in any form — not plaintext, not a hash. The
-- Admin API takes a plaintext password and has no parameter for a
-- pre-computed one, so a stored hash could only be used by hand-writing
-- bcrypt straight into GoTrue's own table. A hash here would also just be an
-- offline-crackable credential store guarded by RLS. Approval instead issues
-- an invite link and the user sets their own password, so it never exists
-- anywhere but GoTrue.
-- ---------------------------------------------------------------------------

create table if not exists public.signup_requests (
  id               uuid primary key default gen_random_uuid(),
  full_name        text not null,
  email            text not null,
  -- CHECK constraints on both enum-valued columns. This schema had exactly
  -- one CHECK before the pre-production audit, and unconstrained enum text is
  -- what allowed material_master_items.behavior_type to fill with a value the
  -- app cannot parse.
  requested_role   text not null check (requested_role in ('sales', 'engineer', 'approver', 'admin')),
  invite_code_used text not null,
  status           text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at       timestamptz not null default now(),
  reviewed_by      uuid references public.profiles (id) on delete set null,
  reviewed_at      timestamptz,
  rejection_reason text
);

create index if not exists signup_requests_status_idx
  on public.signup_requests (status, created_at desc);

-- One outstanding request per email, enforced by the database rather than
-- only by the RPC's check. A partial unique index allows any number of
-- historical approved/rejected rows for the same person while permitting
-- exactly one pending. Lowercased so casing cannot be used to slip past it.
create unique index if not exists signup_requests_one_pending_per_email
  on public.signup_requests (lower(email)) where status = 'pending';

alter table public.signup_requests enable row level security;

-- Admin and Approver both review the queue (Slice 4), so both need SELECT.
-- Its own helper rather than reusing can_edit_bom(), which happens to cover
-- the same two roles today: coupling them would mean a future change to who
-- may edit a BoM silently changing who can read applicants' names and email
-- addresses.
create or replace function public.is_signup_reviewer()
returns boolean
language sql
security definer
set search_path = public
stable
as $fn$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'approver') and active
  );
$fn$;

drop policy if exists "reviewers select signup_requests" on public.signup_requests;
create policy "reviewers select signup_requests" on public.signup_requests
  for select to authenticated
  using (public.is_signup_reviewer());

-- No INSERT/UPDATE/DELETE policy for any role. Submission goes through
-- request_signup() below; review will go through Slice 4's RPCs. anon has no
-- policy at all, so an unauthenticated caller cannot read a single row.

-- ---------------------------------------------------------------------------
-- Submission — callable with the anon key, because the applicant has no
-- session and (by design) never gets one from this slice.
--
-- Returns a bare boolean. Every rejection reason collapses into the same
-- `false`: unknown, expired, revoked or exhausted code, and a role the code
-- does not permit. Nothing distinguishes them, so this cannot be used to
-- probe which codes exist or what they are for.
--
-- DELIBERATE DEVIATION, worth understanding before changing it: an email that
-- is already registered, or that already has a pending request, returns
-- **true** and silently writes nothing. Returning false there would satisfy
-- "all failures look alike" while defeating its purpose — anyone holding one
-- valid invite code could then submit requests to learn which email addresses
-- have accounts. Collapsing those two cases into the success response removes
-- that oracle entirely: with a valid code, EVERY email answers the same way.
-- The cost is that someone who already has an account gets a confirmation and
-- no further contact, which the screen's wording covers.
--
-- Does NOT consume the invite code. Consumption happens at approval, so a
-- rejected or mistyped request cannot burn a code and an attacker cannot
-- destroy one by submitting junk against it.
--
-- Creates no auth.users row and no profiles row, under any circumstance.
-- ---------------------------------------------------------------------------
create or replace function public.request_signup(
  p_full_name      text,
  p_email          text,
  p_requested_role text,
  p_code           text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_valid boolean;
  v_role  text;
  v_email text;
  v_name  text;
begin
  v_email := lower(trim(coalesce(p_email, '')));
  v_name  := trim(coalesce(p_full_name, ''));

  if v_email = '' or v_name = '' or coalesce(p_requested_role, '') = '' then
    return false;
  end if;

  -- Reuses the Slice 2 validation path rather than re-implementing expiry /
  -- revocation / exhaustion, so the two can never disagree about what makes a
  -- code usable.
  select v.valid, v.role_allowed
    into v_valid, v_role
    from public.validate_signup_invite(p_code) v;

  if not coalesce(v_valid, false) then
    return false;
  end if;

  -- The code decides the role. A request for anything else is refused, and
  -- refused identically to a bad code.
  if v_role is distinct from p_requested_role then
    return false;
  end if;

  -- Email-status checks. See the deviation note above: these return true.
  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    return true;
  end if;
  if exists (
    select 1 from public.signup_requests r
    where lower(r.email) = v_email and r.status = 'pending'
  ) then
    return true;
  end if;

  insert into public.signup_requests
    (full_name, email, requested_role, invite_code_used)
  values
    (v_name, v_email, p_requested_role, upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g')));

  return true;
exception
  -- Belt and braces for the partial unique index: two simultaneous
  -- submissions for the same email race past the exists() check above, and
  -- the loser must look exactly like every other outcome.
  when unique_violation then
    return true;
end;
$fn$;

revoke all on function public.is_signup_reviewer() from public, anon;
grant execute on function public.is_signup_reviewer() to authenticated;
revoke all on function public.request_signup(text, text, text, text) from public;
grant execute on function public.request_signup(text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- SLICE 4 — Review queue: approve / reject a signup request
--
-- Approval spans TWO systems: GoTrue (creating auth.users, issuing the link)
-- and Postgres (the invite code, the request row, the profile). They are
-- separate services reached over HTTP, so no single transaction can cover
-- both and true atomicity is impossible. What is guaranteed instead:
--
--   every intermediate state is INERT — granting nothing, consuming nothing,
--   claiming nothing — and every step is individually re-runnable.
--
-- The ordering that buys this:
--
--   1. Edge Function verifies the caller's JWT and reads their role from
--      profiles SERVER-SIDE. Never from the request body.
--   2. Create the Auth user with NO `role` in raw_app_meta_data. Slice 0's
--      handle_new_user then writes a profile with role='engineer',
--      active=false, and Slice 1 makes active=false mean no data access at
--      all. A half-finished approval is therefore a login that can see
--      nothing.
--   3. approve_signup_request() below — ONE transaction consuming the code,
--      flipping the request pending->approved, and activating the profile.
--      All three or none.
--   4. generateLink, after the database is already consistent.
--
-- Failing at step 3 leaves an inactive, role-less account and a still-pending
-- request: visible, harmless, and fixed by simply approving again. The
-- opposite ordering ("reserve the code first") would instead leave a dead
-- code and a request reading `approved` with no account behind it — silently
-- and permanently wrong. Failing toward "not yet done" is the whole point.
--
-- WHY AN EDGE FUNCTION AND NOT JUST THIS RPC: creating an auth.users row and
-- minting a link are GoTrue operations. SECURITY DEFINER grants Postgres
-- privileges, not GoTrue ones, so no amount of SQL can do it. See
-- supabase/functions/review-signup/index.ts.
-- ---------------------------------------------------------------------------

-- created_user_id (an audit-trail link from a request to the account it
-- produced) was specified here but never actually applied to the live
-- database. approve_signup_request() below wrote to it, so EVERY approval
-- failed with `column "created_user_id" ... does not exist` until that
-- assignment was removed.
--
-- The ALTER is deliberately NOT reinstated: the decision was to drop the
-- column rather than add it. Removing the statement keeps this file honest —
-- re-applying schema.sql must not silently recreate a column the deployed
-- function no longer writes and nothing reads.
--
-- If the audit link is ever wanted back, BOTH halves have to return: this
-- ALTER *and* the assignment in approve_signup_request(). Restoring only one
-- reproduces exactly the failure above.
--
-- granted_role is the ANSWER to the gap created_user_id left behind, not a
-- repeat of it. requested_role is what the applicant's invite code allowed;
-- it is NOT what they were granted — the reviewer's choice at approval time
-- can differ, and given both Admin and Approver may grant all four roles
-- (may_approve_role, Slice 5), "who was made an admin, and by whom" was NOT
-- answerable from this table alone. This column, and the matching assignment
-- inside approve_signup_request() below, close that gap.
--
-- Nullable, and stays null forever for a pending or rejected request — it is
-- written exactly once, inside the same transaction that flips status to
-- 'approved', so it can never point at a grant that did not actually happen.
-- APPLY THIS BEFORE (or together with) approve_signup_request()'s updated
-- definition below — the function assigns to this column, and doing it in
-- the wrong order reproduces the exact created_user_id failure this comment
-- is warning about.
alter table public.signup_requests
  add column if not exists granted_role text
    check (granted_role in ('sales', 'engineer', 'approver', 'admin'));

-- ---------------------------------------------------------------------------
-- The approval authority matrix, in one place so the Edge Function and the
-- RPC cannot disagree about it.
--
--   Admin     may grant any of the four roles.
--   Approver  may grant any of the four roles.
--   Engineer  may grant nothing.
--   Sales     may grant nothing.
--
-- So the two reviewer roles now have IDENTICAL granting authority; the
-- distinction between Admin and Approver carries no weight here any more,
-- only elsewhere (notably signup_invites, which Approver still cannot read —
-- see that table's SELECT policy).
--
-- CHANGED DELIBERATELY, by the project owner's explicit decision, from an
-- earlier stricter rule where Approver could grant only sales/engineer. That
-- earlier rule existed to stop privilege escalation by proxy, and dropping it
-- has real consequences worth understanding before relying on it:
--
--   * this function is the authority approve_signup_request() itself checks,
--     so an Approver can now genuinely CREATE an Admin account, not merely be
--     offered the option in the UI;
--   * the granted role is the reviewer's choice and is NOT bound by what the
--     request asked for, so any pending request — even one submitted for
--     'sales' — can be approved as 'admin';
--   * Approver still cannot mint an invite code, so bootstrapping an account
--     from nothing still needs an Admin-issued code to exist first. That is
--     now the only remaining structural limit on an Approver.
--
-- Rejection is held to the same matrix (reject_signup_request calls this too),
-- so an Approver can likewise now dispose of an admin/approver request.
-- ---------------------------------------------------------------------------
create or replace function public.may_approve_role(p_reviewer_role text, p_target_role text)
returns boolean
language sql
immutable
as $fn$
  select case
    when p_reviewer_role = 'admin'    then p_target_role in ('sales', 'engineer', 'approver', 'admin')
    when p_reviewer_role = 'approver' then p_target_role in ('sales', 'engineer', 'approver', 'admin')
    else false
  end;
$fn$;

-- ---------------------------------------------------------------------------
-- Looks up the Auth account for an email. Needed by the Edge Function's
-- orphan-recovery path, which must be able to find the inert account a
-- previous failed attempt left behind.
--
-- Its own function rather than GoTrue's listUsers, which pages: this answers
-- exactly, in one round trip, and cannot silently miss a user past the end of
-- the first page as the project grows.
--
-- service_role only. auth.users is not readable by any client role, and this
-- deliberately does not change that.
-- ---------------------------------------------------------------------------
create or replace function public.auth_user_id_for_email(p_email text)
returns uuid
language sql
security definer
set search_path = public
stable
as $fn$
  select u.id from auth.users u
  where lower(u.email) = lower(trim(coalesce(p_email, '')))
  limit 1;
$fn$;

-- ---------------------------------------------------------------------------
-- Step 3: the whole database side of an approval, in one transaction.
--
-- Called ONLY by the Edge Function, with the service_role key. That is not a
-- convention — it is load-bearing. prevent_self_role_escalation refuses any
-- change to profiles.role/active unless auth.uid() is null or the caller is
-- an admin, and an APPROVER is neither. Under service_role there is no `sub`
-- claim, auth.uid() is null, and the trigger exempts the write. That trigger
-- is doing exactly its job and is not weakened here.
--
-- Because auth.uid() is null, this function cannot discover its caller. The
-- reviewer's id is therefore a parameter — but one the Edge Function has
-- ALREADY verified by validating the JWT against GoTrue. This function still
-- re-derives that reviewer's role and authority from profiles rather than
-- trusting anything passed in.
--
-- It also refuses to trust the Edge Function about WHICH account to activate:
-- the account's email must match the request's, and the account must still be
-- inactive. So even a buggy or compromised Edge Function cannot use this to
-- activate or re-role an existing live user.
--
-- Returns a jsonb outcome for the expected "nothing to do" case, and RAISES
-- for anything that must roll the transaction back.
-- ---------------------------------------------------------------------------
create or replace function public.approve_signup_request(
  p_request_id  uuid,
  p_reviewer_id uuid,
  p_user_id     uuid,
  p_granted_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_reviewer_role   text;
  v_reviewer_active boolean;
  v_req             public.signup_requests%rowtype;
  v_account_email   text;
begin
  if p_granted_role not in ('sales', 'engineer', 'approver', 'admin') then
    raise exception 'unknown_role' using errcode = '22023';
  end if;

  -- Reviewer authority, re-derived here rather than accepted from the caller.
  select p.role, p.active into v_reviewer_role, v_reviewer_active
    from public.profiles p where p.id = p_reviewer_id;

  if v_reviewer_role is null or not coalesce(v_reviewer_active, false) then
    raise exception 'not_a_reviewer' using errcode = '42501';
  end if;

  -- The granted role comes from the approver's action. It is NOT taken from
  -- requested_role, and it is NOT bounded by the invite code's role_allowed
  -- (an Admin may legitimately approve someone at a different level than the
  -- code they were sent). It IS bounded by what this reviewer may grant.
  if not public.may_approve_role(v_reviewer_role, p_granted_role) then
    raise exception 'role_above_reviewer' using errcode = '42501';
  end if;

  -- Compare-and-swap on the request. Zero rows means somebody already
  -- reviewed it; nothing else in this transaction has run yet, so returning
  -- here has written nothing at all.
  --
  -- created_user_id is deliberately NOT written here. The column was
  -- specified in this file but never applied to the live database, so the
  -- assignment failed every approval outright with
  -- `column "created_user_id" of relation "signup_requests" does not exist`.
  -- Removed rather than adding the column, by explicit decision: it was an
  -- audit-trail nicety, and nothing in the approval contract depends on it.
  -- p_user_id is still used below (email match, profile activation) and is
  -- still part of this function's signature.
  --
  -- CONSEQUENCE, worth knowing before someone tries to reconstruct history:
  -- there is now no stored link from a signup_request to the account it
  -- produced. "Which account came from which request" is answerable only by
  -- matching email, or full_name, between signup_requests and profiles.
  update public.signup_requests r
     set status       = 'approved',
         reviewed_by  = p_reviewer_id,
         reviewed_at  = now(),
         granted_role = p_granted_role
   where r.id = p_request_id
     and r.status = 'pending'
  returning r.* into v_req;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'already_reviewed');
  end if;

  -- The account being activated must be the account for THIS request's
  -- email. Without this, a caller that passed the wrong user id could hand
  -- someone else's account a new role.
  select lower(u.email) into v_account_email from auth.users u where u.id = p_user_id;
  if v_account_email is null or v_account_email is distinct from lower(v_req.email) then
    raise exception 'account_email_mismatch' using errcode = '42501';
  end if;

  -- Consume the invite code, re-evaluating the SAME predicate
  -- validate_signup_invite() applies — so a code revoked, expired or used up
  -- between submission and approval is caught here rather than at submission
  -- time. UPDATE takes a row lock and, under READ COMMITTED, re-checks this
  -- WHERE clause against the updated row after waiting: two approvals racing
  -- for one single-use code cannot both pass `uses < max_uses`.
  update public.signup_invites i
     set uses = i.uses + 1
   where i.code = v_req.invite_code_used
     and i.revoked_at is null
     and (i.expires_at is null or i.expires_at > now())
     and i.uses < i.max_uses;

  if not found then
    -- Rolls back the approval above. The request stays pending and can be
    -- approved again once a usable code is issued.
    raise exception 'invite_unusable' using errcode = 'P0001';
  end if;

  -- Activate. `and not active` is the guarantee that this only ever finishes
  -- an account THIS flow created and left inert — never adopts a live one.
  update public.profiles p
     set role = p_granted_role, active = true
   where p.id = p_user_id
     and not p.active;

  if not found then
    raise exception 'account_not_inert' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'user_id', p_user_id,
    'email', v_req.email,
    'granted_role', p_granted_role
  );
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Rejection. Postgres only — no account, no code consumed, no GoTrue call —
-- so this one really is atomic, and a double rejection touches zero rows.
--
-- THE APPLICANT IS NEVER TOLD. Nothing here, and nothing in the Edge
-- Function's reject branch, sends any notification. That is deliberate: an
-- in-app status screen or a "you were rejected" response keyed to the email
-- address would turn request_signup() into an oracle for whether an account
-- or a prior request exists — precisely the leak Slice 3's design avoids.
-- rejection_reason below is recorded for the REVIEWER to read in the history
-- view; passing it to the applicant is a MANUAL step a human must perform.
--
-- REJECTING FREES THE EMAIL. signup_requests_one_pending_per_email is scoped
-- `where status = 'pending'`, so once a request is rejected the same address
-- can submit a new one and will get the same neutral confirmation. A reviewer
-- seeing repeat requests from somebody they already turned down is expected
-- behaviour, not a bug — and the applicant has no way to know they were
-- rejected, so they have every reason to try again.
--
-- Routed through the Edge Function alongside approve() rather than exposed to
-- `authenticated` directly, even though it needs no elevated privilege. One
-- authority boundary and one audit path is worth more here than saving a
-- round trip: whoever inherits this should not have to discover that two
-- superficially similar actions are gated in two different places.
-- ---------------------------------------------------------------------------
create or replace function public.reject_signup_request(
  p_request_id  uuid,
  p_reviewer_id uuid,
  p_reason      text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_reviewer_role   text;
  v_reviewer_active boolean;
  v_req             public.signup_requests%rowtype;
begin
  select p.role, p.active into v_reviewer_role, v_reviewer_active
    from public.profiles p where p.id = p_reviewer_id;

  if v_reviewer_role is null or not coalesce(v_reviewer_active, false) then
    raise exception 'not_a_reviewer' using errcode = '42501';
  end if;

  select r.* into v_req from public.signup_requests r where r.id = p_request_id;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'reason', 'already_reviewed');
  end if;

  -- Same matrix as approval: an Approver cannot dispose of a request they
  -- could not have granted.
  if not public.may_approve_role(v_reviewer_role, v_req.requested_role) then
    raise exception 'role_above_reviewer' using errcode = '42501';
  end if;

  update public.signup_requests r
     set status           = 'rejected',
         reviewed_by      = p_reviewer_id,
         reviewed_at      = now(),
         rejection_reason = nullif(trim(coalesce(p_reason, '')), '')
   where r.id = p_request_id
     and r.status = 'pending';

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'already_reviewed');
  end if;

  return jsonb_build_object('ok', true, 'request_id', p_request_id);
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Grants. Both review RPCs are service_role ONLY: they are reachable through
-- the Edge Function and nowhere else. An Approver holding their own JWT
-- cannot call them directly, which is what stops the reviewer id from being
-- something a client simply asserts.
--
-- may_approve_role() is granted to authenticated too — it is a pure lookup
-- table with no side effects, and the client uses it to avoid offering a
-- reviewer a grant the server would only refuse.
-- ---------------------------------------------------------------------------
revoke all on function public.approve_signup_request(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.reject_signup_request(uuid, uuid, text)         from public, anon, authenticated;
revoke all on function public.auth_user_id_for_email(text)                    from public, anon, authenticated;
grant execute on function public.approve_signup_request(uuid, uuid, uuid, text) to service_role;
grant execute on function public.reject_signup_request(uuid, uuid, text)        to service_role;
grant execute on function public.auth_user_id_for_email(text)                   to service_role;

-- The Edge Function pre-flights the invite code BEFORE creating an account,
-- so an obviously-dead code never leaves an inert orphan behind. It reuses
-- THIS function rather than re-implementing the predicate, which means the
-- pre-flight and the consumption inside approve_signup_request() cannot
-- disagree. Read-only, and it consumes nothing.
grant execute on function public.validate_signup_invite(text) to service_role;

revoke all on function public.may_approve_role(text, text) from public, anon;
grant execute on function public.may_approve_role(text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Which roles the CURRENT reviewer may grant. Takes no parameter on purpose:
-- it reads auth.uid() itself, so a client cannot ask "what could an admin
-- grant?" and act on the answer. Used only to avoid offering a reviewer a
-- choice the server would refuse — approve_signup_request() is still the
-- authority, and still re-checks.
-- ---------------------------------------------------------------------------
create or replace function public.grantable_roles()
returns text[]
language sql
security definer
set search_path = public
stable
as $fn$
  select coalesce(array_agg(r order by r), '{}'::text[])
  from unnest(array['admin', 'approver', 'engineer', 'sales']) as r
  where public.may_approve_role(
    (select p.role from public.profiles p where p.id = auth.uid() and p.active),
    r
  );
$fn$;

revoke all on function public.grantable_roles() from public, anon;
grant execute on function public.grantable_roles() to authenticated;
