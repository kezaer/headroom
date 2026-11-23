# Headroom T3 fork: development plan

This fork (`kezaer/headroom`) changes Headroom so it reads the Codex, Antigravity and Claude logins that
T3 Code already holds, and so it can show several accounts of the same provider. The prototype from
2026-11-20 worked, but it was built in one uncommitted working tree with four features mixed together.
This plan is how we continue from here.

## Branches

| Branch | What it is | Rules |
|---|---|---|
| `upstream/main` | kylezantos/headroom | Read-only. No PRs upstream unless we decide to. |
| `t3/dev` | Fork integration branch, based on upstream 1.8.1 (`441bcae`) | Always builds, tests pass, installable. Only changed by merging a feature branch. |
| `t3/snapshot-2026-11-20` | Frozen prototype, exactly what was installed on 2026-11-20 (`5c96e07`, on upstream 1.8) | Never edited. Used as the source to re-land code from. |
| `t3/feat/<name>` | One topic each, branched off `t3/dev` | Merged into `t3/dev` through a PR **inside the fork** (base `kezaer/headroom:t3/dev`), then deleted. |

## Working rules

1. **One topic per branch.** Each brief lists the files and UI areas the branch may touch. Anything
   outside that list goes to the backlog, not into the branch.
2. **Leave the rest of Headroom's UI as it is.** Only the areas a milestone names change.
3. **Each implementer works in its own git worktree** off `t3/dev`, never in the shared `~/Git/headroom`
   checkout. `~/Git/headroom` stays on `t3/dev` for local builds.
4. **Commit at the end of every round.** No work left uncommitted between sessions.
5. **Merge gate:**
   - `swift build --target HeadroomCoreTests && swift test --skip-build` passes;
   - the app builds and installs with `Scripts/t3-install-local.sh` (milestone M0.0);
   - for UI changes, the user has tried the installed build and approved it.
6. **Upstream sync:** after each upstream release, rebase `t3/dev` onto it in its own branch
   (`t3/sync/<version>`), fix conflicts there, and merge it like a feature.
7. **Secrets:** never print, log or commit tokens or `auth.json` contents. Never refresh Codex tokens
   from Headroom; Codex does that (`codex app-server`). Don't write to T3 settings, the shadow homes or
   `~/.codex`. Test homes go in a scratch folder, not `/tmp`. The fork is public: no personal paths or
   emails in committed files.

## Milestones

### M0: Clean base (re-land the prototype on 1.8.1, one topic at a time)

Each step is one branch and one fork PR into `t3/dev`, taken from `t3/snapshot-2026-11-20`, rebased
onto 1.8.1, tidied, and tested on its own. Order follows dependencies.

| Step | Branch | Contents | Design |
|---|---|---|---|
| M0.0 | `t3/feat/local-build-script` | `Scripts/t3-install-local.sh`: release build with Command Line Tools, bundle, remove Sparkle feed, ad-hoc sign, back up the installed app, install, relaunch. Replaces the manual steps from 2026-11-20. | — |
| M0.1 | `t3/feat/codex-shadow-homes` | The original goal. `AccountOrigin`, `BorrowedHomes`, `BorrowedHomePaths`, `T3Installation`, `CodexAppServerProvider`, `CodexLimits`, registry/store lifecycle, storage gates, and only the Settings controls needed to add, hide and rename a home. | `design/01-*` |
| M0.2 | `t3/feat/antigravity-t3` | T3-managed Antigravity discovery (`AntigravityLaunch`). Must be merged with upstream 1.8.1's Antigravity fixes (#255), which touch the same files. | `design/00-grounding.md` |
| M0.3 | `t3/feat/menubar-brand-glyphs` | Severity-filled brand glyphs in the menu bar, OpenAI blossom for Codex, editable corner badges (`100` / `200`) shown only when one provider has two or more accounts in the menu bar. | `design/01-*` (menu bar part) |
| M0.4 | `t3/feat/accounts-settings-v7` | Settings › Accounts v7: Account / Source / Plan / Version columns, one `+ Add Source…` sheet (T3 Code / Existing CLI login / Separate login), `Stop Tracking` and `Sign Out & Stop Tracking` menus. | `design/04-*` |

M0 is done when `t3/dev` matches the snapshot's behaviour on 1.8.1, installed and working on this Mac
with both Codex accounts (100 and 200) showing.

### M1: Test pass and fixes

Use the installed `t3/dev` build for a few days. Collect issues in `docs/fork/BACKLOG.md`, then fix them
in small `t3/feat/fix-*` branches.

### M2: Account Pre-Warm MVP

Send the smallest request that starts a new quota window once the old window has reset. Research and
the UI design are done (`design/05-*`). Build it as one feature branch after M1.

## Open questions and known gaps

- **Widgets and iCloud sync** are not in local builds: they need full Xcode and a signing identity.
- **Upstreaming:** M0.1 (shadow homes / app-server transport) could be useful upstream. Undecided.
- **Fork `main`** is still at upstream 1.8. It can be fast-forwarded to upstream or ignored; `t3/dev`
  is the fork's working branch.
