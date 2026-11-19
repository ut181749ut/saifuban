# AIの財布番 (Saifuban) — a spending guard for AI agents

**AIがお金を使う前に、あなたのスマホに承認を聞きにくる。AIエージェントのAPI代も1日の予算で止める。Claude・ChatGPT・Museで使えて、Museならチャットに1通送るだけ。日本語・円対応。**
**Hard daily caps on your AI agents' API spend, plus phone approval before any other payment.**

👉 https://ut181749ut.github.io/saifuban/

<img src="demo-ja.gif" width="420" alt="デモ: AIが無断で支払おうとして、スマホで却下する">

---

## 日本語

AIエージェントは支払いの前に財布番に「払っていいか」を聞きます。財布番はあなたが決めたルールで答えます。

- 少額(例: 300円以下)は自動で許可
- それを超えるとスマホに通知 → 承認 / 却下をワンタップ
- 1日・1週間・1か月の予算、1回の上限、支払先の制限
- 「聞かずに払う」のを、前に払ったことがある支払先だけにする設定(初めての支払先はスマホで確認)
- 緊急停止ボタン
- AIごとに別々のルール
- サブスク(定期購入)は金額に関係なく必ずスマホで確認。通知に年額を表示。AIが申告し忘れても、理由や支払先の文言から定期購入らしいものを見つけて確認に回す
- AIが自分の過去の申請を調べられる(同じ支払いを二重にしないため)
- APIキーを預ければ、AIエージェントのAPI代も1日・週・月の予算で強制停止(AIには代理のキーだけを渡す)
- LangChain・CrewAI・OpenAI Agents SDK・Vercel AI SDK・Claude Codeでは、接続先と鍵を差し替えるだけ(コード例は英語版の「Use it from your agent framework」)
- 日本語・円で使える。メール登録なし・無料

財布番はお金を動かしません。カード情報や口座は預かりません。

APIキーを他人のサーバーに預けたくない場合は、全部を自分のSupabaseとCloudflare(どちらも無料枠で足ります)で動かせます。手順は [SELF_HOST.md](SELF_HOST.md)。

### 使い方

Claude Codeを使っているなら、Claude Codeの中で3行打つだけです(登録・AI作成・APIキー預け・設定まで全部やります。APIキーをチャットに貼る必要はありません):

```
/plugin marketplace add ut181749ut/saifuban
/plugin install saifuban@saifuban
/saifuban:setup 1000円
```

