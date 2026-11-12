# Testing

Covers `ghuri test` (Vitest), the vitest config, test databases (`@ghuri/orm/testing`), the app test client (`@ghuri/core/testing`), `APIClient` (`@ghuri/rest/testing`), GraphQL/WebSocket helpers, query counting, commands, cron/queue handlers.

## Django/DRF habit -> Ghuri

| Django / DRF | Ghuri |
|---|---|
| `python manage.py test` | `npx ghuri test` (runs the project's `vitest run`; `--watch`; extra args go to vitest) |
| `class T(TestCase): def test_x(self)` | plain Vitest `describe` / `it` / `expect` |
| test DB created by the runner | `await setupTestDatabase({ using })` in `beforeAll` |
| transaction rollback per test (`TestCase`) | `await db.flush()` in `beforeEach`/`afterEach` (`TransactionTestCase` style) |
| `django.test.Client` | `createTestClient(app, { env })` from `@ghuri/core/testing` |
| `client.force_login(u)` / `client.login(...)` | `await client.forceLogin(u)` / `await client.login({ username, password })` |
| `APIClient().force_authenticate(user=u)` | `api.forceAuthenticate(u)` (sync) |
| `client.credentials(HTTP_AUTHORIZATION='Token k')` | `api.credentials({ Authorization: 'Token k' })` |
| `self.client.post(url, data, format='json')` | `api.post(url, data, { format: 'json' })` |
| `response.data` / `response.status_code` | `res.data` / `res.status` |
| `self.assertNumQueries(3)` | `const [, queries] = await captureQueries(fn); expect(queries).toHaveLength(3)` |
| `call_command('x', y=1)` | `await callCommand('x', { y: 1 }, bufferIO())` |
| `GraphQLTestCase.query()` | `graphqlQuery(client, query, { variables })` |
| Channels `WebsocketCommunicator` | `WebSocketCommunicator` from `@ghuri/realtime/testing` |

## vitest.config.ts

```ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  // Ghuri decorators (@action, @admin.register, @display, @tool) need legacy decorator lowering under oxc.
  oxc: { decorator: { legacy: true } } as Record<string, unknown>,
  test: {
    include: ['src/**/tests.ts', 'src/**/*.test.ts', 'tests/**/*.test.ts'],
    testTimeout: 30_000,   // PGlite / D1 (Miniflare) take seconds to start
    hookTimeout: 60_000,
  },
})
```

Without the `include`, Vitest only collects `*.test.ts` / `*.spec.ts`, so Django-style `tests.ts` files are silently skipped. `vitest` must be a devDependency of the project.

## Canonical setup (adapted from examples/blog/src/blog/tests.ts, which defaults to `'d1'`)

```ts
import { PBKDF2PasswordHasher, User } from '@ghuri/auth'
import { createApp, type GhuriContext } from '@ghuri/core'
import { setupTestDatabase, type TestBackend, type TestDatabase } from '@ghuri/orm/testing'
import { APIClient } from '@ghuri/rest/testing'
import { memoryStorage } from '@ghuri/storage'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest'
import settings from '../settings'
import { Post } from './models'

const env: Record<string, unknown> = { SECRET_KEY: 'test-secret-key', DEBUG: 'false' }  // ONE shared object
const app = createApp(settings)
let ctx: GhuriContext
let db: TestDatabase
let api: APIClient

beforeAll(async () => {
  ctx = await app.setup(env)                                          // 1. populate apps, global context
  ctx.settings.PASSWORD_HASHERS = [new PBKDF2PasswordHasher({ iterations: 1000 })]  // fast hashing
  ctx.settings.STORAGES = { default: memoryStorage() }
  db = await setupTestDatabase({ using: (process.env.GHURI_TEST_DB as TestBackend) ?? 'sqlite' })  // 2.
  api = new APIClient(app, { env, defaultFormat: 'json' })            // 3. same env object
}, 60_000)

afterAll(async () => {
  await db?.teardown()
})

beforeEach(async () => {
  await db.flush()            // empty tables, re-send postMigrate (content types, permissions)
  api.forceAuthenticate(null)
  api.credentials()
  api.client.clearCookies()
})

describe('posts API', () => {
  it('creates a post as the request user', async () => {
    const bob = await User.objects.createUser('bob', 'bob@example.com', 'pw-bob')
    expect((await api.post('/api/posts/', { title: 'Nope', slug: 'nope' })).status).toBe(401)
    api.forceAuthenticate(bob)
    const res = await api.post('/api/posts/', { title: 'Mine', slug: 'mine', body: 'Hi' })
    expect(res.status).toBe(201)
    expect(res.data).toMatchObject({ slug: 'mine', author: bob.pk })
    expect(await Post.objects.filter({ slug: 'mine' }).exists()).toBe(true)
  })
})
```

Order matters: `app.setup(env)` first, then `setupTestDatabase()` (it merges `DATABASES.default` into the current context's settings), then the client with the **same `env` object**. Settings are cached per `env` object, so a client built with a different (or no) `env` resolves fresh settings that point at the real database (`d1('DB')`) instead of the test one.

`GHURI_TEST_DB` above is a convention of the example app, not read by the framework. The framework reads `GHURI_TEST_BACKENDS` (see `testBackends()`).

## setupTestDatabase (`@ghuri/orm/testing`)

| Option | Default | Meaning |
|---|---|---|
| `using` | `'sqlite'` | `'sqlite'` (better-sqlite3 in memory), `'pglite'` (Postgres via WASM), `'d1'` (D1 via Miniflare) |
| `models` | all registered | limit tables to these models (array or module object) |
| `appLabel` | `'tests'` | label given to unlabeled models passed in `models` |
| `alias` | `'default'` | `DATABASES` alias to install |
| `createTables` | `true` | run migrations of apps that have them, create tables for the rest, send `postMigrate` |

Returns `TestDatabase { alias, using, connection, models, flush(opts?), teardown() }`. `flush({ inhibitPostMigrate: true })` leaves tables fully empty. `teardown()` closes the DB and restores previous `DATABASES` (or drops the context it created). Without a prior `app.setup()`, it creates its own minimal context (`INSTALLED_APPS: []`), which is enough for pure ORM tests on models passed via `models`.

Peer deps: `better-sqlite3` for sqlite, `@electric-sql/pglite` for pglite, `miniflare` (comes with wrangler) for d1.

Run the suite on several dialects:

```ts
import { setupTestDatabase, testBackends, type TestDatabase } from '@ghuri/orm/testing'
import { afterAll, afterEach, beforeAll, describe } from 'vitest'

describe.each(testBackends())('posts on %s', (using) => {
  let db: TestDatabase
  beforeAll(async () => { db = await setupTestDatabase({ using }) })
  afterEach(() => db.flush())
  afterAll(() => db.teardown())
})
// GHURI_TEST_BACKENDS=sqlite,pglite npx ghuri test
```

There is no per-test transaction rollback (D1 cannot do it); isolation is `flush()`.

## Test client (`@ghuri/core/testing`)

```ts
import { createApp } from '@ghuri/core'
import { createTestClient } from '@ghuri/core/testing'
import settings from '../settings'

const env = { SECRET_KEY: 'test', DEBUG: 'true' }
const app = createApp(settings)
const client = createTestClient(app, { env })   // opts: env, baseUrl ('http://testserver'), headers, csrf

const r1 = await client.get('/blog/', { query: { q: 'ghuri' } })
const r2 = await client.post('/contact/', { form: { email: 'a@b.c', file: new File(['x'], 'x.txt') } })
const r3 = await client.patch('/api/posts/x/', { json: { published: true }, headers: { Authorization: 'Token k' } })
const r4 = await client.get('/old/', { follow: true })   // r4.redirectChain: [['/new/', 301]]
const html = await r1.text()
```

- Methods: `get/head/options/post/put/patch/delete(path, { json?, form?, body?, query?, headers?, follow?, csrf? })`. Responses are real `Response`s (`await res.json()`, `res.text()`) plus `redirectChain`, `request`.
- `form` is urlencoded, or multipart when it contains a `File`/`Blob` or is a `FormData`.
- Cookies persist: `getCookie`, `setCookie`, `deleteCookie`, `clearCookies`.
- CSRF token is added automatically to unsafe requests; `csrf: false` (client or request) to test failures.
- `await client.forceLogin(user)`, `await client.login({ username, password })` (returns boolean), `await client.logout()`. Registered as hooks when `@ghuri/auth` is imported; need `SessionsConfig` + `SessionMiddleware`.
- `await client.waitForBackgroundTasks()` awaits `waitUntil()` work. `client.withContext(fn)` runs `fn` in a context for the client's env.
- `registerTestClientHook(name, fn)` / `client.callHook(name, ...args)` to extend.
- Requests use host `testserver`; if `ALLOWED_HOSTS` is restricted, add `'testserver'` or every request is 400.

## APIClient (`@ghuri/rest/testing`)

```ts
import { createApp } from '@ghuri/core'
import { APIClient } from '@ghuri/rest/testing'
import settings from '../settings'

const env = { SECRET_KEY: 'test' }
const api = new APIClient(createApp(settings), { env, defaultFormat: 'json' })

await api.get('/api/posts/', { page: 2, search: 'x' })              // 2nd arg is the QUERY, not a body
await api.post('/api/posts/', { title: 'T' })                       // body; format from defaultFormat
await api.patch('/api/posts/t/', { cover: new File([new Uint8Array([1])], 'c.png') }, { format: 'multipart' })
await api.delete('/api/posts/t/')
await api.get('/api/schema/', {}, { headers: { Accept: 'application/json' } })
```

- Signatures: `get(path, query?, opts?)`, `head(path, query?, opts?)`, `options(path, opts?)`, `post/put/patch/delete(path, data?, opts?)`. `opts`: `format` (`'json' | 'multipart' | 'form'`), `headers`, `query`, `follow`, `csrf`.
- Default body format is `REST_FRAMEWORK.TEST_REQUEST_DEFAULT_FORMAT` = `'multipart'` (like DRF). Pass `defaultFormat: 'json'` to the constructor to avoid surprises with nested data.
- `res.data` is the parsed JSON body (undefined for non-JSON).
- `forceAuthenticate(user, token?)` / `forceAuthenticate(null)`: bypasses authentication classes, honored only where authentication goes through `@ghuri/rest`'s request (API views/viewsets, the `@ghuri/agents` MCP endpoint). For admin, plain views and session-based GraphQL use `await api.client.forceLogin(user)`.
- `credentials({ Authorization: 'Token <key>' | 'Bearer <jwt>' })`; `credentials()` clears. `logout()` clears both plus cookies.
- `api.client` is the underlying `TestClient` (`forceLogin`, `clearCookies`, raw `get` for non-API pages). `createAPIClient(app, opts)` is the factory form.

## Query counting (`@ghuri/orm`)

```ts
import { captureQueries } from '@ghuri/orm'
import { expect } from 'vitest'
import { Post } from './models'

const [posts, queries] = await captureQueries(() => Post.objects.all().selectRelated('author').fetch())
expect(queries).toHaveLength(1)          // QueryEvent { alias, vendor, sql, params, durationMs }
```

There is no `assertNumQueries`. `fn` must return a promise: wrap any awaited query, e.g. `captureQueries(async () => await Post.objects.count())`. `onQuery(listener)` subscribes to every statement (returns an unsubscribe function).

## GraphQL (`@ghuri/graphql/testing`)

```ts
import { assertResponseHasErrors, assertResponseNoErrors, graphqlQuery, payloadErrors } from '@ghuri/graphql/testing'
import { expect } from 'vitest'

const res = await graphqlQuery(api.client, 'query ($id: ID!) { post(id: $id) { slug } }', {
  variables: { id },
  headers: { Authorization: `Token ${token}` },   // also: path ('/graphql/'), method 'GET', csrf, operationName
})
assertResponseNoErrors(res)
expect(res.data.post.slug).toBe('hello')
assertResponseHasErrors(await graphqlQuery(api.client, 'mutation { deletePost(input: { id: "x" }) { ok } }'), { code: 'UNAUTHENTICATED' })
payloadErrors(res.data.createPost)    // { field: [messages] } from mutation payload errors
```

Pass the core `TestClient` (`api.client`), not the `APIClient`. Change the default endpoint once with `graphqlTestDefaults.path = '/api/graphql/'`.

## WebSockets (`@ghuri/realtime/testing`)

```ts
import { WebSocketCommunicator } from '@ghuri/realtime/testing'
import { expect } from 'vitest'

const ws = new WebSocketCommunicator(app, '/ws/chat/lobby/', { user: alice, env })
expect((await ws.connect()).connected).toBe(true)
await ws.sendJson({ text: 'hi' })
expect(await ws.receiveJson()).toEqual({ type: 'chat.message', text: 'hi' })
expect(await ws.receiveNothing({ timeout: 100 })).toBe(true)
await ws.disconnect()
```

Also `sendText`, `sendBytes`, `receiveFrom`, `receiveClose`. See the realtime reference for consumers.

## Commands, cron, queues, signals

```ts
import { bufferIO, callCommand, taskHandlers } from '@ghuri/core'
import { postSave } from '@ghuri/orm'
import { expect, vi } from 'vitest'
import { Post } from './models'

const io = bufferIO()
await callCommand('publish_scheduled', { dryRun: true, limit: '10' }, io)   // args NOT parsed: camelCase, no defaults
expect(io.out).toContain('Nothing to publish.')                              // io.out / io.err are string[]

await app.scheduled({ cron: '0 * * * *', scheduledTime: Date.now() }, env)
const msg = { id: '1', timestamp: new Date(), body: { postId: 1 }, ack: vi.fn(), retry: vi.fn() }
await app.queue({ queue: 'emails', messages: [msg], ackAll: vi.fn(), retryAll: vi.fn() }, env)
expect(msg.ack).toHaveBeenCalled()
taskHandlers.clear()

const spy = vi.fn()
postSave.connect(spy, { sender: Post })
try { /* ... */ } finally { postSave.disconnect(spy) }
```

## Gotchas

- No `TestCase` classes, `setUp`, `self.assert*`, fixtures files or `@override_settings`: use Vitest hooks and mutate `ctx.settings` (returned by `app.setup(env)`) in `beforeAll`.
- Every ORM call is async: `await User.objects.createUser(...)`, `await Post.objects.count()`.
- Call `app.setup(env)` BEFORE `setupTestDatabase()`, and pass the identical `env` object to `app.setup`, `createTestClient`/`APIClient`, `app.scheduled`/`app.queue`.
- Isolation is `db.flush()` per test; nothing rolls back automatically. `flush()` re-creates permissions/content types via `postMigrate`.
- Default `PBKDF2PasswordHasher` iterations make user creation slow: set `PASSWORD_HASHERS` to `[new PBKDF2PasswordHasher({ iterations: 1000 })]`.
- `api.get(path, query)` - the second argument is query params. Bodies go on post/put/patch/delete.
- `APIClient` posts multipart by default; nested objects get JSON-stringified per field. Use `defaultFormat: 'json'` or `{ format: 'json' }`.
- `forceAuthenticate` does not log in for admin/HTML views; use `client.forceLogin(user)` (async, returns a promise).
- `client.forceLogin`/`login` throw "No test client hook" unless `@ghuri/auth` is imported somewhere in the test process.
- Test files named `tests.ts` need the `include` pattern in `vitest.config.ts`; decorators need `oxc.decorator.legacy`.
- Tests talk to `http://testserver`; restricted `ALLOWED_HOSTS` must include `'testserver'`.
- `callCommand` passes args straight to `handle()`; option defaults from `addArguments` are not applied.
- Signal receivers are global module state: disconnect in `finally`. Use `taskHandlers.clear()` for cron/queue handlers.
