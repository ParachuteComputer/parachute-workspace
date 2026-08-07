/**
 * Voice transcription, end to end, in a browser.
 *
 * What this proves that a unit test cannot: a person opens the app, sees a
 * microphone, records, and a transcript comes back. The bug this was written
 * for (parachute-vault: `capability.ts` had no `whisper-cpp` branch) was
 * invisible to the vault's own test suite because the WORKER was fine — only
 * the capability flag lied, and the only thing that reads that flag is the UI.
 *
 * Run it against a vault image built from `main` and it fails at the first
 * assertion, rendering "Voice transcription isn't enabled on this vault".
 * That paired run is the evidence; a green run on its own is not.
 */
import { expect, test } from "@playwright/test";

const VAULT_URL = process.env.E2E_VAULT_URL ?? "http://app:8080/vault/demo";
const VAULT_TOKEN = process.env.E2E_VAULT_TOKEN ?? "e2e-scratch-token-not-a-secret";

/** Mirrors `vaultIdFromUrl` in @openparachute/surface-client: strip the
 *  scheme, collapse every run of non-`[\w.-]` characters to a single `_`. */
function vaultIdFromUrl(url: string): string {
  return url.replace(/^https?:\/\//, "").replace(/[^\w.-]+/g, "_");
}

test("a recording becomes a transcript", async ({ page }) => {
  const vaultId = vaultIdFromUrl(VAULT_URL);

  // Seed the app's connected-vault state directly instead of driving OAuth.
  // The harness has no hub by design, and `VAULT_AUTH_TOKEN` is a
  // server-wide bearer — so the honest shortcut is to hand the app the
  // token it would have ended up holding anyway. Everything downstream of
  // this (the capability fetch, the upload, the transcript) is the real
  // product path.
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
      // NOTE: active_vault is a RAW string, not JSON — writing JSON here
      // silently yields no active vault and a blank app.
      localStorage.setItem("lens:active_vault", id);
      localStorage.setItem(
        `lens:token:${id}`,
        JSON.stringify({ accessToken: token, scope: "vault:demo:write", vault: "demo" }),
      );
    },
    [vaultId, VAULT_URL, VAULT_TOKEN] as const,
  );

  await page.goto("/new");

  const record = page.getByRole("button", { name: "Record voice memo" });
  const unavailable = page.getByTestId("voice-unavailable");

  // Wait for the capability fetch to SETTLE before judging it. Asserting
  // `unavailable` has count 0 straight after navigation passes trivially —
  // the element hasn't rendered yet either way — which made this spec fail
  // on the unfixed build for the wrong reason. Waiting for whichever of the
  // two states appears first turns a race into a real observation.
  await expect(record.or(unavailable).first()).toBeVisible({ timeout: 30_000 });

  // The assertion that carries the fix. `voice-unavailable` is what the app
  // renders when the vault's landing reports transcription disabled — the
  // exact symptom reported from the field.
  await expect(unavailable).toHaveCount(0);
  await expect(record).toBeVisible();

  // Guard against the harness lying to us: if Chromium can't produce a
  // supported mime type, the app renders its unsupported path and the video
  // would show a different bug than the one under test.
  const mime = await page.evaluate(() =>
    ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"].find((t) => MediaRecorder.isTypeSupported(t)),
  );
  expect(mime, "headless Chromium exposed no supported MediaRecorder mime type").toBeTruthy();

  await record.click();

  // Chromium's fake device loops the WAV; a few seconds is plenty for the
  // fixture phrase.
  const stop = page.getByRole("button", { name: /Recording —.*stop/ });
  await expect(stop).toBeVisible({ timeout: 10_000 });
  await page.waitForTimeout(5_000);
  await stop.click();

  await expect(page.getByText(/Recorded \d\d:\d\d/)).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole("switch", { name: "Transcribe this recording" })).toBeChecked();

  // A fresh vault asks once whether to keep audio after transcribing, and the
  // prompt sits between the recording and the save. Keeping the audio is the
  // choice that leaves the most evidence behind if this run needs debugging.
  const keepAudio = page.getByRole("button", { name: "Keep my recordings" });
  if (await keepAudio.isVisible().catch(() => false)) await keepAudio.click();

  // "Save to commit" — the recording only becomes an attachment on the note
  // when the note is created, and only then does the vault see
  // `attachment:created` and enqueue transcription.
  await page.getByRole("button", { name: "Create" }).click();

  // Transcription runs server-side, so the note lands first and the text
  // fills in after. tiny.en on a few seconds of speech is quick, but give a
  // cold container room.
  await expect(page.getByText(/quick brown fox/i)).toBeVisible({ timeout: 120_000 });
});
