# Vectors and RAG (@ghuri/vectors)

Covers retrieval in Ghuri: the `VECTORS` setting and its stores (`vectorize()`, `pgvector()`, `databaseStore()`, `memoryStore()`), embedding model ids, `VectorIndex` (index, chunk, search, metadata filters), `ModelIndex` (model rows kept in sync on save/delete), tenant scoping, background indexing through `@ghuri/tasks`, the agent search tool (`@ghuri/vectors/agents`), commands, checks and test helpers.

Install: `npm install @ghuri/vectors@next` (0.1.0-alpha.0; needs `@ghuri/core` and `@ghuri/orm` 0.1.0-alpha.5+, `@ghuri/agents` optional). Add `VectorsConfig` to `INSTALLED_APPS` and run `npx ghuri migrate`: it adds the manifest `vectors_vectordocument` (skips unchanged documents; Vectorize needs it to delete) and `vectors_vectorembedding` (used by `databaseStore()` only). No `ai` / LangChain dependency.

Entry points (from `packages/vectors/package.json`):

| Import | Exports you use |
|---|---|
| `@ghuri/vectors` | `VectorsConfig`, `vectorize`, `pgvector`, `databaseStore`, `memoryStore`, `VectorIndex`, `ModelIndex`, `getVectorIndex`, `vectorIndexes`, `vectorStores`, `embed`, `embedMany`, `chunkText`, `registerEmbeddingProvider`, `resolveEmbedding`, `openAICompatibleEmbedder`, `knownDimensions`, `BaseVectorStore`, `VectorsError`, `InvalidVectorStore`, `EmbeddingError`, `DimensionMismatch`, `FilterError`, `TenantRequired`, `VECTOR_TASK_NAME`, `runVectorJob`, types `Document`, `SearchHit`, `SearchOptions`, `IndexResult`, `ModelSearchHit`, `Filter`, `Embedder`, `VectorStore` |
| `@ghuri/vectors/agents` | `searchTool`, `formatHits`, `retrieve`, types `SearchToolOptions`, `SearchToolHit` |
| `@ghuri/vectors/testing` | `fakeEmbedding`, `fakeVectorize`, `useVectorStore`, `memoryStore`, `MemoryVectorStore` |

## Habit -> Ghuri

| LangChain / pgvector / Pinecone / Django habit | Ghuri |
|---|---|
| `new OpenAIEmbeddings()` / `embeddings.embedQuery(q)` | model id on the store: `embedding: 'openai:text-embedding-3-small'`; `index.search(q)` embeds for you (`embed(text)` / `embedMany(texts)` if you need raw vectors) |
| `PineconeStore.fromDocuments(docs, emb)` / `vectorStore.addDocuments()` | `await index.index([{ key, text, metadata }])` (chunks, embeds, upserts; unchanged docs skipped) |
| `RecursiveCharacterTextSplitter({ chunkSize, chunkOverlap })` | `chunk: { size, overlap, separators }` on the index (characters), or `chunkText(text, opts)` |
| `similaritySearch(q, k, filter)` / `asRetriever()` | `await index.search(q, { k, filter, exclude, minScore })` / `retrieve(index, q)` |
| Pinecone / Chroma filter `{ year: { $gte: 2025 } }` | Django lookups: `filter: { year__gte: 2025, lang__in: ['en'] }`, `exclude: { status: 'draft' }` |
| Pinecone `namespace` per customer | automatic: the current tenant goes into the namespace; `namespace` option for extra partitions |
| `env.VECTORIZE.query(...)` / `env.AI.run(...)` in app code | never: `vectorize('VECTORIZE', { embedding: 'workers-ai:...' })` in settings, then the index API |
| pgvector-python `VectorField` + `CosineDistance` + `HnswIndex` | no vector field yet: `pgvector({ index: 'hnsw', m, efConstruction })` store + `ModelIndex` |
| django-haystack `SearchIndex` / `index_queryset` / `RealtimeSignalProcessor` / `update_index` | `ModelIndex(Model, { text, metadata, indexQueryset })`, `autoIndex` (on by default), `npx ghuri update_index` |
| LangChain retriever tool | `searchTool(index, { description, k, filter })` |

## Settings

