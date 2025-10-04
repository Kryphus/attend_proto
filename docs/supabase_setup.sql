-- =====================================================
-- SUPABASE SETUP FOR ATTENDANCE TRACKER (O4)
-- Minimal, Supabase-compatible SQL (single run)
-- =====================================================

-- 1) Extensions (safe on Supabase)
create extension if not exists "uuid-ossp";
create extension if not exists "postgis";

-- 2) Tables
create table if not exists public.users (
  id uuid primary key default uuid_generate_v4(),
  email text unique not null,
  full_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.sessions (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  geofence_center geography(point,4326) not null,
  geofence_radius_m integer not null default 100,
  created_by uuid references public.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint sessions_valid_time_range check (ends_at > starts_at),
  constraint sessions_valid_radius check (geofence_radius_m > 0 and geofence_radius_m <= 10000)
);

create table if not exists public.devices (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.users(id) on delete cascade,
  device_identifier text not null,
  label text not null,
  is_trusted boolean default true,
  last_seen_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (user_id, device_identifier)
);

create table if not exists public.attendance_events (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.users(id) on delete cascade,
  device_id uuid references public.devices(id),
  session_id uuid references public.sessions(id),
  event_type text not null check (event_type in ('ATTEND_IN','ATTEND_OUT','HEARTBEAT')),

  event_timestamp timestamptz not null,
  location_lat double precision not null,
  location_lng double precision not null,
  location_accuracy double precision not null,
  biometric_verified boolean default false,
  biometric_timestamp timestamptz,

  dedupe_key text not null unique,
  client_event_id uuid,

  status text not null default 'PENDING' check (status in ('PENDING','CONFIRMED','REJECTED')),
  server_reason text,

  raw_payload jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 3) Indexes (separate from table definitions)
create index if not exists idx_sessions_time_range on public.sessions (starts_at, ends_at);
create index if not exists idx_sessions_geofence on public.sessions using gist (geofence_center);
create index if not exists idx_devices_user_trusted on public.devices (user_id, is_trusted);
create index if not exists idx_events_user_session on public.attendance_events (user_id, session_id);
create index if not exists idx_events_timestamp on public.attendance_events (event_timestamp);
create index if not exists idx_events_status on public.attendance_events (status);
create index if not exists idx_events_dedupe on public.attendance_events (dedupe_key);

-- 4) Helper function: geofence check
create or replace function public.is_within_geofence(
  p_event_lat double precision,
  p_event_lng double precision,
  p_center geography,
  p_radius_m integer
)
returns boolean
language plpgsql
as $$
begin
  return ST_DWithin(
    p_center,
    ST_SetSRID(ST_MakePoint(p_event_lng, p_event_lat), 4326)::geography,
    p_radius_m
  );
end
$$;

-- 5) Composite rule validator (server-side)
create or replace function public.validate_attendance_rules(
  p_user_id uuid,
  p_session_id uuid,
  p_device_id uuid,
  p_event_type text,
  p_event_timestamp timestamptz,
  p_location_lat double precision,
  p_location_lng double precision,
  p_location_accuracy double precision,
  p_biometric_verified boolean,
  p_biometric_timestamp timestamptz
) returns table(is_valid boolean, error_code text, error_message text)
language plpgsql
as $$
declare
  session_rec record;
  device_rec record;
  last_event_type text;
  biometric_age interval;
