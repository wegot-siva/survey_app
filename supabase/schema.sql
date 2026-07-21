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
-- are read from the new user's metadata if the Dashboard's "User Metadata"
-- field was filled in (e.g. {"full_name": "Ravi Kumar", "role": "engineer"});
-- otherwise falls back to the email and 'engineer' so the insert can never
-- fail the NOT NULL/check constraints above — a failing trigger would abort
-- the auth.users insert itself, since both run in the same transaction.
-- Whatever the fallback lands on, an Admin can always correct full_name/role
-- afterwards directly in the Table Editor (this slice's verification step).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email),
    coalesce(new.raw_user_meta_data ->> 'role', 'engineer')
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

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

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
  using (role = 'engineer' and active = true);

drop policy if exists "admin selects any profile" on public.profiles;
create policy "admin selects any profile" on public.profiles
  for select to authenticated
  using (public.is_admin());

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
  if public.is_admin() then
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
