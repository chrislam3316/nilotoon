"""Geometric checks for NiloPerspectiveCorrection.hlsl; run with Python 3, no packages.

These test the projection model, not Unity's shader compiler or GPU rendering.
"""

import math
import random
import unittest


def project(point, focal=(1.3, 1.8), shift=(0.0, 0.0), near=0.1, far=100.0):
    x, y, z = point
    depth = -z
    # D3D-style perspective depth, deliberately independent from effective depth.
    return (
        focal[0] * x + shift[0] * depth,
        focal[1] * y + shift[1] * depth,
        far / (far - near) * depth - near * far / (far - near),
        depth,
    )


def smoothstep(start, end, value):
    t = min(1.0, max(0.0, (value - start) / (end - start)))
    return t * t * (3.0 - 2.0 * t)


def corrected_clip(point, pivot, amount, focal=(1.3, 1.8), shift=(0.0, 0.0),
                   near=0.1, orthographic=False):
    """CPU model of the shader: virtual view depth, original vertex NDC depth."""
    original = project(point, focal, shift, near)
    depth, pivot_depth = -point[2], -pivot[2]
    amount = min(1.0, max(0.0, amount))
    if orthographic or amount <= 0 or depth <= near or pivot_depth <= near or original[3] <= 1e-6:
        return original
    amount *= smoothstep(near, 2.0 * near, pivot_depth)
    effective_z = point[2] + amount * (pivot[2] - point[2])
    projected = project((point[0], point[1], effective_z), focal, shift, near)
    if projected[3] <= 1e-6:
        return original
    return (projected[0], projected[1], original[2] / original[3] * projected[3], projected[3])


def ndc(clip):
    return tuple(component / clip[3] for component in clip[:3])


def perspective_interpolate(values, clip_w, weights):
    return sum(a * b / w for a, b, w in zip(values, weights, clip_w)) / sum(
        b / w for b, w in zip(weights, clip_w)
    )


def view_from_world(point, camera, yaw):
    x, y, z = (p - c for p, c in zip(point, camera))
    return (math.cos(yaw) * x - math.sin(yaw) * z, y,
            math.sin(yaw) * x + math.cos(yaw) * z)