begin
  -- Session exists
  select * into session_rec from public.sessions where id = p_session_id;
  if not found then
    return query select false, 'SESSION_NOT_FOUND', 'Session does not exist';
    return;
  end if;

  -- Device exists and belongs to user
  select * into device_rec from public.devices where id = p_device_id and user_id = p_user_id;
  if not found then
    return query select false, 'DEVICE_NOT_FOUND', 'Device not found or not owned by user';
    return;
  end if;

  -- Trusted device
  if not device_rec.is_trusted then
    return query select false, 'UNTRUSTED_DEVICE', 'Device is not trusted';
    return;
  end if;

  -- Time window
  if p_event_timestamp < session_rec.starts_at then
    return query select false, 'SESSION_NOT_STARTED', 'Event before session start';
    return;
  end if;

  if p_event_timestamp > session_rec.ends_at then
    return query select false, 'SESSION_ENDED', 'Event after session end';
    return;
  end if;

  -- Geofence (skip for heartbeat)
  if p_event_type <> 'HEARTBEAT' then
    if not public.is_within_geofence(p_location_lat, p_location_lng, session_rec.geofence_center, session_rec.geofence_radius_m) then
      return query select false, 'GEOFENCE_VIOLATION', 'Location outside geofence';
      return;
    end if;
  end if;

  -- Accuracy
  if p_location_accuracy > 50.0 then
    return query select false, 'POOR_ACCURACY', 'Location accuracy too poor';
    return;
  end if;

  -- Biometric freshness (attendance only)
  if p_event_type in ('ATTEND_IN','ATTEND_OUT') then
    if not p_biometric_verified then
      return query select false, 'BIOMETRIC_REQUIRED', 'Biometric verification required';
      return;
    end if;

    if p_biometric_timestamp is null then
      return query select false, 'BIOMETRIC_TIMESTAMP_MISSING', 'Biometric timestamp required';
      return;
    end if;

    biometric_age := p_event_timestamp - p_biometric_timestamp;
    if biometric_age > interval '5 minutes' then
      return query select false, 'BIOMETRIC_STALE', 'Biometric verification too old';
      return;
    end if;

    -- Sequence
    select event_type into last_event_type
    from public.attendance_events
    where user_id = p_user_id
      and session_id = p_session_id
      and event_type in ('ATTEND_IN','ATTEND_OUT')
      and status = 'CONFIRMED'
    order by event_timestamp desc
    limit 1;

    if last_event_type = p_event_type then
      return query select false, 'DUPLICATE_EVENT', 'Cannot perform same action twice in a row';
      return;
    end if;

    if p_event_type = 'ATTEND_OUT' and (last_event_type is null or last_event_type = 'ATTEND_OUT') then
      return query select false, 'SIGN_OUT_WITHOUT_SIGN_IN', 'Cannot sign out without signing in first';
      return;
    end if;
  end if;

  -- All good
  return query select true, null::text, null::text;
end
$$;

-- 6) RPC: validate_attendance(event_data jsonb) → jsonb
create or replace function public.validate_attendance(event_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_device_id uuid;
  v_session_id uuid;
  v_event_type text;
  v_timestamp timestamptz;
  v_lat double precision;
  v_lng double precision;
  v_acc double precision;
  v_bio_ok boolean;
  v_bio_ts timestamptz;
  v_dedupe_key text;
  v_client_event_id uuid;

  v_validation record;
  v_event_id uuid;
  v_result jsonb;
begin
  -- Extract fields
  v_user_id := (event_data->>'user_id')::uuid;
  v_device_id := (event_data->>'device_id')::uuid;
  v_session_id := (event_data->>'session_id')::uuid;
  v_event_type := event_data->>'event_type';
  v_timestamp := (event_data->>'timestamp')::timestamptz;
  v_lat := (event_data->'location'->>'lat')::double precision;
  v_lng := (event_data->'location'->>'lng')::double precision;
  v_acc := (event_data->'location'->>'accuracy')::double precision;
  v_bio_ok := coalesce((event_data->>'biometric_ok')::boolean, false);
  v_bio_ts := (event_data->>'biometric_timestamp')::timestamptz;
  v_dedupe_key := event_data->>'dedupe_key';
  v_client_event_id := (event_data->>'client_event_id')::uuid;

  -- Idempotency check
  select id into v_event_id from public.attendance_events where dedupe_key = v_dedupe_key;
  if found then
    select jsonb_build_object(
      'status', status,
      'reason', coalesce(server_reason, 'Event already processed'),
      'event_id', id,
      'duplicate', true
    ) into v_result
    from public.attendance_events where id = v_event_id;

    return v_result;
  end if;

  -- Validate
  select * into v_validation
  from public.validate_attendance_rules(
    v_user_id, v_session_id, v_device_id, v_event_type,
    v_timestamp, v_lat, v_lng, v_acc, v_bio_ok, v_bio_ts
  );

  -- Insert new event with server decision
  insert into public.attendance_events (
    user_id, device_id, session_id, event_type,
    event_timestamp, location_lat, location_lng, location_accuracy,
    biometric_verified, biometric_timestamp,
    dedupe_key, client_event_id,
    status, server_reason, raw_payload
  ) values (
    v_user_id, v_device_id, v_session_id, v_event_type,
    v_timestamp, v_lat, v_lng, v_acc,
    v_bio_ok, v_bio_ts,
    v_dedupe_key, v_client_event_id,
    case when v_validation.is_valid then 'CONFIRMED' else 'REJECTED' end,
    case when v_validation.is_valid then 'Event validated successfully'
         else coalesce(v_validation.error_code,'ERROR') || ': ' || coalesce(v_validation.error_message,'') end,
    event_data
  ) returning id into v_event_id;

  return jsonb_build_object(
    'status', case when v_validation.is_valid then 'CONFIRMED' else 'REJECTED' end,
    'reason', case when v_validation.is_valid then 'Event validated successfully'
                   else coalesce(v_validation.error_code,'ERROR') || ': ' || coalesce(v_validation.error_message,'') end,
    'event_id', v_event_id,
    'duplicate', false
  );
end
$$;

-- 7) RPC: record_heartbeat(heartbeat_data jsonb) → jsonb
create or replace function public.record_heartbeat(heartbeat_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (heartbeat_data->>'user_id')::uuid;
  v_device_id uuid := (heartbeat_data->>'device_id')::uuid;
  v_session_id uuid := (heartbeat_data->>'session_id')::uuid;
  v_timestamp timestamptz := (heartbeat_data->>'timestamp')::timestamptz;
  v_lat double precision := (heartbeat_data->'location'->>'lat')::double precision;
  v_lng double precision := (heartbeat_data->'location'->>'lng')::double precision;
  v_acc double precision := (heartbeat_data->'location'->>'accuracy')::double precision;
  v_dedupe_key text := heartbeat_data->>'dedupe_key';
  v_client_event_id uuid := (heartbeat_data->>'client_event_id')::uuid;
  v_event_id uuid;
begin
  -- Idempotency
  select id into v_event_id from public.attendance_events where dedupe_key = v_dedupe_key;
  if found then
    return jsonb_build_object(
      'status','CONFIRMED',
      'reason','Heartbeat already recorded',
      'event_id', v_event_id,
      'duplicate', true
    );
  end if;

  -- Insert heartbeat directly (no biometric or geofence enforcement here)
  insert into public.attendance_events (
    user_id, device_id, session_id, event_type,
    event_timestamp, location_lat, location_lng, location_accuracy,
    biometric_verified, dedupe_key, client_event_id,
    status, server_reason, raw_payload
  ) values (
    v_user_id, v_device_id, v_session_id, 'HEARTBEAT',
    v_timestamp, v_lat, v_lng, v_acc,
    false, v_dedupe_key, v_client_event_id,
    'CONFIRMED', 'Heartbeat recorded successfully', heartbeat_data
  ) returning id into v_event_id;

  return jsonb_build_object(
    'status','CONFIRMED',
    'reason','Heartbeat recorded successfully',
    'event_id', v_event_id,
    'duplicate', false
  );
end
$$;

-- 8) Seed (can re-run safely)
insert into public.users (id, email, full_name)
values ('550e8400-e29b-41d4-a716-446655440000','test@example.com','Test User')
on conflict (email) do nothing;

