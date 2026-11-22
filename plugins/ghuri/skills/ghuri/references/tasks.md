# Background tasks (@ghuri/tasks)

Covers Django 6.0's `django.tasks` in Ghuri: `task()`, `.enqueue()`, `.using()`, `getResult()`, `TaskResult`, the `TASKS` setting and backends (Cloudflare Queues, the database, immediate, dummy), retries, periodic tasks (`periodicTask`), the `db_worker` worker, request context carried to the worker, signals, admin, checks and testing. For the low-level hooks it is built on (`onSchedule`, `onQueue`) see signals-cache-tasks-commands.md.

Install: `npm install @ghuri/tasks@next` (needs `@ghuri/core` 0.1.0-alpha.5+ for `db_worker --beat` and `serve({ scheduler: true })`). Add `TasksConfig` to `INSTALLED_APPS` and run `npx ghuri migrate` (table `tasks_dbtaskresult`). Projects from `npm create ghuri` (CLI 0.1.0-alpha.7+) already have `TasksConfig`, `TASKS`, a `<name>-tasks` queue in `wrangler.jsonc`, `npm run worker` and a `tasks.ts` per app.

Entry points (from `packages/tasks/package.json`):

| Import | Exports you use |
|---|---|
| `@ghuri/tasks` | `task`, `Task`, `TaskContext`, `TaskResult`, `TaskResultStatus`, `TasksConfig`, `cloudflareQueues`, `database`, `immediate`, `dummy`, `taskBackends`, `defaultTaskBackend`, `periodicTask`, `periodicTasks`, `runWorker`, `drainTasks`, `getTask`, `registeredTasks`, `taskEnqueued`, `taskStarted`, `taskFinished`, `DBTaskResult`, `InvalidTask`, `InvalidTaskBackend`, `TaskResultDoesNotExist`, `TaskResultMismatch`, `TaskResultNotReady`, `NotImplementedError` |
| `@ghuri/tasks/testing` | `useTaskBackend`, `captureTasks`, `dummy`, `immediate`, `DummyBackend`, `ImmediateBackend` |
| `@ghuri/tasks/admin` | importing it registers `DBTaskResultAdmin` (read-only, "Run selected tasks again", "Mark selected tasks as failed") |

## Django / Celery habit -> Ghuri

| Django 6.0 / Celery | Ghuri |
|---|---|
| `@task(queue_name='emails')` on a function in `tasks.py` | `export const sendReceipt = task(async (orderId: number) => {...}, { queueName: 'emails' })` in `src/<app>/tasks.ts`, plus `tasks = tasks` on the AppConfig |
| task identity = `module_path` | `task.modulePath` = `'<app label>.<export name>'` (`'shop.sendReceipt'`); `task.name` = `'sendReceipt'` |
| `my_task.enqueue(order.pk)` / `aenqueue` | `await sendReceipt.enqueue(order.pk)` (always async; positional args only, no kwargs) |
| `my_task.using(priority=10, run_after=timedelta(minutes=5))` | `sendReceipt.using({ priority: 10, runAfter: 300 })` (`runAfter`: a `Date` or seconds) |
| `my_task.get_result(id)` / `result.refresh()` | `await sendReceipt.getResult(id)` / `await result.refresh()` |
| `result.return_value` (ValueError if not done) | `result.returnValue` (throws `TaskResultNotReady`) |
| `TASKS = {"default": {"BACKEND": "...ImmediateBackend"}}` | `TASKS: { default: immediate() }` (or `database()`, `cloudflareQueues({...})`, `dummy()`) |
| django-tasks `db_worker` | `npx ghuri db_worker` (`npm run worker`) |
| Celery `autoretry_for` / `max_retries` | `task(fn, { maxAttempts: 3, retryDelay: 30 })` |
| Celery beat schedule | `periodicTask('0 3 * * *', cleanUp)` in `AppConfig.ready()` |
| `transaction.on_commit(lambda: t.enqueue(...))` | `await onCommit(() => t.enqueue(...))` (`onCommit` from `@ghuri/orm`) |
| `takes_context=True` | `task(async (ctx, ...args) => ..., { takesContext: true })`; `ctx.attempt`, `ctx.taskResult` |

## Defining and enqueuing

