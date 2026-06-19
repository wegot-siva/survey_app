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
