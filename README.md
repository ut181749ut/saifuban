# AIの財布番 (Saifuban) — a spending guard for AI agents

**AIがお金を使う前に、あなたのスマホに承認を聞きにくる。AIエージェントのAPI代も1日の予算で止める。日本語・円で使えます。**
**Hard daily caps on your AI agents' API spend, plus phone approval before any other payment.**

👉 https://ut181749ut.github.io/saifuban/

<img src="demo-ja.gif" width="420" alt="デモ: AIが無断で支払おうとして、スマホで却下する">

---

## 日本語

AIエージェントは支払いの前に財布番に「払っていいか」を聞きます。財布番はあなたが決めたルールで答えます。

- 少額(例: 300円以下)は自動で許可
- それを超えるとスマホに通知 → 承認 / 却下をワンタップ
- 1日の予算・1回の上限・支払先の制限
- 緊急停止ボタン
- AIごとに別々のルール
- APIキーを預ければ、AIエージェントのAPI代も1日の予算で強制停止(AIには代理のキーだけを渡す)
- 日本語・円で使える。メール登録なし・無料

財布番はお金を動かしません。カード情報や口座は預かりません。

### 使い方

1. サイトで「はじめる」→ 予算を選ぶ → AI用のURLが出る
2. そのURLをAIに登録(Claude: コネクタ / ChatGPT: 開発者モードのアプリ / Muse: チャットでURLを送る / Cursor・VS Code: MCP設定)
3. AIに「財布番で今日の残り予算を見て」と聞いて確認

## English

**Stop your AI agents from overspending.** Saifuban puts a hard daily cap on your agents' API bills and makes them ask your phone before any other payment.

<img src="api-en.gif" width="420" alt="Demo: an agent loops overnight and Saifuban stops its API calls at the daily budget">

### Hard cap on API bills

Store your OpenAI, Anthropic, Google or OpenRouter key in Saifuban. Your agent only gets a proxy key (`sbk_...`), every call is metered, and requests are refused once the agent's daily budget is reached. Your real key never reaches the agent.

### Phone approval for everything else

<img src="demo-en.gif" width="420" alt="Demo: the AI tries to pay on its own and you reject it from your phone">

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
