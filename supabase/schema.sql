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