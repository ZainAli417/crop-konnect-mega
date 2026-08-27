-- ════════════════════════════════════════════════════════════════════════════
--  Crop Konnect Mega — soil sampling schema
--
--  farms (1) ──< soil_samples (many)
--
--  Creates the `farms` parent table and the `soil_samples` child table written
--  by the Soil Sampling screen (SoilSampleRepository / SoilSample) and read
--  back by the DSS Center's "Choose Recorded Soil Sample" option.
--
--  Column names are the ones the Dart model maps, so do not rename them:
--    lib/src/models/soil_sample.dart  (toMap / fromMap)
--
--  Conventions follow the existing tables (sensor_readings, station_settings,
--  irrigation_profiles): timestamptz for instants, double precision for
--  measurements, no RLS.
--
--  Run order matters — `farms` must exist and be seeded before `soil_samples`
--  can reference it.
-- ════════════════════════════════════════════════════════════════════════════

-- Needed for gen_random_uuid(). Supabase projects normally have it already.
create extension if not exists pgcrypto;


-- ─── farms (parent) ─────────────────────────────────────────────────────────
-- The ids here MUST match FarmCatalog.farms in lib/src/models/farm.dart. The
-- app still reads its farm list from that Dart constant, so adding a farm means
-- adding it in both places — otherwise its samples fail the FK below.
create table if not exists public.farms (
  id           text not null,
  name         text not null,
  location     text null,
  area_acres   double precision null,
  primary_crop text null,

  -- The logger installed on this farm (one per farm for now).
  station_id   integer null,

  created_at   timestamp with time zone not null default now(),

  constraint farms_pkey primary key (id),
  constraint farms_station_id_fkey foreign key (station_id)
    references public.stations (id) on delete set null
) TABLESPACE pg_default;

create index if not exists ix_farms_station_id
  on public.farms using btree (station_id) TABLESPACE pg_default;

-- Seed the single assumed farm, linked to its logger by device_id.
insert into public.farms (id, name, location, area_acres, primary_crop, station_id)
values (
  'farm-001',
  'Gardezi Farm',
  'Multan, Punjab',
  42.5,
  'Wheat',
  (select id from public.stations where device_id = 'RPAWTEX' limit 1)
)
on conflict (id) do nothing;


-- ─── soil_samples (child) ───────────────────────────────────────────────────
create table if not exists public.soil_samples (
  -- The app generates a client-side uuid v4 so a sample keeps its identity
  -- offline; the default covers rows inserted from SQL or another service.
  id uuid not null default gen_random_uuid(),

  -- When the probe reading was captured (sent as UTC ISO-8601).
  captured_at timestamp with time zone not null default now(),
  created_at  timestamp with time zone not null default now(),

  -- The farm this sample was taken on. Matches Farm.id in
  -- lib/src/models/farm.dart (e.g. 'farm-001'). NOT NULL + FK, so every
  -- sample is guaranteed to belong to a real farm.
  farm_id text not null,

  -- Plot / block name typed into the capture form.
  farm_name text null,

  -- Crop chosen in the form. crop_id is the bundled timeline key
  -- (e.g. 'spring_maize'); crop_name is the display name.
  crop_id   text null,
  crop_name text null,

  -- 'YYYY-MM-DD'. Nullable: the app always sends a value, but a sample built
  -- without one sends null rather than an empty string.
  sowing_date date null,

  -- GPS fix + reverse-geocoded label captured with the sample.
  lat     double precision null,
  lng     double precision null,
  address text null,

  notes text not null default '',

  -- Probe readings (calibration offsets already applied).
  n     double precision null, -- nitrogen, mg/kg
  p     double precision null, -- phosphorus, mg/kg
  k     double precision null, -- potassium, mg/kg
  ph    double precision null, -- pH
  ec    double precision null, -- conductivity, µS/cm
  moist double precision null, -- moisture, %
  temp  double precision null, -- soil temperature, °C

  constraint soil_samples_pkey primary key (id),

  -- Deleting a farm is blocked while it still has samples — field measurements
  -- should not disappear with a config change. Swap to `on delete cascade` if
  -- you would rather match sensor_readings' behaviour.
  constraint soil_samples_farm_id_fkey foreign key (farm_id)
    references public.farms (id) on delete restrict
) TABLESPACE pg_default;

-- Serves the repository's main query:
--   select * where farm_id = ? order by captured_at desc limit ?
create index if not exists ix_soil_samples_farm_captured_at
  on public.soil_samples using btree (farm_id, captured_at desc) TABLESPACE pg_default;

-- Serves the unfiltered variant (fetchSamples with no farmId).
create index if not exists ix_soil_samples_captured_at
  on public.soil_samples using btree (captured_at desc) TABLESPACE pg_default;

create index if not exists ix_soil_samples_crop_id
  on public.soil_samples using btree (crop_id) TABLESPACE pg_default;


-- ─── Upgrading a soil_samples table you created earlier ─────────────────────
-- Safe to re-run. Do these in order; the FK cannot be added while any row has
-- a farm_id that is null or missing from `farms`.
--
-- alter table public.soil_samples add column if not exists farm_id text;
-- alter table public.soil_samples add column if not exists crop_id text;
-- alter table public.soil_samples add column if not exists crop_name text;
-- alter table public.soil_samples add column if not exists sowing_date date;
-- alter table public.soil_samples add column if not exists address text;
--
-- -- 1. Adopt any pre-FK rows into the seeded farm.
-- update public.soil_samples
--    set farm_id = 'farm-001'
--  where farm_id is null or farm_id = '';
--
-- -- 2. Check nothing is left orphaned (must return zero rows).
-- select s.id, s.farm_id
--   from public.soil_samples s
--   left join public.farms f on f.id = s.farm_id
--  where f.id is null;
--
-- -- 3. Enforce the relationship.
-- alter table public.soil_samples alter column farm_id set not null;
-- alter table public.soil_samples
--   add constraint soil_samples_farm_id_fkey foreign key (farm_id)
--   references public.farms (id) on delete restrict;


-- ─── Row Level Security ─────────────────────────────────────────────────────
-- Left DISABLED above, matching sensor_readings / stations / station_settings,
-- which the app already reads with the anon key.
--
-- If you enable RLS on this project, the sampling screen needs anon INSERT and
-- SELECT or saves will fail with a 401 and the DSS sample list will come back
-- empty. Uncomment to apply:
--
alter table public.soil_samples enable row level security;

create policy "anon can read soil samples"
  on public.soil_samples for select
  to anon, authenticated
  using (true);

create policy "anon can insert soil samples"
  on public.soil_samples for insert
  to anon, authenticated
  with check (true);

create policy "anon can update soil samples"
  on public.soil_samples for update
  to anon, authenticated
  using (true)
  with check (true);


-- ─── Realtime (optional) ────────────────────────────────────────────────────
-- The Mega repository fetches on demand and refreshes after each save, so this
-- is not required. Add it only if you want other devices to see new samples
-- appear live:
--
-- alter publication supabase_realtime add table public.soil_samples;


-- ─── Handy checks ───────────────────────────────────────────────────────────
-- Samples per farm:
--
-- select f.id, f.name, count(s.id) as samples, max(s.captured_at) as latest
--   from public.farms f
--   left join public.soil_samples s on s.farm_id = f.id
--  group by f.id, f.name
--  order by f.name;
