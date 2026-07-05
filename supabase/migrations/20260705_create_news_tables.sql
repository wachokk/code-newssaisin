-- 適用済み: 2026-07-05 に Supabase プロジェクト rsykqkjcolptspzrpucx へ
-- (mcp__Supabase__apply_migration / migration name: create_news_tables)
-- このファイルはスキーマの記録用。再構築時は Supabase MCP か CLI で適用する。

-- 日次AIニュース収集の実行履歴
create table public.news_runs (
  id uuid primary key default gen_random_uuid(),
  run_date date not null default (now() at time zone 'Asia/Tokyo')::date,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  item_count integer not null default 0,
  status text not null default 'running' check (status in ('running', 'completed', 'failed')),
  notes text
);

-- 収集したニュース記事
create table public.news_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references public.news_runs (id) on delete set null,
  collected_date date not null default (now() at time zone 'Asia/Tokyo')::date,
  category text not null check (category in ('ai_general', 'ai_education')),
  title text not null,
  url text not null unique,
  source text,
  published_at date,
  summary text not null,
  key_points jsonb,
  tags text[] default '{}',
  importance smallint check (importance between 1 and 5),
  language text not null default 'ja',
  created_at timestamptz not null default now()
);

create index news_items_collected_date_idx on public.news_items (collected_date desc);
create index news_items_category_idx on public.news_items (category);
create index news_items_published_at_idx on public.news_items (published_at desc);

-- 外部公開はしない(書き込みはMCP経由のサーバーサイドのみ)。
-- RLSを有効化しポリシーを作らないことで anon/authenticated からのアクセスを遮断する。
alter table public.news_runs enable row level security;
alter table public.news_items enable row level security;

comment on table public.news_items is '毎朝5時の定期収集で蓄積するAI/AI教育ニュース';
comment on table public.news_runs is '日次ニュース収集の実行ログ';
