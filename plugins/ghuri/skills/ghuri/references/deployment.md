# Deployment

Covers Cloudflare Workers (wrangler.jsonc bindings, secrets, remote migrations, `ghuri deploy`), cron/queue handlers, Durable Objects, Node + Postgres (`serve()`, Hyperdrive, Docker), local database options, and moving D1 -> Postgres.

One project, two runtimes. `src/index.ts` (`export default createApp(settings)`) is the Worker entry; `src/server.ts` (`serve()` from `@ghuri/core/node`) is the Node entry. Settings pick adapters from `env` (Worker bindings on Cloudflare, `process.env` on Node). Models, views, serializers and admin never change between them.

## Django habit -> Ghuri

| Django | Ghuri |
|---|---|
| `wsgi.py` / gunicorn | `src/index.ts` (Workers) or `src/server.ts` + `serve()` (Node) |
| `.env` read by `django-environ` | `env` argument of `defineSettings((env) => ...)`; `.dev.vars` / `.env` locally, `wrangler secret put` in production |
| `python manage.py migrate` on the server | `npx ghuri migrate --remote` (D1 from your machine/CI) or `npx ghuri migrate` with `DATABASE_URL` |
| push + `collectstatic` + restart | `npx ghuri deploy --migrate` (no collectstatic: admin assets ship in `@ghuri/admin`) |
| `manage.py check --deploy` | `npx ghuri check --deploy` |
| Celery beat / crontab | `"triggers": { "crons": [...] }` + `onSchedule(cron, handler)` |
| Celery queue | Cloudflare Queues + `onQueue(queue, handler)` |
| `DATABASES['default'] = {...ENGINE...}` | `DATABASES: { default: d1('DB') }` / `postgres({ url })` / `postgres({ hyperdrive: 'HYPERDRIVE' })` |
| `MEDIA_ROOT` on disk | R2 binding `r2('MEDIA')` (Workers) or `s3()` / `fileSystemStorage()` (Node) |

## Entry points

```ts
// src/index.ts - Worker entry (wrangler "main"); has fetch, scheduled and queue handlers
import { createApp } from '@ghuri/core'
import settings from './settings'

export default createApp(settings)
```

```ts
// src/server.ts - Node / VPS entry ("start": "node --import jiti/register src/server.ts")
import { createApp } from '@ghuri/core'
import { serve } from '@ghuri/core/node'
import settings from './settings'

serve(createApp(settings), {
  port: Number(process.env.PORT ?? 8000),
  env: process.env,
})
```

`ServeOptions`: `port` (default `PORT` or 8000), `hostname` (default `'0.0.0.0'`), `env` (default `process.env`), `onListen`. Handles `waitUntil()` and SIGINT/SIGTERM. `package.json` declares the settings module: `"ghuri": { "settings": "src/settings.ts" }`.

## Portable settings (examples/blog/src/settings.ts pattern)

```ts
import { defineSettings, type Env, kvCache, memoryCache } from '@ghuri/core'
import { type DatabaseConfig, d1, postgres } from '@ghuri/orm'
import { r2 } from '@ghuri/storage'
import { fileSystemStorage } from '@ghuri/storage/fs'

function databases(env: Env): Record<string, DatabaseConfig> {
  if (env.HYPERDRIVE) return { default: postgres({ hyperdrive: 'HYPERDRIVE' }) }  // Postgres on Workers
  if (env.DATABASE_URL) return { default: postgres({ url: env.DATABASE_URL, max: 10 }) }  // Node / CLI
  return { default: d1('DB') }                                                   // Cloudflare D1
}

export default defineSettings((env) => ({
  SECRET_KEY: env.SECRET_KEY,
  DEBUG: env.DEBUG === 'true',
  ALLOWED_HOSTS: env.ALLOWED_HOSTS ? String(env.ALLOWED_HOSTS).split(',') : ['*'],
  CSRF_TRUSTED_ORIGINS: ['https://blog.example.com'],
  DATABASES: databases(env),
  STORAGES: {
    default: env.MEDIA
      ? r2('MEDIA')
      : fileSystemStorage({ location: env.MEDIA_ROOT ?? '.data/media', baseUrl: '/media/' }),
  },
  MEDIA_URL: '/media/',
  CACHES: { default: env.CACHE ? kvCache('CACHE') : memoryCache() },
}))
```

`PostgresOptions`: `url`, `hyperdrive` (binding name), `max` (pool size, default 5), `driverOptions` (postgres.js options, e.g. `{ ssl: 'require' }`). Needs `npm install postgres`. Local alternatives on Node: `sqlite({ filename: 'db.sqlite3' })` from `@ghuri/orm/sqlite` (better-sqlite3) and `pglite({ dataDir })` from `@ghuri/orm/pglite` (in-process Postgres). Both are Node-only imports: never statically import them (or `@ghuri/storage/fs`) into code bundled for Workers unless guarded; examples/blog loads PGlite through a non-literal dynamic `import()` so wrangler never bundles it.

