# AI agents and MCP (@ghuri/agents)

Covers `AgentsConfig`, the `Agent` class, tools (`@tool`, `ModelTools`, `ViewSetTools`, `RouterTools`), `AgentRouter` HTTP endpoints, the MCP server, `AGENTS` settings, model strings and providers, conversation memory, queued runs and testing.

`@ghuri/agents` is built on the Vercel AI SDK (`ai`, v7) and `zod`. An `Agent` is like a viewset whose client is an LLM: tools are generated from your models/viewsets/routers and every tool call runs **as the requesting user** through your REST permission classes, querysets and serializers. Provider packages load lazily: install only `workers-ai-provider`, `@ai-sdk/anthropic` or `@ai-sdk/openai` as needed.

## Habit -> Ghuri

| You might write | Ghuri |
|---|---|
| LangChain / raw `generateText` with hand-written tools | `class X extends Agent { tools = [new ModelTools(Post)] }` |
| Tool that queries the DB with no auth check | `ModelTools(Model, { filter: (qs, user) => qs.filter({ owner: user.pk }) })`: runs through REST permissions as the user |
| `this.user` / `self.request.user` in an agent | No such thing. Tools get `(input, ctx)` with `ctx.user`; hooks/instructions get `ctx.user` |
| `model: 'gpt-4o'` | `model = 'openai:gpt-4o'` (always `'<provider>:<model-id>'`) |
| Express route calling the LLM | `agents.register('support', SupportAgent)` + `path('agents/', include(agents.urls))` |
| `@modelcontextprotocol/sdk` server | `path('mcp/', agents.mcp({ name: 'blog', tools: [...] }))` |
| MCP OAuth | Not implemented. Header auth via REST authentication classes (`TokenAuthentication`) |
| Storing chat history yourself | `AgentsConfig` in `INSTALLED_APPS` -> `Conversation` / `Message` models, automatic |

## Setup

```ts
import { AgentsConfig } from '@ghuri/agents'
import { AuthConfig, AuthTokenConfig, ContentTypesConfig, SessionsConfig } from '@ghuri/auth'
import { JWTAuthentication, SessionAuthentication, TokenAuthentication } from '@ghuri/auth/rest'
import { defineSettings } from '@ghuri/core'

export default defineSettings((env) => ({
  // ...
  INSTALLED_APPS: [ContentTypesConfig, AuthConfig, SessionsConfig, AuthTokenConfig, AgentsConfig, BlogConfig],
  AGENTS: {
    DEFAULT_MODEL: env.AGENT_MODEL ?? 'workers-ai:@cf/meta/llama-3.3-70b-instruct-fp8-fast',
    PROVIDERS: { anthropic: { apiKey: env.ANTHROPIC_API_KEY } },
    AUTHENTICATION_CLASSES: [TokenAuthentication, JWTAuthentication, SessionAuthentication],
    MAX_STEPS: 5,
  },
}))
```

`AgentsConfig` (label `agents`) ships its migration (adapted to `AUTH_USER_MODEL`): run `npx ghuri migrate`, no `makemigrations agents`. Put it after your user model's app. Workers AI needs `"ai": { "binding": "AI" }` in `wrangler.jsonc`.

### AGENTS settings (packages/agents/src/settings.ts)

| Key | Default | |
|---|---|---|
| `DEFAULT_MODEL` | none | `'provider:model-id'` or an AI SDK `LanguageModel` |
| `AI_BINDING` | `'AI'` | Workers AI binding name |
| `PROVIDERS` | `{}` | `{ anthropic: { apiKey }, openai: { apiKey, baseURL }, 'workers-ai': { gateway } }`; extra keys go to the provider factory |
| `MAX_STEPS` | `10` | Tool round trips per run |
| `AUTHENTICATION_CLASSES` | `REST_FRAMEWORK.DEFAULT_AUTHENTICATION_CLASSES` | Chat and MCP endpoints |
| `PERMISSION_CLASSES` | `[IsAuthenticated]` | For agents without `permissionClasses`, and the MCP endpoint |
| `QUEUE_BINDING` | `'AGENTS_QUEUE'` | Queue producer used by `agent.enqueue()` |

No other keys exist. Without `PROVIDERS` keys, `anthropic:` / `openai:` read `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` from env.

## Models and providers

Built-in providers: `workers-ai:` (needs the AI binding + `workers-ai-provider`), `anthropic:` (`@ai-sdk/anthropic`), `openai:` (`@ai-sdk/openai`). A bad string or missing package raises `ModelResolutionError` (HTTP 503 `ModelUnavailable` from the chat view). Add others:

