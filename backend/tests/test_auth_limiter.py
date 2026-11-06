import time
import unittest

try:
    from app.auth import (
        _cleanup_stale_ip_records,
        _failed_attempts,
        _blocked_ips,
        _request_history,
        LOCKOUT_TIME_SECONDS,
    )
    AUTH_AVAILABLE = True
except ImportError:
    AUTH_AVAILABLE = False


class TestAuthRateLimiter(unittest.TestCase):
    def setUp(self):
        if not AUTH_AVAILABLE:
            self.skipTest("FastAPI not available in local host environment")
        _failed_attempts.clear()
        _blocked_ips.clear()
        _request_history.clear()

    def test_cleanup_stale_ip_records(self):
        now = time.time()
        # Add an expired blocked IP
        _blocked_ips["192.168.1.1"] = now - 10.0
        # Add a currently blocked IP
        _blocked_ips["192.168.1.2"] = now + 100.0

        # Add stale request history (> 60s ago)
        _request_history["192.168.1.3"] = [now - 120.0, now - 80.0]
        # Add recent request history
        _request_history["192.168.1.4"] = [now - 10.0, now]

        _cleanup_stale_ip_records(now)

        # 192.168.1.1 should be unblocked and removed
        self.assertNotIn("192.168.1.1", _blocked_ips)
        # 192.168.1.2 should remain blocked
        self.assertIn("192.168.1.2", _blocked_ips)

        # 192.168.1.3 has no valid timestamps left, should be removed
        self.assertNotIn("192.168.1.3", _request_history)
        # 192.168.1.4 should still have its recent history
        self.assertIn("192.168.1.4", _request_history)


if __name__ == "__main__":
    unittest.main()