## wrangler.jsonc

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "blog",
  "main": "src/index.ts",
  "compatibility_date": "2026-11-01",
  "compatibility_flags": ["nodejs_compat"],          // required (AsyncLocalStorage, Buffer)
  "observability": { "enabled": true },
  "d1_databases": [
    { "binding": "DB", "database_name": "blog-db", "database_id": "<from wrangler d1 create>" }
  ],
  "r2_buckets": [{ "binding": "MEDIA", "bucket_name": "blog-media" }],
  "kv_namespaces": [{ "binding": "CACHE", "id": "<from wrangler kv namespace create CACHE>" }],
  "ai": { "binding": "AI" },                          // Workers AI for @ghuri/agents 'workers-ai:' models
  "hyperdrive": [{ "binding": "HYPERDRIVE", "id": "<from wrangler hyperdrive create>" }],
  "triggers": { "crons": ["0 3 * * *"] },
  "queues": {
    "producers": [{ "binding": "EMAILS", "queue": "emails" }],
    "consumers": [{ "queue": "emails", "max_batch_size": 10, "max_retries": 3 }]
  },
  "durable_objects": { "bindings": [{ "name": "REALTIME", "class_name": "GhuriRoom" }] },
  "migrations": [{ "tag": "realtime-v1", "new_sqlite_classes": ["GhuriRoom"] }],
  "routes": [{ "pattern": "blog.example.com", "custom_domain": true }],
  "vars": { "DEBUG": "false", "ALLOWED_HOSTS": "blog.example.com" }
}
```

Binding names must match settings: `d1('DB')`, `r2('MEDIA')`, `kvCache('CACHE')`, `postgres({ hyperdrive: 'HYPERDRIVE' })`, `AGENTS.AI_BINDING` (default `'AI'`), `AGENTS.QUEUE_BINDING` (default `'AGENTS_QUEUE'`), `durableObjectLayer('REALTIME')`. The placeholder `database_id` `00000000-...` works locally only.

## Cloudflare deploy steps

```sh
npx wrangler login
npx wrangler d1 create blog-db                 # paste database_id into wrangler.jsonc
npx wrangler r2 bucket create blog-media
npx wrangler kv namespace create CACHE         # optional
openssl rand -base64 48 | npx wrangler secret put SECRET_KEY   # secrets never go in "vars"
npx ghuri migrate --remote                     # apply migrations to remote D1
npx ghuri createsuperuser --remote
npx ghuri check --deploy
npx ghuri deploy --migrate                     # migrate --remote, then wrangler deploy
```

Locally, secrets live in `.dev.vars` (and `.env`), git-ignored. `ghuri deploy` options: `--migrate` (no prompt; failed migration aborts), `--skip-migrations`, `--dry-run`, `--no-input` (CI; migrations only with `--migrate`); extra args go to wrangler. Global CLI options (every command): `--settings <path>`, `--env <name>` (wrangler environment), `--remote` (remote D1/R2/KV via wrangler's platform proxy; needs wrangler 4, login or `CLOUDFLARE_API_TOKEN`, and the real `database_id`), `--persist-to <dir>`, `--traceback`. Dev server: `npx ghuri runserver` (wrangler dev, port 8787) or `npx ghuri runserver --node` (port 8000).

Alternative D1 workflow: `npx ghuri sqlmigrate --all --dialect sqlite --out migrations-sql`, set `"migrations_dir": "migrations-sql"` on the D1 binding, `npx wrangler d1 migrations apply DB --remote`. Pick one workflow per database.

Release order: migrate before deploy when adding columns/tables; when removing a column, deploy code first (`--skip-migrations`), then `npx ghuri migrate --remote`.

## Cron and queues

`createApp()` returns `{ fetch, scheduled, queue }`. Register handlers in an `AppConfig.ready()`:

```ts
import { AppConfig, getEnv, onQueue, onSchedule } from '@ghuri/core'
import * as models from './models'

export class BlogConfig extends AppConfig {
  name = 'blog'
  path = import.meta.dirname
  models = models

  ready() {
    onSchedule('0 3 * * *', async (event, ctx) => {         // exact string from "triggers.crons", or '*'
      await models.Post.objects.filter({ published: false }).delete()
    })
    onQueue<{ postId: number }>('emails', async (batch) => { // queue NAME, not the binding
      for (const msg of batch.messages) {
        try { /* ... */ msg.ack() } catch { msg.retry({ delaySeconds: 60 }) }
      }
    })
  }
}

// producing, from a view: await getEnv().EMAILS.send({ postId: post.pk })
```

Handlers run inside a Ghuri context (ORM, cache, storage work; user is anonymous). A queue batch with no handler throws `ImproperlyConfigured` (retried). `taskHandlers.schedulesFor(cron)` / `queuesFor(name)` / `clear()` help tests. Local cron: `npx ghuri runserver --test-scheduled` then `curl "http://localhost:8787/__scheduled?cron=0+3+*+*+*"`. On Node there are no triggers: call `app.scheduled({ cron, scheduledTime: Date.now() }, process.env, ctx)` from crontab with `createExecutionContext()` from `@ghuri/core/node` (`await ctx.drain()`), or use a management command. Agents' queue: `agents.consumeQueue('agents')` (see agents.md).

If you export your own default object (e.g. to add Durable Objects), forward all three: `export default { fetch: app.fetch, scheduled: app.scheduled, queue: app.queue }`. Realtime rooms:

```ts
import { createApp } from '@ghuri/core'
import { createRoomClass } from '@ghuri/realtime/cloudflare'
import settings from './settings'

