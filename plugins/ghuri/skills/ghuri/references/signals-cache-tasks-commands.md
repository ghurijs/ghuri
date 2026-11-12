# Signals, cache, background tasks and management commands

Covers `Signal`/`receiver` (`@ghuri/core`) and the ORM/auth signals, the cache API (`cache`, `caches`, `CACHES`, backends), Cron Triggers and Queues (`onSchedule`, `onQueue`), and custom `ghuri` commands (`BaseCommand`, `callCommand`).

## Django habit -> Ghuri

| Django | Ghuri |
|---|---|
| `from django.db.models.signals import post_save` | `import { postSave } from '@ghuri/orm'` |
| `@receiver(post_save, sender=Post)` | `receiver(postSave, { sender: Post })(fn)` (`receiver` from `@ghuri/core`) |
| `post_save.connect(fn, sender=Post, dispatch_uid='x')` | `postSave.connect(fn, { sender: Post, uid: 'x' })` |
| `def fn(sender, instance, created, **kwargs)` | `async ({ sender, instance, created }) => {}` (one object argument) |
| `Signal()` + `sig.send(sender=X, a=1)` | `new Signal<{ a: number }>('name')` + `await sig.send(X, { a: 1 })` |
| `send_robust` | none: a throwing receiver propagates and stops the rest |
| `from django.core.cache import cache` | `import { cache } from '@ghuri/core'` |
| `cache.get('k')` (sync) | `await cache.get('k')` (every method is async) |
| `cache.get_or_set('k', fn, 300)` | `await cache.getOrSet('k', fn, 300)` |
| `caches['pages']` | `caches.get('pages')` |
| `CACHES = {'default': {'BACKEND': '...'}}` | `CACHES: { default: kvCache('CACHE') }` |
| Celery beat / crontab | `onSchedule('0 * * * *', fn)` + `triggers.crons` in `wrangler.jsonc` |
| Celery task + `.delay()` | `await getEnv().EMAILS.send(body)` + `onQueue('emails', fn)` |
| `management/commands/x.py` auto-discovery | `commands = { x: XCommand }` on the `AppConfig` |
| `add_arguments(self, parser)` | `addArguments(parser) { parser.argument(...).option(...) }` |
| `handle(self, *args, **options)` | `async handle(args, io)` |
| `self.stdout.write(self.style.SUCCESS('ok'))` | `io.stdout(io.style.success('ok'))` |
| `call_command('x', limit=10)` | `await callCommand('x', { limit: 10 }, bufferIO())` |

## Signals

Built-in signals:

| Signal | Import from | Receiver args (plus `sender`) |
|---|---|---|
| `preSave`, `postSave` | `@ghuri/orm` | `instance`, `raw`, `using`, `updateFields`; `postSave` adds `created` |
| `preDelete`, `postDelete` | `@ghuri/orm` | `instance`, `using`, `origin` (sent per object, incl. cascades and `qs.delete()`) |
| `m2mChanged` | `@ghuri/orm` | `instance`, `action` (`'pre_add' \| 'post_add' \| 'pre_remove' \| 'post_remove' \| 'pre_clear' \| 'post_clear'`), `reverse`, `model`, `pkSet`, `using`; sender is the through model |
| `preMigrate`, `postMigrate` | `@ghuri/orm` | `appConfig`, `using`, `plan`; sender is the `AppConfig` (also sent by `flush` / test DB setup) |
| `userLoggedIn`, `userLoggedOut`, `userLoginFailed` | `@ghuri/auth` | `c`, `user` / `credentials` |
| `requestStarted`, `requestFinished` | `@ghuri/core` | `request`, (`response`) |

`qs.update()` and `bulkCreate()` send no save signals (same as Django). `preInit`/`postInit` are not exported.

