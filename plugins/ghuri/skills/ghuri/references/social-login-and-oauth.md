# Social login and login strategies (@ghuri/socialauth, @ghuri/oauth)

Two packages, layered:

| Need | Package | Django/Node equivalent |
|---|---|---|
| "Log in with GitHub / Google / Facebook / Microsoft / Discord / GitLab / any OIDC issuer", configured in settings | `@ghuri/socialauth` | django-allauth `socialaccount` (same tables) |
| Your own login flows: any OAuth 2.0 / OIDC provider in code, username+password, magic links, API bearer tokens | `@ghuri/oauth` | Passport.js strategies |

Pick `@ghuri/socialauth` for social buttons; drop to `@ghuri/oauth` only for flows it does not cover. Both run on Workers and Node (WebCrypto only), need `@ghuri/core` and `@ghuri/auth` (socialauth: auth `0.1.0-alpha.2`+), and are alpha:

```sh
npm install @ghuri/socialauth@next @ghuri/oauth@next
```

Not available yet: Apple, X, LinkedIn and Slack providers. Do not invent them; write a custom `Provider` (below) or use `openid_connect`.

## Social login (@ghuri/socialauth)

### Setup

```ts
// src/settings.ts
import { AuthConfig, ContentTypesConfig, SessionsConfig } from '@ghuri/auth'
import { defineSettings } from '@ghuri/core'
import { SocialAuthConfig } from '@ghuri/socialauth'

export default defineSettings((env) => ({
  // ...
  INSTALLED_APPS: [ContentTypesConfig, AuthConfig, SessionsConfig, SocialAuthConfig /* , your apps */],
  SOCIALACCOUNT: {
    PROVIDERS: {
      github: { APP: { clientId: env.GITHUB_CLIENT_ID, secret: env.GITHUB_SECRET } },
      google: { APP: { clientId: env.GOOGLE_CLIENT_ID, secret: env.GOOGLE_SECRET } },
    },
  },
}))
```

```ts
// src/urls.ts
import { authUrls } from '@ghuri/auth'
import { include, path } from '@ghuri/core'
import { socialUrls } from '@ghuri/socialauth'

export const urlpatterns = [
  path('accounts/', include(authUrls)),
  path('accounts/', include(socialUrls)),
]
```

Then `npx ghuri migrate` (creates `socialaccount_*` tables). Secrets go in `.dev.vars` locally and `wrangler secret put` in production, never in code. The redirect URI to register with each provider is `https://<host>/accounts/<provider>/login/callback/`.

A login button is a **POST** form with the CSRF token (a GET shows a confirmation page unless `LOGIN_ON_GET: true`):

```html
<form method="post" action="/accounts/github/login/?next=/dashboard/">
  <input type="hidden" name="csrfmiddlewaretoken" value="{csrfToken}">
  <button>Continue with GitHub</button>
</form>
```

Build the URL with `reverse('socialaccount_login', { provider: 'github' })`.

### Providers

| id | Notes |
|---|---|
| `github` | Email = primary **verified** address from `/user/emails`. `settings.webUrl` / `apiUrl` for GitHub Enterprise |
| `google` | OpenID Connect |
| `facebook` | Graph API (`VERSION`, default `v21.0`); emails unverified unless `VERIFIED_EMAIL: true` |
| `microsoft` | Entra ID (OIDC), `settings.tenant` (default `common`); emails never trusted by default |
| `discord` | `verified` from `/users/@me` |
| `gitlab` | OIDC; `settings.url` for self-hosted |
| `openid_connect` | Any OIDC issuer (Auth0, Okta, Keycloak, Cognito, Zitadel), several at once via `APPS` |

```ts
SOCIALACCOUNT: {
  PROVIDERS: {
    openid_connect: {
      APPS: [
        { providerId: 'okta', name: 'Okta', clientId: env.OKTA_ID, secret: env.OKTA_SECRET, settings: { serverUrl: 'https://acme.okta.com' } },
      ],
    },
  },
},
// → /accounts/okta/login/
```

Per provider: `APP` or `APPS`, `SCOPE` (replaces defaults), `AUTH_PARAMS`, `VERIFIED_EMAIL`. Credentials may also be `SocialApp` rows managed in the admin; settings win.

Custom provider: subclass `Provider`, return an `OAuth2Strategy` / `OIDCStrategy` from `createStrategy()`, and `registerProvider(new MyProvider())`.

### Callback logic (in order)

