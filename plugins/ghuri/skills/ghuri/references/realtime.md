# Realtime / WebSockets (@ghuri/realtime)

Covers Channels-style WebSocket consumers: `WebSocketConsumer` / `JsonWebSocketConsumer`, routing with `path()`, rooms, `this.state` (consumers rebuilt per event), group events, `channelLayer`, the `REALTIME` setting and layers, the Cloudflare Durable Object setup, Node serving, handshake auth, limits and `WebSocketCommunicator` tests.

Install: `npm install @ghuri/realtime@next` (needs `@ghuri/core` / `@ghuri/auth` 0.1.0-alpha.1+). It is a library, not an app: nothing goes in `INSTALLED_APPS`.

Entry points (from `packages/realtime/package.json`):

| Import | Exports you use |
|---|---|
| `@ghuri/realtime` | `WebSocketConsumer`, `JsonWebSocketConsumer`, `channelLayer`, `memoryLayer`, `memoryStorage`, `handlerName`, `type Scope`, `type GroupEvent`, `type Room`, `RealtimeUser`, `RealtimeError`, `RealtimeStateTooLarge`, `ConsumerStateError`, `MAX_RECORD_BYTES`, `MAX_TAGS`, `MAX_TAG_LENGTH` |
| `@ghuri/realtime/cloudflare` | `durableObjectLayer(binding = 'REALTIME')`, `createRoomClass(app)` |
| `@ghuri/realtime/node` | `attachRealtime(server, app, { env, maxPayload })` |
| `@ghuri/realtime/testing` | `WebSocketCommunicator`, `CommunicatorClosed` |

## Django Channels habit -> Ghuri

| Channels | Ghuri |
|---|---|
| `AsyncWebsocketConsumer` / `AsyncJsonWebsocketConsumer` | `WebSocketConsumer` / `JsonWebSocketConsumer` |
| `websocket_urlpatterns` + `URLRouter` in `asgi.py` | `path('ws/chat/<slug:room>/', ChatConsumer.asView())` in normal `urls.ts` |
| `AuthMiddlewareStack` | your `MIDDLEWARE` (runs on the handshake) + `static authenticationClasses` |
| `AllowedHostsOriginValidator` | built in: request host, `CSRF_TRUSTED_ORIGINS`, `REALTIME.ALLOWED_ORIGINS` |
| `self.scope['user']` | `this.user` |
| `self.scope['url_route']['kwargs']` | `this.scope.params` (strings) |
| `group_add(group, self.channel_name)` | `static room` (exactly one room per socket) or `this.tag(name)` within the room |
| `channel_layer.group_send(group, {'type': 'chat.message', ...})` | `await this.room.groupSend({ type: 'chat.message', ... })` / `channelLayer.groupSend(room, event)` |
| `async def chat_message(self, event)` | `async chatMessage(event)` |
| `self.channel_name` / `channel_layer.send(name, ev)` | `this.scope.connectionId` / `channelLayer.send(id, ev)` |
| `await self.send_json(x)` / `await self.accept()` | `this.sendJson(x)` / `this.accept()` (synchronous) |
| `receive_json(self, content)` | `async receiveJson(data)` |
| `InMemoryChannelLayer` / `RedisChannelLayer` | `memoryLayer()` / `durableObjectLayer()` |
| `self.foo = ...` kept between messages | `this.state.foo = ...` (instance fields are lost) |
| `database_sync_to_async` | not needed: ORM is async |
| `WebsocketCommunicator` | `WebSocketCommunicator` |

## A consumer

```ts
// src/chat/consumers.ts
import { JsonWebSocketConsumer, type Scope } from '@ghuri/realtime'
import { IsAuthenticated } from '@ghuri/rest'
import { Message } from './models'

export class ChatConsumer extends JsonWebSocketConsumer {
  static room = (scope: Scope) => `chat.${scope.params.room}`
  static permissionClasses = [IsAuthenticated]

  async connect() {
    this.accept()
    this.state.sent = 0
    await this.room.groupSend({ type: 'chat.joined', user: this.user.username }, { exclude: this })
  }

  async receiveJson(data: { text: string }) {
    this.state.sent = ((this.state.sent as number) ?? 0) + 1
    if ((this.state.sent as number) > 100) return this.close(4429, 'Slow down')
    const msg = await Message.objects.create({ room: this.scope.params.room, author: this.user.pk, text: data.text })
    await this.room.groupSend({ type: 'chat.message', id: msg.pk, text: msg.text, user: this.user.username })
  }

  // group event handlers: 'chat.message' / 'chat-message' / 'chat_message' -> chatMessage()
  async chatMessage(event: { id: number; text: string; user: string }) {
    this.sendJson(event)
  }

  async chatJoined(event: { user: string }) {
    this.sendJson({ type: 'joined', user: event.user })
  }

  async disconnect(code: number, reason: string) {
    await this.room.broadcast({ type: 'left', user: this.user.username })
  }
}
```