```ts
// src/settings.ts
import { defineSettings } from '@ghuri/core'
import { pgvector, VectorsConfig, vectorize } from '@ghuri/vectors'

export default defineSettings((env) => ({
  INSTALLED_APPS: [/* ... */, VectorsConfig, SupportConfig],
  VECTORS: {
    default: env.VECTORIZE
      ? vectorize('VECTORIZE', { embedding: 'workers-ai:@cf/baai/bge-base-en-v1.5' })   // Workers
      : pgvector({ database: 'default', embedding: 'openai:text-embedding-3-small' }),  // Node + Postgres
  },
  AGENTS: { PROVIDERS: { openai: { apiKey: env.OPENAI_API_KEY } } },   // keys shared with @ghuri/agents
}))
```

`VECTORS` maps aliases to factories, like `CACHES`. Missing `VECTORS` (or alias) raises `ImproperlyConfigured` on first use: there is no silent default.

| Factory | Runs on | Search | Use for |
|---|---|---|---|
| `vectorize(binding, opts)` | Workers, Vectorize binding | ANN; tenants = native namespaces | Workers production |
| `pgvector({ database, table, index, m, efConstruction, lists, ...opts })` | Postgres + `vector` extension (postgres.js, Hyperdrive, PGlite) | `index: 'hnsw'` (default), `'ivfflat'`, `null` = exact | Node production |
| `databaseStore({ database, ...opts })` | any `DATABASES` alias: D1, SQLite, Postgres | exact, in JS, reads every row of a namespace | small apps, tests |
| `memoryStore(opts)` | the process | exact | tests, scripts |

Options every factory takes: `embedding` (model id, AI SDK embedding model or `Embedder`; without it the store raises `InvalidVectorStore`), `dimensions` (known for the built-in ids, else measured from the first vector; `pgvector()` needs it for unknown models), `metric` (`'cosine'` default, `'euclidean'`, `'dot-product'`), `providerOptions` (API key, `baseURL`, `headers`). `pgvector` table default: `vectors_pgembedding` (`vectors_pgembedding_<alias>` for other aliases).

| Embedding id | Credentials | Dimensions |
|---|---|---|
| `workers-ai:@cf/baai/bge-base-en-v1.5` (`bge-small-en-v1.5`, `bge-large-en-v1.5`, `bge-m3`, `@cf/google/embeddinggemma-300m`, `@cf/qwen/qwen3-embedding-0.6b`) | AI binding `env[AGENTS.AI_BINDING ?? 'AI']` | 768 (384, 1024, 1024, 768, 1024) |
| `openai:text-embedding-3-small` / `-3-large` / `text-embedding-ada-002` | `apiKey` / `baseURL` (compatible APIs), else `OPENAI_API_KEY` / `OPENAI_BASE_URL` | 1536 / 3072 / 1536 |
| `ghuri-ai:openai/text-embedding-3-small` | `baseURL` / `apiKey`, else `GHURI_AI_URL` / `GHURI_AI_API_KEY`; sends `x-ghuri-tenant` | as the model |
| an AI SDK model (`google.textEmbeddingModel('text-embedding-004')`) | the provider package's own | `dimensions` if unknown |

Provider options come from the store's `providerOptions`, which REPLACE `AGENTS.PROVIDERS[provider]` (no merge); any key missing from both falls back to the env var (Worker `env`, then `process.env`). `registerEmbeddingProvider('name', (modelId, ctx) => embedder)` adds a `name:` prefix; `openAICompatibleEmbedder({ modelId, model, baseURL, apiKey })` builds one for any `/embeddings` API.

## Indexing

Define indexes at module top level in a module the app loads, so commands and task workers find them by name:

```ts
// src/support/vectors.ts
import { VectorIndex } from '@ghuri/vectors'
export const handbook = new VectorIndex('support.handbook', { chunk: { size: 800, overlap: 150 } })

// src/support/app.ts
import * as vectors from './vectors'
export class SupportConfig extends AppConfig { name = 'support'; override modules = { vectors } }
```

```ts
const r = await handbook.index([
  { key: 'refunds', text: refundPolicy, metadata: { section: 'billing', year: 2026 } },
  { key: 'shipping', text: shippingPolicy, metadata: { section: 'delivery' } },
])   // { indexed: 2, skipped: 0, deleted: 0, chunks: 5 }
await handbook.index({ key: 'refunds', text: refundPolicy }, { force: true })   // embed even if unchanged
await handbook.delete('shipping')            // or an array of keys
await handbook.keys()                        // indexed keys (needs the vectors app)
await handbook.clear()                       // every document of this index (this tenant / namespace)
```

