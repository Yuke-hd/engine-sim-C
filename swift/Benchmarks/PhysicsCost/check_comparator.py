"""Prove firing-order changes are caught even with stable RMS/dominant peaks."""
import unittest

import numpy as np

from compare import BIN_HZ, FFT_COUNT, SAMPLE_RATE, compare, metrics


class ComparatorTests(unittest.TestCase):
    def capture(self, firing_bin, firing_amplitude=500):
        time = np.arange(FFT_COUNT) / SAMPLE_RATE
        # Weak firing component under a stronger lower engine order. Its removal
        # changes whole-signal RMS by less than 1%, so the power check must catch it.
        return (10000 * np.sin(2 * np.pi * 75 * BIN_HZ * time)
                + firing_amplitude * np.sin(2 * np.pi * firing_bin * BIN_HZ * time))

    def test_unchanged_capture_passes(self):
        baseline = metrics(self.capture(149), 1500)
        self.assertEqual(compare(baseline, baseline, 1500), [])

    def test_firing_attenuation_fails_with_stable_rms_and_peak(self):
        baseline = metrics(self.capture(149), 1500)
        attenuated = metrics(self.capture(149, 100), 1500)
        self.assertLess(abs(attenuated["rms"] / baseline["rms"] - 1), 0.01)
        self.assertEqual(baseline["dominant"], attenuated["dominant"])
        self.assertEqual(compare(baseline, attenuated, 1500), ["relative firing power changed"])

    def test_two_bin_shift_fails_even_inside_expected_frequency_range(self):
        baseline = metrics(self.capture(149), 1500)
        shifted = metrics(self.capture(151), 1500)
        self.assertLess(abs(shifted["firing"] - 100), 3)
        self.assertEqual(baseline["dominant"], shifted["dominant"])
        self.assertIn("firing frequency changed", compare(baseline, shifted, 1500))


if __name__ == "__main__":
    unittest.main()
