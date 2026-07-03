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
  unit                 text not null,
  behavior_type        text not null,              -- enum name: fixed | derived | variable
  sensor_size          text,                        -- enum name; null = any size
  sensor_type          text,                        -- enum name; null = any type
  quantity_per_sensor  double precision not null default 0,
  derived_formula      text,                        -- enum name; e.g. ceilWiredSensorsDividedByDivisor
  formula_divisor      double precision,
  variable_source      text,                        -- enum name; e.g. ductLoraCableLength
  notes                text
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
  owner_type  text not null,   -- source_point | inlet_point | gateway | footer
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
