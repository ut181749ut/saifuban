# Per-owner time zone test

Run on 2026-11-18 at 07:19 UTC against the live database functions, inside one transaction that is rolled back at the end. Script: [`timezone.sql`](timezone.sql).

Each account has its own time zone. Daily, weekly and monthly budgets reset at midnight in that zone.

- The site and the `npx` setup command set it automatically from the owner's device, but only the first time. A later device in another zone doesn't silently move the boundary.
- It can be changed by hand in Settings.
- Agents can't change it.
- Accounts that never set one stay on Japan time (Asia/Tokyo).

At the moment of the test it was **Nov 17** in Los Angeles and **Nov 18** in Tokyo. Two accounts, each with a ¥100 daily cap:

| Step | Result |
|---|---|
| automatic set to America/Los_Angeles (first time) | set |
| automatic set to Europe/Paris (already set) | ignored, stays America/Los_Angeles |
| set to `Mars/Olympus` | rejected (`bad_timezone`) |
| budget check reports | "midnight America/Los_Angeles" / "midnight Asia/Tokyo" |
| LA metered call (¥9.77) | recorded on **Nov 17**, counts toward LA's today |
| Tokyo metered call (¥9.77) | recorded on **Nov 18**, counts toward Tokyo's today |
| LA payment request (¥30, MCP) | recorded on **Nov 17** |
| LA call that started at 23:59 LA time and settled after midnight | recorded on **Nov 16**, the LA day it started |
| **final** | LA today **¥39.77**, Tokyo today **¥9.77**, as expected |

The [reserve → settle → release](reserve-settle-release.md) and [day boundary](day-boundary.md) tests were run again after this change, with the same results.
