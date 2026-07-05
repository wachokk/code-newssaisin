---
description: AI全般とAI×教育の最新ニュースを収集し、Supabase(news_items)に蓄積する日次ワークフロー(毎朝5時の定期実行用。手動実行も可)
argument-hint: [--hours N](収集対象期間。デフォルト24時間)
---

日次のAIニュース収集・蓄積を実行します。引数: $ARGUMENTS

これはデータベース蓄積用の軽量ワークフローです。レポート生成(analyst/fact-checker を使う深掘り調査)は `/news-research` が担当し、このコマンドでは行いません。収集は news-scout(Sonnet)のみで完結させ、コストを抑えます。

## 前提

- **Supabase プロジェクトID**: `rsykqkjcolptspzrpucx`(wachokk's Project / ap-northeast-1)
- 対象テーブル: `public.news_runs`(実行ログ)、`public.news_items`(記事。`url` にユニーク制約があり重複は自動排除)
- Supabase MCP ツール(`mcp__Supabase__execute_sql` など)が未ロードなら ToolSearch でロードする
- 日付・時刻は **JST(Asia/Tokyo)** 基準で扱う

## 0. 準備

- 収集対象期間: `--hours N` があれば直近N時間、なければ直近24時間
- 作業ディレクトリ: `research/daily/<YYYY-MM-DD>/`(JSTの本日日付)
- 実行ログを開始登録する:

```sql
insert into news_runs (status) values ('running') returning id;
```

返ってきた `id` を以降の run_id として使う。

## 1. 並列収集(news-scout × 2)

**2体の news-scout を同一ターンで並列起動する**(直列起動は禁止)。各scoutへのプロンプトには以下を含める:

| scout | 担当観点 | category値 | 出力先 |
|---|---|---|---|
| A | AI全般の最新動向(モデル・製品リリース、研究、企業・業界の動き、規制・政策) | `ai_general` | `research/daily/<日付>/scout-ai-general.md` |
| B | AIを活用した教育(EdTech製品、学校・大学での導入事例、教育政策・ガイドライン、学習効果の研究) | `ai_education` | `research/daily/<日付>/scout-ai-education.md` |

scoutへの共通指示:
- 対象期間は直近N時間(上記)。それより古い記事は原則含めない
- 日本語・英語の両方で検索する
- 5〜15件を目安に収集し、**各記事を必ず次の項目で構造化**する:
  - タイトル / URL / 媒体名 / 公開日(YYYY-MM-DD) / 要約(2〜3文・日本語) / 重要度(1〜5) / タグ(3個程度)
- 同一の話題を複数媒体が報じている場合は最も一次に近いソースを優先する

## 2. Supabase への挿入

両scoutの出力ファイルを読み、全記事を `news_items` に挿入する:

- 1回の `mcp__Supabase__execute_sql` でまとめて multi-row INSERT する
- 文字列は必ずドル引用(`$q$ ... $q$`)でエスケープ問題を回避する
- 重複は `on conflict (url) do nothing` で排除し、`returning id` で実挿入件数を数える

```sql
insert into news_items
  (run_id, category, title, url, source, published_at, summary, key_points, tags, importance, language)
values
  ('<run_id>', 'ai_general', $q$タイトル$q$, $q$https://...$q$, $q$媒体名$q$, '2026-07-05',
   $q$要約テキスト$q$, null, array['タグ1','タグ2'], 4, 'ja'),
  ...
on conflict (url) do nothing
returning id;
```

- `published_at` が不明な記事は null でよい
- 記事の要約が英語ソース由来でも `summary` は日本語で書く(`language` はソース記事の言語)

## 3. 実行ログの完了更新

```sql
update news_runs
set finished_at = now(), item_count = <実挿入件数>, status = 'completed',
    notes = $q$ai_general: X件 / ai_education: Y件 / 重複スキップ: Z件$q$
where id = '<run_id>';
```

途中で失敗した場合は `status = 'failed'` とし、`notes` に原因を記録してから終了する。

## 4. 完了報告

最終メッセージで以下を報告する(記事の全文は繰り返さない):
- 挿入件数(カテゴリ別内訳)と重複スキップ件数
- 特に重要度の高い記事(4〜5)のタイトルを数件
- 失敗・欠落があればその内容
