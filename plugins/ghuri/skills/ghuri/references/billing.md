# Billing and subscriptions (@ghuri/billing)

Covers dj-stripe style subscriptions in Ghuri: the `BILLING` setting and the `stripe()` provider, the mirrored models (`Customer`, `Product`, `Price`, `Subscription`, `SubscriptionItem`, `Invoice`, `Event`), the checkout / portal / webhook views in `billingUrls`, webhook verification and idempotency, access helpers (`getSubscription`, `hasFeature`, `getEntitlements`, ...), REST permissions, plans and `usageLimits()` for agents, signals, admin, commands, checks, the Stripe CLI and the in-memory `fakeStripe()`.

Install: `npm install @ghuri/billing@next` (0.1.0-alpha.0; peers `@ghuri/core` 0.1.0-alpha.4+, `@ghuri/orm` 0.1.0-alpha.5+, `hono`; `@ghuri/rest` and `@ghuri/admin` only for the `/rest` and `/admin` subpaths). It IS an app: add `BillingConfig` to `INSTALLED_APPS`, then `npx ghuri migrate` (ships `billing.0001_initial`, `billing_*` tables). Runs on Workers + D1 and on Node + SQLite/Postgres; no Stripe SDK, no Node modules.

Entry points (from `packages/billing/package.json`):

| Import | Exports you use |
|---|---|
| `@ghuri/billing` | `BillingConfig`, `stripe`, `StripeProvider`, `billingUrls`, `checkoutView`, `portalView`, `webhookView`, `getCustomer`, `getSubscription`, `hasActiveSubscription`, `isActive`, `getPlan`, `planKeyOf`, `getEntitlements`, `hasFeature`, `usageLimits`, `clearEntitlementsCache`, `subscriptionRequired`, `requireSubscriber`, `requestSubscriber`, `getProvider`, `billingSettings`, `Customer`, `Product`, `Price`, `Subscription`, `SubscriptionItem`, `Invoice`, `Event`, `formatAmount`, `subscriptionCreated`, `subscriptionUpdated`, `subscriptionCancelled`, `invoicePaid`, `invoicePaymentFailed`, `webhookProcessed`, `syncProductsAndPrices`, `syncSubscription`, `ensureCustomer`, `handleWebhook`, `processEventById`, `PROCESS_EVENT_TASK_NAME`, `BillingError`, `ProviderError`, `SignatureVerificationError`, `NoSubscriber`, types `BillingSettings`, `PlanConfig`, `Entitlements`, `PlanInfo`, `BillingProvider`, `StripeOptions` |
| `@ghuri/billing/rest` | `HasActiveSubscription`, `HasFeature` |
| `@ghuri/billing/admin` | side-effect import (registers every model); `CustomerAdmin`, `ProductAdmin`, `PriceAdmin`, `SubscriptionAdmin`, `SubscriptionItemAdmin`, `InvoiceAdmin`, `EventAdmin`, `processAgain` |
| `@ghuri/billing/testing` | `fakeStripe`, `FakeStripe`, `signPayload`, `parseForm` |

## Habit -> Ghuri