```ts
import { getContext, receiver, Signal } from '@ghuri/core'
import { postSave, preSave } from '@ghuri/orm'
import { Post } from './models'

// connect(): idempotent with uid; same fn + same sender twice is ignored too
postSave.connect(
  async ({ instance, created }) => {
    if (!created && (instance as Post).published) await notify(instance as Post)
  },
  { sender: Post, uid: 'blog.notify-on-publish' },
)

// receiver(): decorator-style helper (NOT an @decorator), returns the function
export const autoSlug = receiver(preSave, { sender: Post })(async ({ instance }) => {
  const post = instance as Post
  if (!post.slug) post.slug = post.title.toLowerCase().replace(/\s+/g, '-')
})

// Slow work: hand it to waitUntil on Workers so the response is not delayed
postSave.connect(({ instance }) => {
  const work = reindex(instance as Post)
  const ex = getContext().executionCtx
  if (ex) ex.waitUntil(work)
  else return work
}, { sender: Post, uid: 'blog.reindex' })

// Custom signal
export const postPublished = new Signal<{ post: Post; by: unknown }>('postPublished')
// await postPublished.send(SomeSender, { post, by: user })  -> receivers get { post, by, sender }

async function notify(_p: Post) {}
async function reindex(_p: Post) {}
```

- Receivers are awaited sequentially before `send()` resolves; a slow receiver slows the request. A thrown error propagates to the caller (`instance.save()` rejects) and skips later receivers. Only `requestFinished` failures are logged and swallowed.
- `disconnect(fn | uid, sender?)` returns `true` if removed; `hasListeners(sender?)`.
- Connect at load time: in a `signals.ts` module assigned to `AppConfig.modules` (`modules = { signals }`) or imported in `ready()` (`async ready() { await import('./signals') }`). Nothing discovers `signals.ts` by name.
- Skip work when `raw` is true (fixtures via `loaddata`).

## Cache

```ts
import { cfCache, defineSettings, kvCache, memoryCache } from '@ghuri/core'
import { urlpatterns } from './urls'

export default defineSettings((env) => ({
  SECRET_KEY: env.SECRET_KEY,
  INSTALLED_APPS: [],
  ROOT_URLCONF: urlpatterns,
  CACHES: {
    default: env.CACHE ? kvCache('CACHE', { keyPrefix: 'v1' }) : memoryCache(),   // binding NAME, not env.CACHE
    local: memoryCache({ timeout: 60, maxEntries: 1000 }),
    pages: cfCache(),                                                                // Workers Cache API
  },
}))
```

| Backend | Storage / scope | Notes |
|---|---|---|
| `memoryCache({ keyPrefix?, timeout?, maxEntries? })` | `Map` per isolate / process (default 10,000 entries) | default when `CACHES` unset |
| `kvCache(binding, { keyPrefix?, timeout? })` | Workers KV, global, eventually consistent | min TTL 60 s (rounded up); `clear()` lists + deletes |
| `cfCache({ name?, baseUrl?, keyPrefix?, timeout? })` | Cache API, per data center, best effort | `clear()` throws |

`timeout` = default TTL in seconds (300 if unset; `null` = never expire). Unconfigured non-default alias throws `ImproperlyConfigured`. Custom backend: `{ backend: 'name', create(env): CacheBackend }` where `CacheBackend` has `get/set/delete` (+ optional `has`, `clear(prefix)`) over JSON strings.

```ts
import { cache, caches, json } from '@ghuri/core'
import { postSave } from '@ghuri/orm'
import type { Context } from 'hono'
import { Post } from './models'

export async function popular(c: Context) {
  const data = await cache.getOrSet('blog:popular:v1', async () =>
    Post.objects.filter({ published: true }).orderBy('-createdAt').values('id', 'title').slice(0, 10), 300)
  return json(c, data)
}

postSave.connect(async () => { await cache.delete('blog:popular:v1') }, { sender: Post, uid: 'blog.popular-cache' })

export async function demo() {
  await cache.set('k', { a: 1 }, 300)          // seconds; null = forever; <= 0 deletes
  await cache.get<{ a: number }>('k')          // value or undefined
  await cache.get('missing', 'fallback')
  await cache.add('lock', true, 30)            // true if stored (not atomic)
  await cache.has('k')
  await cache.incr('hits')                     // throws if missing; decr() too (not atomic)
  await cache.setMany({ a: 1, b: 2 }, 60)
  await cache.getMany(['a', 'b'])              // { a: 1, b: 2 }
  await cache.deleteMany(['a', 'b'])
  await caches.get('local').clear()
}
```

