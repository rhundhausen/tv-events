# GitHub setup

Manual steps in the GitHub UI after the move back from Azure DevOps on 2026-11-04. Do them in order.

## 1. The repository

`rhundhausen/weekendboise` (named `WeekendBoise` until 2026-11-05) already exists. It was recreated on 2026-11-03 and holds 3 commits that only touch `README.md`; the pre-ADO history is not in it. The local clone at `C:\Projects\Data\Repos\GitHub\rhundhausen\WeekendBoise` tracks it, so commit the moved files on top of `main` and push normally. No force push is needed.

If you would rather start from an empty history, delete and recreate the repo instead. Force-pushing over it works too, but it rewrites the 3 README commits.

## 2. Default branch

Settings > General > Default branch: `main`. The nightly schedule only runs on the default branch.

## 3. Enable Actions

Settings > Actions > General:

- Actions permissions: allow all actions, or at least actions created by GitHub (`actions/checkout`, `actions/upload-artifact`).
- Workflow permissions: either setting works, because `ingest.yml` asks for `contents: write` itself. Read and write is not required.

If `main` gets a branch protection rule or ruleset later, allow `github-actions[bot]` to push to it, or the nightly data commit will be rejected.

## 4. Repository secrets

Settings > Secrets and variables > Actions > New repository secret. The names must match exactly:

| Secret | Needed now |
| --- | --- |
| `TICKETMASTER_KEY` | Yes, 13 Ticketmaster sources are running |
| `BANDSINTOWN_APP_ID` | No, once an app id is approved |
| `EVENTBRITE_TOKEN` | No, adapter is disabled |
| `SEATGEEK_CLIENT_ID` | No, adapter is disabled |
| `SONGKICK_API_KEY` | No, adapter is disabled |

A secret you don't create reaches the scripts as empty, and that source fails with a warning while the rest run.

## 5. Prove the data commit with one source

Before the midnight (Boise time) schedule runs on its own:

1. Actions > ingest > Run workflow, branch `main`, source `idaho-steelheads` (or any one running source).
2. When it finishes, check:
   - The run is green and the `out` artifact holds `idaho-steelheads.json` and `run.json`.
   - `main` has a new commit by "WeekendBoise bot" titled `data: nightly ingest YYYY-MM-DD` that changes only files under `data/`.
   - The test workflow did not run for that commit.
3. If the commit step fails with a permission error, recheck step 3.

After that, leave the schedule to run nightly. GitHub turns off scheduled workflows in a public repo after 60 days with no repository activity; the nightly data commits count as activity, so this only matters if ingest stops committing.