```ts
// src/chat/urls.ts
import { path } from '@ghuri/core'
import { ChatConsumer } from './consumers'

export const urlpatterns = [path('ws/chat/<slug:room>/', ChatConsumer.asView(), { name: 'chat-socket' })]
```

Browser: `new WebSocket(\`wss://${location.host}/ws/chat/lobby/\`)`. A plain HTTP GET to that URL gets 426.

### Handlers you override (exact names)

| Method | When |
|---|---|
| `async connect()` | Handshake arrived. Default calls `this.accept()`. Calling `close()` or not calling `accept()` rejects with 403. |
| `async receive({ text?, bytes? })` | Frame arrived (`WebSocketConsumer`). `JsonWebSocketConsumer` parses text and calls `receiveJson(data)`; binary frame -> close 1003, bad JSON -> close 1007. |
| `async receiveJson(data)` | JSON consumer only. |
| `async disconnect(code, reason)` | Socket closed from either side. Runs once. |
| `async <handlerName>(event)` | Group event of matching `type`. Unknown types are dropped (warning when `DEBUG`). |

Methods you call: `accept(subprotocol?)` (only in `connect()`), `send(data)` (string / ArrayBuffer / Uint8Array), `sendJson(data)`, `close(code = 1000, reason = '')`, `tag(...tags)` / `untag(...tags)` / `tags`, `await refreshUser()` (false + close 4401 when the user is gone or inactive), `dispatch(event)`.

Reserved names that can never be event handlers: `connect`, `receive`, `receiveJson`, `disconnect`, `accept`, `send`, `sendJson`, `close`, `tag`, `untag`, `refreshUser`, `dispatch`. `handlerName('chat.message') === 'chatMessage'`.

### Static configuration

| Static | Meaning |
|---|---|
| `room` | `string` or `(scope) => string \| null \| Promise<...>`. Default: the request path. `null` -> 403. |
| `authenticationClasses` | REST authentication classes run on the handshake (default: the user set by `MIDDLEWARE`). |
| `permissionClasses` | REST permission classes checked before `connect()`. Denied: 401 anonymous, 403 otherwise. |
| `subprotocols` | Subprotocols this consumer speaks; first one the client offered is accepted. |

`asView(initkwargs)` assigns values to every instance: `path('ws/feed/news/', FeedConsumer.asView({ kind: 'news' }))`.

### Inside a handler

- `this.scope`: `path`, `params` (route params as strings: `<int:id>` arrives as `'42'`), `query`, `routeName`, `room`, `connectionId` (`<room>:<uuid>`), `headers` (`origin`, `userAgent`, `subprotocols`), `user` (snapshot), `sessionKey`, `auth` (token payload when small).
- `this.user`: a `RealtimeUser` rebuilt from the handshake snapshot (`pk`, `username`, `isAuthenticated`, `isActive`, `isStaff`, `isSuperuser`). `await this.user.hasPerm('app.perm')` loads the real user. `getUser()` from `@ghuri/core` returns the same user.
- `this.room`: the connection's `Room`.
- `this.state`: per-connection JSON data, saved after every handler.

## Consumers are rebuilt for every event

On Cloudflare each room is a Durable Object using the WebSocket Hibernation API; a hibernated object keeps no memory. So a **fresh consumer instance is built for every message, group event and disconnect** from the saved `scope` + `state` + tags. Fields set on `this` (other than `state`) are gone by the next event. Node behaves the same so code is portable.

