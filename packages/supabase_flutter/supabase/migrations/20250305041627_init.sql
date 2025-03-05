-- create a table for posts
create table posts (
  id uuid primary key default gen_random_uuid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  title text not null,
  content text,
  user_id uuid references auth.users(id) on delete cascade,
  published boolean default false not null
);

-- enable row level security
alter table posts enable row level security;

-- create policies
-- policy to allow users to view published posts
create policy "anyone can view published posts" on posts
  for select using (published = true);

-- policy to allow users to insert their own posts
create policy "users can insert their own posts" on posts
  for insert with check ((select auth.uid()) = user_id);

-- policy to allow users to update their own posts
create policy "users can update their own posts" on posts
  for update using ((select auth.uid()) = user_id);

-- policy to allow users to delete their own posts
create policy "users can delete their own posts" on posts
  for delete using ((select auth.uid()) = user_id);

-- enable realtime for the posts table
alter publication supabase_realtime add table posts;