const app = createApp(settings)
export default app
export const GhuriRoom = createRoomClass(app)
// settings: REALTIME: { LAYER: durableObjectLayer('REALTIME') }  (from '@ghuri/realtime/cloudflare')
```

## Node + Postgres (VPS / Docker)

- Run: `DATABASE_URL=postgres://... SECRET_KEY=... npm start`. Build option: `tsup src/server.ts --format esm --target node22 --out-dir dist`, then `node dist/server.js`.
- The `ghuri` CLI loads TypeScript sources with jiti: keep `src/` and `@ghuri/cli` where you run `migrate` (in Docker, copy `src/` into the runtime image and move `@ghuri/cli` to `dependencies`, or migrate from CI). Without a wrangler config the CLI builds `env` from `process.env` + `.env` files.
- Run `npx ghuri migrate` as a release step (compose one-shot service, Fly `release_command`, k8s Job), never in the web container's `CMD`.
- Storage on Node: `s3({...})` (AWS, MinIO, or R2's S3 endpoint, keeping the same bucket) or `fileSystemStorage({ location, baseUrl })` served by Caddy/nginx. `r2('MEDIA')` does not work on Node.
- `memoryCache()` is per process. One Node process per site when using `@ghuri/realtime` memory layer (`attachRealtime(server, app, { env })` from `@ghuri/realtime/node`).
- Postgres on Workers: `npx wrangler hyperdrive create mysite-pg --connection-string="postgres://..."`, add the `hyperdrive` binding, `postgres({ hyperdrive: 'HYPERDRIVE' })`. Migrate with `DATABASE_URL=... npx ghuri migrate`.

## Moving D1 -> Postgres

```ts
import { defineSettings } from '@ghuri/core'
import { d1, postgres } from '@ghuri/orm'

export default defineSettings((env) => ({
  DATABASES: {
    default: d1('DB'),
    ...(env.PG_URL ? { pg: postgres({ url: env.PG_URL }) } : {}),   // use a var OTHER than the one switching default
  },
}))
```

```sh
npx ghuri migrate --remote                                   # D1 fully migrated
npx ghuri migrate --database pg                              # same migration files, Postgres DDL
npx ghuri copydata --remote --from default --to pg --flush --no-input
# or: npx ghuri dumpdata --remote --database default --indent 2 -o data.json
#     npx ghuri loaddata data.json --database pg
```

`copydata` loads in FK dependency order, upserts by primary key (ids preserved), runs in one transaction on Postgres and resets sequences; `--flush` truncates the destination first (needed because `migrate` creates content types/permissions with different ids); `-e/--exclude <label>` and `app`/`app.Model` args narrow it. Then make `postgres(...)` the `default` alias (keep `d1('DB')` under another alias for rollback). Files in R2 stay put: reach them from Node with `s3({ endpoint: 'https://<account>.r2.cloudflarestorage.com', ... })`.

## Gotchas

- Never read `env.DB` / `env.MEDIA` / `env.CACHE` in app code; only settings pass binding names to `d1()`, `r2()`, `kvCache()`.
- Forgetting `"compatibility_flags": ["nodejs_compat"]` breaks Ghuri on Workers.
- Secrets go through `wrangler secret put` (production) and `.dev.vars` (local), not `vars` and not committed files. Never deploy with `DEBUG: "true"`.
- `ghuri migrate` without `--remote` hits the LOCAL D1 simulator (`.wrangler/state`), not production.
- There is no `ghuri collectstatic`, no gunicorn/uvicorn, no `MEDIA_ROOT`.
- D1 `atomic()` has no rollback; use `(await connections.get()).batch([...])` (`connections` from `@ghuri/orm`) for all-or-nothing writes, or Postgres.
- `onSchedule` matches the exact cron string from `wrangler.jsonc` (`'0 * * * *'` != `'0 */1 * * *'`); `onQueue` takes the queue name, not the producer binding. Cron/queue handlers do not fire on Node.
- Node-only modules (`@ghuri/storage/fs`, `@ghuri/orm/sqlite`, `@ghuri/orm/pglite`) must not end up in the Worker bundle.
- When migrating D1 -> Postgres, do not reuse the env var that already flips `default` to Postgres, or you copy a database onto itself.
- SQLite/D1 ignore `varchar(n)` lengths; Postgres enforces them, so bad legacy rows fail `copydata`.
- Durable Object `migrations` entries are append-only once deployed; add new tags instead of editing.
- `APPEND_SLASH` only redirects GET: give API/MCP clients the exact trailing-slash URL.
