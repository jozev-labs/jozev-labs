# Virtual fencing dashboard (simulation)

A browser simulation of a cattle virtual-fencing system: 48 collared cows on a rotating pasture plan, three radio gateways, and a fence that opens toward the next pasture and then sweeps forward to push the herd.

Everything you see is simulated. There are no real collars, radios or GPS fixes behind it.

## Run it

Open `index.html` in a browser. Nothing to install.

## Send the simulated alerts to Sentry (optional)

1. Copy `sentry-config.example.js` to `sentry-config.js`.
2. Paste your project's DSN (Data Source Name) into it. You find it in Sentry under Project Settings, Client Keys (DSN).
3. Reload the page. The pill in the toolbar reads "Sentry: connected".

`sentry-config.js` is in `.gitignore`, so your DSN stays out of the repo. Every event is tagged `data_source: simulated`.

What gets sent:

| Situation | Event | Grouped by |
|---|---|---|
| Collars go quiet together | CollarSilenceBurst | gateway |
| Impossible GPS position held back | ImplausiblePositionError | rule (speed or null fix) |
| Cow appears outside its fence with checks off | CollarOutsideFence | one issue for all |
| Fence update sent but not confirmed | FenceUpdateNotConfirmed | one issue for all |

Every alert line in the dashboard also becomes a breadcrumb, so an event in Sentry shows what led up to it.

## What is mine and what is not

- The problem is real and existing companies sell virtual fencing. Nothing here is a new idea.
- The patterns are standard: tracking a command as sent and then confirmed, a tenant ID on every table, rejecting positions a cow cannot have reached.
- The database and fence-state design come from an interview exercise. Some requirements were in the brief. The tenant ID on every table and the sent-then-confirmed fence states were my choices.
- This simulation was written with Claude, from my design and my direction. I use it to test how the design behaves when things fail.
- The Sentry browser SDK (Software Development Kit) in `vendor/sentry.js` is version 11.1.0 from npm, bundled into one file so the page works offline.
