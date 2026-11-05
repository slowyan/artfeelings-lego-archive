-- Apply after schema.sql in Supabase SQL Editor.
-- New accounts begin with no course access; only admins can change that flag.

alter table public.profiles
  add column if not exists has_course_access boolean not null default false;

update public.profiles set has_course_access = true where role = 'admin';

create or replace function public.admin_set_course_access(
  p_user_id uuid,
  p_has_course_access boolean
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
  update public.profiles
  set has_course_access = p_has_course_access
  where id = p_user_id;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_set_course_access(uuid, boolean) from public;
grant execute on function public.admin_set_course_access(uuid, boolean) to authenticated;

-- Store a public display name from registration metadata, with a unique fallback.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_username text;
  chosen_username text;
begin
  base_username := left(coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
    nullif(split_part(new.email, '@', 1), ''),
    'Участник'
  ), 47);
  chosen_username := base_username;
  if exists (select 1 from public.profiles p where p.username = chosen_username) then
    chosen_username := base_username || '-' || substr(replace(new.id::text, '-', ''), 1, 12);
  end if;
  insert into public.profiles (id, username, role)
  values (new.id, chosen_username, 'student');
  return new;
end;
$$;

-- Profile rows are visible only to the owner and course administrators.
drop policy if exists "Authenticated can read profiles" on public.profiles;
drop policy if exists "Read own profile or admin" on public.profiles;
create policy "Read own profile or admin"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_course_admin());
grant select on public.profiles to authenticated;

-- Prevent users from changing their own role/access flag through the Data API.
revoke update on public.profiles from authenticated;
grant update (username) on public.profiles to authenticated;

-- Existing task policies are replaced with course-access-aware policies.
drop policy if exists "Read own tasks or admin" on public.completed_tasks;
drop policy if exists "Complete own tasks" on public.completed_tasks;
drop policy if exists "Undo own tasks" on public.completed_tasks;
drop policy if exists "Read tasks for course members" on public.completed_tasks;
drop policy if exists "Complete tasks for course members" on public.completed_tasks;
drop policy if exists "Undo tasks for course members" on public.completed_tasks;
create policy "Read tasks for course members"
  on public.completed_tasks for select to authenticated
  using (
    public.is_course_admin() or (user_id = (select auth.uid()) and exists (
      select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
    ))
  );
create policy "Complete tasks for course members"
  on public.completed_tasks for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
  ));
create policy "Undo tasks for course members"
  on public.completed_tasks for delete to authenticated
  using (public.is_course_admin() or (user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
  )));

-- Existing lesson-comment policies are replaced with course-access-aware policies.
drop policy if exists "Signed-in users read lesson comments" on public.lesson_comments;
drop policy if exists "Users add comments as themselves" on public.lesson_comments;
drop policy if exists "Authors edit own comments or admin" on public.lesson_comments;
drop policy if exists "Authors delete own comments or admin" on public.lesson_comments;
drop policy if exists "Course members read lesson comments" on public.lesson_comments;
drop policy if exists "Course members add own comments" on public.lesson_comments;
create policy "Course members read lesson comments"
  on public.lesson_comments for select to authenticated
  using (public.is_course_admin() or exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
  ));
grant select, insert, update, delete on public.completed_tasks to authenticated;
create policy "Course members add own comments"
  on public.lesson_comments for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
  ));
create policy "Authors edit own comments or admin"
  on public.lesson_comments for update to authenticated
  using (public.is_course_admin() or (user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
  )))
  with check (public.is_course_admin() or (user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
  )));
create policy "Authors delete own comments or admin"
  on public.lesson_comments for delete to authenticated
  using (public.is_course_admin() or (user_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.has_course_access
  )));
grant select, insert, update, delete on public.lesson_comments to authenticated;
