-- ════════════════════════════════════════════════════════════════════════════
--  Seed: two soil samples for farm-001
--
--  Run AFTER supabase/soil_samples.sql (which creates `farms` + `soil_samples`
--  and seeds the farm row).
--
--  These give the DSS "Choose Recorded Soil Sample" option something real to
--  work with. Your live soil sensor is currently reporting zeros
--  (soil_nitrogen/phosphorus/potassium/ph/ec/moisture = 0 on reading 1861), so
--  a default-sensor DSS run has no usable soil signal — these samples do.
--
--  What gets sent to the DSS when you pick one of these:
--    soil_sensor     ← this sample's n/p/k/ph/ec/temp/moist
--    weather_station ← your latest sensor_readings row, untouched
--                      (wind 0.3 m/s → 1.1 km/h, rain 0; temperature,
--                       humidity and uv are sent as 0 because sensor_readings
--                       has no columns for them)
-- ════════════════════════════════════════════════════════════════════════════

-- ─── 0. Point the farm at your real logger (station_id = 2) ─────────────────
-- soil_samples.sql links the farm by device_id = 'RPAWTEX'. If station 2 uses a
-- different device_id that lookup returned null, so set it explicitly.
update public.farms
   set station_id = 2
 where id = 'farm-001';


-- ─── 1. The two samples ─────────────────────────────────────────────────────
insert into public.soil_samples (
  captured_at,
  farm_id, farm_name,
  crop_id, crop_name, sowing_date,
  lat, lng, address,
  n, p, k, ph, ec, moist, temp,
  notes
) values
  -- Sample A — lighter, drier block. Captured 10 days before the latest reading.
  (
    '2026-07-20 09:15:00+00',
    'farm-001', 'North Block',
    'maize', 'Maize', '2026-06-20',
    30.157500, 71.524900, 'North Block, Gardezi Farm, Multan, Punjab',
    38, 14, 142, 7.8, 285, 18.4, 29.6,
    'Probe sample — sandy patch near the north watercourse.'
  ),
  -- Sample B — heavier, better-fed block. Captured 3 days before.
  (
    '2026-07-27 08:40:00+00',
    'farm-001', 'South Block',
    'maize', 'Maize', '2026-06-20',
    30.155100, 71.527300, 'South Block, Gardezi Farm, Multan, Punjab',
    61, 23, 176, 7.5, 372, 27.9, 28.1,
    'Probe sample — taken two days after irrigation.'
  );

-- `id` is omitted on purpose: gen_random_uuid() fills it, matching what the app
-- would have generated client-side.


-- ─── 2. Verify ──────────────────────────────────────────────────────────────
-- Should return the two rows, newest first — exactly what the DSS sample picker
-- and the Soil Sampling screen's history list will show.
select captured_at, farm_name, crop_name,
       n, p, k, ph, ec, moist, temp
  from public.soil_samples
 where farm_id = 'farm-001'
 order by captured_at desc;

-- Confirm the parent/child link resolves:
select f.id, f.name, f.station_id, s.device_id,
       count(ss.id) as samples
  from public.farms f
  left join public.stations s   on s.id = f.station_id
  left join public.soil_samples ss on ss.farm_id = f.id
 group by f.id, f.name, f.station_id, s.device_id;