```ts
import { registerProvider } from '@ghuri/agents'

registerProvider('google', async (id, { config }) => {
  const { createGoogleGenerativeAI } = await import('@ai-sdk/google')
  return createGoogleGenerativeAI({ apiKey: config.apiKey as string })(id)
})
// model = 'google:gemini-2.5-flash'; config is AGENTS.PROVIDERS.google; ctx also has env, settings
```

Also exported: `unregisterProvider`, `getProviders`, `resolveModel`, `isLanguageModel`. examples/blog registers an offline `fake` provider (src/blog/fake-model.ts, `MockLanguageModelV4` from `ai/test`) in `BlogConfig.ready()` when `DEBUG`, selected with `AGENT_MODEL=fake:blog`.

## Defining an agent (examples/blog/src/blog/agents.ts)

```ts
import { Agent, ModelTools, RouterTools, ToolError, tool } from '@ghuri/agents'
import { IsAuthenticated } from '@ghuri/rest'
import { z } from 'zod'
import { router } from '../router'
import { Post } from './models'
import { PostSerializer } from './serializers'

export function blogTools() {
  return [
    new ModelTools(Post, {
      actions: ['list', 'retrieve'],
      serializer: PostSerializer,
      searchFields: ['title', 'body'],
      orderingFields: ['createdAt'],
      filterFields: ['published'],
      pageSize: 10,
    }),
    new RouterTools(router, { include: ['tags', 'comments'], readOnly: true }),
  ]
}

export class SupportAgent extends Agent {
  static agentName = 'support'
  instructions = 'You help the editors of this blog. Use the tools to look up posts, tags and comments. Be brief.'
  tools = blogTools()
  permissionClasses = [IsAuthenticated]

  @tool({
    description: 'Count the words of a post body',
    input: z.object({ slug: z.string().describe('The post slug') }),
  })
  async wordCount({ slug }: { slug: string }) {
    const post = await Post.objects.filter({ slug }).first()
    if (!post) throw new ToolError(`No post with slug '${slug}'.`)
    return { slug, words: post.body.split(/\s+/).filter(Boolean).length }
  }
}
```

| Member | |
|---|---|
| `static agentName` | Conversation / MCP name (`ask_<name>`). Default: class name minus `Agent`, kebab-case. Set it (minifiers rename classes). `AgentRouter.register(name, ...)` overrides |
| `static description` | Description of the `ask_<name>` MCP tool |
| `static tools` | `{ name: tool({...}) }` implemented by same-named methods (no decorators) |
| `model` | `'provider:model-id'` or `LanguageModel` (default `AGENTS.DEFAULT_MODEL`) |
| `instructions` | string or `(ctx: AgentRunContext) => string \| Promise<string>` |
| `tools` | array or record of toolkits, `tool({... execute})`, `AgentTool`s |
| `permissionClasses` | REST permission classes for HTTP/MCP access |
| `maxSteps`, `temperature`, `maxOutputTokens`, `providerOptions` | AI SDK call settings |
| `memory` | `true` by default; `false` = stateless |
| `beforeRun(ctx)`, `onToolCall(call, ctx)`, `afterRun(result, ctx)` | hooks; throw `ToolError` in `onToolCall` to refuse a call |

## Tools

All generated tools invoke the viewset pipeline without HTTP: permissions, throttles, `getQueryset()`, filters, pagination, serializer validation. 4xx answers become tool errors the model reads (`"... (HTTP 403)"`).

**`new ModelTools(Model, opts)`** -> `posts_list`, `posts_retrieve`, `posts_create`, `posts_update` (partial update), `posts_delete` (prefix = plural verbose name). Options (`ModelToolsOptions`): `actions` (default `['list', 'retrieve']`), `serializer`, `filter: (qs, user) => qs`, `saveKwargs: (user, action) => values`, `searchFields`, `orderingFields`, `ordering`, `filterFields`, `pageSize` (20), `maxPageSize` (max(100, pageSize)), `permissionClasses`, `prefix`, `descriptions`.

**`new ViewSetTools(PostViewSet, opts)`** or `new ViewSetTools(router.registry[0])`: tools for routed actions including custom `@action`s. Name = `<prefix>_<snake_case(action)>`: `posts_list`, `posts_partial_update`, `posts_destroy`, `posts_publish`. Options: `actions` (`'delete'` aliases `destroy`), `prefix`, `basename`, `descriptions`.

**`new RouterTools(router, opts)`**: one `ViewSetTools` per registration. Options: `include`, `exclude` (prefixes/basenames, or tool names like `'posts_destroy'`, or predicates), `actions: { posts: ['list', 'create'] }`, `readOnly: true`.

Custom tools, three forms (`tool()` options: `description` required, `name`, `input` (Zod object or JSON Schema), `output`, `annotations`, `execute`):

