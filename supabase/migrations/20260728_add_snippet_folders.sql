-- Additive, private folder filing for clipboard snippets.
create table if not exists public.folders (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.folders add column if not exists user_id uuid default auth.uid() references auth.users(id) on delete cascade;
create index if not exists folders_user_id_idx on public.folders(user_id);

create table if not exists public.snippet_folders (
    snippet_id uuid not null references public.clipboard_items(id) on delete cascade,
    folder_id uuid not null references public.folders(id) on delete cascade,
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    added_at timestamptz not null default now(),
    primary key (snippet_id, folder_id)
);

create index if not exists snippet_folders_user_id_idx on public.snippet_folders(user_id);
create index if not exists snippet_folders_folder_id_idx on public.snippet_folders(folder_id);

-- Preserve assignments from the former one-folder-per-item model when that column exists.
do $$
begin
    if exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'clipboard_items'
          and column_name = 'folder_id'
    ) then
        execute $migration$
            insert into public.snippet_folders (snippet_id, folder_id, user_id)
            select ci.id, ci.folder_id, f.user_id
            from public.clipboard_items ci
            join public.folders f on f.id = ci.folder_id
            where ci.folder_id is not null and f.user_id is not null
            on conflict (snippet_id, folder_id) do nothing
        $migration$;
    end if;
end $$;

alter table public.folders enable row level security;
alter table public.snippet_folders enable row level security;

drop policy if exists "folders_select_own" on public.folders;
drop policy if exists "folders_insert_own" on public.folders;
drop policy if exists "folders_update_own" on public.folders;
drop policy if exists "folders_delete_own" on public.folders;
create policy "folders_select_own" on public.folders for select using (auth.uid() = user_id);
create policy "folders_insert_own" on public.folders for insert with check (auth.uid() = user_id);
create policy "folders_update_own" on public.folders for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "folders_delete_own" on public.folders for delete using (auth.uid() = user_id);

drop policy if exists "snippet_folders_select_own" on public.snippet_folders;
drop policy if exists "snippet_folders_insert_own" on public.snippet_folders;
drop policy if exists "snippet_folders_delete_own" on public.snippet_folders;
create policy "snippet_folders_select_own" on public.snippet_folders for select using (auth.uid() = user_id);
create policy "snippet_folders_insert_own" on public.snippet_folders for insert with check (
    auth.uid() = user_id
    and exists (select 1 from public.folders f where f.id = folder_id and f.user_id = auth.uid())
);
create policy "snippet_folders_delete_own" on public.snippet_folders for delete using (auth.uid() = user_id);
