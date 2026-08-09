/**
 * The narrated walkthrough: a screen recording of the app being driven, paced
 * so each on-screen state lasts exactly as long as the narration that
 * describes it.
 *
 * Narration is synthesised FIRST (see `narrate/`), which yields a timing file.
 * This spec reads that file and holds each step for its segment's duration, so
 * the finished recording and the voice track line up without hand-editing. If
 * a step's actions take longer than its narration, the spec says so in the
 * console rather than silently drifting.
 *
 * Not a test — it asserts only enough to fail loudly if the app isn't in the
 * state the narration claims. Correctness lives in `transcription.spec.ts`.
 */
import { expect, test } from "@playwright/test";
import { readFileSync, writeFileSync } from "fs";

const VAULT_URL = process.env.E2E_VAULT_URL ?? "http://localhost:8080/vault/demo";
const VAULT_TOKEN = process.env.E2E_VAULT_TOKEN ?? "e2e-scratch-token-not-a-secret";
const TIMING = process.env.E2E_TIMING ?? "/e2e/narrate/tour_timing.json";

type Seg = { id: string; step: string; seconds: number; startsAt: number };

function vaultIdFromUrl(url: string): string {
  return url.replace(/^https?:\/\//, "").replace(/[^\w.-]+/g, "_");
}

test("walkthrough", async ({ page }) => {
  const segs: Seg[] = JSON.parse(readFileSync(TIMING, "utf8"));
  const by = (step: string) => segs.find((s) => s.step === step)!;
  const total = segs.reduce((a, s) => a + s.seconds, 0);
  test.setTimeout(Math.ceil(total * 1000) + 120_000);

  const vaultId = vaultIdFromUrl(VAULT_URL);
  await page.addInitScript(
    ([id, url, token]) => {
      const now = new Date().toISOString();
      localStorage.setItem("lens:vaults", JSON.stringify({
        [id]: { id, url, name: "demo", issuer: new URL(url).origin,
                clientId: "e2e-harness", scope: "vault:demo:write",
                addedAt: now, lastUsedAt: now },
      }));
      localStorage.setItem("lens:active_vault", id);
      localStorage.setItem(`lens:token:${id}`, JSON.stringify({
        accessToken: token, scope: "vault:demo:write", vault: "demo",
      }));
    },
    [vaultId, VAULT_URL, VAULT_TOKEN] as const,
  );

  // Everything before this point is browser startup and would appear as dead
  // air at the head of the recording. Record when the tour actually begins so
  // the muxing step can trim exactly that much off.
  const contextStart = Date.now();
  await page.goto("/new");
  const record = page.getByRole("button", { name: "Record voice memo" });
  await expect(record).toBeVisible({ timeout: 30_000 });
  const tourStart = Date.now();

  /** Hold the current screen until this segment's narration would have ended. */
  async function hold(step: string, startedAt: number) {
    const seg = by(step);
    const spent = Date.now() - startedAt;
    const remaining = Math.round(seg.seconds * 1000) - spent;
    if (remaining < 0) {
      console.warn(`[pace] step "${step}" overran its narration by ${-remaining}ms`);
      return;
    }
    await page.waitForTimeout(remaining);
  }

  /** Drift the cursor somewhere, so the eye has something to follow. */
  async function glideTo(locator: ReturnType<typeof page.locator>) {
    const box = await locator.boundingBox();
    if (box) await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 28 });
  }

  // 01 — open
  let t = Date.now();
  await hold("open", t);

  // 02 — the microphone, which is the whole point
  t = Date.now();
  await glideTo(record);
  await hold("point_mic", t);

  // 03 — the explanation, held on the same screen
  t = Date.now();
  await hold("explain", t);

  // 04 — record. The fake device loops the fixture, so the take is however
  // long this segment's narration is.
  t = Date.now();
  await record.click();
  const stop = page.getByRole("button", { name: /Recording —.*stop/ });
  await expect(stop).toBeVisible({ timeout: 15_000 });
  await hold("record", t);

  // 05 — stop
  t = Date.now();
  await glideTo(stop);
  await stop.click();
  await expect(page.getByText(/Recorded \d\d:\d\d/)).toBeVisible({ timeout: 15_000 });
  await hold("stop", t);

  // 06 — the one-time audio-retention question
  t = Date.now();
  const keep = page.getByRole("button", { name: "Keep my recordings" });
  if (await keep.isVisible().catch(() => false)) {
    await glideTo(keep);
    await keep.click();
  }
  await hold("retention", t);

  // 07 — save; this is what uploads the audio and triggers transcription
  t = Date.now();
  const create = page.getByRole("button", { name: "Create" });
  await glideTo(create);
  await create.click();
  await hold("save", t);

  // 08 — the transcribing state
  t = Date.now();
  await hold("transcribing", t);

  // 09 — the transcript itself
  t = Date.now();
  await expect(page.getByText(/quick brown fox/i)).toBeVisible({ timeout: 120_000 });
  await hold("transcript", t);

  // 10 — close
  t = Date.now();
  await hold("close", t);

  writeFileSync(
    process.env.E2E_OFFSET_OUT ?? "/e2e/artifacts/walkthrough-offset.json",
    JSON.stringify({ preRollMs: tourStart - contextStart, tourMs: Date.now() - tourStart }, null, 1),
  );
});
