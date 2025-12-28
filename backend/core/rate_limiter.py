from typing import Dict
from datetime import datetime, timedelta
from collections import defaultdict
from core.logger import setup_logger

logger = setup_logger(__name__)


class RateLimiter:
    """Simple in-memory rate limiter."""
    
    def __init__(
        self,
        max_requests_per_minute: int = 60,
        max_requests_per_hour: int = 1000
    ):
        self.max_per_minute = max_requests_per_minute
        self.max_per_hour = max_requests_per_hour
        self.minute_requests: Dict[str, list] = defaultdict(list)
        self.hour_requests: Dict[str, list] = defaultdict(list)
    
    def is_allowed(self, identifier: str = "default") -> tuple[bool, str]:
        """
        Check if request is allowed.
        Returns (is_allowed, message)
        """
        now = datetime.now()
        
        # Clean old entries
        self._clean_old_entries(identifier, now)
        
        # Check minute limit
        if len(self.minute_requests[identifier]) >= self.max_per_minute:
            return False, f"Rate limit exceeded: {self.max_per_minute} requests per minute"
        
        # Check hour limit
        if len(self.hour_requests[identifier]) >= self.max_per_hour:
            return False, f"Rate limit exceeded: {self.max_per_hour} requests per hour"
        
        # Record request
        self.minute_requests[identifier].append(now)
        self.hour_requests[identifier].append(now)
        
        return True, "OK"
    
    def _clean_old_entries(self, identifier: str, now: datetime):
        """Remove old entries outside the time windows."""
        # Clean minute requests (older than 1 minute)
        self.minute_requests[identifier] = [
            req_time for req_time in self.minute_requests[identifier]
            if now - req_time < timedelta(minutes=1)
        ]
        
        # Clean hour requests (older than 1 hour)
        self.hour_requests[identifier] = [
            req_time for req_time in self.hour_requests[identifier]
            if now - req_time < timedelta(hours=1)
        ]
    
    def get_stats(self, identifier: str = "default") -> Dict:
        """Get rate limit statistics for an identifier."""
        now = datetime.now()
        self._clean_old_entries(identifier, now)
        
        return {
            "requests_last_minute": len(self.minute_requests[identifier]),
            "requests_last_hour": len(self.hour_requests[identifier]),
            "limit_per_minute": self.max_per_minute,
            "limit_per_hour": self.max_per_hour
        }


rate_limiter = RateLimiter()