- Values are JSON-serialized: model instances come back as plain objects. Cache `values()` / serializer output, not instances. `undefined` cannot be cached (use `null`).
- `cache` resolves the default alias from the current context each call; use it inside requests, commands, tasks or after `app.setup()`.
- Never use `add`/`incr` on KV for locks or exact counters.
- No `@cache_page` / per-view cache decorator; for public pages prefer `Cache-Control` headers and Cloudflare's CDN.

## Background tasks (Cron Triggers, Queues)

`createApp(settings)` returns `{ fetch, scheduled, queue }`, a complete Workers module handler; `export default createApp(settings)` wires everything. If you export your own object (e.g. alongside a Durable Object class), forward all three methods.

```ts
import { AppConfig, getEnv, onQueue, onSchedule } from '@ghuri/core'
import * as models from './models'
import { Post } from './models'

export class BlogConfig extends AppConfig {
  name = 'blog'
  models = models

  ready() {
    // cron string must equal a wrangler.jsonc "triggers": { "crons": [...] } entry exactly; '*' = every trigger
    onSchedule('0 * * * *', async (event, ctx) => {
      await Post.objects.filter({ published: false, createdAt__lte: new Date(event.scheduledTime) }).update({ published: true })
    })

    // queue NAME (not binding); '*' = every queue; type param types msg.body
    onQueue<{ postId: number }>('emails', async (batch) => {
      for (const msg of batch.messages) {
        try {
          await sendMail(msg.body.postId)
          msg.ack()
        } catch {
          msg.retry({ delaySeconds: 60 })
        }
      }
    })
  }
}

// Producer (in a view, signal receiver, ...): binding from wrangler.jsonc "queues.producers"
export async function enqueueEmail(postId: number) {
  await getEnv().EMAILS.send({ postId })
}

async function sendMail(_id: number) {}
```

- Handlers run inside a Ghuri context: settings, ORM, cache, storage, `getContext().executionCtx.waitUntil()` work; `getUser()` is `AnonymousUser`.
- Register in `AppConfig.ready()` so handlers exist after `apps.populate()`. `onSchedule`/`onQueue` return an unregister function.
- Cron: all matching handlers run; failures are logged, the rest still run, then the invocation fails (one error or `AggregateError`). No matching handler: warning only.
- Queue: every matching handler gets the same batch in order; a throw stops later handlers and fails the batch (unacked messages redelivered). A batch with no handler throws `ImproperlyConfigured`. Ack/retry per message.
- There is no `enqueue()`/`delay()` task API in core and no built-in scheduler on Node: call `app.scheduled({ cron, scheduledTime: Date.now() }, process.env, ctx)` from crontab/a scheduler (with `createExecutionContext()` from `@ghuri/core/node`, then `await ctx.drain()`), and `app.queue({ queue, messages, ackAll, retryAll }, env)` from your own consumer.
- Local: `npx ghuri runserver` (wrangler dev) delivers queue messages; `npx ghuri runserver --test-scheduled` then `curl "http://localhost:8787/__scheduled?cron=0+*+*+*+*"`.
- `taskHandlers.schedulesFor(cron)`, `taskHandlers.queuesFor(name)`, `taskHandlers.clear()` for introspection/tests.
- `@ghuri/agents` builds on this (`agents.consumeQueue('agents')`, `agent.enqueue()`).

## Management commands