class PerspectiveMathTests(unittest.TestCase):
    def assertVectorAlmostEqual(self, actual, expected):
        for a, b in zip(actual, expected):
            self.assertAlmostEqual(a, b, places=10)

    def test_disabled_and_negative_strength_are_exact_identity(self):
        point, pivot = (0.8, -0.3, -2.0), (0.4, 1.0, -4.0)
        for strength in (0, -1):
            self.assertEqual(corrected_clip(point, pivot, strength), project(point))

    def test_full_correction_has_equal_scale_for_near_and_far_features(self):
        pivot = (2.0, 0.6, -5.0)
        for depth in (0.3, 1.0, 5.0, 12.0):
            point = (2.7, 1.4, -depth)
            actual = ndc(corrected_clip(point, pivot, 1, shift=(0.2, -0.1)))
            self.assertVectorAlmostEqual(actual[:2], (1.3 * 2.7 / 5 + 0.2, 1.8 * 1.4 / 5 - 0.1))

    def test_off_axis_pivot_is_stationary_at_every_strength(self):
        pivot = (2.4, -1.1, -4.0)
        for strength in (0.0, 0.1, 0.5, 0.9, 1.0):
            self.assertVectorAlmostEqual(
                ndc(corrected_clip(pivot, pivot, strength, shift=(0.3, -0.4))),
                ndc(project(pivot, shift=(0.3, -0.4))),
            )

    def test_partial_correction_matches_virtual_view_depth(self):
        point, pivot = (0.9, 1.7, -2.0), (1.0, 0.3, -6.0)
        # A halfway virtual mesh lies at depth 4, including lens-shift terms.
        actual = ndc(corrected_clip(point, pivot, 0.5, shift=(0.1, 0.2)))
        self.assertVectorAlmostEqual(actual[:2], ndc(project((0.9, 1.7, -4.0), shift=(0.1, 0.2)))[:2])

    def test_original_vertex_depth_is_preserved(self):
        rng = random.Random(817)
        for _ in range(100):
            point = (rng.uniform(-2, 2), rng.uniform(-2, 2), -rng.uniform(0.3, 80))
            pivot = (1.0, -0.2, -rng.uniform(0.3, 80))
            actual = ndc(corrected_clip(point, pivot, rng.random()))
            self.assertAlmostEqual(actual[2], ndc(project(point))[2], places=12)

    def test_full_correction_uses_affine_uv_interpolation(self):
        points = ((-1.0, -1.0, -2.0), (1.0, -1.0, -4.0), (0.0, 1.0, -8.0))
        pivot, uv, weights = (0.0, 0.0, -5.0), (0.0, 1.0, 0.5), (0.2, 0.3, 0.5)
        new_w = [corrected_clip(point, pivot, 1)[3] for point in points]
        actual = perspective_interpolate(uv, new_w, weights)
        self.assertAlmostEqual(actual, sum(u * weight for u, weight in zip(uv, weights)))
        self.assertNotAlmostEqual(actual, perspective_interpolate(uv, [-point[2] for point in points], weights))

    def test_two_cameras_use_their_own_view_without_changing_world_mesh(self):
        points = ((-0.7, 1.2, 0.8), (0.9, 1.8, -0.6), (0.3, 0.4, 0.2))
        saved_points, pivot = tuple(points), (0.0, 1.0, 0.0)
        views = (((0.0, 1.0, 5.0), 0.0), ((5.0, 1.0, 0.0), math.pi / 2))
        results = []
        for camera, yaw in views:
            pivot_vs = view_from_world(pivot, camera, yaw)
            result = []
            for point in points:
                point_vs = view_from_world(point, camera, yaw)
                actual = ndc(corrected_clip(point_vs, pivot_vs, 1))[:2]
                expected = (1.3 * point_vs[0] / 5, 1.8 * point_vs[1] / 5)
                self.assertVectorAlmostEqual(actual, expected)
                result.append(actual)
            results.append(result)
        self.assertNotEqual(results[0], results[1])
        self.assertEqual(points, saved_points)

    def test_stereo_asymmetric_projection_keeps_each_eye_shift(self):
        point, pivot = (0.3, 0.5, -2.0), (0.0, 0.0, -4.0)
        left = ndc(corrected_clip(point, pivot, 1, shift=(-0.07, 0.02)))
        right = ndc(corrected_clip(point, pivot, 1, shift=(0.07, 0.02)))
        self.assertAlmostEqual(right[0] - left[0], 0.14)
        self.assertAlmostEqual(right[1], left[1])

    def test_orthographic_camera_does_not_apply_perspective_correction(self):
        point, pivot = (0.6, 0.8, -2.0), (0.0, 0.0, -4.0)
        self.assertEqual(corrected_clip(point, pivot, 1, orthographic=True), project(point))

    def test_near_plane_and_behind_camera_are_identity_and_finite(self):
        for vertex_depth, pivot_depth in ((0, 4), (-2, 4), (0.1, 4), (2, 0), (2, -1), (2, 0.1)):
            point, pivot = (0.8, 0.3, -vertex_depth), (0.0, 0.0, -pivot_depth)
            actual = corrected_clip(point, pivot, 1)
            self.assertEqual(actual, project(point))
            self.assertTrue(all(math.isfinite(value) for value in actual))

    def test_pivot_near_plane_fades_correction_continuously(self):
        point = (0.3, 0.5, -2.0)
        pivot = (0.0, 0.0, -0.15)
        # Halfway through [near, 2*near], smoothstep yields half strength.
        self.assertAlmostEqual(corrected_clip(point, pivot, 1)[3], (2.0 + 0.15) / 2)
        before = corrected_clip(point, (0.0, 0.0, -0.1), 1)
        after = corrected_clip(point, (0.0, 0.0, -0.10000001), 1)
        self.assertVectorAlmostEqual(before, after)

    def test_strength_is_clamped_and_no_finite_depth_produces_nan(self):
        point, pivot = (2.0, 0.3, -0.11), (0.0, 0.0, -80.0)
        self.assertEqual(corrected_clip(point, pivot, 10), corrected_clip(point, pivot, 1))
        for strength in (0, 0.25, 0.5, 0.75, 1):
            self.assertTrue(all(math.isfinite(value) for value in corrected_clip(point, pivot, strength)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
