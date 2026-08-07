import { defineConfig, devices } from "@playwright/test";

/**
 * Harness config for the containerised Parachute e2e stack.
 *
 * `video: "on"` is deliberate and differs from most suites' "retain-on-failure":
 * the video IS the deliverable here, not a debugging aid. Every PR is expected
 * to carry one showing the change working, so a green run has to produce a
 * file too.
 */
export default defineConfig({
  testDir: "./specs",
  // One worker: the stack is a single vault with a single transcription
  // worker, so parallel specs would contend for it and produce flaky timings
  // that look like product bugs.
  workers: 1,
  reporter: [["list"], ["html", { outputFolder: "artifacts/report", open: "never" }]],
  outputDir: "artifacts/output",
  timeout: 180_000,
  use: {
    baseURL: process.env.E2E_APP_URL ?? "http://app:8080",
    video: { mode: "on", size: { width: 1280, height: 720 } },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    ...devices["Desktop Chrome"],
    launchOptions: {
      args: [
        // Feed a known WAV to getUserMedia instead of a real microphone, and
        // auto-grant the permission prompt. This exercises the genuine
        // getUserMedia + MediaRecorder path — nothing is stubbed in the app.
        // The file must live INSIDE this container: colima only mounts $HOME
        // from the host, and Chromium reads it from its own filesystem.
        "--use-fake-ui-for-media-stream",
        "--use-fake-device-for-media-stream",
        `--use-file-for-fake-audio-capture=${process.env.E2E_AUDIO_FIXTURE ?? "/e2e/fixtures/spoken-phrase.wav"}`,
        "--autoplay-policy=no-user-gesture-required",
        // `getUserMedia` is gated on a SECURE CONTEXT, and `http://app:8080`
        // over the compose network is neither HTTPS nor localhost. Without
        // this Chromium hides `navigator.mediaDevices` entirely and the app
        // honestly reports "Microphone is not available in this browser" —
        // which looks exactly like the bug under test and isn't.
        //
        // `--unsafely-treat-insecure-origin-as-secure` did NOT work here
        // (tried; mediaDevices stayed undefined). What does work is making
        // the ORIGIN literally localhost, which Chromium always treats as
        // potentially trustworthy, and pointing localhost's resolution at
        // the app container. The secure-context decision is made on the
        // origin's hostname, not on the address it resolves to.
        //
        // Nothing in the product is stubbed or relaxed by this — it only
        // changes which host the browser dials for the name `localhost`.
        `--host-resolver-rules=MAP localhost ${process.env.E2E_APP_HOST ?? "app"}`,
      ],
    },
  },
});