```ts
// src/shop/tasks.ts
import { task } from '@ghuri/tasks'
import { Order } from './models'

export const sendReceipt = task(
  async (orderId: number) => {
    const order = await Order.objects.get({ pk: orderId })
    // ... send the email
    return { sent: true }                         // must be JSON (or nothing)
  },
  { queueName: 'emails', maxAttempts: 3, retryDelay: (attempt) => 30 * attempt },
)

// src/shop/app.ts
import * as tasks from './tasks'
export class ShopConfig extends AppConfig {
  name = 'shop'
  models = models
  migrations = migrations
  tasks = tasks                                   // names them 'shop.<export name>'
}

// anywhere (view, signal receiver, agent tool)
const result = await sendReceipt.enqueue(order.pk) // TaskResult, status 'READY' on a queue backend
await sendReceipt.using({ runAfter: new Date(Date.now() + 3600_000) }).enqueue(order.pk)
```

- `task()` options: `name` (only for tasks NOT exported from an app's `tasks` module), `priority` (-100..100, larger first), `queueName` (default `'default'`), `backend` (TASKS alias), `takesContext`, `maxAttempts` (default 1), `retryDelay` (seconds or `(attempt) => seconds`; default `2 ** attempt`, max 1 h).
- `runAfter` is only on `using()`, not `task()`.
- Arguments and return values must survive a JSON round trip: a `Date`, `Map`, `undefined`, `NaN` or a model instance raises `InvalidTask` (args) or fails the task (return). Pass primary keys and ISO strings.
- `await t.call(...args)` runs the function now, without a backend.
- The request context registered with core's context carriers (the current tenant with `@ghuri/tenants`) is captured at `enqueue()` and restored around every attempt. The request user is NOT carried: pass `user.pk`.

## Results

`TaskResult`: `id` (UUIDv7), `status` (`'READY' | 'RUNNING' | 'FAILED' | 'SUCCESSFUL'`, also `TaskResultStatus.READY`…), `args`, `backend`, `enqueuedAt`, `startedAt`, `finishedAt`, `lastAttemptedAt`, `runAfter`, `attempts` (finished ones), `errors` (`[{ exceptionClassPath, traceback }]`), `workerIds`, `isFinished`, `returnValue`, `refresh()`.

## Settings and backends

```ts
// src/settings.ts
import { cloudflareQueues, database, TasksConfig } from '@ghuri/tasks'

INSTALLED_APPS: [/* ... */, TasksConfig, ShopConfig],
TASKS: {
  // Queues on Workers (binding TASKS_QUEUE), the database elsewhere (run `npx ghuri db_worker`)
  default: env.TASKS_QUEUE
    ? cloudflareQueues({ queues: { default: 'TASKS_QUEUE', emails: 'EMAILS_QUEUE' } })
    : database({ queues: ['default', 'emails'] }),
},
```

| | `immediate()` | `dummy()` | `cloudflareQueues({ queues })` | `database({ database?, staleAfter? })` |
|---|---|---|---|---|
| Runs | inside `enqueue()` | never (tests) | the Worker's `queue()` handler | `ghuri db_worker`, or `drainTasks()` from a cron |
| `runAfter` | no (`InvalidTask`) | yes | up to 24 h | yes |
| `priority` | accepted, ignored | yes | no (`InvalidTask` if not 0) | yes |
| `getResult()` | no (`NotImplementedError`) | no | only with `TasksConfig` installed | yes |

- No `TASKS` setting = `{ default: immediate() }` (tasks run inside the request).
- Every factory takes `queues` (allowed queue names, default `['default']`; `[]` = any). A task on another queue raises `InvalidTask`.
- `cloudflareQueues` maps queue name -> producer binding. `export default createApp(settings)` already has the `queue()` handler; it runs task messages and leaves other messages to your `onQueue()` handlers. Messages max 128 KB.

```jsonc
// wrangler.jsonc
"queues": {
  "producers": [{ "binding": "TASKS_QUEUE", "queue": "mysite-tasks" }],
  "consumers": [{ "queue": "mysite-tasks", "max_retries": 3 }]   // keep >= maxAttempts - 1
},
"triggers": { "crons": ["0 3 * * *"] }
```

## Workers for the database backend

```sh
npx ghuri db_worker                              # all queues until SIGTERM
npx ghuri db_worker --queue-name emails --interval 2
npx ghuri db_worker --batch                      # run what is ready, then exit
npx ghuri db_worker --beat                       # also fire Cron Triggers (periodic tasks): ONE process only
npx ghuri prune_db_task_results --min-age-days 14 [--only-failed] [--dry-run]
```

On Workers without Queues: `onSchedule('* * * * *', drainTasks({ seconds: 25 }))` in a `ready()`. In code: `await runWorker({ batch: true })`. A `RUNNING` task older than `staleAfter` (default 3600 s) lost its worker and is retried or failed.

## Periodic tasks

```ts
import { periodicTask } from '@ghuri/tasks'

ready() {
  periodicTask('0 3 * * *', purgeOldDrafts)                     // enqueue at 03:00 UTC
  periodicTask('*/10 * * * *', syncFeeds, { args: [10], inline: true })   // or run in the cron handler
}
```

Crons use Cloudflare syntax in UTC: day of week is **1-7 with 1 = Sunday** (or `SUN`-`SAT`), not Unix 0 = Sunday. On Workers, list every cron in `wrangler.jsonc` `triggers.crons`. On Node, run the scheduler in exactly one process: `serve(app, { scheduler: true })` (`@ghuri/core/node`) or `npx ghuri db_worker --beat`.

## Agents

With `@ghuri/agents` 0.1.0-alpha.6+, `agent.enqueue(input, { user })` becomes the `agents.run` task (3 attempts) when `@ghuri/tasks` is loaded and returns `{ conversationId, taskResult, taskResultId }`. See agents.md.

## Signals, admin, checks

- `taskEnqueued`, `taskStarted`, `taskFinished`: sender = backend class, args `{ taskResult }`. `taskFinished` fires once, on `SUCCESSFUL` or final `FAILED` (not on a retried attempt).
- `import '@ghuri/tasks/admin'` in your admin module.
- `ghuri check`: `tasks.E001` bad `TASKS` entry, `tasks.E002` task uses an unknown backend/queue, `tasks.E003` periodic cron missing from `wrangler.jsonc`, `tasks.E004` `database()` without `TasksConfig`, `tasks.E005` producer binding missing from `wrangler.jsonc`, `tasks.W002` consumer `max_retries` < `maxAttempts - 1`, `tasks.W004` queue without a consumer, `tasks.W001` (`--deploy`) default backend is `immediate()`.

## Testing

```ts
import { captureTasks, dummy, useTaskBackend } from '@ghuri/tasks/testing'

const { backend, restore } = useTaskBackend(dummy({ queues: [] }))
try {
  await api.post('/api/orders/', data)
  expect(backend.results.map((r) => r.task.modulePath)).toEqual(['shop.sendReceipt'])
  await backend.runPending()                     // runs them in-process (retries and context included)
} finally {
  restore()
}

const results = await captureTasks(() => api.post('/api/orders/', data))   // any backend
```

With `database()` in tests, enqueue then `await runWorker({ batch: true })` (`TasksConfig` must be installed so `setupTestDatabase()` creates the table).

## Gotchas

- Forgetting `tasks = tasks` on the AppConfig: `enqueue()` raises `InvalidTask` ("has no name"). Tasks outside an app need `task(fn, { name: 'billing.sync' })`.
- Renaming a task's export renames it (`'shop.sendReceipt'` -> ...): messages already queued under the old name fail as "not registered".
- Without `TASKS`, `immediate()` runs the task inside the request (fine in dev, slow in prod; `check --deploy` warns).
- `using({ runAfter })` on `immediate()` and `priority` on `cloudflareQueues()` raise `InvalidTask`.
- A task that throws is retried only with `maxAttempts > 1`; Django has no retries. Retries can repeat side effects: make tasks idempotent.
- The worker's database backend is a compare-and-set claim: run as many `db_worker` processes as you like, but `--beat` in one only.
- Do not import Celery, BullMQ or `node-cron` patterns; do not call `env.TASKS_QUEUE.send()` yourself (use `enqueue()`).
- Cron day-of-week numbering differs from Unix; prefer names (`MON-FRI`).
