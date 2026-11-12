# AGENTS.md — working on Ghuri itself

Instructions for AI coding agents contributing to the Ghuri framework. (Building an app *with* Ghuri? Use the
`AGENTS.md` that `ghuri startproject` writes into every project — source:
`packages/cli/templates/project/AGENTS.md`.)

Ghuri is Django for TypeScript: settings, apps, models/managers/QuerySets, migrations, admin, a DRF clone, GraphQL
(graphene-django style) and Channels-style WebSockets, built on **Hono + Drizzle**, Cloudflare Workers + D1 + R2 by
default and portable to Node + Postgres/SQLite.

## Repository layout

This directory is the **meta repo** (`ghurijs/ghuri`): the spec, workspace config and scripts. Everything else is
its own git repo, cloned into git-ignored directories:

```
ARCHITECTURE.md     the spec every package is built against (§14 "As-built notes" supersede earlier sections)
package.json        npm workspace: packages/*, examples/*
scripts/            bootstrap.sh (clone + install + build), publish-all.sh (maintainer only)
packages/<name>/    one repo per package: github.com/ghurijs/<name>
                    core, orm, auth, rest, storage, mail, admin, agents, graphql, realtime, oauth,
                    oauth-provider, socialauth, tenants, cli, create-ghuri
examples/           github.com/ghurijs/examples — examples/blog is the end-to-end test project
docs/               github.com/ghurijs/docs — Starlight site (not a workspace; not cloned by bootstrap:
                    git clone https://github.com/ghurijs/docs.git docs)
```

`npm run bootstrap` clones the repos and runs `npm install && npm run build`. Sibling ranges (`^0.1.0-alpha.0`)
resolve to the local clones through npm workspaces, and packages import each other through `dist/`, so **rebuild a
package before testing the packages or examples that depend on it**.

Git: run `git` inside the repo you changed (`cd packages/orm && git status`). The meta repo ignores `packages/`,
`examples/` and `docs/`, so a commit at the root never contains package changes.

## Commands

Per package (`cd packages/<name>`):

```bash
npm run build       # tsup → dist/ (esm + d.ts)
npm test            # vitest run
npm run typecheck   # tsc --noEmit
npm run lint        # biome check src test   (npm run format to fix formatting)
```

Package CI runs `npm install`, `npm run typecheck`, `npm test`, `npm run build`.

Workspace root: `npm run build`, `npm test`, `npm run typecheck` (each runs across every workspace, `--if-present`).

Example app (`cd examples/blog`): `npx ghuri test`, `npx ghuri makemigrations --check`, `npx ghuri check`,
`npm run typecheck`, and `bash scripts/portability.sh` (D1 → PGlite/Postgres data move + Node server, end to end).

Docs (`cd docs`): `npm run build` (Astro/Starlight; also generates `llms.txt` / `llms-full.txt`).

## Conventions

- **Django parity is the product.** Match Django/DRF/graphene-django/Channels names, semantics, defaults, error
  messages and table names, translated mechanically: `snake_case` → `camelCase` options and methods, keyword
  arguments → one object, every DB operation `async`, settings keys `UPPER_SNAKE`, DB columns `snake_case`.
  Deliberate differences go into ARCHITECTURE.md §14 and the docs' `django-developers.md` "Differences" section.
- **Adapters, not platform calls.** No app or framework feature code touches `env.DB`, R2/KV bindings or
  `process.env` directly: databases, storage, cache, sessions and runtime sit behind adapters chosen in settings
  (`d1()`, `postgres()`, `sqlite()`, `r2()`, `s3()`, `kvCache()`, …). The portability matrix (§12) must stay green.
- **Workers-safe entries.** Never import Node-only modules (`fs`, `path`, `better-sqlite3`, `pg`) from a package's
  main entry; put them behind a subpath (`@ghuri/orm/sqlite`, `@ghuri/core/node`, `@ghuri/storage/fs`) or a dynamic
  import. Must run with `compatibility_flags: ["nodejs_compat"]`.
- ESM only, TypeScript ~5.9 `strict`, target ES2022, `moduleResolution: bundler`. The public API is what
  `src/index.ts` and declared subpath exports export; everything else is internal.
- `@ghuri/*` siblings that share global state are **peerDependencies** (plus devDependencies), never bundled.
- Errors extend `GhuriError` from `@ghuri/core`. Each package keeps a README quick start and a `CHANGELOG.md`.
- Tests: vitest. DB behaviour is tested on SQLite (better-sqlite3), PGlite (Postgres dialect) and D1 (Miniflare)
  where relevant. Add or update tests with every change.
- CLI templates (`packages/cli/templates/`): `_name` renders to `.name`, `name.tpl` to `name`, `{{var}}` and
  `{{#if flag}}…{{/if}}` (see `src/render.ts`), conditional files in `template.json`. `test/startproject.test.ts`
  and `test/startapp.test.ts` assert the rendered output — update them with template changes.
- Docs live in `docs/src/content/docs/` (`topics/`, `reference/`, `tutorial/`). A user-visible API change needs a
  docs change; keep examples consistent with `examples/blog`.

## Commits and releases

- Conventional Commits with the package as scope: `feat(orm): …`, `fix(cli): …`, `test(core): …`,
  `docs(orm): …`, `chore(core): release 0.1.0-alpha.1`. The meta repo uses `docs: …` / `chore: …`.
- Commit only when asked. Do not bump versions or edit CHANGELOG entries for a release unless asked.
- Packages are alpha. `scripts/publish-all.sh` picks the dist-tag per package: **`latest`** while a package has no
  stable release (so `npm create ghuri` and `npm install` get the newest alpha), `next` for prereleases once a
  stable release exists; `scripts/publish-all.sh <tag>` forces one, and `--sync-latest` re-points `latest` without
  publishing. It builds and publishes in dependency order and needs npm 2FA in the browser, so **only the
  maintainer runs it, while present**. Agents never run `npm publish` or the publish script.

## How to verify a change

1. In the touched package: `npm run build && npm test` (plus `npm run typecheck` and `npm run lint`).
2. Rebuild any package that depends on it, then run its tests if the change crosses package boundaries.
3. In `examples/blog`: `npx ghuri test` and `npx ghuri check` (and `scripts/portability.sh` for DB/storage/runtime
   changes). For CLI/template changes, render a project with
   `node packages/cli/dist/bin.js startproject demo /tmp/demo --no-install` and inspect it.
4. If behaviour or an API changed: update the docs page and, for spec-level decisions, ARCHITECTURE.md §14.
