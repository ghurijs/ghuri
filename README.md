<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img alt="Ghuri" src="assets/logo-light.svg" width="320">
  </picture>
</p>

<h3 align="center">Django for TypeScript. Cloudflare first, portable everywhere.</h3>

<p align="center">
  <a href="https://ghurijs.github.io/docs/">Documentation</a> ·
  <a href="https://ghurijs.github.io/docs/tutorial/part-1-models/">Tutorial</a> ·
  <a href="https://github.com/ghurijs/examples">Examples</a>
</p>

Ghuri gives you Django's structure — settings, installed apps, models with managers, migrations,
`urls.ts`, class-based views, an admin, a REST framework, GraphQL — written in TypeScript and built on
**Hono + Drizzle**, running by default on **Cloudflare Workers with D1 and R2**.

Start a startup on Cloudflare for almost nothing. When you outgrow it, switch `DATABASES` to
Postgres, run `ghuri migrate` and `ghuri dumpdata | ghuri loaddata`, and deploy the same code to
Node on any VPS. No rewrite.

```ts
// src/blog/models.ts
export class Post extends Model({
  title: new CharField({ maxLength: 200 }),
  body: new TextField({ blank: true }),
  author: new ForeignKey(() => User, { onDelete: CASCADE, relatedName: 'posts' }),
  createdAt: new DateTimeField({ autoNowAdd: true }),
}) {
  static Meta = { ordering: ['-createdAt'] }
}

const recent = await Post.objects.filter({ author__username: 'rifat' }).orderBy('-createdAt').slice(0, 10)
```

## Packages

| Package | What it is |
|---|---|
| [`@ghuri/core`](https://github.com/ghurijs/core) | settings, apps, URLs, views, middleware, signals, cache, commands |
| [`@ghuri/orm`](https://github.com/ghurijs/orm) | models, QuerySets, relations, migrations — D1, Postgres, SQLite |
| [`@ghuri/auth`](https://github.com/ghurijs/auth) | users, groups, permissions, sessions, tokens, JWT |
| [`@ghuri/rest`](https://github.com/ghurijs/rest) | serializers, viewsets, routers, permissions, pagination, OpenAPI |
| [`@ghuri/graphql`](https://github.com/ghurijs/graphql) | GraphQL in graphene-django style: model types, Relay connections and filters, serializer mutations, GraphiQL |
| [`@ghuri/storage`](https://github.com/ghurijs/storage) | R2 / S3 / filesystem storage, `FileField` |
| [`@ghuri/admin`](https://github.com/ghurijs/admin) | the Django admin, server-rendered on Workers |
| [`@ghuri/agents`](https://github.com/ghurijs/agents) | AI agents with tools generated from your models and viewsets, MCP server |
| [`@ghuri/cli`](https://github.com/ghurijs/cli) | `ghuri startproject`, `startapp`, `migrate`, `createsuperuser`, … |
| [`create-ghuri`](https://github.com/ghurijs/create-ghuri) | `npm create ghuri@latest` |

## Get started

```bash
npm create ghuri@latest mysite
cd mysite
npx ghuri startapp blog
npx ghuri makemigrations && npx ghuri migrate
npx ghuri createsuperuser
npm run dev
```

## This repository

This is the meta repo: the [architecture spec](./ARCHITECTURE.md) every package is built
against, and the local development workspace.

```bash
git clone https://github.com/ghurijs/ghuri && cd ghuri
npm run bootstrap   # clones every package repo into packages/ and installs
```

Status: **alpha**. License: MIT.