`scope` + `state` + tags must fit in `MAX_RECORD_BYTES` (2048 bytes, Cloudflare's `serializeAttachment` limit, enforced on every backend). Exceeding it throws `RealtimeStateTooLarge` (the handler fails -> close 1011). Keep larger data in `this.room.storage` or the database.

## Rooms and the channel layer

Each socket belongs to exactly one room, chosen at handshake. Need two streams? Open two sockets, or use a per-user room (`` static room = (s: Scope) => (s.user.isAuthenticated ? `user.${s.user.pk}` : null) ``).

| `Room` member | Does |
|---|---|
| `groupSend(event, { tag?, exclude? })` | Runs the event's handler on every (matching) connection; resolves when all ran. `exclude` takes a consumer (`this`) or a connection id. Event needs a string `type`. |
| `broadcast(message, { tag?, exclude? })` | Sends the same frame to every socket without running consumer code (objects JSON-encoded). Cheaper. |
| `send(connectionId, event)` | Runs the handler on one connection. |
| `connections({ tag? })` / `count({ tag? })` | `{ id, userPk, tags, connectedAt }[]` / number. |
| `storage` | `get`, `put`, `delete`, `list({ prefix, limit })`: DO storage on Cloudflare, memory on Node. |

From anywhere else (views, signal receivers, cron, queue handlers):

```ts
import { getContext } from '@ghuri/core'
import { postSave } from '@ghuri/orm'
import { channelLayer } from '@ghuri/realtime'
import { Post } from './models'

postSave.connect(
  async ({ instance, created }) => {
    const post = instance as Post
    if (created && post.published) {
      await channelLayer.broadcast('feed', { type: 'post.created', id: post.pk, title: post.title })
    }
  },
  { sender: Post, uid: 'feed-new-posts' },
)

// In a view, without waiting for delivery:
export function notify(pk: unknown, text: string) {
  getContext().executionCtx?.waitUntil(channelLayer.groupSend(`user.${pk}`, { type: 'notify', text }))
}
```

`channelLayer`: `room(name)`, `groupSend(room, event, opts?)`, `broadcast(room, message, opts?)`, `send(connectionId, event)`. Needs a Ghuri context (inside a request, handler or `app.run()`). Delivery is at-most-once, no replay: reconnecting clients reload missed data over HTTP.

## Settings: `REALTIME`

```ts
import { defineSettings } from '@ghuri/core'
import { durableObjectLayer } from '@ghuri/realtime/cloudflare'

export default defineSettings((env) => ({
  // ...
  REALTIME: {
    LAYER: durableObjectLayer('REALTIME'),     // Node / tests: memoryLayer() from '@ghuri/realtime' (the default)
    ALLOWED_ORIGINS: ['https://app.example.com', 'https://*.example.com'],
    TOKEN_SOURCES: ['subprotocol'],             // and/or 'query' (?token=)
    TOKEN_KEYWORD: 'Bearer',                    // 'Token' for TokenAuthentication
    MAX_MESSAGE_BYTES: 1_048_576,               // larger frames close with 1009
    REVALIDATE_SECONDS: 0,                      // >0: reload user before an event after N seconds
  },
}))
```

Keys (source `settings.ts`): `LAYER`, `ALLOWED_ORIGINS`, `TOKEN_SOURCES`, `TOKEN_KEYWORD`, `MAX_MESSAGE_BYTES`, `REVALIDATE_SECONDS`. Nothing else. `memoryLayer({ name? })` is the default when `LAYER` is unset.

## Cloudflare: Durable Object export + wrangler

```ts
// src/index.ts (Worker entry)
import { createApp } from '@ghuri/core'
import { createRoomClass } from '@ghuri/realtime/cloudflare'
import settings from './settings'

const app = createApp(settings)
export default app
export const GhuriRoom = createRoomClass(app)
```

```jsonc
// wrangler.jsonc
"durable_objects": { "bindings": [{ "name": "REALTIME", "class_name": "GhuriRoom" }] },
"migrations": [{ "tag": "realtime-v1", "new_sqlite_classes": ["GhuriRoom"] }]
```

The binding name must match `durableObjectLayer('REALTIME')`. `wrangler dev` runs DOs locally, so use the DO layer in development too. `memoryLayer()` throws `ImproperlyConfigured` on Workers. Keep the migration entry once deployed; add new tags instead of editing. Sockets drop on every deploy; clients reconnect with backoff. `ping` text frames get `pong` without waking the object. One room = one single-threaded object (a few thousand connections is the practical ceiling). Consumers run with the Worker's bindings, so the ORM (D1) works inside them.

## Node

```ts
// src/server.ts
import { createApp } from '@ghuri/core'
import { serve } from '@ghuri/core/node'
import { attachRealtime } from '@ghuri/realtime/node'
import settings from './settings'

const app = createApp(settings)
const server = await serve(app, { port: Number(process.env.PORT ?? 8000), env: process.env })
attachRealtime(server, app, { env: process.env })
```

Handshakes still go through `app.fetch` (middleware, routing). With `memoryLayer()` rooms live in the process: run **one** Node process (no multi-process layer yet). The reverse proxy must pass `Upgrade` / `Connection` headers. Without `attachRealtime`, handshakes get 426.

## Handshake: auth and permissions

Order after `MIDDLEWARE`: (1) Origin check: browser `Origin` must match the host, `CSRF_TRUSTED_ORIGINS` or `ALLOWED_ORIGINS` (else 403; `Origin: null` refused; no Origin header passes). (2) `authenticationClasses` (invalid credentials 401). (3) `permissionClasses` (`hasPermission({ user, auth, method: 'GET', c }, ConsumerClass)`). (4) `static room` (`null` -> 403). (5) scope size check (431 if over 2 KB). (6) `connect()` in the room.

Browsers cannot set `Authorization` on a WebSocket: send the token as a subprotocol; Ghuri copies it into `Authorization: <TOKEN_KEYWORD> <token>` and echoes the `ghuri` subprotocol.

```ts
import { JWTAuthentication } from '@ghuri/auth/rest'
import { JsonWebSocketConsumer, type Scope } from '@ghuri/realtime'
import { IsAuthenticated } from '@ghuri/rest'

// client: new WebSocket(url, ['ghuri', `bearer.${accessToken}`])
export class NotificationsConsumer extends JsonWebSocketConsumer {
  static authenticationClasses = [JWTAuthentication]
  static permissionClasses = [IsAuthenticated]
  static room = (s: Scope) => `user.${s.user.pk}`

  async notify(event: { text: string }) {
    this.sendJson({ note: event.text })
  }
}
```

Users are checked only on the handshake: call `await this.refreshUser()` before sensitive actions or set `REVALIDATE_SECONDS`. Logout does not close open sockets.

## Errors and close codes

| Situation | Result |
|---|---|
| Handler throws | Logged; socket closes 1011 |
| Frame > `MAX_MESSAGE_BYTES` | Close 1009 |
| Invalid JSON / binary frame in `JsonWebSocketConsumer` | Close 1007 / 1003 |
| `connect()` neither accepts nor closes | Handshake 403 |
| `send()` in `connect()` before `accept()` | `ConsumerStateError` |
| `accept('x')` for a subprotocol the client did not offer | `ConsumerStateError` |
| More than `MAX_TAGS` (10) tags or tag > `MAX_TAG_LENGTH` (256) | `ConsumerStateError` |
| `refreshUser()` finds the user gone or inactive | Close 4401 |

## Testing

Use `memoryLayer()` (the default) in test settings.

```ts
import { createApp } from '@ghuri/core'
import { WebSocketCommunicator } from '@ghuri/realtime/testing'
import { expect, it } from 'vitest'
import settings from '../settings'

const app = createApp(settings)
const env = { SECRET_KEY: 'test' }
declare const ann: unknown, bob: unknown

it('broadcasts to the room', async () => {
  const a = new WebSocketCommunicator(app, '/ws/chat/lobby/', { user: ann, env })
  const b = new WebSocketCommunicator(app, '/ws/chat/lobby/', { user: bob, env })
  expect((await a.connect()).connected).toBe(true)
  await b.connect()
  await a.sendJson({ text: 'hi' })
  expect(await b.receiveJson()).toMatchObject({ text: 'hi' })
  expect(await a.receiveJson()).toMatchObject({ type: 'joined' }) // b's join, sent with exclude: b
  await a.disconnect()
  await b.disconnect()
})

it('rejects anonymous users', async () => {
  expect(await new WebSocketCommunicator(app, '/ws/chat/lobby/', { env }).connect())
    .toMatchObject({ connected: false, status: 401 })
})
```

Options: `user` (via `forceLogin`), `headers` (e.g. `origin`), `subprotocols`, `env`, `baseUrl`. Methods: `connect()` -> `{ connected, status, subprotocol?, body? }`; `sendText` / `sendJson` / `sendBytes` (resolve after the handler ran); `receiveFrom` / `receiveJson({ timeout })` (default 1000 ms; throw `CommunicatorClosed` with `code` / `reason` if the server closed); `receiveNothing({ timeout })` (default 100 ms); `receiveClose()` -> `{ code, reason }`; `disconnect(code?, reason?)`.

## Gotchas

- Do not store data on `this` between events: instances are rebuilt per event. Use `this.state` (JSON, 2 KB total with scope and tags), `this.room.storage` or the DB.
- No `group_add` / `group_discard`: one room per socket via `static room`; sub-groups are `tag()` + `{ tag }` filters.
- `accept()`, `send()`, `sendJson()`, `close()` are synchronous; `groupSend` / `broadcast` / `refreshUser` / `hasPerm` are async and must be awaited.
- Event `type` with dots maps to camelCase methods (`chat.message` -> `chatMessage`), not snake_case `chat_message`.
- `this.scope` is an object (`this.scope.params.room`), not `scope['url_route']['kwargs']`; params are strings.
- Routes live in normal `urls.ts` via `Consumer.asView()`; there is no `asgi.py` / `URLRouter` / `ProtocolTypeRouter`.
- Never use `memoryLayer()` on Cloudflare Workers; use `durableObjectLayer()` + `export const GhuriRoom = createRoomClass(app)` + wrangler binding and migration.
- Import `durableObjectLayer` / `createRoomClass` from `@ghuri/realtime/cloudflare` and `attachRealtime` from `@ghuri/realtime/node`, not the root.
- Browser token auth uses the `['ghuri', 'bearer.<token>']` subprotocol pair, not headers; set `TOKEN_KEYWORD: 'Token'` for `TokenAuthentication`.
- No GraphQL subscriptions, no SSE, no multi-process Node layer yet.
- Do not touch `env.REALTIME` (the DO namespace) from app code; go through `channelLayer` / `this.room`.
