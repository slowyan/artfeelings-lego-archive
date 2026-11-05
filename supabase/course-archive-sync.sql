-- Run once after course-lesson-edits.sql.
-- Stores the shared, administrator-managed course archive as one JSON document.

create table public.course_archive_data (
  singleton boolean primary key default true check (singleton),
  archive jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.course_archive_data enable row level security;

create function public.read_course_archive_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.is_course_admin() and not exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.has_course_access
      and (p.course_access_until is null or p.course_access_until > now())
  ) then
    raise exception 'active course access required' using errcode = '42501';
  end if;

  select d.archive into result from public.course_archive_data d where d.singleton;
  return result;
end;
$$;

create function public.admin_save_course_archive(p_archive jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_course_admin() then
    raise exception 'admin role required' using errcode = '42501';
  end if;
  if p_archive is null or jsonb_typeof(p_archive) <> 'object' then
    raise exception 'course archive must be a JSON object' using errcode = '22023';
  end if;

  insert into public.course_archive_data (singleton, archive, updated_at)
  values (true, p_archive, now())
  on conflict (singleton) do update
  set archive = excluded.archive, updated_at = now();
end;
$$;
