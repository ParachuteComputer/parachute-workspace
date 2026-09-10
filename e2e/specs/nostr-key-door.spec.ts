/**
 * The human key door, end to end, in a browser against a real hub.
 *
 * Design: team-vault `Design/Human key door — sign in with a Nostr key`
 * (https://parachute.techne.coop/n/01M1J1CHW7KM8FD35FR1AH06HK) §6, "End-to-end".
 *
 * What this proves that hub's own suite cannot. `nostr-login.test.ts` calls the
 * handler directly and `nostr-login-ui.test.ts` compiles the shipped client
 * script with `new Function(...)` over a fake DOM — excellent tests, but neither
 * has a browser, a cookie jar, a real `fetch`, or a hub process. Here a real
 * Chromium loads the hub's real `/login`, the page's own inlined script runs, it
 * calls a `window.nostr` that signs with a real BIP-340 key, and the hub answers
 * over HTTP with a `Set-Cookie` the browser then actually holds. The one thing
 * standing in for a person is the browser extension.
 *
 * ## The signer
 *
 * `window.nostr` is a shim, and the crypto behind it runs in the TEST process,
 * not the page: `context.exposeFunction` publishes `__e2eNostrSign`, and the
 * init script's `signEvent` is a one-line forward to it. Bundling
 * @noble/curves into a page script would work (yesterday's demo rig did exactly
 * that) but it would put 77 KB of vendored, regenerated JavaScript in this repo
 * to prove something the harness does not doubt. What the page sees is
 * indistinguishable: an object with `getPublicKey` and `signEvent`, resolving
 * promises, injected before any page script runs.
 *
 * The shim signs the `event_template` the hub returned VERBATIM — it never
 * rebuilds the `u` tag or the statement. That is not a convenience: the door
 * refuses a `u` tag naming an unbound origin and refuses a `content` that isn't
 * the statement recomputed from that origin, so a shim that reconstructed
 * either would be testing its own guesswork.
 *
 * ## What is proven here, and what is not
 *
 * PROVEN: challenge → sign → verify → session cookie → the hub's own post-login
 * page; the four negatives; and `/v/<vault>/n/<id>` resolving on the seeded
 * vault and rendering the note.
 *
 * NOT PROVEN: that the hub session from the first half is what produces the
 * vault token used in the second. The app reaches a vault by OAuth against a
 * hub that ISSUES for it, and this hub does not issue for this vault — the hub
 * proxies only modules it supervises at `127.0.0.1:<port>` (`services.json` has
 * no host field at all), so a vault in a sibling container cannot be registered
 * with it, and the vault would additionally have to be configured to trust the
 * hub's JWKS and reach its revocation list. Both halves are real and neither is
 * stubbed; the join between them is seeded, exactly as `transcription.spec.ts`
 * seeds it, and is stated here rather than implied.
 *
 * ## What this spec expects of the stack
 *
 * `run.sh` links the two keys below to the hub user before the browser starts,
 * because `parachute auth link-pubkey` writes hub.db directly and only the host
 * can reach the container to run it. That seeding is a PRECONDITION, not a
 * fixture this file can rebuild: the "unlinked after login" case spends
 * `linkedForUnlink`'s link, so driving Playwright twice against one `--keep-up`
 * stack needs run.sh's seeding step again in between. `run.sh` re-runs it on
 * every invocation, and `link-pubkey` is idempotent, so the documented
 * entrypoint is always in the right state.
 */
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { schnorr } from "@noble/curves/secp256k1.js";
import { type BrowserContext, type Page, expect, test } from "@playwright/test";

const HUB_URL = process.env.E2E_HUB_URL ?? "http://hub:1939";
const HUB_USER = process.env.E2E_HUB_USER ?? "keyholder";
const VAULT_URL = process.env.E2E_VAULT_URL ?? "http://app:8080/vault/demo";
const VAULT_TOKEN = process.env.E2E_VAULT_TOKEN ?? "e2e-scratch-token-not-a-secret";
const KEYS_FILE = process.env.E2E_NOSTR_KEYS ?? "/e2e/fixtures/nostr-keys.json";

/** Cookie the hub sets on a minted session (`sessions.ts`). */
const SESSION_COOKIE = "parachute_hub_session";
/** Ids the door's markup uses (`nostr-login-ui.ts`). */
const BUTTON = "#nostr-signin-button";
const STATUS = "#nostr-signin-status";
/** Where `POST_LOGIN_DEFAULT` lands a session with no forced password change. */
const POST_LOGIN = "/admin/vaults";

/**
 * The sentence the door shows for an unlinked key, copied from
 * `NOSTR_LOGIN_ERROR_MESSAGES.unknown_pubkey`. Asserted in full rather than by
 * substring: the design note's §4 dead end is that both remedies have to be on
 * screen, and half the sentence would satisfy a looser check.
 */
