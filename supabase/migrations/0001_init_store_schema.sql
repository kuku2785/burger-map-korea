create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null,
  latitude double precision not null,
  longitude double precision not null,
  burger_style text,
  verification_status text not null default 'pending',
  is_active boolean not null default false,
  source_type text not null,
  source_as_of date,
  verified_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint stores_name_nonempty check (btrim(name) <> ''),
  constraint stores_address_nonempty check (btrim(address) <> ''),
  constraint stores_latitude_range check (latitude between -90 and 90),
  constraint stores_longitude_range check (longitude between -180 and 180),
  constraint stores_burger_style_nonempty check (
    burger_style is null or btrim(burger_style) <> ''
  ),
  constraint stores_verification_status_allowed check (
    verification_status in ('pending', 'needs_recheck', 'verified', 'rejected')
  ),
  constraint stores_source_type_allowed check (
    source_type in (
      'public_data',
      'manual_review',
      'user_submission',
      'owner_submission',
      'mixed'
    )
  ),
  constraint stores_verified_at_consistent check (
    (verification_status = 'verified' and verified_at is not null)
    or (verification_status <> 'verified' and verified_at is null)
  )
);

create index stores_public_map_coordinates_idx
  on public.stores (latitude, longitude)
  where verification_status = 'verified' and is_active = true;

create or replace function public.set_stores_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger stores_set_updated_at
before update on public.stores
for each row
execute function public.set_stores_updated_at();

alter table public.stores enable row level security;

revoke all privileges on table public.stores from anon, authenticated;
grant select on table public.stores to anon, authenticated;

create policy stores_public_read_verified_active
on public.stores
for select
to anon, authenticated
using (
  verification_status = 'verified'
  and is_active = true
);
