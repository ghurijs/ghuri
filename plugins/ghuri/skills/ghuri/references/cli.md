# CLI (`ghuri`)

Every `ghuri` command (Django's `manage.py`), how the CLI finds and loads a project, and the `ghuri mcp` dev server for coding agents.

## Basics

```sh
npm create ghuri@latest mysite                  # django-admin startproject (asks db / package manager / git)
npm create ghuri@latest mysite -- --db postgres # --db d1 (default) | postgres | sqlite
npx ghuri <command> [args] [options]            # python manage.py <command>
npx ghuri help                                  # all commands, grouped [ghuri] / [orm] / per app
npx ghuri help <command>                        # or: npx ghuri <command> --help
```

- The binary comes from `@ghuri/cli`, a dev dependency of every project; `npx ghuri` runs the project's own copy. Packages are published under the `next` dist-tag (`npm install @ghuri/core@next`).
- Options use dashes: `--no-input`, `--dry-run` (`--noinput` is accepted as an alias).
- Exit codes: `0` ok, `1` `CommandError` / failed check, `2` usage error.

## How the CLI loads a project

1. Walks up from the cwd to a `package.json` with a `"ghuri"` key or a `src/settings.ts` (override: `--settings <path>`).
2. Loads TypeScript with jiti (no build step).
3. Builds `env` from wrangler bindings (local Miniflare state in `.wrangler/state`, shared with `wrangler dev`; remote with `--remote`), `process.env`, `.dev.vars`, `.env*`, and wrangler `vars`.
4. Runs `createApp(settings).setup(env)`, then the command.

Global options: `--settings <path>`, `--env <name>` (wrangler environment), `--remote` (remote D1/R2/KV; needs `wrangler login` and a real `database_id`), `--persist-to <dir>`, `--traceback`, `--no-color`, `-h/--help`.

## Built-in commands (`@ghuri/cli`)

| Command | Use |
|---|---|
| `startproject <name> [dir] [--db d1\|postgres\|sqlite] [--pm npm\|pnpm\|bun\|yarn] [--graphql] [--no-install]` | new project |
| `startapp <name> [dir] [--no-register]` | creates `src/<name>/` (app.ts, models.ts, views.ts, urls.ts, serializers.ts, schema.ts, admin.ts, tests.ts, migrations/index.ts) and adds `<Name>Config` to INSTALLED_APPS; prints the `path(...)` line to add to `src/urls.ts` (you add it) |
| `runserver [addrport] [-p port] [--host h] [--node] [--remote]` | `wrangler dev` on 8787; `--node` (or no wrangler config) serves on 8000. `npm run dev` |
| `shell [-c "<code>"]` | REPL with apps, settings, env and every model by class name; top-level `await` |
| `check [--deploy] [-t tag] [--fail-level L] [--list-tags]` | system checks |
| `test [--watch] [vitest args]` | `vitest run` |
| `deploy [--migrate] [--skip-migrations] [--dry-run] [--no-input]` | optional `migrate --remote`, then `wrangler deploy` |
| `routes [--format table\|json]` (alias `show_urls`) | URL patterns with names, methods, views |
| `diffsettings [--all] [--show-secrets]` | settings that differ from defaults |
| `version [--short]`, `help [command]` | |
| `mcp [--docs-url <url>]` | MCP server over stdio for coding agents (see below) |

## Database commands (`@ghuri/orm`)

All take `--database <alias>` (default `default`) and the global `--remote`.

| Command | Use |
|---|---|
| `makemigrations [app...] [-n name] [--empty] [--dry-run] [--check] [--merge] [--no-input]` | write migrations (see migrations.md) |
| `migrate [app] [name\|zero] [--fake] [--fake-initial] [--plan] [--run-syncdb] [--no-input]` | apply / roll back |
| `showmigrations [app...] [-p]` | status |
| `sqlmigrate <app> <name> [--backwards] [--dialect sqlite\|postgresql]`; `sqlmigrate --all --out <dir>` | SQL |
| `dumpdata [app[.Model]...] [-e label] [--indent n] [-o file]` | Django-format JSON fixtures |
| `loaddata <fixture...> [-e label]` | upsert fixtures (files, `<app>/fixtures/` names, or `-`) |
| `copydata --from <alias> --to <alias> [app...] [--flush] [--no-input]` | copy all rows between aliases (migrate the target first) |
| `flush [--no-input]` | delete all rows, keep schema |

`squashmigrations` and `inspectdb` do not exist.

## App commands

| Command | From |
|---|---|
| `createsuperuser [--username u] [--email e] [--password p] [--no-input]` | `AuthConfig`; non-interactive: `GHURI_SUPERUSER_PASSWORD=... npx ghuri createsuperuser --no-input --username admin --email a@example.com` |
| `changepassword [username] [--password p]` | `AuthConfig` |
| `clearsessions` | `SessionsConfig` |
| `drf_create_token <username> [-r]` | `AuthTokenConfig` |
| `flushexpiredtokens` | `TokenBlacklistConfig` |
| `generateschema [--file f] [--format openapi\|openapi-json] [--title t] [--description d] [--api-version v] [--url u] [--indent n]` | `RestFrameworkConfig` (`@ghuri/rest`); YAML by default, JSON with `--format openapi-json` or a `.json` file; matches what `/api/schema/` serves |
| `graphql_schema [-o file] [--json] [--sort] [--indent n]` | `GraphQLConfig` |

Custom commands: a `BaseCommand` subclass listed in the app's `AppConfig.commands`; see signals-cache-tasks-commands.md. Run from code with `await callCommand('migrate')` (`@ghuri/core`).

## Typical sequences

```sh
# new project, local
npm create ghuri@latest mysite && cd mysite
npx ghuri migrate && npx ghuri createsuperuser && npm run dev

# new app
npx ghuri startapp blog            # then add path('blog/', include(blogUrls)) to src/urls.ts
# edit src/blog/models.ts
npx ghuri makemigrations blog && npx ghuri migrate

# quick data check
npx ghuri shell -c "await Post.objects.count()"

# CI
npx ghuri makemigrations --check && npx ghuri check --deploy && npx ghuri test

# production (Cloudflare)
npx ghuri deploy --migrate
```

Agents running commands non-interactively should pass `--no-input` where supported (`makemigrations`, `migrate`, `flush`, `copydata`, `createsuperuser`, `deploy`), because prompts block without a TTY.

## `ghuri mcp`: the dev MCP server

`npx ghuri mcp` (run in the project directory) starts a Model Context Protocol server over stdio that lets a coding agent inspect the real project instead of guessing. Tools:

| Tool | Returns / does |
|---|---|
| `project_info` | project root, settings module, versions, databases |
| `list_apps` | installed apps and their labels |
| `list_models` / `describe_model` | models with fields, options, relations, managers |
| `list_routes` | URL patterns with names, methods, views |
| `list_commands` | available management commands |
| `show_migrations` | applied / pending migrations |
| `openapi_schema` | the project's real OpenAPI document: by default a list of operations (`GET /api/posts/ — listPosts [api]`); `path` prefix, `tag` or `summary: false` for JSON of the matching paths and the schemas they use |
| `run_command` | run a management command (`makemigrations`, `migrate` on the local DB, `check`, `test`, `startapp`, `sqlmigrate`, app commands); `runserver`, `shell`, `deploy`, `flush` and `--remote` are refused |
| `search_docs` / `get_doc` | search and read the Ghuri docs (https://ghurijs.github.io/docs/llms-full.txt; `--docs-url` overrides) |

It does not support `--remote` (local bindings only). Configure clients with `{"command": "npx", "args": ["ghuri", "mcp"]}` in the project's `.mcp.json` (new projects get one).

## Gotchas

- `python manage.py ...` / `django-admin ...`: use `npx ghuri ...`.
- `ghuri runserver 0.0.0.0:8000` serves through wrangler unless `--node`; Workers dev is port 8787.
- `ghuri migrate` without `--remote` only touches the local Miniflare D1.
- Commands that need a project fail outside it ("No Ghuri project found"): run from the project root or pass `--settings`.
- Interactive prompts (`makemigrations` renames, `createsuperuser`, `deploy`) hang in non-TTY agents: pass `--no-input` and explicit options.