- `VectorIndex(name, { store = 'default', chunk, tenant = 'auto', storeText = true, prefixes: { query, document } })`. Names: 1-48 chars of `[A-Za-z0-9_.:-]`; re-creating a name replaces the old index.
- `index(docs, { namespace, force, background })`. Document keys: string or number, 1-255 chars. Text with no chunks (blank) deletes the document.
- Everything is embedded before anything is written: a failed model call (`EmbeddingError`) leaves the index as it was. A shorter new version deletes its stale chunks.
- Metadata values: string, number or boolean (`null` / `undefined` are dropped). Keys `[A-Za-z0-9_-]{1,64}`; `_key`, `_chunk`, `_text` and every `_*` key are reserved.

## Chunking

Default: recursive character splitter, `{ size: 1000, overlap: 200 }` characters (not tokens), splitting on `DEFAULT_SEPARATORS` (`'\n\n'`, `'\n'`, `'. '`, `' '`, then characters). `chunk: false` = one chunk per document; `chunk: (text) => string[]` = your own splitter (e.g. by Markdown heading). `chunkText(text, { size, overlap, separators })` is the same splitter for direct use.

## Searching and filters

```ts
const hits = await handbook.search('how long do refunds take?', {
  k: 5,                                                     // default 4
  filter: { section: 'billing', year__gte: 2025, lang__in: ['en', 'bn'] },
  exclude: { status: 'draft' },
  minScore: 0.5,                                            // cosine / dot-product only
})
// [{ id, key: 'refunds', chunk: 0, score: 0.83, text: 'Refunds are paid...', metadata: { section: 'billing', year: 2026 } }]
```

- Lookups: `field` / `field__exact`, `__in` (non-empty list), `__gt`, `__gte`, `__lt`, `__lte`; all AND. `exclude` takes exact and `__in` only. Anything else (`__icontains`, `__range`, `__isnull`, `Q`) raises `FilterError`.
- Hits are chunks, best first; one document can appear several times (no per-document distinct yet). `score` = cosine similarity, euclidean distance (lower is closer) or dot product, as the store reports it.
- `search(vector)` accepts a `number[]`; `includeValues: true` returns stored vectors; `namespace` searches a partition.

## Tenant scoping

With `@ghuri/tenants` loaded, every index is scoped by default (`tenant: 'auto'`): the current tenant from the request (`TenantMiddleware`) or `runAsTenant()` goes into the store namespace (`support.handbook|t=42`). You never pass a tenant argument.

```ts
import { runAsTenant } from '@ghuri/tenants'
await runAsTenant(store, () => handbook.index({ key: 'faq', text }))   // queue/cron/scripts
export const legal = new VectorIndex('platform.legal', { tenant: false })   // shared by every tenant
```

No tenant -> `index`, `search`, `delete`, `clear`, `keys` and `update` throw `TenantRequired`, also inside `withoutTenant()`. There is no cross-tenant search: platform code loops over tenants. Vectorize isolates by native namespace; the other stores add `namespace = ...` to every query. `ModelIndex.search()` loads rows through `objects`, so tenant managers apply too.

## Model indexes (kept in sync by signals)

```ts
// src/blog/vectors.ts
import { ModelIndex } from '@ghuri/vectors'
import { Post } from './models'

export const posts = new ModelIndex(Post, {
  // name: default '<app label>.<model>' = 'blog.post'
  text: (p) => `${p.title}\n\n${p.body}`,                   // or field names: ['title', 'body']
  metadata: (p) => ({ status: p.status, authorId: p.authorId, year: p.createdAt.getFullYear() }),
  indexQueryset: (qs) => qs.filter({ status: 'published' }),
})

const hits = await posts.search('cancel my subscription', { k: 5 })
hits[0].object   // the Post (one pk__in query; rows deleted meanwhile are dropped)
```

- `autoIndex` (default true) connects `postSave` / `postDelete`, runs after commit (`onCommit`), skips `raw` saves (`loaddata`). A row leaving `indexQueryset` is removed on its next save; a re-save with unchanged text/metadata costs no embedding call.
- `bulkCreate()`, `QuerySet.update()` and raw SQL send no `postSave`: run `npx ghuri update_index` (or `await posts.update()`) afterwards.
- Also: `posts.index(objs)`, `posts.delete(objsOrPks)`, `posts.indexPks(pks)`, `posts.document(obj)`, `posts.disconnectSignals()`.