insert into public.devices (id, user_id, device_identifier, label, is_trusted)
values ('550e8400-e29b-41d4-a716-446655440001','550e8400-e29b-41d4-a716-446655440000','test-device-001','Test Device', true)
on conflict (user_id, device_identifier) do nothing;

-- IMPORTANT: Update coordinates to your location before running
insert into public.sessions (
  id, name, description, starts_at, ends_at, geofence_center, geofence_radius_m, created_by
) values (
  '550e8400-e29b-41d4-a716-446655440002',
  'Test Session',
  'Test attendance session for development',
  now() - interval '1 hour',
  now() + interval '8 hours',
  ST_SetSRID(ST_MakePoint(125.353906, 6.682057), 4326)::geography, -- CHANGE to your lng/lat
  100,
  '550e8400-e29b-41d4-a716-446655440000'
)
on conflict (id) do nothing;

-- 9) RLS (Row-Level Security)
alter table public.users enable row level security;
alter table public.devices enable row level security;
alter table public.sessions enable row level security;
alter table public.attendance_events enable row level security;

-- Allow users to see and manage their own data (basic policies)
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='users' and policyname='Users can access their row') then
    create policy "Users can access their row" on public.users
      for all using (auth.uid() = id);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='devices' and policyname='Users manage own devices') then
    create policy "Users manage own devices" on public.devices
      for all using (auth.uid() = user_id);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='sessions' and policyname='Sessions readable') then
    create policy "Sessions readable" on public.sessions
      for select using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='attendance_events' and policyname='Users manage own events') then
    create policy "Users manage own events" on public.attendance_events
      for all using (auth.uid() = user_id);
  end if;
end$$;

-- 10) Summary view (optional)
create or replace view public.attendance_summary as
select
  ae.user_id,
  ae.session_id,
  s.name as session_name,
  count(*) as total_events,
  count(*) filter (where ae.event_type = 'ATTEND_IN') as sign_ins,
  count(*) filter (where ae.event_type = 'ATTEND_OUT') as sign_outs,
  count(*) filter (where ae.event_type = 'HEARTBEAT') as heartbeats,
  count(*) filter (where ae.status = 'CONFIRMED') as confirmed_events,
  count(*) filter (where ae.status = 'REJECTED') as rejected_events,
  min(ae.event_timestamp) as first_event,
  max(ae.event_timestamp) as last_event
from public.attendance_events ae
join public.sessions s on s.id = ae.session_id
group by ae.user_id, ae.session_id, s.name;

-- Done