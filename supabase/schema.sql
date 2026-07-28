-- Clipboard items schema with optimizations
create table if not exists public.clipboard_items (
    id               uuid primary key default gen_random_uuid(),
    type             text not null,
    title            text,
    preview_text     text,
    full_text        text,
    source_app_name  text not null default 'Unknown',
    source_bundle_id text,
    created_at       timestamptz not null default now(),
    is_favorite      boolean not null default false,
    storage_path     text,
    file_name        text,
    file_size        bigint,
    mime_type        text,
    detected_language text,
    rtf_data         text,
    html_data        text,
    rtfd_data        text,
    pasteboard_types jsonb,
    sync_status      text not null default 'synced'
);
create index if not exists clipboard_items_created_at_idx
    on public.clipboard_items (created_at desc);
create index if not exists clipboard_items_type_idx
    on public.clipboard_items (type);
create index if not exists clipboard_items_favorite_idx
    on public.clipboard_items (is_favorite);
create index if not exists clipboard_items_search_idx
    on public.clipboard_items
    using gin (to_tsvector('simple', coalesce(full_text, '') || ' ' || coalesce(source_app_name, '')));
alter table public.clipboard_items enable row level security;
drop policy if exists "anon_select" on public.clipboard_items;
drop policy if exists "anon_insert" on public.clipboard_items;
drop policy if exists "anon_update" on public.clipboard_items;
drop policy if exists "anon_delete" on public.clipboard_items;
create policy "anon_select" on public.clipboard_items
    for select using (true);
create policy "anon_insert" on public.clipboard_items
    for insert with check (true);
create policy "anon_update" on public.clipboard_items
    for update using (true) with check (true);
create policy "anon_delete" on public.clipboard_items
    for delete using (true);
insert into storage.buckets (id, name, public)
values
    ('clipboard-images',   'clipboard-images',   true),
    ('clipboard-files',    'clipboard-files',    true),
    ('clipboard-videos',   'clipboard-videos',   true),
    ('clipboard-previews', 'clipboard-previews', true)
on conflict (id) do nothing;
drop policy if exists "clipboard_storage_read"   on storage.objects;
drop policy if exists "clipboard_storage_write"  on storage.objects;
drop policy if exists "clipboard_storage_update" on storage.objects;
drop policy if exists "clipboard_storage_delete" on storage.objects;
create policy "clipboard_storage_read" on storage.objects
    for select using (bucket_id in ('clipboard-images','clipboard-files','clipboard-videos','clipboard-previews'));
create policy "clipboard_storage_write" on storage.objects
    for insert with check (bucket_id in ('clipboard-images','clipboard-files','clipboard-videos','clipboard-previews'));
create policy "clipboard_storage_update" on storage.objects
    for update using (bucket_id in ('clipboard-images','clipboard-files','clipboard-videos','clipboard-previews'));
create policy "clipboard_storage_delete" on storage.objects
    for delete using (bucket_id in ('clipboard-images','clipboard-files','clipboard-videos','clipboard-previews'));

-- Wardrobe items schema
create table if not exists public.wardrobe_items (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid references auth.users(id) on delete cascade,
    content_type     text not null,
    content          text,
    source           text not null default 'external',
    source_snippet_id uuid,
    source_app_name  text,
    source_bundle_id text,
    storage_path     text,
    file_name        text,
    file_size        bigint,
    mime_type        text,
    created_at       timestamptz not null default now()
);

create index if not exists wardrobe_items_user_id_idx
    on public.wardrobe_items (user_id);
create index if not exists wardrobe_items_created_at_idx
    on public.wardrobe_items (created_at desc);

alter table public.wardrobe_items enable row level security;

drop policy if exists "wardrobe_select" on public.wardrobe_items;
drop policy if exists "wardrobe_insert" on public.wardrobe_items;
drop policy if exists "wardrobe_update" on public.wardrobe_items;
drop policy if exists "wardrobe_delete" on public.wardrobe_items;

create policy "wardrobe_select" on public.wardrobe_items
    for select using (true);
create policy "wardrobe_insert" on public.wardrobe_items
    for insert with check (true);
create policy "wardrobe_update" on public.wardrobe_items
    for update using (true) with check (true);
create policy "wardrobe_delete" on public.wardrobe_items
    for delete using (true);

-- Wardrobe storage bucket
insert into storage.buckets (id, name, public)
values ('wardrobe-items', 'wardrobe-items', true)
on conflict (id) do nothing;

drop policy if exists "wardrobe_storage_read" on storage.objects;
drop policy if exists "wardrobe_storage_write" on storage.objects;
drop policy if exists "wardrobe_storage_update" on storage.objects;
drop policy if exists "wardrobe_storage_delete" on storage.objects;

create policy "wardrobe_storage_read" on storage.objects
    for select using (bucket_id = 'wardrobe-items');
create policy "wardrobe_storage_write" on storage.objects
    for insert with check (bucket_id = 'wardrobe-items');
create policy "wardrobe_storage_update" on storage.objects
    for update using (bucket_id = 'wardrobe-items');
create policy "wardrobe_storage_delete" on storage.objects
    for delete using (bucket_id = 'wardrobe-items');


-- Add file_extension column for icon lookup
ALTER TABLE public.wardrobe_items
ADD COLUMN IF NOT EXISTS file_extension text;

-- Folders table
create table if not exists public.folders (
    id               uuid primary key default gen_random_uuid(),
    name             text not null,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now()
);

create index if not exists folders_created_at_idx
    on public.folders (created_at desc);

alter table public.folders enable row level security;

drop policy if exists "folders_select" on public.folders;
drop policy if exists "folders_insert" on public.folders;
drop policy if exists "folders_update" on public.folders;
drop policy if exists "folders_delete" on public.folders;

create policy "folders_select" on public.folders
    for select using (true);
create policy "folders_insert" on public.folders
    for insert with check (true);
create policy "folders_update" on public.folders
    for update using (true) with check (true);
create policy "folders_delete" on public.folders
    for delete using (true);

-- Add folder_id to clipboard_items if it doesn't exist
ALTER TABLE public.clipboard_items
ADD COLUMN IF NOT EXISTS folder_id uuid references public.folders(id) on delete set null;

create index if not exists clipboard_items_folder_id_idx
    on public.clipboard_items (folder_id);