const UNKNOWN_PUBKEY_MESSAGE =
  "No account on this hub is linked to that Nostr key. Ask your hub operator to link it, or join a channel whose vault is attached to this hub.";

/** How long a sign-in nonce stays spendable (`NOSTR_LOGIN_CHALLENGE_TTL_MS`). */
const CHALLENGE_TTL_MS = 5 * 60 * 1000;

type Keypair = { secret: string; pubkey: string };
const KEYS = JSON.parse(readFileSync(KEYS_FILE, "utf8")) as Record<string, Keypair>;

const hexToBytes = (hex: string): Uint8Array => Uint8Array.from(Buffer.from(hex, "hex"));
const bytesToHex = (bytes: Uint8Array): string => Buffer.from(bytes).toString("hex");

interface EventTemplate {
  kind: number;
  content: string;
  tags: string[][];
}
interface SignedEvent extends EventTemplate {
  pubkey: string;
  created_at: number;
  id: string;
  sig: string;
}

/** NIP-01 id: sha256 of the canonical serialization. */
function nostrEventId(e: Omit<SignedEvent, "id" | "sig">): string {
  return createHash("sha256")
    .update(JSON.stringify([0, e.pubkey, e.created_at, e.kind, e.tags, e.content]))
    .digest("hex");
}

/** Sign a draft with `secretHex`. The draft's fields are used exactly as given. */
function signEvent(secretHex: string, draft: EventTemplate & { created_at: number }): SignedEvent {
  const secret = hexToBytes(secretHex);
  const unsigned = {
    pubkey: bytesToHex(schnorr.getPublicKey(secret)),
    created_at: draft.created_at,
    kind: draft.kind,
    tags: draft.tags,
    content: draft.content,
  };
  const id = nostrEventId(unsigned);
  return { ...unsigned, id, sig: bytesToHex(schnorr.sign(hexToBytes(id), secret)) };
}

/**
 * Install a NIP-07 signer into every page of `context`, backed by `secretHex`.
 *
 * Order matters only in that `exposeFunction` has to be registered before the
 * init script that calls it; both are installed before any navigation, so the
 * page can never observe a half-built `window.nostr`.
 */
async function installSigner(context: BrowserContext, secretHex: string): Promise<void> {
  await context.exposeFunction(
    "__e2eNostrSign",
    (draft: EventTemplate & { created_at: number }) => signEvent(secretHex, draft),
  );
  await context.addInitScript((pubkey: string) => {
    (window as unknown as { nostr: unknown }).nostr = {
      getPublicKey: async () => pubkey,
      signEvent: async (draft: unknown) =>
        (window as unknown as { __e2eNostrSign(d: unknown): Promise<unknown> }).__e2eNostrSign(
          draft,
        ),
    };
  }, bytesToHex(schnorr.getPublicKey(hexToBytes(secretHex))));
}

/** Land on the hub's login page with the door's button live. */
async function openLoginWithSigner(page: Page): Promise<void> {
  await page.goto(`${HUB_URL}/login`);
  // The script re-checks for a signer on a backoff before it gives up, so the
  // button is briefly disabled even when the shim is present. Waiting for
  // "enabled" (rather than asserting it) is the difference between reading the
  // settled state and racing the first tick.
  await expect(page.locator(BUTTON)).toBeEnabled({ timeout: 15_000 });
}

/** The hub session cookie currently held by `context`, or undefined. */
async function sessionCookie(context: BrowserContext): Promise<string | undefined> {
  const cookies = await context.cookies(HUB_URL);
  return cookies.find((c) => c.name === SESSION_COOKIE)?.value;
}

// --- the door opens -------------------------------------------------------