| dj-stripe / stripe-node / tutorial habit | Ghuri |
|---|---|
| `npm install stripe`, `new Stripe(process.env.STRIPE_SECRET_KEY)` | does not exist: `BILLING.PROVIDER: stripe({ secretKey: env.STRIPE_SECRET_KEY, webhookSecret: env.STRIPE_WEBHOOK_SECRET })` in the settings factory |
| your own route calling `stripe.checkout.sessions.create` / `stripe.billingPortal.sessions.create` | `POST billing/checkout/` with `{ plan: 'pro' }` (server picks price, trial, customer) / `POST billing/portal/` |
| `stripe.webhooks.constructEvent(rawBody, sig, secret)` + `switch (event.type)` | `billing/webhook/` verifies, stores, syncs; react with signals |
| Next.js `bodyParser: false` for the webhook | nothing: the view reads the raw body itself |
| `user.stripeCustomerId` / `user.plan` columns | `Customer` (generic subscriber ref) + `await getPlan(user)` |
| `DJSTRIPE_SUBSCRIBER_MODEL` / `..._REQUEST_CALLBACK` | `BILLING.SUBSCRIBER_MODEL` / `BILLING.SUBSCRIBER` |
| `djstripe_sync_models` | `npx ghuri billing_sync` (products and prices only) |
| `WEBHOOK_SIGNALS[...]`, `djstripe.signals` | `subscriptionCreated` / `Updated` / `Cancelled`, `invoicePaid`, `invoicePaymentFailed`, `webhookProcessed` |
| `customer.has_active_subscription()` / `subscription.is_valid()` | `await hasActiveSubscription(user)` / `isActive(sub)` |
| `djstripe_id` / `id` | `pk` (local auto id) / `providerId` (`cus_…`, `sub_…`) |
| `stripe.subscriptions.update(id, { cancel_at_period_end: true })` | `await getProvider().cancelSubscription(sub.providerId, { atPeriodEnd: true })`; the local row changes via the webhook |
| `stripe-mock`, nock, `price.unit_amount / 100` floats | `fakeStripe()`; integer minor units with `formatAmount(1250, 'usd')`, `price.humanReadable` |

## Settings

```ts
// src/settings.ts
import { BillingConfig, stripe } from '@ghuri/billing'
import { defineSettings } from '@ghuri/core'
export default defineSettings((env) => ({
  INSTALLED_APPS: [ContentTypesConfig, AuthConfig, SessionsConfig, BillingConfig /* , ... */],
  BILLING: {
    PROVIDER: stripe({ secretKey: env.STRIPE_SECRET_KEY, webhookSecret: env.STRIPE_WEBHOOK_SECRET }),
    PLANS: {
      free: { features: [], limits: { projects: 1, agentTokens: { day: 20_000 } } },
      pro: {
        prices: ['pro_monthly', 'pro_yearly'],          // price ids, lookup keys or product ids
        features: ['export', 'api'],
        limits: { projects: 50, agentTokens: { day: 500_000, month: 5_000_000 } },
        trialPeriodDays: 14,                            // server-side; the client cannot set a trial
      },
    },
    DEFAULT_PLAN: 'free',
    SUCCESS_URL: '/billing/thanks/?session={CHECKOUT_SESSION_ID}', CANCEL_URL: '/pricing/', RETURN_URL: '/account/',
  },
}))
```

| Key | Default | |
|---|---|---|
| `PROVIDER` | none (`billing.E001`) | `stripe({...})`, or any object implementing `BillingProvider`. |
| `SUBSCRIBER_MODEL` | `AUTH_USER_MODEL` (`'auth.User'`) | Who owns customers: `'tenants.Tenant'` / `'stores.Store'` to bill tenants. |
| `SUBSCRIBER` | the authenticated request user | `(c) => instance \| null`; multi-tenant: `() => currentTenant()`. |
| `PLANS` | `{}` | `{ [key]: { prices?, name?, features?, limits?, trialPeriodDays? } }`. Your own vocabulary. |
| `DEFAULT_PLAN` | none | Plan of subscribers without an active subscription. |
| `ACTIVE_STATUSES` | `['active', 'trialing']` | Add `'past_due'` for a grace period. |
| `SUCCESS_URL` / `CANCEL_URL` / `RETURN_URL` | `'/'` | Relative, or on the request host / `ALLOWED_HOSTS`. `{CHECKOUT_SESSION_ID}` is kept. |
| `WEBHOOK_TASKS` | `false` | Process webhooks in the `billing.processEvent` task (`@ghuri/tasks`). |
| `CHECKOUT_OPTIONS` | `{}` | Raw Stripe params merged into every Checkout Session (`{ allow_promotion_codes: true }`). |

