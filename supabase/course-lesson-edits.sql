-- Run once in Supabase SQL Editor after schema.sql and auth-course-access.sql.
-- Stores the two editable lesson versions centrally so course members see the same text.

create table public.course_lesson_edits (
  module_index integer not null check (module_index >= 0),
  lesson_title text not null check (char_length(lesson_title) between 1 and 300),
  original_text text not null default '',
  christian_text text not null default '',
  updated_at timestamptz not null default now(),
  primary key (module_index, lesson_title)
);

alter table public.course_lesson_edits enable row level security;

create function public.read_course_lesson_edits()
returns table (
  module_index integer,
  lesson_title text,
  original_text text,
  christian_text text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_course_admin() and not exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.has_course_access
      and (p.course_access_until is null or p.course_access_until > now())
  ) then
    raise exception 'active course access required' using errcode = '42501';
  end if;

  return query
  select e.module_index, e.lesson_title, e.original_text, e.christian_text, e.updated_at
  from public.course_lesson_edits e;
end;
$$;

create function public.admin_save_course_lesson_text(
  p_module_index integer,
  p_lesson_title text,
  p_original_text text,
  p_christian_text text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_course_admin() then
    raise exception 'admin role required' using errcode = '42501';
  end if;
  if p_module_index < 0 or char_length(trim(p_lesson_title)) not between 1 and 300 then
    raise exception 'invalid lesson identifier' using errcode = '22023';
  end if;

  insert into public.course_lesson_edits (
    module_index, lesson_title, original_text, christian_text, updated_at
  ) values (
    p_module_index, trim(p_lesson_title), coalesce(p_original_text, ''), coalesce(p_christian_text, ''), now()
  )
  on conflict (module_index, lesson_title) do update
  set original_text = excluded.original_text,
      christian_text = excluded.christian_text,
      updated_at = now();
end;
$$;
