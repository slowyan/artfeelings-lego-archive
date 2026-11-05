-- Run in Supabase SQL Editor after auth-course-access.sql.
-- Adds expiring course access and admin-only account listing/management.

alter table public.profiles
  add column if not exists course_access_until timestamptz;

drop function if exists public.admin_set_course_access(uuid, boolean);

create or replace function public.admin_set_course_access(
  p_user_id uuid,
  p_has_course_access boolean,
  p_access_until timestamptz default null
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
  if p_has_course_access and p_access_until is not null and p_access_until <= now() then
    raise exception 'course access expiry must be in the future' using errcode = '22023';
  end if;

  update public.profiles
  set has_course_access = p_has_course_access,
      course_access_until = case when p_has_course_access then p_access_until else null end
  where id = p_user_id;

  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_set_course_access(uuid, boolean, timestamptz) from public;
grant execute on function public.admin_set_course_access(uuid, boolean, timestamptz) to authenticated;

create or replace function public.admin_list_course_users()
returns table(
  user_id uuid,
  email text,
  username text,
  role text,
  has_course_access boolean,
  course_access_until timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_course_admin() then
    raise exception 'admin role required' using errcode = '42501';
  end if;
  return query
    select p.id, u.email::text, p.username, p.role,
           p.has_course_access, p.course_access_until, p.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    order by p.created_at asc;
end;
$$;
revoke all on function public.admin_list_course_users() from public;
grant execute on function public.admin_list_course_users() to authenticated;

-- Expired grants stop task progress; comments remain available until access is revoked.
drop policy if exists "Read tasks for course members" on public.completed_tasks;
drop policy if exists "Complete tasks for course members" on public.completed_tasks;
drop policy if exists "Undo tasks for course members" on public.completed_tasks;
drop policy if exists "Read tasks for active course members" on public.completed_tasks;
drop policy if exists "Complete tasks for active course members" on public.completed_tasks;
drop policy if exists "Undo tasks for active course members" on public.completed_tasks;
create policy "Read tasks for active course members"
  on public.completed_tasks for select to authenticated
  using (
    public.is_course_admin() or (
      user_id = (select auth.uid()) and exists (
        select 1 from public.profiles p
        where p.id = (select auth.uid()) and p.has_course_access
          and (p.course_access_until is null or p.course_access_until > now())
      )
    )
  );
create policy "Complete tasks for active course members"
  on public.completed_tasks for insert to authenticated
  with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.has_course_access
        and (p.course_access_until is null or p.course_access_until > now())
    )
  );
create policy "Undo tasks for active course members"
  on public.completed_tasks for delete to authenticated
  using (
    public.is_course_admin() or (
      user_id = (select auth.uid()) and exists (
        select 1 from public.profiles p
        where p.id = (select auth.uid()) and p.has_course_access
          and (p.course_access_until is null or p.course_access_until > now())
      )
    )
  );

drop policy if exists "Course members read lesson comments" on public.lesson_comments;
drop policy if exists "Course members add own comments" on public.lesson_comments;
drop policy if exists "Authors edit own comments or admin" on public.lesson_comments;
drop policy if exists "Authors delete own comments or admin" on public.lesson_comments;
drop policy if exists "Active course members read lesson comments" on public.lesson_comments;
drop policy if exists "Active course members add own comments" on public.lesson_comments;
create policy "Course members read lesson comments after expiry"
  on public.lesson_comments for select to authenticated
  using (
    public.is_course_admin() or exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.has_course_access
    )
  );
create policy "Course members add own comments after expiry"
  on public.lesson_comments for insert to authenticated
  with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.has_course_access
    )
  );
create policy "Authors edit own comments or admin"
  on public.lesson_comments for update to authenticated
  using (
    public.is_course_admin() or (user_id = (select auth.uid()) and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.has_course_access
    ))
  )
  with check (
    public.is_course_admin() or (user_id = (select auth.uid()) and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.has_course_access
    ))
  );
create policy "Authors delete own comments or admin"
  on public.lesson_comments for delete to authenticated
  using (
    public.is_course_admin() or (user_id = (select auth.uid()) and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.has_course_access
    ))
  );