`stripe(options)`: `secretKey`, `webhookSecret` (string or array while rotating), `apiVersion` (default: the account's), `tolerance` (300 s), `maxNetworkRetries` (2, same `Idempotency-Key`), `fetch` (test seam), `apiBase`. Keys sit in private fields (never in JSON or the debug page).

Secrets come from `env` in the settings factory only: `npx wrangler secret put STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` in production, `.dev.vars` (git-ignored) locally. Use `sk_test_…` keys until launch. Never `process.env` in app code, never a key literal.

## Models (app label `billing`)

| Model | Key fields (all have `provider`, `providerId` unique, `livemode`, `metadata`, `created`) |
|---|---|
| `Customer` | `subscriberType` (`'auth.user'`), `subscriberId` (pk as string), `email`, `name`, `currency`, `deleted`; `await customer.getSubscriber()` |
| `Product` | `name`, `description`, `active` |
| `Price` | `product` (FK, `relatedName: 'prices'`), `active`, `currency`, `unitAmount`, `type` (`one_time`/`recurring`), `recurringInterval`, `recurringIntervalCount`, `lookupKey`, `nickname`, `trialPeriodDays`; `humanReadable` |
| `Subscription` | `customer` (FK, `subscriptions`), `status`, `currentPeriodStart/End`, `cancelAtPeriodEnd`, `cancelAt`, `canceledAt`, `endedAt`, `trialStart/End`, `lastEventAt` |
| `SubscriptionItem` | `subscription` (FK, `items`), `price` (FK, PROTECT), `quantity` (no `livemode`/`metadata`/`created`) |
| `Invoice` | `customer`, `subscription` (nullable), `status`, `currency`, `amountDue`, `amountPaid`, `amountRemaining`, `subtotal`, `total`, `number`, `hostedInvoiceUrl`, `invoicePdf`, `periodStart/End`, `paidAt` |
| `Event` | `type`, `data` (raw payload), `status` (`pending`/`processed`/`failed`/`ignored`), `attempts`, `error`, `receivedAt`, `processedAt` |

The subscriber is a generic reference, not a FK, so no migration changes when you switch from users to tenants. One live customer per subscriber (partial unique constraint `WHERE NOT deleted`). FK accessors are async: `await invoice.customer`.

```ts
import { getCustomer, Invoice } from '@ghuri/billing'
const customer = await getCustomer(getUser(c))                    // Customer | null (no provider call)
const invoices = customer ? await Invoice.objects.filter({ customer }).orderBy('-created') : []
```

## Checkout, portal and webhook views

```ts
// src/urls.ts
import { billingUrls } from '@ghuri/billing'
import { include, path } from '@ghuri/core'
export const urlpatterns = [
  // ...
  path('billing/', include(billingUrls)),                  // reverse('billing:checkout' | 'billing:portal' | 'billing:webhook')
]
```

| Route | Body (JSON or form) | Answers |
|---|---|---|
| `POST billing/checkout/` | `{ plan, interval? }` or `{ price }` (id or lookup key), `quantity?`, `successUrl?`, `cancelUrl?` | JSON `{ id, url }`; form post `303` to Stripe; 401 no subscriber; 400 bad plan/price/URL; 502 `{ detail, code }` on a Stripe error |
| `POST billing/portal/` | `returnUrl?` | JSON `{ url }` or `303`; 401 |
| `POST billing/webhook/` | raw Stripe event | `{ received: true, eventId, type, result }`; 400 bad signature; 500 processing failed |

Checkout creates the Stripe customer on first use (`metadata.ghuri_subscriber = 'auth.user:42'`, also `client_reference_id`). When any plan lists `prices`, only those can be bought. Both views are CSRF-protected session views; `webhook/` is `csrfExempt`.

```tsx
<form method="post" action="/billing/checkout/">
  <input type="hidden" name="csrfmiddlewaretoken" value={getCsrfToken(c)} />
  <input type="hidden" name="plan" value="pro" />
  <button>Upgrade to Pro</button>
</form>

// SPA on the same session: send the `csrftoken` cookie value as X-CSRFToken, then follow the URL
const headers = { 'Content-Type': 'application/json', 'X-CSRFToken': csrfToken }
const res = await fetch('/billing/checkout/', { method: 'POST', headers, body: JSON.stringify({ plan: 'pro', interval: 'year' }) })
window.location.assign(((await res.json()) as { url: string }).url)
```

## Webhooks

Point a Stripe endpoint at `https://<app>/billing/webhook/` with `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `customer.*`, `customer.subscription.*`, `product.*`, `price.*`, `invoice.*`.

- **Signature:** `Stripe-Signature` HMAC-SHA256 over the raw body (WebCrypto, constant-time), timestamp within `tolerance`. Every configured `webhookSecret` is tried. Failure -> 400, nothing stored.
- **Idempotency:** the event is stored in `Event` by its Stripe id first; a processed/ignored repeat answers `duplicate`. Concurrent deliveries claim the row (compare-and-set on `attempts`): one processes, the other gets `busy`. A subscription event older than its `lastEventAt` is skipped (out-of-order delivery).
- **What is synced** (by object kind): customers, products, prices (upserted; `*.deleted` deactivates, never deletes), subscriptions with items (missing prices/products/customers are fetched), invoices (`invoice.deleted` deletes the row; `invoice.paid` / `invoice.payment_failed` send signals), and completed checkouts (link the customer to the subscriber, fetch the subscription). Anything else (`payment_intent.*`, `charge.*`, ...) is stored as `ignored`.
- **Failure:** the event becomes `failed` with `error`, the view answers 500 and Stripe retries. Replay with `npx ghuri billing_process_events` or the admin action. No transaction (D1): each step is an idempotent upsert.
- **Tasks:** with `@ghuri/tasks` installed (`TasksConfig` in `INSTALLED_APPS`) and `WEBHOOK_TASKS: true`, the view answers `queued` and the task `billing.processEvent` (`PROCESS_EVENT_TASK_NAME`, 3 attempts) does the work. Billing finds tasks through an interop object; no import.

## Access helpers

A `subject` is a user/tenant instance, a `Customer`, `{ type?, id }`, or a Hono `Context` (resolved with `BILLING.SUBSCRIBER`). Anonymous or `null` -> no subscription.

| Function | Returns |
|---|---|
| `getCustomer(subject, { create? })` | live `Customer` or `null`; `create: true` creates it at Stripe |
| `getSubscription(subject)` | the current `Subscription`: an active one (latest period end) else the most recent of ANY status, or `null` |
| `isActive(sub)` | status in `ACTIVE_STATUSES` (sync) |
| `hasActiveSubscription(subject, { plans? })` | `boolean` |
| `planKeyOf(sub)` | the first `PLANS` key whose `prices` match an item's price id, lookup key or product id |
| `getPlan(subject)` | `{ key, plan, subscription, active }` (`DEFAULT_PLAN` when not active) |
| `getEntitlements(subject)` | `{ plan, features, limits, active, subscription }` |
| `hasFeature(subject, feature)` | `boolean` |
| `requireSubscriber(c)` | the request's subscriber or throws `NoSubscriber` |

```ts
import { getEntitlements, hasFeature } from '@ghuri/billing'
import { getUser } from '@ghuri/core'
export async function createProject(c: Context) {
  const user = getUser(c)
  const { limits } = await getEntitlements(user)                   // or getEntitlements(c)
  if ((await Project.objects.filter({ owner: user.pk }).count()) >= Number(limits.projects ?? 0))
    return c.json({ detail: 'Upgrade to add more projects.', api: await hasFeature(user, 'api') }, 402)
}
```

## REST permissions and the view decorator

```ts
import { subscriptionRequired } from '@ghuri/billing'
import { HasActiveSubscription, HasFeature } from '@ghuri/billing/rest'
import { APIView, IsAuthenticated } from '@ghuri/rest'
class ExportView extends APIView {
  static requiredPlans = ['pro']                                   // optional narrowing
  override permissionClasses = [IsAuthenticated, HasActiveSubscription]
}
class SsoView extends APIView { override permissionClasses = [IsAuthenticated, HasFeature('sso')] }

export const dashboard = subscriptionRequired({ plans: ['pro'], redirectTo: '/pricing/' })(async (c) => c.text('ok'))
```

403 messages: `'An active subscription is required.'` (`subscription_required`), `"Your plan does not include 'sso'."` (`feature_not_in_plan`). `subscriptionRequired()` without `redirectTo` raises 403.

## Plans, entitlements and agent usage limits

`usageLimits(limit, { scope?, otherwise?, cacheSeconds? })` builds a function for `AGENTS.USAGE_LIMITS` in `@ghuri/agents` (subject `{ scope, key, user }`, result `{ day?, month? } | null` tokens):

```ts
import { usageLimits } from '@ghuri/billing'

AGENTS: { USAGE_LIMITS: { tenant: usageLimits('agentTokens') } },   // `user:` when users pay
```

- It reads `PLANS[plan].limits[limit]` of the subscriber whose pk is `key`, for the scope matching `SUBSCRIBER_MODEL` (`'user'` if it is the user model, else `'tenant'`). Other scopes get `otherwise` (default `null` = no limit).
- `limit` may be a function: `usageLimits((e) => (e.active ? { day: 1_000_000 } : { day: 10_000 }))`.
- Entitlements are cached in memory for `cacheSeconds` (60; `0` = off). Subscription signals clear it in the process that got the webhook; other isolates see a plan change within the TTL. `clearEntitlementsCache()` clears it by hand.

## Signals, admin, commands, checks

| Signal | Receiver gets |
|---|---|
| `subscriptionCreated` | `{ subscription, sender }` |
| `subscriptionUpdated` | `{ subscription, previousStatus, sender }` |
| `subscriptionCancelled` | `{ subscription, previousStatus, sender }` (sent instead of updated when it becomes `canceled`) |
| `invoicePaid` / `invoicePaymentFailed` | `{ invoice, sender }` |
| `webhookProcessed` | `{ event, type, sender }` for every processed or ignored event |

```ts
import { type Customer, invoicePaymentFailed } from '@ghuri/billing'
import { sendMail } from '@ghuri/mail'
invoicePaymentFailed.connect(async ({ invoice }) => {
  const customer = (await invoice.customer) as Customer
  if (customer.email) await sendMail('Your payment failed', `Update your card: ${invoice.hostedInvoiceUrl}`, null, [customer.email])
}, { uid: 'accounts.payment-failed-mail' })
```

- Admin: `import '@ghuri/billing/admin'` in your admin module. Every model is read-only (no add/delete); `Event` has the `process_again` action.
- Commands: `npx ghuri billing_sync [--kinds products,prices]`; `npx ghuri billing_process_events [--status failed|pending|all] [--limit 100]`.
- Checks: `billing.E001` no `PROVIDER`; `E002` empty/malformed/publishable (`pk_`) secret key; `E003` no webhook secret; `E004` unknown `SUBSCRIBER_MODEL`; `E005` bad `PLANS` / `DEFAULT_PLAN`; `W001` (`ghuri check --deploy`) test key with `DEBUG` false; `W002` `WEBHOOK_TASKS` without `@ghuri/tasks`.

## Local webhooks with the Stripe CLI

```sh
stripe listen --forward-to localhost:8787/billing/webhook/    # prints a whsec_… secret: put it in .dev.vars as STRIPE_WEBHOOK_SECRET
npx ghuri billing_sync                                        # import test-mode products and prices
npx ghuri runserver                                           # wrangler dev on :8787; pay with Stripe's test cards
```

## Testing with the fake Stripe

```ts
import { User } from '@ghuri/auth'
import { hasActiveSubscription, syncProductsAndPrices } from '@ghuri/billing'
import { fakeStripe } from '@ghuri/billing/testing'
const fake = fakeStripe()                                          // in-memory Stripe API, no network, no keys
ctx.settings.BILLING = { ...ctx.settings.BILLING, PROVIDER: fake.provider() }   // in beforeAll, after app.setup(env)

it('subscribes through checkout', async () => {
  const product = fake.createProduct({ name: 'Pro' })
  fake.createPrice({ product: product.id, unit_amount: 1200, lookup_key: 'pro_monthly' })
  await syncProductsAndPrices()
  const user = await User.objects.createUser({ username: 'ada', email: 'ada@example.com', password: 'pw' })
  await client.forceLogin(user)
  const res = await client.post('/billing/checkout/', { json: { plan: 'pro' } })
  const { id } = (await res.json()) as { id: string; url: string }
  const session = fake.completeCheckout(id)                       // "the customer paid"
  const { body, headers } = await fake.webhook(fake.event('checkout.session.completed', session))
  expect((await client.post('/billing/webhook/', { body, headers, csrf: false })).status).toBe(200)
  expect(await hasActiveSubscription(user)).toBe(true)
})
```

Fake helpers: `createCustomer`, `createProduct`, `createPrice({ product, unit_amount, currency, recurring: { interval }, lookup_key })`, `createSubscription({ customer, price, status?, trialDays? })`, `updateSubscription(id, { status: 'past_due' })`, `cancelSubscription(id)`, `createInvoice({ subscription, status?, amount? })`, `event(type, object, { id?, created? })`, `webhook(event, { secret?, timestamp? })` (signed), plus `requests`, `checkoutSessions`, `portalSessions`, `failNext = [500]`. Pass `{ created }` to test out-of-order events; reuse `{ id }` to test duplicates. In `beforeEach`: `fake.reset()` and `clearEntitlementsCache()`.

## Gotchas

- Importing the `stripe` npm package, reading `process.env.STRIPE_*`, or writing your own checkout/webhook route: all wrong. Use `stripe({...})` in settings and `billingUrls`.
- Do not `switch (event.type)` or edit `Subscription` rows yourself: Stripe is the source of truth; react to signals and let webhooks update rows.
- Signal receivers run inside webhook processing: a throw marks the event `failed`, answers 500 and Stripe retries, so receivers must be idempotent. Slow work: `WEBHOOK_TASKS` or `waitUntil`.
- Webhook processing has no request user and no tenant: load the owner with `await customer.getSubscriber()` and wrap tenant-scoped work in `runAsTenant(...)`. With `TENANTS.REQUIRED: true` the webhook request (no tenant) gets 404.
- Checkout/portal use the session user (`AuthenticationMiddleware`); a JWT-only SPA gets 401 unless `BILLING.SUBSCRIBER` resolves the subscriber.
- `{ plan, interval }` and lookup keys resolve through LOCAL `Price` rows: run `billing_sync` (or receive `price.*` events) first, or checkout answers 400.
- `getSubscription()` can return a `canceled` subscription; check `isActive(sub)` or use `hasActiveSubscription()`. `past_due` loses access unless added to `ACTIVE_STATUSES`.
- Amounts are integers in minor units (BigInteger columns): wrap in `Number()`, never store floats.
- `requireSubscriber()` throws `NoSubscriber`, not an HTTP error; in views prefer `subscriptionRequired()`, or `await requestSubscriber(c)` and answer 401 yourself.
- Not supported in 0.1: separate test/live customers for one subscriber (switching keys needs fresh customers), providers other than Stripe (Paddle / Lemon Squeezy planned; custom `BillingProvider` possible), PaymentIntents, charges, payment methods, coupons and tax ids (not mirrored), usage-based/metered billing, proration previews. Invoices are synced from `invoice.*` events only (`billing_sync` pulls products and prices, not customers, subscriptions or invoices). No `startproject --billing` yet. Two concurrent first checkouts can create two Stripe customers (one stays unused).
