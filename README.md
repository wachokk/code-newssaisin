# code-newssaisin — ニュース最新調査システム

Claude Code のサブエージェント機能を使い、**Fable 5 / Opus / Sonnet を適材適所で使い分けて**ニュースを包括的に調査し、レポートを生成するプロジェクト。

## アーキテクチャ

```
メインセッション(Fable 5)= オーケストレーター
│  調査計画の立案 → 調査観点(アングル)への分解
│
├─ news-scout × N(Sonnet 5)…… 並列でWeb検索・記事収集(観点ごとに1体)
│     └ 収集結果を research/ に構造化して保存
│
├─ news-analyst(Opus 4.8)…… 収集結果の横断分析
│     └ 傾向・対立点・背景文脈・信頼性の評価
│
├─ fact-checker(Opus 4.8)…… 重要ファクトの裏取り・出典検証
│
└─ 最終レポート統合(Fable 5 本体)→ reports/YYYY-MM-DD-<topic>.md
```

## モデルの使い分けと根拠

| 役割 | モデル | 価格(入力/出力 per 1Mトークン) | 選定理由 |
|---|---|---|---|
| オーケストレーター & 最終レポート執筆 | **Claude Fable 5** | $10 / $50 | 最高の推論力と長期タスク遂行力。調査全体の設計判断と、大量の収集情報を一貫したレポートに統合する工程に最も価値が出る |
| 横断分析・ファクトチェック | **Claude Opus 4.8** | $5 / $25 | 検証系タスクに強く、矛盾の検出や情報源の信頼性評価など「深く読む」工程に適する。Fable 5の半額 |
| ニュース収集(並列ファンアウト) | **Claude Sonnet 5** | $3 / $15(2026-08-31まで $2 / $10) | 検索→取得→要約の定型的な工程。速度とコスト効率に優れ、複数体を並列起動しても費用が抑えられる |

**設計原則:トークン消費が最も多い「幅の広い収集」を安いモデルに、判断の質が結果を左右する「統合・検証」を高いモデルに割り当てる。** 収集した生データはサブエージェント内で消費され、要約だけがメインセッションに戻るため、Fable 5 のコンテキストとコストを節約できる。

## 使い方

このリポジトリを Claude Code で開き、以下を実行:

```
/news-research 半導体業界の最新動向
```

オプションで観点数や期間を指定:

```
/news-research 生成AI規制 --angles 6 --days 7
```

完了すると `reports/` に日付き Markdown レポートが生成される。

## 日次ニュース蓄積(Supabase)

`/news-research`(レポート生成)とは別に、**毎朝5時(JST)にAI全般とAI×教育の最新ニュースを自動収集し、Supabaseに蓄積する**仕組みを持つ。

```
定期トリガー(Claude Code Routines, 毎朝5:00 JST)
│  新規クラウドセッションを起動し /daily-news-ingest を実行
│
├─ news-scout × 2(Sonnet 5)…… 並列収集
│     ├ AI全般(モデル・研究・業界・規制)      → category: ai_general
│     └ AI×教育(EdTech・導入事例・教育政策)   → category: ai_education
│
└─ メインセッション …… 構造化して Supabase へ INSERT
      ├ news_items(記事。url ユニーク制約で重複自動排除)
      └ news_runs(実行ログ)
```

- **Supabase プロジェクト**: `rsykqkjcolptspzrpucx`(ap-northeast-1)
- **スキーマ**: `supabase/migrations/20260705_create_news_tables.sql`(適用済み)
- **ワークフロー定義**: `.claude/commands/daily-news-ingest.md`(手動実行も可: `/daily-news-ingest`)
- **スケジュール管理**: [claude.ai/code/routines](https://claude.ai/code/routines) から確認・変更・一時停止できる
- 両テーブルはRLS有効・ポリシーなし(=RESTからの外部アクセス遮断)。読み書きはSupabase MCP経由

蓄積データの例(直近7日の教育関連を新しい順に):

```sql
select collected_date, title, source, url, importance
from news_items
where category = 'ai_education' and collected_date > current_date - 7
order by collected_date desc, importance desc;
```

## ディレクトリ構成

| パス | 用途 |
|---|---|
| `.claude/agents/` | サブエージェント定義(scout / analyst / fact-checker) |
| `.claude/commands/news-research.md` | 調査ワークフローを起動するスラッシュコマンド |
| `.claude/commands/daily-news-ingest.md` | 日次収集→Supabase蓄積ワークフロー |
| `supabase/migrations/` | Supabaseスキーマの記録 |
| `research/` | 収集・分析の中間成果物(調査ごとにサブディレクトリ) |
| `reports/` | 最終レポート |

## ワークフロー詳細

1. **計画(Fable 5)** — トピックを4〜6個の独立した調査観点に分解(例:市場動向 / 主要プレイヤー / 規制 / 技術 / 世論・リスク)
2. **並列収集(Sonnet 5 × N)** — 各観点に news-scout を同時起動。Web検索で直近の記事を集め、`research/<調査ID>/scout-<観点>.md` に「事実・出典URL・日付・一次/二次の別」を構造化して保存
3. **横断分析(Opus 4.8)** — news-analyst が全 scout 出力を読み、トレンド・対立する報道・情報の欠落・信頼性を分析して `analysis.md` を作成
4. **検証(Opus 4.8)** — fact-checker がレポートの根幹となる主張(数値・引用・因果関係)を抽出し、Web で裏取り。確認できないものは「未確認」とラベル付け
5. **統合(Fable 5)** — メインセッションが分析と検証結果を統合し、エグゼクティブサマリー付きの最終レポートを執筆

## コスト目安(1回の調査あたり)

概算(観点4つ・標準的な記事量の場合):

- Sonnet scout × 4:約 40〜80万トークン消費 → **$1.5〜3**
- Opus analyst + fact-checker:約 20〜40万トークン → **$1.5〜3**
- Fable 5 本体(計画+統合):約 10〜20万トークン → **$2〜5**

**合計:おおよそ $5〜11 / 回**。全工程を Fable 5 単体で行った場合の半額以下で、収集の並列化により所要時間も短縮される。

## 発展的な構成(API直接利用)

Claude Code を介さず Anthropic API で同等のシステムを組む場合は、Managed Agents の multiagent(coordinator)機能、または Messages API + `web_search_20260209` サーバーツールで実装できる。その際の要点:

- Fable 5 は `thinking` パラメータ不要(常時ON)。`output_config.effort` で深さを制御
- Fable 5 には `fallbacks: [{"model": "claude-opus-4-8"}]`(beta `server-side-fallback-2026-06-01`)を既定で付与し、安全分類器の誤検知に備える
- 収集ワーカーは Batches API(50%割引)に載せるとさらに安価
