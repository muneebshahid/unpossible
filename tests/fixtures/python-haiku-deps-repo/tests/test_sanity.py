import unittest

import tests.bootstrap  # noqa: F401


class TestSanity(unittest.TestCase):
    def test_sanity(self) -> None:
        self.assertTrue(True)