## Background ingestion with @ghuri/tasks

When `@ghuri/tasks` is installed and imported (`TasksConfig` in settings), work can run as the `vectors.index` task (`VECTOR_TASK_NAME`, 3 attempts, tenant carried). Vectors does not import tasks; it uses tasks' interop object.

```ts
const r = await handbook.index(docs, { background: true })   // enqueued: { indexed: 0, ..., taskResultId }
await handbook.delete('old', { background: true })
new ModelIndex(Post, { text: ['title', 'body'], background: 'auto' })   // default: model saves enqueue pks
```

`VectorIndex.index()` / `delete()` default to `background: false`; `true` without tasks raises `ImproperlyConfigured`; `'auto'` runs inline without tasks. Model jobs carry primary keys (rows reloaded in the worker); document jobs carry the full text, so keep them under the 128 KB Queues message limit. For big inputs write your own task that loads the text by id:

```ts
// src/support/tasks.ts  (exported from the app's tasks module -> 'support.ingestArticle')
import { task } from '@ghuri/tasks'
import { Article } from './models'
import { handbook } from './vectors'

export const ingestArticle = task(async (articleId: number) => {
  const a = await Article.objects.get({ pk: articleId })
  return (await handbook.index({ key: `article-${a.pk}`, text: a.body, metadata: { section: a.section } })).chunks
}, { maxAttempts: 3 })

// in a view: await onCommit(() => ingestArticle.enqueue(article.pk))   // onCommit from @ghuri/orm
```

## Agent search tool

```ts
// src/support/agents.ts
import { Agent } from '@ghuri/agents'
import { retrieve, searchTool } from '@ghuri/vectors/agents'
import { handbook } from './vectors'

export class SupportAgent extends Agent {
  model = 'workers-ai:@cf/meta/llama-3.3-70b-instruct-fp8-fast'
  instructions = 'Answer from the handbook. Search it before answering and cite the keys.'
  tools = [
    searchTool(handbook, {
      description: 'Search the support handbook.',
      k: 5,                                                      // maxK 10, maxChars 2000 per hit
      filter: (ctx) => (ctx.user.isAuthenticated ? undefined : { audience: 'public' }),
    }),
  ]
}

const context = await retrieve(handbook, question, { k: 4 })   // '[1] (refunds) Refunds are paid...' block
```

The tool is named `search_<index>` (sanitized: `search_support_handbook`), takes `{ query, k? }`, returns `{ results: [{ key, score, text, metadata }] }`, and is `readOnlyHint` for MCP. Options: `name`, `description`, `k`, `maxK`, `filter` (object or `(ctx) => Filter`), `exclude`, `minScore`, `maxChars`. It searches as the current tenant. `formatHits(hits)` formats hits you already have.

## wrangler.jsonc for Vectorize

Create the index with the embedding model's dimensions and the store's metric, plus a metadata index for every key you filter on:

```sh
npx wrangler vectorize create mysite-default --dimensions=768 --metric=cosine
npx wrangler vectorize create-metadata-index mysite-default --property-name=section --type=string
```

```jsonc
"vectorize": [{ "binding": "VECTORIZE", "index_name": "mysite-default" }],
"ai": { "binding": "AI" }          // for workers-ai: embeddings (AGENTS.AI_BINDING to rename)
```

## Commands and checks

| Command | Does |
|---|---|
| `npx ghuri update_index [index...] [--tenant pk] [--namespace n] [--batch-size 100] [--force]` | index every row of each `ModelIndex` (unchanged skipped, gone rows removed); plain `VectorIndex`es are skipped |
| `npx ghuri clear_index [index...] [--tenant pk] [--namespace n]` | delete the vectors and manifest rows |
| `npx ghuri rebuild_index [index...] [--tenant pk] [--namespace n] [--batch-size n]` | clear, then update with force |
| `npx ghuri createvectortable [--store alias]` | `CREATE EXTENSION IF NOT EXISTS vector`, table and ANN index of each `pgvector()` store |

`npx ghuri check`: `vectors.E001` entry is not a store, `E002` index names an unconfigured alias, `E003` Vectorize or `databaseStore()` without `VectorsConfig`, `E004` no embedding, `E005` Vectorize binding missing from wrangler.jsonc, `E006` pgvector without known dimensions, `W001` / `W002` memory / database store with `DEBUG` off, `W003` `workers-ai:` model without an `ai` binding.

