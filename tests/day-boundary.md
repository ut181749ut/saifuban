# Daily reset boundary test

Run on 2026-11-18 against the live database functions, inside one transaction that is rolled back at the end. Script: [`day-boundary.sql`](day-boundary.sql).

**Whose timezone:** the owner's. Each account has its own time zone, set from the owner's device the first time they open the site or run the setup command, and changeable in Settings. It defaults to Japan time (Asia/Tokyo). This test uses a Japan-time account; see the [time zone test](timezone.md) for a Los Angeles account next to a Tokyo one.

**Rule:** a call is charged to the day it was **reserved** (started), not the day its callback arrives. A call that starts at 23:59 and ends at 00:01 belongs to the earlier day. That day's budget was the one checked when the call was let through. While the call is still open, its reservation also counts against the new day, so it can't be used to slip extra calls in after midnight.

Setup: an agent with a **¥100 daily cap**. On the earlier day, ¥50 is already spent. At 23:59, call A reserves ¥45 (50 + 45 ≤ 100, so it is allowed). The clock can't be moved inside the database, so the 23:59 reservation is inserted exactly as `sb_proxy_begin_v3` would have created it at that time. A then really costs ¥5.12, and the new day's call B costs ¥9.77.

## Scene 1: starts at 23:59, settles at 00:01

| Step | Decision / result | Earlier day settled | New day settled | Reserved |
|---|---|---:|---:|---:|
| 23:59 A reserves ¥45 | allowed | ¥50 | ¥0 | ¥45 |
| after midnight: begin B | allowed (A's open ¥45 still counts) | ¥50 | ¥0 | ¥90 |
| after midnight: begin C | **blocked**: "could cost up to ¥45, ¥10 left" | ¥50 | ¥0 | ¥90 |
| 00:01 settle A | ¥5.12 charged to **the earlier day** | ¥55.12 | ¥0 | ¥45 |
| settle B | ¥9.77 charged to the new day | ¥55.12 | ¥9.77 | ¥0 |
| **final** | | **¥55.12** | **¥9.77** | **¥0** |

## Scene 2: starts at 23:59, callback never arrives

| Step | Decision / result | Earlier day settled | New day settled | Reserved |
|---|---|---:|---:|---:|
| 23:59 A reserves ¥45 | allowed | ¥50 | ¥0 | ¥45 |
| next call, more than 10 min later: begin B | allowed; A expires and is charged at ¥45 to **the earlier day** | ¥95 | ¥0 | ¥45 |
| begin C | allowed (A no longer holds the new day's room) | ¥95 | ¥0 | ¥90 |
| A's callback finally arrives | corrected from ¥45 to ¥5.12, still on the earlier day | ¥55.12 | ¥0 | ¥45 |
| settle B | ¥9.77 | ¥55.12 | ¥9.77 | ¥0 |
| **final** | | **¥55.12** | **¥9.77** | **¥0** |

Neither day goes over its ¥100 cap at any point.

Before this change, a call was charged to the day its callback arrived. Nothing could go over the cap, because the open reservation was counted on both days. But a call that started at 23:59 landed in the next day's spending and ate into that day's budget. Now it stays on the day it was approved against.

The [reserve → settle → release test](reserve-settle-release.md) was run again after this change and still ends at ¥14.89 in all three scenes.
