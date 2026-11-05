-- Run in Supabase SQL Editor after course-access-expiration.sql.
-- Adds task score and latest sign-in/task/comment activity to the admin user list.

create function public.admin_list_course_user_activity()
returns table(
  user_id uuid,
  email text,
  username text,
  role text,
  has_course_access boolean,
  course_access_until timestamptz,
  created_at timestamptz,
  points bigint,
  completed_task_count bigint,
  last_activity_at timestamptz
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
    select p.id,
           u.email::text,
           p.username,
           p.role,
           p.has_course_access,
           p.course_access_until,
           p.created_at,
           coalesce(tasks.task_count, 0)::bigint,
           coalesce(tasks.task_count, 0)::bigint,
           greatest(u.last_sign_in_at, tasks.last_task_at, comments.last_comment_at)
    from public.profiles p
    join auth.users u on u.id = p.id
    left join lateral (
      select count(*)::bigint as task_count, max(t.completed_at) as last_task_at
      from public.completed_tasks t
      where t.user_id = p.id
    ) tasks on true
    left join lateral (
      select max(c.created_at) as last_comment_at
      from public.lesson_comments c
      where c.user_id = p.id
    ) comments on true
    order by p.created_at desc;
end;
$$;

