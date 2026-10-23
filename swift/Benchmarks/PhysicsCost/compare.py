"""Compare the host probe's raw PCM16 captures (requires NumPy)."""
import glob
import json
import sys

import numpy as np

reference, candidate = sys.argv[1:3]
rows = []
for path in sorted(glob.glob(reference + "-*.pcm")):
    other = candidate + path[len(reference):]
    baseline = np.fromfile(path, dtype=np.int16).astype(float)
    proposed = np.fromfile(other, dtype=np.int16).astype(float)
    if len(baseline) != 88200 or len(proposed) != 88200:
        raise SystemExit(f"Incomplete two-second capture: {path} or {other}")
    rpm = int(path.split("-")[-2])

    def metrics(samples):
        count = 65536
        window = samples[-count:] * np.hanning(count)
        power = abs(np.fft.rfft(window)) ** 2
        frequencies = np.fft.rfftfreq(count, 1 / 44100)
        target = rpm / 15
        firing = (frequencies > target * 0.9) & (frequencies < target * 1.1)
        lower = (frequencies > 40) & (frequencies < 600)
        return dict(
            rms=float(np.sqrt(np.mean(samples * samples))),
            peak=float(max(abs(samples))),
            clipped=int(sum(abs(samples) >= 32767)),
            firing=float(frequencies[firing][np.argmax(power[firing])]),
            dominant=float(frequencies[lower][np.argmax(power[lower])]),
        )

    before, after = metrics(baseline), metrics(proposed)
    rows.append(dict(
        case=path[len(reference) + 1:], reference=before, candidate=after,
        rms_change_pct=100 * (after["rms"] / before["rms"] - 1),
    ))

print(json.dumps(rows, indent=2))
failures = []
for row in rows:
    rpm = int(row["case"].split("-")[1])
    before, after = row["reference"], row["candidate"]
    if not (abs(after["firing"] - rpm / 15) <= (rpm / 15) * 0.03
            and abs(after["dominant"] - before["dominant"]) <= 44100 / 65536
            and abs(row["rms_change_pct"]) <= 1
            and after["rms"] > 100 and after["clipped"] == 0):
        failures.append(row["case"])
if len(rows) != 18 or failures:
    raise SystemExit(f"Output comparison failed: {len(rows)} cases; {failures}")