```ts
import { Agent, defineTool, tool, type ToolContext } from '@ghuri/agents'
import { z } from 'zod'

class OpsAgent extends Agent {
  // 1. TC39 decorator: (parsedInput, ctx) => result
  @tool({ description: 'Refund an order', input: z.object({ orderId: z.number() }) })
  async refund({ orderId }: { orderId: number }, { user }: ToolContext) {
    return { orderId, by: user.pk }
  }
  // 2. no decorators: options here, implementation in method cancelJob()
  static tools = { cancelJob: tool({ description: 'Cancel a job', input: z.object({ id: z.string() }) }) }
  async cancelJob({ id }: { id: string }) { return { cancelled: id } }
  // 3. standalone (needs name + execute), and defineTool(name, opts, execute) -> AgentTool
  tools = [
    tool({ name: 'now', description: 'Current time', execute: () => new Date().toISOString() }),
    defineTool('ping', { description: 'Health check' }, () => 'pong'),
  ]
}
```

`ToolContext`: `user`, `agent?`, `conversationId?`, `toolCallId?`, `signal?`, `request?`. Errors: throw `ToolError(message, { status?, detail? })` for failures the model should see. Ghuri `PermissionDenied`/`Http404`/`ValidationError`/REST `APIException` are converted automatically; any other exception becomes "The tool failed with an internal error." (real message only with `DEBUG`) and is logged. Bad input -> `ToolInputError`. A run only throws for model/config errors. Duplicate tool names raise `ImproperlyConfigured`. Custom toolkits: extend `Toolkit` and implement `getTools(): AgentTool[]`.

## HTTP: AgentRouter (examples/blog/src/urls.ts)

```ts
import { AgentRouter } from '@ghuri/agents'
import { include, path } from '@ghuri/core'
import { blogTools, SupportAgent } from './blog/agents'

export const agents = new AgentRouter()           // opts: { urlNamePrefix?: 'agents' }
agents.register('support', SupportAgent)

export const urlpatterns = [
  path('agents/', include(agents.urls)),
  path('mcp/', agents.mcp({
    name: 'blog',
    version: '1.0.0',
    instructions: 'Tools for the Ghuri example blog.',
    tools: blogTools(),
    agents: true,                                 // ask_<name> per registered agent; or ['support'] / false
  })),
]
```

| Endpoint | |
|---|---|
| `POST agents/<name>/chat` (and `/chat/`) | `{ message, conversationId? }` or an AI SDK `useChat` body. JSON `{ conversationId, text, toolCalls, usage, finishReason }`; SSE UI message stream with `Accept: text/event-stream` or `?stream=1` (header `x-conversation-id`) |
| `GET agents/<name>/conversations/` | `{ count, results }`, `?limit=&offset=` |
| `GET` / `DELETE agents/<name>/conversations/<uuid:id>/` | owner only |

URL names: `agents-<name>-chat`, `agents-<name>-conversations`, `agents-<name>-conversation`. Auth: `AGENTS.AUTHENTICATION_CLASSES`; access: the agent's `permissionClasses`. Session auth needs CSRF on POST. Other members: `agents.create(name)`, `agents.names`, `agents.consumeQueue(queue = '*')`, `agents.mcpServer(opts)`. Views exported: `AgentChatView`, `ConversationListView`, `ConversationDetailView`.

## MCP server

`agents.mcp(opts)` returns URL patterns (mount at a path with trailing slash). Without a router: `const mcp = new McpServer({ name: 'shop', tools, agents: { editor: () => new EditorAgent() } })` then `path('mcp/', mcp.urls)` (`McpView` is the view behind `mcp.asView()`).

`McpServerOptions`: `name` ('ghuri'), `version` ('0.1.0'), `title`, `instructions`, `tools`, `agents` (factory map on `McpServer`; `true`/names/`false` on `agents.mcp()`), `authenticationClasses`, `permissionClasses`, `allowAnyOrigin` (false).

- Streamable HTTP, JSON-RPC 2.0 over POST with JSON responses; GET/DELETE answer 405. Methods: `initialize`, `ping`, `notifications/*`, `tools/list`, `tools/call`, empty `resources/list` / `prompts/list`; batches OK. Protocol versions: `MCP_PROTOCOL_VERSIONS` (`2025-11-25` newest).
- An agent's own `tools` are not exposed individually: MCP sees `ask_<name>` (`{ message, conversationId? }` -> `{ text, conversationId }`). Pass toolkits in `tools` for direct access.
- **No OAuth.** Clients send `Authorization: Token <key>` (create with `npx ghuri drf_create_token alice`); 401 + JSON-RPC error `-32001` otherwise. Foreign `Origin` headers get 403 unless in `CSRF_TRUSTED_ORIGINS`.