test("a linked key signs in to the hub, and the seeded note renders", async ({
  context,
  page,
  request,
}) => {
  // The note first: it has to exist in the vault before the browser asks for
  // it, and creating it here rather than in run.sh keeps the spec's fixtures
  // where its assertions are.
  const created = await request.post(`${VAULT_URL}/api/notes`, {
    headers: { authorization: `Bearer ${VAULT_TOKEN}` },
    data: {
      // No `path`. The vault assigns one, and two runs against a `--keep-up`
      // stack would otherwise collide on `path_conflict` — a 409 that reads
      // like a broken write when it only means "you have run this before".
      content:
        "# The key door opened\n\nThis note was written by the e2e harness and fetched with a vault token.",
    },
  });
  expect(created.ok(), `vault refused the seed note: ${await created.text()}`).toBe(true);
  const noteId = ((await created.json()) as { id?: string }).id;
  expect(noteId, "vault POST /api/notes returned no note id").toBeTruthy();

  await installSigner(context, KEYS.linked.secret);
  await openLoginWithSigner(page);

  // No session before the click — otherwise a stale cookie could carry the
  // assertion below and the door would never have to work.
  expect(await sessionCookie(context)).toBeUndefined();

  await page.locator(BUTTON).click();

  // The script follows the destination the SERVER resolved. `keyholder` is
  // env-seeded with `password_changed = true`, so that is POST_LOGIN_DEFAULT.
  await page.waitForURL(`${HUB_URL}${POST_LOGIN}`, { timeout: 20_000 });
  expect(await sessionCookie(context), "no session cookie after a signed sign-in").toBeTruthy();

  // And the session is real, not just a cookie: an authenticated read that a
  // signed-out browser cannot make.
  const me = await page.evaluate(async () =>
    (await fetch("/api/me", { credentials: "same-origin" })).json(),
  );
  expect(me).toMatchObject({ hasSession: true, user: { displayName: HUB_USER } });

  // --- the vault half ----------------------------------------------------
  // Seeded, not driven through OAuth — see the header for exactly why, and for
  // what that means this spec does not prove.
  await seedConnectedVault(page);
  await page.goto(`/v/demo/n/${encodeURIComponent(noteId as string)}`);

  // `/v/<vault>/n/<id>` is a REDIRECT: it switches the active vault and then
  // navigates to the canonical `/n/<id>`, which is what renders. Asserting on
  // the original URL would assert on a URL the app is designed to leave.
  await expect(page).toHaveURL(new RegExp(`/n/${noteId}$`), { timeout: 30_000 });
  await expect(page.getByRole("heading", { level: 1, name: "The key door opened" })).toBeVisible({
    timeout: 30_000,
  });
  await expect(page.locator(".prose-note")).toContainText("written by the e2e harness");
});

/**
 * Hand the app the connected-vault state OAuth would have left behind. Copied
 * from `transcription.spec.ts`, which documents the shape; the one thing worth
 * repeating is that `lens:active_vault` is a RAW string, and writing JSON there
 * yields a blank app rather than an error.
 */
