-- Artfeelings course: profiles, scores, completed tasks, comments.
-- Run once in Supabase Dashboard -> SQL Editor -> New query.
-- Supabase Auth stores password hashes; never create a password column here.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 1 and 60),
  role text not null default 'student' check (role in ('student', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.completed_tasks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_key text not null check (char_length(task_key) between 1 and 300),
  completed_at timestamptz not null default now(),
  primary key (user_id, task_key)
);

create table if not exists public.lesson_comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  module_index integer not null check (module_index >= 0),
  lesson_title text not null check (char_length(lesson_title) between 1 and 300),
  body text not null check (char_length(body) between 1 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists lesson_comments_lesson_created_idx
  on public.lesson_comments (module_index, lesson_title, created_at desc);

create or replace function public.is_course_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

alter table public.profiles enable row level security;
alter table public.completed_tasks enable row level security;
alter table public.lesson_comments enable row level security;

-- Authenticated users can see names/roles for the course leaderboard.
drop policy if exists "Authenticated can read profiles" on public.profiles;
create policy "Authenticated can read profiles"
  on public.profiles for select to authenticated using (true);

-- Users cannot set their own role. Admins can manage accounts/profiles.
drop policy if exists "Users update own username, admins manage profiles" on public.profiles;
create policy "Users update own username, admins manage profiles"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()) or public.is_course_admin())
  with check (
    (id = (select auth.uid()) and role = 'student')
    or public.is_course_admin()
  );

drop policy if exists "Admins create profiles" on public.profiles;
create policy "Admins create profiles"
  on public.profiles for insert to authenticated
  with check (public.is_course_admin());

drop policy if exists "Admins delete profiles" on public.profiles;
create policy "Admins delete profiles"
  on public.profiles for delete to authenticated
  using (public.is_course_admin());

-- Completion checkboxes are writable only by the current user; admins may inspect all.
drop policy if exists "Read own tasks or admin" on public.completed_tasks;
create policy "Read own tasks or admin"
  on public.completed_tasks for select to authenticated
  using (user_id = (select auth.uid()) or public.is_course_admin());

drop policy if exists "Complete own tasks" on public.completed_tasks;
create policy "Complete own tasks"
  on public.completed_tasks for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Undo own tasks" on public.completed_tasks;
create policy "Undo own tasks"
  on public.completed_tasks for delete to authenticated
  using (user_id = (select auth.uid()) or public.is_course_admin());

-- Signed-in participants can read and add lesson comments; authors can edit/delete theirs.
drop policy if exists "Signed-in users read lesson comments" on public.lesson_comments;
create policy "Signed-in users read lesson comments"
  on public.lesson_comments for select to authenticated using (true);

drop policy if exists "Users add comments as themselves" on public.lesson_comments;
create policy "Users add comments as themselves"
  on public.lesson_comments for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Authors edit own comments or admin" on public.lesson_comments;
create policy "Authors edit own comments or admin"
  on public.lesson_comments for update to authenticated
  using (user_id = (select auth.uid()) or public.is_course_admin())
  with check (user_id = (select auth.uid()) or public.is_course_admin());

drop policy if exists "Authors delete own comments or admin" on public.lesson_comments;
create policy "Authors delete own comments or admin"
  on public.lesson_comments for delete to authenticated
  using (user_id = (select auth.uid()) or public.is_course_admin());

-- Create a profile after an admin creates an Auth user and sets its username metadata.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'username', ''), split_part(new.email, '@', 1)),
    'student'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_auth_user();

-- Bootstrap initial administrator safely:
-- 1) In Supabase Dashboard -> Authentication -> Users, create your own user.
-- 2) Copy its UUID, then run the statement below after replacing the UUID.
--    Do not put a service-role/secret key in the website.
-- update public.profiles set role = 'admin' where id = 'YOUR-AUTH-USER-UUID';