```ts
import { TokenAuthentication } from '@ghuri/auth/rest'

class BearerTokenAuthentication extends TokenAuthentication {
  keyword = 'Bearer'   // for clients that only send "Bearer <token>"
}
```

## Running from code, streaming, memory, queues

```ts
import { SupportAgent } from './blog/agents'

const r = await new SupportAgent().run('Which posts are drafts?', { user })
r.text; r.toolCalls; r.messages; r.usage; r.finishReason; r.steps; r.conversationId
await SupportAgent.run('And now?', { user, conversationId: r.conversationId })   // static shortcut
const s = await new SupportAgent().stream('Hi', { user })
// s.toUIMessageStreamResponse(), s.textStream, s.toUIMessageStream(), await s.done
```

`RunOptions`: `user` (default anonymous), `conversationId`, `signal`, `memory`, `checkPermissions` (HTTP/MCP always check), `request`, `context` (-> `ctx.extra`), `title`.

Memory: with `AgentsConfig` installed each run creates/extends a `Conversation` (UUID pk, `user`, `agent`, `title`, `metadata`) with `Message` rows (`role`, JSON `content`). Another user's id -> `ConversationNotFound` (404). Helpers: `createConversation`, `getConversation`, `loadMessages`, `saveMessages`, `memoryAvailable`. Not registered in the admin automatically.

Queues (Cloudflare): `wrangler.jsonc` `"queues": { "producers": [{ "binding": "AGENTS_QUEUE", "queue": "agents" }], "consumers": [{ "queue": "agents" }] }`, then `agents.consumeQueue('agents')` once (e.g. in an `AppConfig.ready()`), and `const { conversationId } = await agents.create('support').enqueue('Summarize my week', { user })`. Lower level: `enqueueRun(agent, input, opts)`, `consumeAgentQueue(queue, create)` (built on `onQueue` from `@ghuri/core`).

## Testing (examples/blog/src/blog/tests.ts)

```ts
import { SupportAgent } from './agents'
import { registerFakeProvider } from './fake-model'

registerFakeProvider()
class OfflineAgent extends SupportAgent {
  model = 'fake:blog'
}
const result = await new OfflineAgent().run('Which posts are there?', { user: alice })
expect(result.toolCalls.map((c) => c.toolName)).toEqual(['posts_list'])

// MCP over the REST test client
const rpc = (method: string, id: number) => ({ jsonrpc: '2.0', id, method, params: {} })
expect((await api.post('/mcp/', rpc('tools/list', 1))).status).toBe(401)
api.credentials({ Authorization: `Token ${token}` })
const names = (await api.post('/mcp/', rpc('tools/list', 2))).data.result.tools.map((t: any) => t.name)
```

Or set `model` to a `MockLanguageModelV4` instance from `ai/test` directly.

## Gotchas

- Model strings must be `'<provider>:<model-id>'`; `'gpt-4o'` alone throws `ModelResolutionError`.
- `workers-ai:` needs the `ai` binding in `wrangler.jsonc` and a Cloudflare login even locally; use a fake/mock model for tests.
- There is no `this.user` / `this.request`. Read `ctx.user` in tools (second argument) and hooks.
- Tools must not bypass auth: prefer `ModelTools`/`ViewSetTools` over raw ORM tools, and scope with `filter`. Raw `@tool` methods run with no automatic permission check beyond the agent's `permissionClasses`; filter by `ctx.user` yourself.
- `ModelTools` defaults to read-only (`['list', 'retrieve']`); its `update` is a partial update and `delete` maps to `destroy`.
- `ViewSetTools` names use snake_case actions (`posts_partial_update`, `posts_destroy`), unlike `ModelTools` (`posts_update`, `posts_delete`).
- Throw `ToolError` (not `Error`) for messages the model should see; generic errors are hidden outside `DEBUG`.
- `@tool` options use `input` (not `parameters`/`schema`/`inputSchema`); `description` is required.
- `@tool` is a TC39 standard decorator; do not enable `experimentalDecorators` just for it.
- Agents' own tools are not listed by MCP; only `ask_<name>` and the `tools` option are.
- MCP has no OAuth and no session cookies from clients: configure `TokenAuthentication` (or `JWTAuthentication`) in `AGENTS.AUTHENTICATION_CLASSES`.
- Mount MCP with a trailing slash and give clients that exact URL (`APPEND_SLASH` only redirects GET).
- Forgetting `AgentsConfig` disables memory silently; passing `conversationId` then raises `ImproperlyConfigured`.
- Install `ai` and `zod` (and the provider package) alongside `@ghuri/agents`.