async function seedConnectedVault(page: Page): Promise<void> {
  const vaultId = VAULT_URL.replace(/^https?:\/\//, "").replace(/[^\w.-]+/g, "_");
  await page.addInitScript(
    ([id, url, token]) => {
      const now = new Date().toISOString();
      localStorage.setItem(
        "lens:vaults",
        JSON.stringify({
          [id]: {
            id,
            url,
            name: "demo",
            issuer: new URL(url).origin,
            clientId: "e2e-harness",
            scope: "vault:demo:write",
            addedAt: now,
            lastUsedAt: now,
          },
        }),
      );
      localStorage.setItem("lens:active_vault", id);
      localStorage.setItem(
        `lens:token:${id}`,
        JSON.stringify({ accessToken: token, scope: "vault:demo:write", vault: "demo" }),
      );
    },
    [vaultId, VAULT_URL, VAULT_TOKEN] as const,
  );
}

// --- the door stays shut --------------------------------------------------
//
// Each negative asserts the CODE, not just the failure: the door has ten wire
// codes and a test that only checked "not 200" would pass while the hub
// mistook an expired nonce for an unknown key.

/** Ask the door for a nonce and the exact event it wants signed for it. */
async function getTemplate(
  request: import("@playwright/test").APIRequestContext,
): Promise<EventTemplate> {
  const res = await request.get(`${HUB_URL}/api/auth/nostr/challenge`);
  expect(res.status()).toBe(200);
  return ((await res.json()) as { event_template: EventTemplate }).event_template;
}

/**
 * Sign a template, optionally swapping the `challenge` tag for the case under
 * test. Everything not overridden comes from the hub's own template, so a
 * rejection can only be about the override.
 *
 * `created_at` is stamped HERE and not when the template was fetched. That is
 * load-bearing for the expiry case: `handleVerify` checks the ±5-minute
 * `created_at` skew in step 3 and spends the nonce in step 6, so an event
 * signed five minutes ago is refused as `invalid_event` before the nonce is
 * ever looked at — the right code for the wrong reason.
 */
function signTemplate(
  secretHex: string,
  tpl: EventTemplate,
  over: { challenge?: string } = {},
): SignedEvent {
  const tags =
    over.challenge === undefined
      ? tpl.tags
      : tpl.tags.map((t) => (t[0] === "challenge" ? ["challenge", over.challenge as string] : t));
  return signEvent(secretHex, {
    kind: tpl.kind,
    content: tpl.content,
    tags,
    created_at: Math.floor(Date.now() / 1000),
  });
}

/** POST an event at `/verify` and read back the status, the code, and any cookie. */
async function verify(
  request: import("@playwright/test").APIRequestContext,
  event: SignedEvent,
): Promise<{ status: number; error: string; setCookie: string[] }> {
  const res = await request.post(`${HUB_URL}/api/auth/nostr/verify`, { data: { event } });
  const body = (await res.json()) as { error?: string };
  return {
    status: res.status(),
    error: body.error ?? "",
    setCookie: res
      .headersArray()
      .filter((h) => h.name.toLowerCase() === "set-cookie")
      .map((h) => h.value),
  };
}

test("a nonce this hub never issued is refused, and mints nothing", async ({ request }) => {
  // A perfectly valid signature over a nonce the hub's challenge store has
  // never held. The event is otherwise the hub's own template — so this is
  // testing the nonce and only the nonce.
  const event = signTemplate(KEYS.linked.secret, await getTemplate(request), {
    challenge: "f".repeat(64),
  });
  const res = await verify(request, event);

  expect(res.status).toBe(401);
  expect(res.error).toBe("unknown_challenge");
  expect(res.setCookie.some((c) => c.startsWith(`${SESSION_COOKIE}=`))).toBe(false);
});

test("a nonce that has outlived its window is refused as expired, not as unknown", async ({
  request,
}) => {
  // The one slow test in the harness, and deliberately so. The hub's TTL is a
  // module constant with no env seam, and the distinction that matters —
  // `challenge_expired` versus `unknown_challenge`, which is what tells a
  // member to click again rather than to go find their operator — only exists
  // on the far side of five real minutes. The alternative was to not test it in
  // a browser at all.
  test.setTimeout(CHALLENGE_TTL_MS + 180_000);

  const tpl = await getTemplate(request);
  await new Promise((r) => setTimeout(r, CHALLENGE_TTL_MS + 5_000));
  // Signed NOW, against a nonce issued five minutes ago: fresh `created_at`,
  // dead nonce. That is the only combination that reaches step 6 at all.
  const res = await verify(request, signTemplate(KEYS.linked.secret, tpl));

  expect(res.status).toBe(401);
  expect(res.error).toBe("challenge_expired");
  expect(res.setCookie.some((c) => c.startsWith(`${SESSION_COOKIE}=`))).toBe(false);
});

test("an unlinked key is refused, and the page names both remedies", async ({ context, page }) => {
  await installSigner(context, KEYS.neverLinked.secret);
  await openLoginWithSigner(page);
  await page.locator(BUTTON).click();

  // The whole sentence, on screen, beside the button. This is the design
  // note's §4 dead end and the single most likely first-run outcome.
  await expect(page.locator(STATUS)).toHaveText(UNKNOWN_PUBKEY_MESSAGE, { timeout: 20_000 });
  await expect(page.locator(STATUS)).toHaveAttribute("data-tone", "error");

  // Re-armed, not wedged — a refusal has to leave the member able to try again.
  await expect(page.locator(BUTTON)).toBeEnabled();
  expect(page.url()).toBe(`${HUB_URL}/login`);
  expect(await sessionCookie(context)).toBeUndefined();
});

test("a key unlinked after login no longer opens the door", async ({ context, page }) => {
  await installSigner(context, KEYS.linkedForUnlink.secret);
  await openLoginWithSigner(page);
  await page.locator(BUTTON).click();
  await page.waitForURL(`${HUB_URL}${POST_LOGIN}`, { timeout: 20_000 });

  // Unlink through the account API the way the account SPA does — a same-origin
  // `fetch` from the page, carrying the session cookie and the double-submit
  // `__csrf` token read from `/api/me` (the CSRF cookie is HttpOnly, so the
  // body is the only place a client can get it).
  const unlinked = await page.evaluate(async (pubkey) => {
    const me = (await (await fetch("/api/me", { credentials: "same-origin" })).json()) as {
      csrf: string;
    };
    const res = await fetch("/api/account/pubkeys/unlink", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ pubkey, __csrf: me.csrf }),
    });
    return { status: res.status, body: await res.json() };
  }, KEYS.linkedForUnlink.pubkey);
  expect(unlinked.status, JSON.stringify(unlinked.body)).toBe(200);
  expect(unlinked.body).toMatchObject({ unlinked: true });

  // Drop the session so the next attempt has to come through the door again.
  // (Unlink deliberately does NOT revoke the session it was made from — hub's
  // own comment says so — so leaving it would prove nothing about the door.)
  await context.clearCookies();

  await openLoginWithSigner(page);
  await page.locator(BUTTON).click();
  await expect(page.locator(STATUS)).toHaveText(UNKNOWN_PUBKEY_MESSAGE, { timeout: 20_000 });
  expect(await sessionCookie(context)).toBeUndefined();
});
