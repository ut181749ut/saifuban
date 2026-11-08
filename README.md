# AIの財布番 (Saifuban) — a spending guard for AI agents

**AIがお金を使う前に、あなたのスマホに承認を聞きにくる MCP サーバー。**
**An MCP server that makes AI agents ask before they spend money — small amounts are auto-approved, larger ones go to your phone for one-tap approval.**

👉 https://ut181749ut.github.io/saifuban/

---

## 日本語

AIエージェントは支払いの前に財布番に「払っていいか」を聞きます。財布番はあなたが決めたルールで答えます。

- 少額(例: 300円以下)は自動で許可
- それを超えるとスマホに通知 → 承認 / 却下をワンタップ
- 1日の予算・1回の上限・支払先の制限
- 緊急停止ボタン
- AIごとに別々のルール

財布番はお金を動かしません。カード情報や口座は預かりません。

### 使い方

1. サイトで「はじめる」→ 予算を選ぶ → AI用のURLが出る
2. そのURLをAIに登録(Claude: コネクタ / ChatGPT: 開発者モードのアプリ / Muse: チャットでURLを送る / Cursor・VS Code: MCP設定)
3. AIに「財布番で今日の残り予算を見て」と聞いて確認

## English

Your AI agent asks Saifuban before every payment. Saifuban answers using your rules.

- Auto-approve small amounts (e.g. under ¥300)
- Anything above goes to your phone as a push notification — approve or reject in one tap
- Daily budget, per-transaction limit, allowed merchants
- Kill switch
- Separate rules per agent

Saifuban never moves money and never stores card or bank details. It only decides whether a payment is allowed.

### Setup

1. Open the site, press "はじめる" (Start), pick a budget — you get a personal MCP URL
2. Add the URL to your AI as a remote MCP server (Streamable HTTP, no auth — the key is in the URL)
3. Ask your AI: "Check my remaining budget with Saifuban"

## MCP tools

| Tool | What it does |
|---|---|
| `request_payment` | Ask whether a payment (`merchant`, `amount`, `currency` JPY/USD, `reason`) is allowed. Waits up to 45 s for phone approval. Returns a single-use `payment_token` when approved. |
| `check_payment_status` | Check whether a pending request was approved. |
| `get_budget` | Remaining budget today, per-transaction limit, auto-approve threshold, allowed merchants. |

Endpoint: `https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1/saifuban-mcp/<your-key>` (get your key on the site)

## Hard enforcement: single-use payment tokens

Calling `request_payment` is voluntary, so a prompt-injected agent could simply skip it. To make the guard enforceable, every **approved** request comes with a `payment_token` (`sbt_...`):

- single-use, valid for 24 hours
- bound to the approved merchant and amount
- invalid if the AI is stopped or the kill switch is on

Whatever actually moves the money (your payment tool, wrapper, or merchant backend) should require this token and redeem it before paying:

```bash
curl -X POST https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1/saifuban/redeem \
  -H "content-type: application/json" \
  -d '{"token":"sbt_...","merchant":"OpenAI","amount":12.5,"currency":"USD"}'
# => {"valid":true,"consumed":true,...}  or  {"valid":false,"error":"already_used" | "merchant_mismatch" | "amount_exceeds_approval" | ...}
```

`/verify` takes the same body and checks without consuming. No agent key is needed to redeem, so the payment side doesn't have to share secrets with the agent.

API spend is already hard-enforced: when you store your provider API key in Saifuban, the agent only ever gets a proxy key.

## Links

- [利用規約 / Terms](https://ut181749ut.github.io/saifuban/terms.html)
- [プライバシーポリシー / Privacy](https://ut181749ut.github.io/saifuban/privacy.html)
- Issues / requests: https://github.com/ut181749ut/saifuban/issues
