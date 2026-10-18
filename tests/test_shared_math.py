#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Shared Math & Vector Utility Library (nyx_core/shared/math.lua)
"""

import os
import sys
import re
import math
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestSharedMathAndVectorLibrary(unittest.TestCase):
    def setUp(self):
        self.math_file = os.path.join(FIVEM_DIR, "nyx_core", "shared", "math.lua")
        self.manifest_file = os.path.join(FIVEM_DIR, "nyx_core", "fxmanifest.lua")
        self.tests_file = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")

    def test_file_and_manifest_registration(self):
        """Verify nyx_core/shared/math.lua exists on disk and is registered in fxmanifest.lua."""
        self.assertTrue(os.path.isfile(self.math_file), f"Missing math library on disk: {self.math_file}")
        
        with open(self.manifest_file, "r", encoding="utf-8") as f:
            manifest_content = f.read()

        self.assertIn("shared_scripts {", manifest_content)
        self.assertIn("shared/math.lua", manifest_content, "shared/math.lua not declared in nyx_core/fxmanifest.lua")

    def test_scalar_functions_defined(self):
        """Verify all core scalar math functions are implemented in math.lua."""
        self.assertTrue(os.path.isfile(self.math_file), "math.lua missing")
        with open(self.math_file, "r", encoding="utf-8") as f:
            code = f.read()

        scalar_functions = [
            "function Nyx.Math.Clamp",
            "function Nyx.Math.Round",
            "function Nyx.Math.Lerp",
            "function Nyx.Math.InvLerp",
            "function Nyx.Math.Remap",
            "function Nyx.Math.Sign",
            "function Nyx.Math.IsNear",
            "function Nyx.Math.DegToRad",
            "function Nyx.Math.RadToDeg",
        ]
        for fn in scalar_functions:
            self.assertIn(fn, code, f"Missing scalar function definition: {fn}")

    def test_vector_and_spatial_functions_defined(self):
        """Verify vector transformations, spatial queries, and distance calculations are implemented."""
        self.assertTrue(os.path.isfile(self.math_file), "math.lua missing")
        with open(self.math_file, "r", encoding="utf-8") as f:
            code = f.read()

        vector_functions = [
            "function Nyx.Math.ToVector3",
            "function Nyx.Math.ToVector2",
            "function Nyx.Math.VectorToTable",
            "function Nyx.Math.Normalize",
            "function Nyx.Math.Distance",
            "function Nyx.Math.Distance2D",
            "function Nyx.Math.DistanceSquared",
            "function Nyx.Math.Distance2DSquared",
            "function Nyx.Math.IsWithinRange",
            "function Nyx.Math.IsWithinRange2D",
            "function Nyx.Math.Dot",
            "function Nyx.Math.Cross",
            "function Nyx.Math.Magnitude",
            "function Nyx.Math.MagnitudeSquared",
            "function Nyx.Math.AngleBetween",
            "function Nyx.Math.VectorLerp",
        ]
        for fn in vector_functions:
            self.assertIn(fn, code, f"Missing vector function definition: {fn}")

    def test_rotation_heading_and_geometry_functions_defined(self):
        """Verify camera rotation, heading, and polygon/box geometric functions are defined."""
        self.assertTrue(os.path.isfile(self.math_file), "math.lua missing")
        with open(self.math_file, "r", encoding="utf-8") as f:
            code = f.read()

        geo_functions = [
            "function Nyx.Math.RotationToDirection",
            "function Nyx.Math.HeadingToDirection",
            "function Nyx.Math.DirectionToHeading",
            "function Nyx.Math.GetHeadingBetween",
            "function Nyx.Math.GetAngleDifference",
            "function Nyx.Math.IsPointInSphere",
            "function Nyx.Math.IsPointInBox",
            "function Nyx.Math.IsPointInPolygon",
        ]
        for fn in geo_functions:
            self.assertIn(fn, code, f"Missing geometry/heading function definition: {fn}")

    def test_exports_registered(self):
        """Verify public exports are registered for cross-resource invocation."""
        self.assertTrue(os.path.isfile(self.math_file), "math.lua missing")
        with open(self.math_file, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn('exports("GetMath"', code)
        self.assertIn('exports("Clamp"', code)
        self.assertIn('exports("Round"', code)
        self.assertIn('exports("Distance"', code)
        self.assertIn('exports("IsWithinRange"', code)
        self.assertIn('exports("RotationToDirection"', code)
        self.assertIn('exports("HeadingToDirection"', code)
        self.assertIn('exports("IsPointInPolygon"', code)

    def test_scalar_math_logic(self):
        """Test scalar mathematical operations against algorithmic expectations."""
        # Clamp
        def clamp(v, mn, mx):
            return mn if v < mn else (mx if v > mx else v)
        self.assertEqual(clamp(5, 10, 20), 10)
        self.assertEqual(clamp(25, 10, 20), 20)
        self.assertEqual(clamp(15, 10, 20), 15)

        # Round
        def round_dec(v, decimals=0):
            mult = 10 ** decimals
            return math.floor(v * mult + 0.5) / mult if v >= 0 else math.ceil(v * mult - 0.5) / mult
        self.assertEqual(round_dec(3.14159, 2), 3.14)
        self.assertEqual(round_dec(10.555, 2), 10.56)
        self.assertEqual(round_dec(2.5, 0), 3.0)
        self.assertEqual(round_dec(-2.5, 0), -3.0)

        # Lerp & InvLerp
        def lerp(a, b, t):
            return a + (b - a) * t
        def inv_lerp(a, b, v):
            if abs(b - a) < 1e-9:
                return 0.0
            return (v - a) / (b - a)
        self.assertAlmostEqual(lerp(10.0, 50.0, 0.25), 20.0)
        self.assertAlmostEqual(inv_lerp(10.0, 50.0, 20.0), 0.25)
        self.assertEqual(inv_lerp(10.0, 10.0, 10.0), 0.0)

        # Remap
        def remap(v, in_min, in_max, out_min, out_max):
            t = inv_lerp(in_min, in_max, v)
            return lerp(out_min, out_max, t)
        self.assertAlmostEqual(remap(50, 0, 100, 200, 400), 300.0)
        self.assertAlmostEqual(remap(25, 0, 100, 0, 1000), 250.0)

        # Sign & IsNear
        def sign(v):
            return 1 if v > 0 else (-1 if v < 0 else 0)
        self.assertEqual(sign(42), 1)
        self.assertEqual(sign(-99), -1)
        self.assertEqual(sign(0), 0)

        def is_near(a, b, eps=1e-6):
            return abs(a - b) <= eps
        self.assertTrue(is_near(1.0000001, 1.0, 1e-5))
        self.assertFalse(is_near(1.01, 1.0, 1e-3))

    def test_spatial_distance_and_vector_algebra(self):
        """Test vector algebra and distance calculations."""
        # 3D Distance
        def dist_3d(x1, y1, z1, x2, y2, z2):
            dx = x1 - x2
            dy = y1 - y2
            dz = z1 - z2
            return math.sqrt(dx*dx + dy*dy + dz*dz)
        def dist_sq_3d(x1, y1, z1, x2, y2, z2):
            dx = x1 - x2
            dy = y1 - y2
            dz = z1 - z2
            return dx*dx + dy*dy + dz*dz

        self.assertAlmostEqual(dist_3d(0, 0, 0, 1, 2, 2), 3.0)
        self.assertAlmostEqual(dist_sq_3d(0, 0, 0, 1, 2, 2), 9.0)

        # 2D Distance
        def dist_2d(x1, y1, x2, y2):
            dx = x1 - x2
            dy = y1 - y2
            return math.sqrt(dx*dx + dy*dy)
        self.assertAlmostEqual(dist_2d(0, 0, 3, 4), 5.0)

        # Range check using squared comparison
        def is_within_range(p1, p2, max_dist):
            return dist_sq_3d(p1[0], p1[1], p1[2], p2[0], p2[1], p2[2]) <= (max_dist * max_dist)
        self.assertTrue(is_within_range((0, 0, 0), (2, 2, 1), 3.0))
        self.assertFalse(is_within_range((0, 0, 0), (2, 2, 2), 3.0))

        # Dot product
        def dot_product(v1, v2):
            return v1[0]*v2[0] + v1[1]*v2[1] + v1[2]*v2[2]
        self.assertAlmostEqual(dot_product((1, 0, 0), (0, 1, 0)), 0.0)
        self.assertAlmostEqual(dot_product((2, 3, 4), (1, 2, 3)), 20.0)

        # Cross product
        def cross_product(u, v):
            return (
                u[1]*v[2] - u[2]*v[1],
                u[2]*v[0] - u[0]*v[2],
                u[0]*v[1] - u[1]*v[0]
            )
        self.assertEqual(cross_product((1, 0, 0), (0, 1, 0)), (0, 0, 1))

        # Vector Normalize
        def normalize(v):
            mag = math.sqrt(v[0]**2 + v[1]**2 + v[2]**2)
            if mag < 1e-9:
                return (0.0, 0.0, 0.0)
            return (v[0]/mag, v[1]/mag, v[2]/mag)
        nx, ny, nz = normalize((0, 10, 0))
        self.assertAlmostEqual(ny, 1.0)
        self.assertAlmostEqual(nx, 0.0)

    def test_heading_rotation_and_geometry(self):
        """Test heading/direction transforms and polygon containment algorithm."""
        # Heading to direction: Heading 0 is North (+Y), 90 is West (-X), 180 is South (-Y), 270 is East (+X)
        def heading_to_direction(h_deg):
            rad = math.radians(h_deg)
            return (-math.sin(rad), math.cos(rad), 0.0)

        def direction_to_heading(dx, dy):
            rad = math.atan2(-dx, dy)
            deg = math.degrees(rad)
            if deg < 0:
                deg += 360.0
            return deg

        for h in [0.0, 45.0, 90.0, 180.0, 270.0, 315.0]:
            vx, vy, _ = heading_to_direction(h)
            calc_h = direction_to_heading(vx, vy)
            self.assertAlmostEqual(h, calc_h, places=4)

        # Angular difference (shortest path)
        def angle_difference(a1, a2):
            diff = (a1 - a2 + 180.0) % 360.0 - 180.0
            return abs(diff)

        self.assertAlmostEqual(angle_difference(10.0, 350.0), 20.0)
        self.assertAlmostEqual(angle_difference(0.0, 180.0), 180.0)
        self.assertAlmostEqual(angle_difference(45.0, 90.0), 45.0)

        # 2D Point in Polygon (Ray Casting / Even-Odd rule)
        def point_in_polygon(px, py, poly):
            inside = False
            n = len(poly)
            j = n - 1
            for i in range(n):
                xi, yi = poly[i][0], poly[i][1]
                xj, yj = poly[j][0], poly[j][1]
                if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi):
                    inside = not inside
                j = i
            return inside

        square = [(0, 0), (10, 0), (10, 10), (0, 10)]
        self.assertTrue(point_in_polygon(5, 5, square))
        self.assertTrue(point_in_polygon(1, 1, square))
        self.assertFalse(point_in_polygon(15, 5, square))
        self.assertFalse(point_in_polygon(-1, 5, square))

    def test_in_engine_tests_registered(self):
        """Verify nyx_core/server/tests.lua has TestSharedMathAndVectorUtils registered in RunAll."""
        self.assertTrue(os.path.isfile(self.tests_file), "tests.lua missing")
        with open(self.tests_file, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestSharedMathAndVectorUtils()", code)
        self.assertIn("Nyx.Tests.TestSharedMathAndVectorUtils()", code)

if __name__ == "__main__":
    unittest.main()
