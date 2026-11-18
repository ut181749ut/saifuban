# Reserve → settle → release test

Run on 2026-11-18 against the live database functions (`sb_proxy_begin_v3`, `sb_proxy_settle`, `sb_proxy_release`, `sb_proxy_expire`), inside one transaction that is rolled back at the end, so nothing stays in production. Script: [`reserve-settle-release.sql`](reserve-settle-release.sql).

Setup: one agent with a **¥100 daily cap**. Every call is `claude-sonnet-4-5` (input $3, output $15 per million tokens, ¥155 per $).

- Reservation per call: 1,000 input + 19,000 max output tokens = $0.288, so **¥45** is reserved.
- Actual usage: call A 1,000 in / 2,000 out = **¥5.12**; call B 1,000 in / 4,000 out = **¥9.77**.
- Correct final total: **¥14.89**.

## Scene 1: A's settle is delayed, retried, then cancelled

| Step | Decision / result | Reserved | Settled |
|---|---|---:|---:|
| begin A | allowed, reserves ¥45 | ¥45 | ¥0 |
| begin B | allowed, reserves ¥45 | ¥90 | ¥0 |
| begin C (check) | **blocked**: "could cost up to ¥45, ¥10 left" | ¥90 | ¥0 |
| settle B | charged ¥9.77 | ¥45 | ¥9.77 |
| settle A (delayed) | charged ¥5.12 | ¥0 | ¥14.89 |
| settle A (retry) | duplicate, no charge | ¥0 | ¥14.89 |
| cancel A | duplicate, no charge (release is a no-op) | ¥0 | ¥14.89 |
| **final** | 2 charge rows: ¥9.77, ¥5.12 | **¥0** | **¥14.89** |

## Scene 2: A's settle never arrives in time (worker killed), then arrives late

| Step | Decision / result | Reserved | Settled |
|---|---|---:|---:|
| begin A / begin B | both allowed, ¥45 each | ¥90 | ¥0 |
| begin C (check) | **blocked** | ¥90 | ¥0 |
| settle B | charged ¥9.77 | ¥45 | ¥9.77 |
| next call, 11 min later | A expires and is **charged at its reservation (¥45)**, not dropped; the new call is allowed | ¥45 | ¥54.77 |
| settle A (late) | **corrected** from ¥45 to ¥5.12 | ¥0 | ¥14.89 |
| settle A (retry) | duplicate, no charge | ¥0 | ¥14.89 |
| cancel A | duplicate, no charge | ¥0 | ¥14.89 |
| **final** | 2 charge rows: ¥9.77, ¥5.12 | **¥0** | **¥14.89** |

## Scene 3: the cancel arrives before A's settle

| Step | Decision / result | Reserved | Settled |
|---|---|---:|---:|
| begin A / begin B | both allowed, ¥45 each | ¥90 | ¥0 |
| begin C (check) | **blocked** | ¥90 | ¥0 |
| settle B | charged ¥9.77 | ¥45 | ¥9.77 |
| cancel A | charged at the estimate (¥44.64), reservation freed | ¥0 | ¥54.41 |
| settle A (delayed) | **corrected** from ¥44.64 to ¥5.12 | ¥0 | ¥14.89 |
| settle A (retry) | duplicate, no charge | ¥0 | ¥14.89 |
| cancel A again | duplicate, no charge | ¥0 | ¥14.89 |
| **final** | 2 charge rows: ¥9.77, ¥5.12 | **¥0** | **¥14.89** |

## What changed to make this pass

Before this change, the proxy recorded usage and freed the reservation in two separate, unkeyed calls. That allowed three failures:

- a retried settle would have charged twice;
- a failed record followed by a release would have lost the charge;
- a reservation whose worker died was silently dropped after 10 minutes, so the call was never charged.

Now:

- Each reservation (slot) is settled exactly once. A retry returns `duplicate` and charges nothing.
- Release closes a slot at ¥0 only if it is still open, and only when the call used nothing.
- If the settle call itself fails, the reservation stays open instead of being released.
- An open reservation counts against the cap until it is settled, however long it takes.
- After 10 minutes, an open reservation is charged at its reserved amount.
- A later real settle corrects an expired or cancelled charge down to the actual amount.
