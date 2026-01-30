"""
Jarvis Agent Guardrails

Smart adaptive control to prevent:
- Hallucination and drift
- Runaway loops
- Repetitive tool calls
- Task abandonment

Based on research: Cambridge Agent AI (2025), NeMo Guardrails, LangGraph best practices
"""

from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field
from datetime import datetime
from collections import deque
import hashlib
import json

from core.logger import setup_logger

logger = setup_logger(__name__)


@dataclass
class ToolCallRecord:
    """Record of a tool call for loop detection."""
    tool_name: str
    args_hash: str
    timestamp: datetime
    result_preview: str = ""
    success: bool = True


@dataclass
class AgentMonitor:
    """
    Monitors agent behavior and provides adaptive control signals.
    
    Instead of hard limits, uses:
    - Pattern detection for loops
    - Progress tracking
    - Semantic drift detection
    - Graceful completion guidance
    """
    
    # Configuration (adaptive thresholds)
    base_tool_limit: int = 15  # Base limit, can be extended if making progress
    max_tool_limit: int = 30   # Absolute maximum
    repetition_threshold: int = 3  # Same tool+args this many times = loop
    stagnation_threshold: int = 5  # No progress for this many iterations
    
    # Tracking state
    tool_history: deque = field(default_factory=lambda: deque(maxlen=50))
    original_task: str = ""
    plan_steps_completed: int = 0
    total_plan_steps: int = 0
    last_content_length: int = 0
    stagnation_count: int = 0
    consecutive_errors: int = 0
    current_phase: str = "starting"  # starting, executing, completing, finished
    
    # Computed metrics
    effective_tool_limit: int = 15
    
    def set_task(self, task: str, plan_steps: int = 0):
        """Initialize monitoring for a new task."""
        self.original_task = task
        self.total_plan_steps = plan_steps
        self.plan_steps_completed = 0
        self.stagnation_count = 0
        self.consecutive_errors = 0
        self.current_phase = "starting"
        self.tool_history.clear()
        
        # Adapt limit based on task complexity
        if plan_steps > 5:
            self.effective_tool_limit = min(plan_steps * 3, self.max_tool_limit)
        else:
            self.effective_tool_limit = self.base_tool_limit
        
        logger.info(f"Monitor initialized: {plan_steps} steps, limit={self.effective_tool_limit}")
    
    def record_tool_call(self, tool_name: str, args: Dict[str, Any], result: str = "", success: bool = True):
        """Record a tool call for analysis."""
        # Create hash of tool + args for loop detection
        args_str = json.dumps(args, sort_keys=True, default=str)
        args_hash = hashlib.md5(f"{tool_name}:{args_str}".encode()).hexdigest()[:8]
        
        record = ToolCallRecord(
            tool_name=tool_name,
            args_hash=args_hash,
            timestamp=datetime.now(),
            result_preview=result[:100] if result else "",
            success=success
        )
        self.tool_history.append(record)
        
        if not success:
            self.consecutive_errors += 1
        else:
            self.consecutive_errors = 0
        
        self.current_phase = "executing"
    
    def record_step_completed(self):
        """Record that a plan step was completed."""
        self.plan_steps_completed += 1
        self.stagnation_count = 0  # Reset stagnation on progress
        
        if self.total_plan_steps > 0 and self.plan_steps_completed >= self.total_plan_steps:
            self.current_phase = "completing"
    
    def record_content_generated(self, content_length: int):
        """Track content generation for stagnation detection."""
        if content_length > self.last_content_length:
            self.stagnation_count = 0
        else:
            self.stagnation_count += 1
        self.last_content_length = content_length
    
    def _get_tool_name(self, call) -> str:
        """Get tool name from either ToolCallRecord or dict."""
        if isinstance(call, dict):
            return call.get("tool_name", "unknown")
        return call.tool_name
    
    def _get_args_hash(self, call) -> str:
        """Get args hash from either ToolCallRecord or dict."""
        if isinstance(call, dict):
            return call.get("args_hash", "")
        return call.args_hash
    
    def detect_loop(self) -> Tuple[bool, str]:
        """
        Detect if the agent is stuck in a loop.
        
        Returns: (is_looping, reason)
        """
        if len(self.tool_history) < self.repetition_threshold:
            return False, ""
        
        # Count recent identical calls (same tool + same args)
        recent_calls = list(self.tool_history)[-10:]
        call_counts: Dict[str, int] = {}
        
        for call in recent_calls:
            # Handle both ToolCallRecord objects and dicts (from state restoration)
            tool_name = self._get_tool_name(call)
            args_hash = self._get_args_hash(call)
            key = f"{tool_name}:{args_hash}"
            call_counts[key] = call_counts.get(key, 0) + 1
        
        # Check for repetition
        for key, count in call_counts.items():
            if count >= self.repetition_threshold:
                tool_name = key.split(":")[0]
                return True, f"Repeated '{tool_name}' {count} times with same arguments"
        
        # Check for tool oscillation (A → B → A → B pattern)
        if len(recent_calls) >= 4:
            last_four = [self._get_tool_name(c) for c in recent_calls[-4:]]
            if last_four[0] == last_four[2] and last_four[1] == last_four[3] and last_four[0] != last_four[1]:
                return True, f"Oscillating between '{last_four[0]}' and '{last_four[1]}'"
        
        return False, ""
    
    def detect_stagnation(self) -> Tuple[bool, str]:
        """
        Detect if the agent is making no progress.
        
        Returns: (is_stagnating, reason)
        """
        if self.stagnation_count >= self.stagnation_threshold:
            return True, f"No progress for {self.stagnation_count} iterations"
        
        if self.consecutive_errors >= 3:
            return True, f"{self.consecutive_errors} consecutive errors"
        
        return False, ""
    
    def should_continue(self) -> Tuple[bool, str, str]:
        """
        Main decision: should the agent continue?
        
        Returns: (should_continue, reason, guidance)
        """
        tool_count = len(self.tool_history)
        
        # Check for loops
        is_looping, loop_reason = self.detect_loop()
        if is_looping:
            return False, loop_reason, self._get_loop_recovery_guidance()
        
        # Check for stagnation
        is_stagnating, stag_reason = self.detect_stagnation()
        if is_stagnating:
            return False, stag_reason, self._get_stagnation_recovery_guidance()
        
        # Check effective limit (adaptive)
        if tool_count >= self.effective_tool_limit:
            # If making progress on plan, extend limit
            if self.plan_steps_completed > 0 and self.total_plan_steps > 0:
                progress_ratio = self.plan_steps_completed / self.total_plan_steps
                if progress_ratio > 0.5 and tool_count < self.max_tool_limit:
                    self.effective_tool_limit = min(self.effective_tool_limit + 5, self.max_tool_limit)
                    logger.info(f"Extended tool limit to {self.effective_tool_limit} (progress: {progress_ratio:.0%})")
                    return True, "", ""
            
            return False, f"Tool limit reached ({tool_count}/{self.effective_tool_limit})", self._get_completion_guidance()
        
        # Check absolute maximum
        if tool_count >= self.max_tool_limit:
            return False, "Maximum tool limit reached", self._get_completion_guidance()
        
        # All good, continue
        return True, "", ""
    
    def get_context_injection(self) -> str:
        """
        Get context to inject into the agent's system prompt for adaptive behavior.
        """
        tool_count = len(self.tool_history)
        remaining = self.effective_tool_limit - tool_count
        
        # Build context based on current state
        context_parts = []
        
        # Progress indicator
        if self.total_plan_steps > 0:
            context_parts.append(
                f"📊 Progress: {self.plan_steps_completed}/{self.total_plan_steps} steps completed"
            )
        
        # Warnings based on state
        if remaining <= 3:
            context_parts.append(f"⚠️ {remaining} tool calls remaining. Focus on completing the task.")
        elif remaining <= 7:
            context_parts.append(f"💡 {remaining} tool calls remaining. Be efficient.")
        
        if self.consecutive_errors >= 2:
            context_parts.append(f"⚠️ {self.consecutive_errors} recent errors. Try a different approach.")
        
        if self.current_phase == "completing":
            context_parts.append("✅ All plan steps done. Provide final summary to user.")
        
        # Loop warning
        is_looping, loop_reason = self.detect_loop()
        if is_looping:
            context_parts.append(f"🔄 Loop detected: {loop_reason}. Change approach.")
        
        return "\n".join(context_parts) if context_parts else ""
    
    def _get_loop_recovery_guidance(self) -> str:
        """Guidance for recovering from a loop."""
        return """You appear to be in a loop. Please:
1. Stop the current approach
2. Summarize what you've accomplished so far
3. If the task is incomplete, explain what's blocking progress
4. Ask the user for clarification if needed"""
    
    def _get_stagnation_recovery_guidance(self) -> str:
        """Guidance for recovering from stagnation."""
        return """Progress has stalled. Please:
1. Review the original request
2. Summarize what's been done
3. Either complete with available information or explain what's needed"""
    
    def _get_completion_guidance(self) -> str:
        """Guidance for wrapping up."""
        return """Please wrap up now:
1. Summarize what was accomplished
2. Note any incomplete items
3. Provide the user with a clear final response"""
    
    def get_status(self) -> Dict[str, Any]:
        """Get current monitoring status for debugging/logging."""
        return {
            "tool_count": len(self.tool_history),
            "effective_limit": self.effective_tool_limit,
            "plan_progress": f"{self.plan_steps_completed}/{self.total_plan_steps}",
            "phase": self.current_phase,
            "consecutive_errors": self.consecutive_errors,
            "stagnation_count": self.stagnation_count,
        }


# Global monitor instance (per-request in production)
def create_monitor() -> AgentMonitor:
    """Create a new monitor for a request."""
    return AgentMonitor()
