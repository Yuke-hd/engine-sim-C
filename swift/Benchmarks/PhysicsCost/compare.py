"""Compare the host probe's raw PCM16 captures (requires NumPy)."""
import glob
import json
import sys

import numpy as np

SAMPLE_RATE = 44100
FFT_COUNT = 65536
BIN_HZ = SAMPLE_RATE / FFT_COUNT


def metrics(samples, rpm):
    count = FFT_COUNT
    window = samples[-count:] - np.mean(samples[-count:])
    power = abs(np.fft.rfft(window * np.hanning(count))) ** 2
    frequencies = np.fft.rfftfreq(count, 1 / SAMPLE_RATE)
    target = rpm / 15
    firing = (frequencies > target * 0.9) & (frequencies < target * 1.1)
    firing_band = abs(frequencies - target) <= 2 * BIN_HZ
    lower = (frequencies > 40) & (frequencies < 600)
    return dict(
        rms=float(np.sqrt(np.mean(samples * samples))),
        peak=float(max(abs(samples))),
        clipped=int(sum(abs(samples) >= 32767)),
        firing=float(frequencies[firing][np.argmax(power[firing])]),
        firing_power=float(sum(power[firing_band]) / sum(power)),
        dominant=float(frequencies[lower][np.argmax(power[lower])]),
    )


def compare(before, after, rpm):
    failures = []
    if abs(after["firing"] - rpm / 15) > (rpm / 15) * 0.03:
        failures.append("firing frequency outside expected range")
    if abs(after["firing"] - before["firing"]) > BIN_HZ:
        failures.append("firing frequency changed")
    if before["firing_power"] <= 0 or abs(after["firing_power"] / before["firing_power"] - 1) > 0.05:
        failures.append("relative firing power changed")
    if abs(after["dominant"] - before["dominant"]) > BIN_HZ:
        failures.append("dominant frequency changed")
    if before["rms"] <= 0 or abs(after["rms"] / before["rms"] - 1) > 0.01:
        failures.append("RMS changed")
    if after["rms"] <= 100 or after["clipped"] != 0:
        failures.append("silence or clipping")
    return failures


def main(reference, candidate):
    rows, failures = [], {}
    for path in sorted(glob.glob(reference + "-*.pcm")):
        other = candidate + path[len(reference):]
        baseline = np.fromfile(path, dtype=np.int16).astype(float)
        proposed = np.fromfile(other, dtype=np.int16).astype(float)
        if len(baseline) != 88200 or len(proposed) != 88200:
            raise SystemExit(f"Incomplete two-second capture: {path} or {other}")
        rpm = int(path.split("-")[-2])
        before, after = metrics(baseline, rpm), metrics(proposed, rpm)
        case = path[len(reference) + 1:]
        rows.append(dict(
            case=case, reference=before, candidate=after,
            rms_change_pct=100 * (after["rms"] / before["rms"] - 1),
            firing_power_change_pct=100 * (after["firing_power"] / before["firing_power"] - 1),
        ))
        reasons = compare(before, after, rpm)
        if reasons:
            failures[case] = reasons
    print(json.dumps(rows, indent=2))
    if len(rows) != 18 or failures:
        raise SystemExit(f"Output comparison failed: {len(rows)} cases; {failures}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