```ts
import { type ArgumentParser, BaseCommand, CommandError, type CommandIO } from '@ghuri/core'
import { Post } from '../models'

export class PublishScheduledCommand extends BaseCommand {
  static help = 'Publish drafts.'

  addArguments(parser: ArgumentParser) {
    parser
      .argument('slugs', { help: 'Only these posts', variadic: true })   // positional; required?: true
      .option('--dry-run', { help: 'Do not save' })                       // boolean -> args.dryRun
      .option('-l, --limit <n>', { help: 'Max posts', default: 100 })    // value; numeric default coerces
  }

  async handle(args: Record<string, unknown>, io: CommandIO) {
    const limit = Number(args.limit)
    if (!Number.isInteger(limit) || limit < 1) throw new CommandError('--limit must be a positive integer.')
    let qs = Post.objects.filter({ published: false })
    const slugs = args.slugs as string[] | undefined
    if (slugs?.length) qs = qs.filter({ slug__in: slugs })
    const posts = await qs.orderBy('createdAt').slice(0, limit)
    for (const post of posts) {
      if (args.dryRun) { io.stdout(`Would publish ${io.style.bold(post.title)}`); continue }
      post.published = true
      await post.save({ updateFields: ['published'] })
      io.stdout(io.style.success(`Published "${post.title}"`))
    }
    if (!posts.length) io.stdout(io.style.notice('Nothing to publish.'))
  }
}
```

Register on the app (the key is the command name users type):

```ts
import { AppConfig } from '@ghuri/core'
import { PublishScheduledCommand } from './commands/publish-scheduled'
import * as models from './models'

export class BlogConfig extends AppConfig {
  name = 'blog'
  models = models
  commands = { publish_scheduled: PublishScheduledCommand }
}
```

```sh
npx ghuri publish_scheduled --dry-run
npx ghuri publish_scheduled --remote      # every command gets --remote (real D1/R2)
npx ghuri help publish_scheduled
```

- The CLI runs on your machine/CI, calls `app.setup(env)` (env from `wrangler.jsonc` bindings + `.dev.vars` + `process.env`), then runs `handle` inside that context.
- Option keys are camelCased long flags (`--dry-run` -> `dryRun`); `--no-input` sets `noInput: true` and `input: false`. `<v>` takes a value, `[v]` optional, `<v...>` repeatable.
- `handle` may return a number (exit code). `CommandError(message, returncode = 1)` prints without a stack trace.
- IO: `io.stdout`, `io.stderr`, `io.style.success|warning|error|notice|bold`, optional `io.prompt?(q, { password?, default? })` and `io.confirm?(q, { default? })` (undefined in CI/tests: check before calling).
- Same name in two apps: the app LATER in `INSTALLED_APPS` wins (opposite of Django); app commands also override built-ins except `help`.

```ts
import { bufferIO, callCommand } from '@ghuri/core'
import { PublishScheduledCommand } from './commands/publish-scheduled'

const io = bufferIO()
await callCommand('publish_scheduled', { dryRun: true, limit: 10 }, io)   // or callCommand(PublishScheduledCommand, ...)
console.log(io.out, io.err)                                                // string[] each, unstyled
```

`callCommand` passes `args` straight to `handle`: no parsing, no `addArguments` defaults. Pass every key the command reads, camelCased.

## Gotchas

- Receivers take ONE destructured object (`{ sender, instance, created }`), not `(sender, instance, **kwargs)`.
- `receiver(signal, opts)(fn)` is a function call; there is no `@receiver` decorator.
- Model signals come from `@ghuri/orm`; `Signal`/`receiver` from `@ghuri/core`; login signals from `@ghuri/auth`.
- Receivers are awaited and can fail the triggering `save()`; push slow work to `waitUntil` or a queue.
- Signals/handlers/commands must be wired through `AppConfig` (`modules`, `ready()`, `commands`); there is no file-name discovery (`signals.py`, `management/commands/`, `tasks.py`).
- Every cache call is `await`ed; TTL is the third positional arg in seconds (not `timeout=`).
- `kvCache('CACHE')` takes the binding name string; never pass `env.CACHE` from app code.
- No Celery: no `@shared_task`, `.delay()`, `apply_async`, `enqueue()` in core. Use Cloudflare Queues via a producer binding + `onQueue`.
- `onSchedule` matches the exact cron text from `wrangler.jsonc`; `'0 */1 * * *'` is not `'0 * * * *'`.
- Commands are not `class Command` in a magic file; export any class name and list it in `commands`.
- `addArguments` uses `parser.argument()` / `parser.option(flags, { help, default })`, not argparse's `add_argument('--x', type=int)`.
