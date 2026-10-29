"""Numerical contract checks for face SDF lighting and the toon color composition.

These exercise the equations on CPU; they do not replace Unity shader compilation.
Run: python -m unittest discover -s Tests -p '*_test.py'
"""
import math
import unittest


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def normalize(value):
    length = math.sqrt(dot(value, value))
    return tuple(x / length for x in value)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def face_sdf(light, field, mirrored, softness=0.05,
             forward=(0, 0, 1), right=(1, 0, 0)):
    forward = normalize(forward) if dot(forward, forward) > 1e-6 else (0, 0, 1)
    right = tuple(r - f * dot(right, forward) for r, f in zip(right, forward))
    if dot(right, right) < 1e-6:
        up = (0, 1, 0) if abs(forward[1]) < 0.99 else (1, 0, 0)
        right = cross(up, forward)
    right = normalize(right)
    planar = (dot(light, right), dot(light, forward))
    planar = normalize(planar) if dot(planar, planar) > 1e-6 else (0, 1)
    angle = math.acos(max(-1, min(1, planar[1]))) / math.pi
    sample = field if planar[0] >= 0 else mirrored
    softness = max(0.0001, min(0.49, softness))
    sample = softness + (1 - 2 * softness) * max(0, min(1, sample))
    t = max(0, min(1, (sample - angle + softness) / (2 * softness)))
    return t * t * (3 - 2 * t)


class LightingContractTests(unittest.TestCase):
    def test_front_and_back_are_uniform_even_for_extreme_sdf_texels(self):
        for sample in (0, 0.2, 0.5, 0.8, 1):
            for softness in (0, 0.05, 0.5):
                self.assertAlmostEqual(face_sdf((0, 0, 1), sample, sample, softness), 1)
                self.assertAlmostEqual(face_sdf((0, 0, -1), sample, sample, softness), 0)

    def test_left_and_right_select_opposite_sdf_samples(self):
        self.assertEqual(face_sdf((1, 0, 0), 0.75, 0.25), 1)
        self.assertEqual(face_sdf((-1, 0, 0), 0.75, 0.25), 0)

    def test_light_and_head_rotating_together_preserve_shading(self):
        for degrees in range(0, 360, 15):
            angle = math.radians(degrees)
            rotate = lambda v: (v[0] * math.cos(angle) + v[2] * math.sin(angle),
                                v[1], -v[0] * math.sin(angle) + v[2] * math.cos(angle))
            light = normalize((0.3, 0.2, -0.7))
            self.assertAlmostEqual(
                face_sdf(light, 0.72, 0.23),
                face_sdf(rotate(light), 0.72, 0.23,
                         forward=rotate((0, 0, 1)), right=rotate((1, 0, 0))))

    def test_invalid_basis_and_vertical_light_stay_finite(self):
        for forward, right in (((0, 0, 0), (0, 0, 0)), ((0, 1, 0), (0, 2, 0))):
            result = face_sdf((0, 1, 0), 0.5, 0.5, forward=forward, right=right)
            self.assertTrue(math.isfinite(result))
            self.assertGreaterEqual(result, 0)
            self.assertLessEqual(result, 1)

    def test_material_colored_light_preserves_legacy_composition(self):
        for albedo in (0, 0.1, 0.6, 1, 2):
            for indirect, main, additional in ((0.2, 0.7, 0.1), (0.8, 0.1, 0.1), (0, 0, 0)):
                old_result = albedo * max(indirect, main + additional) + 0.3
                new_result = max(albedo * indirect, albedo * main + albedo * additional) + 0.3
                self.assertAlmostEqual(old_result, new_result)


if __name__ == '__main__':
    unittest.main()