1. A `SocialAccount` with this provider + uid exists → log its user in.
2. `?process=connect` and logged in → link the account to the current user (refused if linked to someone else).
3. `EMAIL_AUTHENTICATION: true` and the provider's email is **verified** and exactly one user has it → link and log in. Unverified emails never link to existing users.
4. Sign up: `AUTO_SIGNUP` (default) creates the user (free username, email if not taken, names, unusable password); if something is missing or taken → `signup/` form.

Success → safe `next` or `LOGIN_REDIRECT_URL`. Errors → `LOGIN_ERROR_URL` (default `LOGIN_URL`) with `?error=`.

### URLs (`socialUrls`)

| Path | Name | |
|---|---|---|
| `providers/` | `socialaccount_providers` | JSON list of configured providers + login URLs |
| `<provider>/login/` | `socialaccount_login` | POST starts login (`?next=`, `?process=connect`) |
| `<provider>/login/callback/` | `socialaccount_callback` | OAuth callback |
| `<provider>/token/` | `socialaccount_native_token` | Native apps: POST `{ id_token }` (OIDC) or `{ access_token }` (GitHub, Facebook); `settings.audiences` adds iOS/Android client ids |
| `token/` | `socialaccount_token_exchange` | SPAs: POST `{ code }` → `{ access, refresh, user }` |
| `signup/` | `socialaccount_signup` | Finish signup (HTML or JSON) |
| `connections/` | `socialaccount_connections` | GET linked accounts; POST `{ account }` disconnects (not the last login method of a passwordless user) |

SPAs: `LOGIN_RESPONSE: 'jwt'` + `FRONTEND_URL` → callback redirects to `FRONTEND_URL#code=<one-time code>` (60 s, single use); the SPA posts it to `token/`. Tokens never appear in URLs.

### Adapter, signals, provider tokens, admin

```ts
import { ImmediateResponse, SocialAccountAdapter } from '@ghuri/socialauth'

class Adapter extends SocialAccountAdapter {
  isOpenForSignup(c, login) {
    return login.profile.email?.endsWith('@acme.com') ?? false
  }
  async preSocialLogin(c, login) {
    if (login.provider.id === 'facebook') throw new ImmediateResponse(c.text('Not here', 403))
  }
}
// settings: SOCIALACCOUNT: { ADAPTER: Adapter }
```

Other hooks: `isAutoSignupAllowed`, `newUser`, `populateUser`, `saveUser`, `generateUsername`, `getConnectRedirectUrl`, `authenticationError`. Signals: `preSocialLogin`, `socialAccountAdded`, `socialAccountUpdated`, `socialAccountRemoved`. Models: `SocialApp`, `SocialAccount`, `SocialToken`.

`STORE_TOKENS: true` keeps provider tokens in `SocialToken` (encrypted with a key derived from `SECRET_KEY`); `await getAccessToken(account)` refreshes when expired. Admin: `import '@ghuri/socialauth/admin'` in your `admin.ts` (tokens are never shown).

### Settings (defaults)

```ts
SOCIALACCOUNT: {
  PROVIDERS: {},
  ADAPTER: SocialAccountAdapter,
  AUTO_SIGNUP: true,
  EMAIL_AUTHENTICATION: false,
  EMAIL_REQUIRED: false,
  LOGIN_ON_GET: false,
  STORE_TOKENS: false,
  LOGIN_RESPONSE: 'session',   // or 'jwt' (needs FRONTEND_URL)
  FRONTEND_URL: undefined,
  LOGIN_ERROR_URL: undefined,  // default LOGIN_URL
}
```

### Testing

```ts
import { socialLogin } from '@ghuri/socialauth/testing'

const res = await socialLogin(client, 'github', { id: '1', username: 'ann', email: 'ann@example.com', emailVerified: true })
// client is now logged in, or res redirects to signup/
```

## Login strategies (@ghuri/oauth)

