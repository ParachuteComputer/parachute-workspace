# narrate — the voiced walkthrough

Turns a finished piece of work into a **screen recording of the app being
driven, narrated as it goes**. Not a slideshow of summary cards: the artifact
has to show the thing working, or it isn't evidence of anything.

## How the sync works

Narration is synthesised **first**. That produces `tour_timing.json` — a
duration per segment. The Playwright tour (`../specs/walkthrough.spec.ts`) reads
that file and holds each on-screen state for exactly its segment's duration, so
picture and voice line up without hand-editing, and regenerate together when the
code changes.

Doing it the other way round — record, then narrate to fit — makes every code
change a re-edit, which is how a walkthrough quietly stops being produced.

If a step's actions outrun its narration the spec logs a `[pace]` warning rather
than drifting silently.

```
# 1. write the script
$EDITOR tour.json

# 2. synthesise (container: kokoro + espeak, nothing installed on the host)
docker build -t uni-narrate .
docker run --rm -v "$PWD:/work" -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  uni-narrate python synth_tour.py

# 3. record the paced tour (needs the e2e stack up — see ../README.md)
docker run --rm --network parachute-e2e_default -v "$(cd .. && pwd):/e2e" -w /e2e \
  -e E2E_APP_URL=http://localhost:8080 -e E2E_APP_HOST=app \
  -e E2E_VAULT_URL=http://localhost:8080/vault/demo \
  mcr.microsoft.com/playwright:v1.58.2-noble \
  sh -c 'npm i --silent && npx playwright test walkthrough'

# 4. mux, trimming the browser-startup pre-roll the spec measured for you
ffmpeg -ss "$(python3 -c 'import json;print(json.load(open("../artifacts/walkthrough-offset.json"))["preRollMs"]/1000)')" \
  -i ../artifacts/output/walkthrough-walkthrough/video.webm -i tour_narration.wav \
  -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -crf 22 -c:a aac -shortest \
  -map_metadata -1 -movflags +faststart walkthrough.mp4
```

## The voice

`af_heart`. Chosen on Kokoro's own model card, which grades every voice: it is
the only one graded **A** (`af_bella` is A-, `af_nicole` and `bf_emma` B-, the
rest C+ or below). Narration like this is dense with terms a weaker voice
mangles — `whisper-cpp`, `ffmpeg`, `getUserMedia` — and a garbled one costs the
viewer a re-listen, which defeats the point. It reads warm and even rather than
announcer-ish. Swapping it is a one-line change; the script is plain text.

## Gotchas

- **The relay rejects webm and rejects mp4 carrying metadata.** Playwright
  records webm, so a share always needs
  `ffmpeg -map_metadata -1 -map_chapters -1 -fflags +bitexact`.
- **Trim the pre-roll.** Playwright starts recording at context creation, before
  navigation, so the head of the file is dead air. The spec writes the measured
  offset to `artifacts/walkthrough-offset.json` — use it rather than eyeballing.
- **Check the sync, don't assume it.** Sample a frame at a segment's midpoint
  and confirm the screen shows what the voice is describing. The arithmetic
  being right is not the same as the video being right.