## Testing

```ts
import { fakeEmbedding, fakeVectorize, memoryStore, useVectorStore } from '@ghuri/vectors/testing'
import { handbook } from '../src/support/vectors'

const embedding = fakeEmbedding({ dimensions: 64 })   // deterministic bag-of-words; no network
let restore: () => void
beforeEach(() => { embedding.reset(); ({ restore } = useVectorStore(memoryStore({ embedding }))) })
afterEach(() => restore())

it('finds the refund policy', async () => {
  await handbook.index({ key: 'refunds', text: 'Refunds are paid within five days.' })
  await handbook.index({ key: 'refunds', text: 'Refunds are paid within five days.' })
  expect(embedding.calls).toBe(1)                     // unchanged: not embedded again (with VectorsConfig)
  expect((await handbook.search('when are refunds paid'))[0].key).toBe('refunds')   // search embeds too
})
```

- `useVectorStore(config, alias = 'default')` overrides a `VECTORS` alias until `restore()`; returns `{ store, restore }`.
- `fakeVectorize({ dimensions, metric })`: in-memory Vectorize binding for `vectorize()` stores; put it in the test env as `VECTORIZE`. It enforces 64-byte ids/namespaces, 10 KiB metadata and topK limits, and records `queries`.
- With `@ghuri/tasks` loaded, model saves enqueue `vectors.index`: use `useTaskBackend(dummy())` + `await backend.runPending()` from `@ghuri/tasks/testing`, or `background: false` on the index.
- Tenant tests: wrap calls in `runAsTenant(tenant, ...)`; assert `TenantRequired` outside.

## Gotchas

- No LangChain-style `VectorStore.fromDocuments`, `similaritySearch`, `asRetriever`, `Document.pageContent`: the API is `index()` / `search()` with `{ key, text, metadata }`. No `upsert` / `query` on the index (those are the low-level `VectorStore` API from `vectorStores.get()`).
- Never call `env.VECTORIZE`, `env.AI` or an embeddings HTTP API from app code; configure a store and use indexes (portability matrix).
- Vectorize has no native delete by document: indexing, deleting and clearing on a `vectorize()` store need `VectorsConfig` (else `ImproperlyConfigured`). Do not drop the manifest table or vectors become undeletable.
- Vectorize is NOT tested end to end (Miniflare has no Vectorize; tests use `fakeVectorize()`; `wrangler dev` hits the remote index). It is eventually consistent: a vector is searchable seconds after `index()` returns. `k` above 50 fails (queries return all metadata). Filters need a metadata index per key, created before you index.
- pgvector is tested only on PGlite + `@electric-sql/pglite-pgvector`, not on a Postgres server (postgres.js / Hyperdrive). Its table is NOT a migration: run `createvectortable` per environment.
- Dimensions are fixed by the Vectorize index and the pgvector `vector(n)` column. Switching embedding models re-embeds everything on the next `index()` / `update_index` (the digest includes the model) but needs a new Vectorize index / pgvector table; mismatches raise `DimensionMismatch`.
- `databaseStore()` reads every vector of a namespace per search: a few thousand chunks max. `memoryStore()` loses everything on restart and is per isolate on Workers.
- Metadata is flat scalars only: no arrays, objects, `Date` or `null` filtering; store dates as numbers (`year`, epoch ms). Booleans compare for equality only. With `storeText` (default) chunk text lives in metadata, and Vectorize caps metadata at 10 KiB per vector: keep chunks well under ~8,000 characters or set `storeText: false` (then `hit.text` is `null`).
- `minScore` with a `'euclidean'` store raises `FilterError` (lower is better there).
- With `@ghuri/tenants`, a shared index (docs, legal text) MUST be `tenant: false`, or platform code gets `TenantRequired`. `withoutTenant()` does not unlock scoped indexes.
- `ModelIndex` needs the model's app label when created (`Meta.appLabel`, or pass `name`). An index defined in a module nothing imports is unknown to workers and commands ("No vector index named ...").
- `embed()` / `embedMany()` default to `kind: 'document'` and skip index `prefixes`; for queries prefer `index.search(text)`.
- Not yet: `VectorField` / `CosineDistance` ORM lookups, hybrid (full-text) search, rerankers, per-document distinct, cross-tenant search, token-based chunking, `examples/blog` or CLI templates using vectors.