Register strategies (Passport's `passport.use`) and turn them into views with `authenticate()`:

```ts
// src/accounts/strategies.ts
import { User } from '@ghuri/auth'
import { MagicLinkStrategy, OIDCStrategy, strategies } from '@ghuri/oauth'

strategies.use(
  'acme',
  new OIDCStrategy(
    {
      name: 'acme',
      issuer: 'https://login.acme.example',
      clientId: (env) => env.ACME_CLIENT_ID,     // EnvValue: a value or (env) => value
      clientSecret: (env) => env.ACME_CLIENT_SECRET,
    },
    // verify({ profile, tokens, c, flow }) → user, or null to refuse
    async ({ profile }) =>
      (await User.objects.filter({ email: profile.email }).first()) ??
      User.objects.createUser(profile.username ?? profile.id, profile.email),
  ),
)

strategies.use(
  'email',
  new MagicLinkStrategy(
    { send: async ({ email, url }) => sendMail(email, 'Your login link', url) },
    async ({ email }) => User.objects.filter({ email }).first(),
  ),
)
```

```ts
// src/accounts/urls.ts
import { path } from '@ghuri/core'
import { authenticate } from '@ghuri/oauth'
import './strategies'

export const urlpatterns = [
  // one URL for both legs: without ?code it redirects to the provider, with it it logs in
  path('login/acme/', authenticate('acme', { failureRedirect: '/login/' })),
  path('login/email/', authenticate('email', { successRedirect: '/' })),
]
```

| Strategy | Use |
|---|---|
| `OAuth2Strategy` | Authorization code + PKCE (S256) + state. `authorizationURL`, `tokenURL`, `clientId`, `clientSecret`, `scope`, `userInfoURL` or `profile(tokens, ctx)`, `tokenAuth: 'body' \| 'basic'`, `authorizationParams`, `callbackURL` |
| `OIDCStrategy` | OAuth2 + discovery from `issuer`, nonce, ID-token validation against JWKS; `issuerValidation` for multi-tenant issuers |
| `LocalStrategy` | Username/password from a JSON or form POST (default verify = `@ghuri/auth` `authenticate()`) |
| `MagicLinkStrategy` | `POST { email }` sends a link; `GET ?token=` logs in; `maxAge` default 15 min, single use |
| `BearerStrategy` | `Authorization: Bearer <token>` → `verify(token)` (API keys) |
| `CustomStrategy` | `new CustomStrategy('name', (c, options) => result)` |

A strategy result is `{ type: 'success', user, info? }`, `'fail'`, `'redirect'`, `'pass'` (try the next one), `'error'` or `'response'`. Profiles are normalized: `{ provider, id, email?, emailVerified?, username?, name?, firstName?, lastName?, avatarUrl?, raw }`.

`authenticate(names, options)`: `names` is one name or an array tried in order. Options: `successRedirect`, `failureRedirect` (adds `?error=`), `successReturnToOrRedirect`, `respond: 'session' | 'jwt' | (c, user, info) => Response`, `session: false`, `next`, `scope`, `state`. `runStrategy(c, names)` runs strategies inside your own view.

Round-trip state (state, PKCE verifier, nonce, `next`) lives in an encrypted HttpOnly cookie, so flows work without sessions; missing/expired/reused state → 400.

REST:

```ts
import { APIView } from '@ghuri/rest'
import { BearerStrategy, strategies } from '@ghuri/oauth'
import { StrategyAuthentication } from '@ghuri/oauth/rest'

strategies.use('api-key', new BearerStrategy(async (token) => ApiKey.userFor(token)))

class Reports extends APIView {
  authenticationClasses = [StrategyAuthentication(['api-key'])]
}
```

Lower level: `OAuth2Client` (`authorizationUrl`, `exchangeCode`, `refresh`, `revoke`), `discover(issuer)`, `verifyJwt`, `signJwt`, `importPkcs8`, `seal` / `unseal`, `pkcePair()`.

Settings: `OAUTH: { STATE_COOKIE: 'ghuri_oauth', STATE_MAX_AGE: 600, HTTP_TIMEOUT: 10_000, CALLBACK_BASE_URL: undefined }` (set `CALLBACK_BASE_URL` behind proxies that rewrite the host).

Testing:

```ts
import { followOAuth, mockOAuthProvider } from '@ghuri/oauth/testing'

const provider = mockOAuthProvider({ issuer: 'https://login.acme.example', profile: { sub: '42', email: 'ann@example.com', email_verified: true } })
const res = await followOAuth(client, '/login/acme/', provider)   // redirect → approve → callback
provider.restore()
```

## Gotchas

- These are not `passport` or `django-allauth`: no `passport.authenticate()` middleware, no `{% provider_login_url %}`, no `allauth.socialaccount.providers.*` apps. One `SocialAuthConfig` includes every provider.
- Settings use camelCase credential keys (`clientId`, `secret`) inside `UPPER_SNAKE` blocks (`SOCIALACCOUNT.PROVIDERS.github.APP`).
- Login buttons must POST with the CSRF token; plain links only show a confirmation page.
- Never trust an unverified provider email to link to an existing user; keep `EMAIL_AUTHENTICATION` off unless you need it.
- Register the exact callback URL (`/accounts/<provider>/login/callback/`, trailing slash) with the provider.
- Docs: https://ghurijs.github.io/docs/topics/social-login/ and https://ghurijs.github.io/docs/topics/login-strategies/
