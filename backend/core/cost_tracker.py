from typing import Dict, Optional
from datetime import datetime, timedelta
from core.logger import setup_logger
import json
from pathlib import Path

logger = setup_logger(__name__)


class CostTracker:
    """Track API costs for OpenAI usage."""
    
    # Pricing as of Dec 2025
    PRICING = {
        "gpt-5-nano": {
            "input": 0.05 / 1_000_000,  # $0.05 per 1M input tokens
            "output": 0.40 / 1_000_000,  # $0.40 per 1M output tokens
        },
        "gpt-4o": {
            "input": 2.50 / 1_000_000,  # $2.50 per 1M input tokens
            "output": 10.00 / 1_000_000,  # $10.00 per 1M output tokens
        },
        "gpt-4o-mini": {
            "input": 0.15 / 1_000_000,  # $0.15 per 1M input tokens
            "output": 0.60 / 1_000_000,  # $0.60 per 1M output tokens
        },
        "text-embedding-3-small": {
            "input": 0.02 / 1_000_000,  # $0.02 per 1M tokens
        }
    }
    
    def __init__(self, storage_path: str = "./data/cost_tracking.json"):
        self.storage_path = Path(storage_path)
        self.storage_path.parent.mkdir(parents=True, exist_ok=True)
        self._load_data()
    
    def _load_data(self):
        """Load cost tracking data from file."""
        if self.storage_path.exists():
            try:
                with open(self.storage_path, 'r') as f:
                    self.data = json.load(f)
            except Exception as e:
                logger.error(f"Error loading cost data: {e}")
                self.data = {"daily_costs": {}, "total_cost": 0.0, "total_tokens": {"input": 0, "output": 0}}
        else:
            self.data = {"daily_costs": {}, "total_cost": 0.0, "total_tokens": {"input": 0, "output": 0}}
    
    def _save_data(self):
        """Save cost tracking data to file."""
        try:
            with open(self.storage_path, 'w') as f:
                json.dump(self.data, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving cost data: {e}")
    
    def track_usage(
        self,
        model: str,
        input_tokens: int = 0,
        output_tokens: int = 0,
        embedding_tokens: int = 0
    ):
        """Track token usage and calculate cost."""
        today = datetime.now().strftime("%Y-%m-%d")
        
        if today not in self.data["daily_costs"]:
            self.data["daily_costs"][today] = {
                "cost": 0.0,
                "tokens": {"input": 0, "output": 0, "embedding": 0}
            }
        
        cost = 0.0
        
        if model in self.PRICING:
            pricing = self.PRICING[model]
            
            if "input" in pricing and input_tokens > 0:
                cost += input_tokens * pricing["input"]
                self.data["daily_costs"][today]["tokens"]["input"] += input_tokens
                self.data["total_tokens"]["input"] += input_tokens
            
            if "output" in pricing and output_tokens > 0:
                cost += output_tokens * pricing["output"]
                self.data["daily_costs"][today]["tokens"]["output"] += output_tokens
                self.data["total_tokens"]["output"] += output_tokens
            
            if "input" in pricing and embedding_tokens > 0:
                cost += embedding_tokens * pricing["input"]
                self.data["daily_costs"][today]["tokens"]["embedding"] += embedding_tokens
        
        self.data["daily_costs"][today]["cost"] += cost
        self.data["total_cost"] += cost
        
        self._save_data()
        
        logger.info(f"Tracked usage: {input_tokens} input, {output_tokens} output tokens. Cost: ${cost:.6f}")
        
        return cost
    
    def get_daily_cost(self, date: Optional[str] = None) -> float:
        """Get cost for a specific date (default: today)."""
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")
        
        return self.data["daily_costs"].get(date, {}).get("cost", 0.0)
    
    def get_total_cost(self) -> float:
        """Get total cost across all time."""
        return self.data["total_cost"]
    
    def get_monthly_cost(self) -> float:
        """Get cost for current month."""
        today = datetime.now()
        month_start = today.replace(day=1)
        
        total = 0.0
        current = month_start
        while current <= today:
            date_str = current.strftime("%Y-%m-%d")
            total += self.data["daily_costs"].get(date_str, {}).get("cost", 0.0)
            current += timedelta(days=1)
        
        return total
    
    def get_stats(self) -> Dict:
        """Get comprehensive cost statistics."""
        return {
            "total_cost": self.get_total_cost(),
            "monthly_cost": self.get_monthly_cost(),
            "daily_cost": self.get_daily_cost(),
            "total_tokens": self.data["total_tokens"],
            "daily_costs": self.data["daily_costs"]
        }


cost_tracker = CostTracker()