ターミナルからなら1行です: `npx https://github.com/ut181749ut/saifuban/archive/refs/heads/main.tar.gz`(WindowsのPowerShellでは `npx.cmd`)。手元に入っているAPIキーを見つけて使うか聞いてくれます。お金をかけずに試すなら、Geminiの無料APIキー([aistudio.google.com/apikey](https://aistudio.google.com/apikey))で「Google Gemini」を選んでください。

1. サイトで「はじめる」→ 予算を選ぶ → AI用のURLが出る
2. そのURLをAIに登録(Claude: コネクタ / ChatGPT: 開発者モードのアプリ / Muse: チャットでURLを送る / Cursor・VS Code: MCP設定)

URLをコピーせずにつなぐこともできます(OAuth)。ClaudeやChatGPTのコネクタに次のURLを登録すると財布番の許可画面が開くので、つなぐAIを選んで「許可する」を押すだけです。

```
https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1/saifuban-mcp
```
3. AIに「財布番で今日の残り予算を見て」と聞いて確認

## English

**Stop your AI agents from overspending.** Saifuban puts a hard daily cap on your agents' API bills and makes them ask your phone before any other payment.

- **Keep your real Anthropic / OpenAI / Google key.** No reseller in between, no markup, new API features work on day one. The agent gets a proxy key; your key stays encrypted on the server.
- **Parallel calls can't go over.** Every call reserves its worst-case cost before it's sent, so ten calls started at once still stop at the cap.
- **Per agent, per day, in your time zone.** Each agent gets its own daily (and optional weekly/monthly) budget that resets at your midnight. Budgets can be shown in USD (Settings → currency).
- **Open source and self-hostable.** Don't want to hand your key to someone else's server? Run the whole thing on your own Supabase and Cloudflare free tiers: [SELF_HOST.md](SELF_HOST.md).

<img src="api-en.gif" width="420" alt="Demo: an agent loops overnight and Saifuban stops its API calls at the daily budget">

### Hard cap on API bills

Store your OpenAI, Anthropic, Google or OpenRouter key in Saifuban. Your agent only gets a proxy key (`sbk_...`), every call is metered, and requests are refused once the agent's daily (or optional weekly/monthly) budget is reached. Your real key never reaches the agent.

Before each call, the proxy reserves the most it could cost (input size + `max_tokens` × the model's price) and settles to the actual usage when the call ends. Reservations count against the caps together with spend, so parallel calls can't all slip under the line. If a stream is cut before the usage arrives, the reserved amount is recorded instead of zero. Each reservation is settled exactly once: a retried or late settle can't charge twice, and a reservation whose settle never arrives is charged at its reserved amount after 10 minutes (and corrected if the real usage shows up later). See the [reserve → settle → release test](tests/reserve-settle-release.md). Days reset at midnight in the owner's own time zone (taken from their device, changeable in Settings), and a call is charged to the day it started, so a call from 23:59 to 00:01 stays on the earlier day ([day boundary test](tests/day-boundary.md)). If a request doesn't set an output limit, the proxy sets one (the model's maximum, up to 32k tokens) and reserves for it, so a call can't write past its reservation; asking for several answers at once (`n`) reserves for each. Web searches and other per-call tool fees are counted too, prices and the exchange rate update daily, and a model missing from the price list is charged at that provider's highest price. If a call doesn't fit only because other calls still hold reservations, the proxy answers 429 (retry shortly), so a retry goes through once they finish. If the rest of the day's budget can't cover the requested `max_tokens` but can cover at least 4,096 tokens, the proxy lowers `max_tokens` to what's left instead of refusing (the response carries `x-saifuban-output-capped`). When the budget is really used up, it answers `429` with `billing_error`, `x-should-retry: false` and `Retry-After` set to the reset time, the same shape Claude Code expects from a spend-limit gateway, so clients stop instead of retrying. Token-counting calls (`count_tokens`, `input_tokens`) pass through free. Endpoints whose cost can't be metered per call (batches, images, audio, video, fine-tuning, realtime) are refused, so they can't go around the cap. The proxy runs on Cloudflare, so responses that take several minutes stream to the end (the older `https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1/saifuban-proxy/...` address still works, but cuts responses at 150 seconds).

Each agent can also have at most a few API requests in flight at once (8 by default, adjustable). Extra requests get a `429` and the official SDKs retry them automatically, so a runaway loop can't fire hundreds of calls before the budget check catches up.

### Use it from your agent framework

**Fastest: from inside Claude Code.** Add the plugin and tell it your daily budget:

```
/plugin marketplace add ut181749ut/saifuban
/plugin install saifuban@saifuban
/saifuban:setup 10
```

It creates your account and an agent with a $10/day cap, stores the Anthropic key that's already in your environment (you never paste it into the chat), checks the key works through the proxy, writes `~/.claude/settings.json`, and opens your dashboard already signed in. Restart Claude Code and every call goes through the cap.

**Or from the terminal**, one command:

```bash
npx https://github.com/ut181749ut/saifuban/archive/refs/heads/main.tar.gz
```

On Windows PowerShell use `npx.cmd` instead of `npx`. Git doesn't need to be installed. It finds the API key already in your environment and offers to use it, remembers your account on this computer, and checks GitHub for a newer version on start. Add `--yes` to accept every default.

**Want to try it for free?** Get a free Gemini API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) and choose "Google Gemini" (or `--provider google`).


Point the client at the Saifuban proxy and give it the agent's proxy key. Nothing else changes.

**Claude Code**
```bash
export ANTHROPIC_BASE_URL="https://saifuban.saifuban-app.workers.dev/proxy/anthropic"
export ANTHROPIC_AUTH_TOKEN="sbk_..."
```
Use `ANTHROPIC_AUTH_TOKEN`, not `ANTHROPIC_API_KEY`: with `ANTHROPIC_API_KEY`, Claude Code asks once whether to use the key, the default answer is No, and a declined key is ignored silently after that. To keep it for every new terminal, put both in the `"env"` block of `~/.claude/settings.json` (`%USERPROFILE%\.claude\settings.json` on Windows). The setup command offers to do this for you.

**OpenAI SDK / OpenAI Agents SDK (Python)**
```python
from openai import AsyncOpenAI
from agents import set_default_openai_client

set_default_openai_client(AsyncOpenAI(
    base_url="https://saifuban.saifuban-app.workers.dev/proxy/openai/v1",
    api_key="sbk_...",
))
```

**LangChain**
```python
from langchain_openai import ChatOpenAI
from langchain_anthropic import ChatAnthropic

gpt = ChatOpenAI(model="gpt-4o-mini", base_url="https://saifuban.saifuban-app.workers.dev/proxy/openai/v1", api_key="sbk_...")
claude = ChatAnthropic(model="claude-sonnet-4-5", base_url="https://saifuban.saifuban-app.workers.dev/proxy/anthropic", api_key="sbk_...")
```

**CrewAI**
```python
from crewai import LLM

llm = LLM(model="openai/gpt-4o-mini", base_url="https://saifuban.saifuban-app.workers.dev/proxy/openai/v1", api_key="sbk_...")
```

**Vercel AI SDK**
```ts
import { createOpenAI } from "@ai-sdk/openai";

const openai = createOpenAI({ baseURL: "https://saifuban.saifuban-app.workers.dev/proxy/openai/v1", apiKey: "sbk_..." });
```

**OpenRouter** (hundreds of models, actual cost reported per call): base URL `https://saifuban.saifuban-app.workers.dev/proxy/openrouter/v1`. **Gemini**: `https://saifuban.saifuban-app.workers.dev/proxy/google/v1beta/openai` (OpenAI-compatible).

### Phone approval for everything else

<img src="demo-en.gif" width="420" alt="Demo: the AI tries to pay on its own and you reject it from your phone">

Your AI agent asks Saifuban before every payment. Saifuban answers using your rules.

- Auto-approve small amounts (e.g. under ¥300)
- Anything above goes to your phone as a push notification — approve or reject in one tap
- Daily, weekly and monthly budgets, per-transaction limit, allowed merchants
- Optional: auto-approve only merchants you've paid before; new merchants always go to your phone
- Kill switch
- Separate rules per agent

Saifuban never moves money and never stores card or bank details. It only decides whether a payment is allowed.

### Setup

1. Open the site, press "はじめる" (Start), pick a budget — you get a personal MCP URL
2. Add the URL to your AI as a remote MCP server (Streamable HTTP, no auth — the key is in the URL). With Muse, just send the URL in a chat message and ask it to connect

Or skip the copy-paste and connect with OAuth: add `https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1/saifuban-mcp` as a connector in Claude or ChatGPT. A Saifuban consent page opens; pick (or create) the agent and press Allow. Dynamic Client Registration and PKCE (S256) are supported.
3. Ask your AI: "Check my remaining budget with Saifuban"

## MCP tools

| Tool | What it does |
|---|---|
| `request_payment` | Ask whether a payment (`merchant`, `amount`, `currency` JPY/USD, `reason`, `recurring` none/week/month/year) is allowed. Waits up to 45 s for phone approval. Returns a single-use `payment_token` when approved. Subscriptions always need your approval, whatever the amount, and the notification shows the yearly cost. Retrying a request that is still pending returns the same request instead of creating a new one (or pass `idempotency_key`). |
| `check_payment_status` | Check whether a pending request was approved. |
| `list_payments` | The agent's own past requests (filter by merchant / days), so it can check e.g. whether a Spotify charge was already approved this month and avoid paying twice. |
| `get_budget` | Remaining budget today, this week and this month, per-transaction limit, auto-approve threshold, allowed merchants. |

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

## Challenge

Think you can make Saifuban approve more than the budget? A live agent with a ¥100/day budget is open to everyone: https://ut181749ut.github.io/saifuban/challenge.html

### Thanks

- **u/organic-humanoid** pointed out that metered API calls were checked before the call but counted after, so calls already in flight could slip past the cap. That led to reserve-then-settle in the proxy. Thank you!

## Links

- [利用規約 / Terms](https://ut181749ut.github.io/saifuban/terms.html)
- [プライバシーポリシー / Privacy](https://ut181749ut.github.io/saifuban/privacy.html)
- Issues / requests: https://github.com/ut181749ut/saifuban/issues
