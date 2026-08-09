import json, numpy as np, soundfile as sf
from kokoro import KPipeline
VOICE = "af_heart"
segs = json.load(open("tour.json"))
pipe = KPipeline(lang_code=VOICE[0])
out, cursor = [], 0.0
for s in segs:
    audio = np.concatenate([a for _, _, a in pipe(s["text"], voice=VOICE, speed=0.95)])
    audio = np.concatenate([audio, np.zeros(int(24000 * 0.5))])  # breath
    sf.write(f"tour_{s['id']}.wav", audio, 24000)
    dur = len(audio) / 24000
    out.append({"id": s["id"], "step": s["step"], "file": f"tour_{s['id']}.wav",
                "seconds": round(dur, 3), "startsAt": round(cursor, 3)})
    cursor += dur
json.dump(out, open("tour_timing.json", "w"), indent=1)
print(json.dumps(out, indent=1))
print("TOTAL", round(cursor, 1), "s")
