"""
Mac Automation Executor - Safe AppleScript/JXA execution with guardrails.

This module provides a secure way to execute AppleScript commands on macOS,
with built-in protection against destructive operations.
"""

import subprocess
import asyncio
import re
from typing import Optional, Dict, Any, Tuple
from dataclasses import dataclass
from enum import Enum
from core.logger import setup_logger

logger = setup_logger(__name__)


class ScriptLanguage(Enum):
    APPLESCRIPT = "applescript"
    JAVASCRIPT = "javascript"  # JXA - JavaScript for Automation


@dataclass
class ExecutionResult:
    """Result of script execution."""
    success: bool
    output: str
    error: Optional[str] = None
    blocked: bool = False
    blocked_reason: Optional[str] = None


class MacAutomationService:
    """
    Safe AppleScript/JXA execution service with guardrails.
    
    GUARDRAILS:
    - Blocks all delete/remove/trash operations
    - Blocks system modification commands
    - Blocks keychain/password access
    - Timeout protection (default 30s)
    """
    
    # Patterns that indicate destructive operations - ALWAYS BLOCKED
    BLOCKED_PATTERNS = [
        # File deletion
        r'\bdelete\b',
        r'\bremove\b',
        r'\btrash\b',
        r'\bermpty\s+trash\b',
        r'\bmove\s+.*\s+to\s+trash\b',
        r'rm\s+-',
        r'rmdir\b',
        r'unlink\b',
        
        # System modification
        r'\bformat\b.*\bdisk\b',
        r'\berase\b.*\bdisk\b',
        r'\bshutdown\b',
        r'\brestart\b.*\bsystem\b',
        r'sudo\s+rm\b',
        r'sudo\s+shutdown',
        r'sudo\s+reboot',
        
        # Security/Privacy sensitive
        r'\bkeychain\b',
        r'\bpassword\b',
        r'\bsecurity\s+',
        r'\bcredential\b',
        r'System\s+Preferences.*Security',
        
        # Dangerous shell commands
        r'>\s*/dev/',
        r'mkfs\b',
        r'dd\s+if=',
    ]
    
    # Compile patterns for efficiency
    _blocked_regex = None
    
    def __init__(self, timeout: int = 30):
        self.timeout = timeout
        if MacAutomationService._blocked_regex is None:
            MacAutomationService._blocked_regex = re.compile(
                '|'.join(self.BLOCKED_PATTERNS),
                re.IGNORECASE | re.MULTILINE
            )
    
    def _check_guardrails(self, script: str) -> Tuple[bool, Optional[str]]:
        """
        Check if script violates guardrails.
        
        Returns:
            Tuple of (is_safe, violation_reason)
        """
        # Check against blocked patterns
        match = self._blocked_regex.search(script)
        if match:
            matched_text = match.group()
            logger.warning(f"Script blocked - matched pattern: {matched_text}")
            return False, f"Operation blocked for safety: '{matched_text}' detected. Jarvis cannot perform delete, remove, or destructive operations."
        
        return True, None
    
    async def execute_applescript(
        self,
        script: str,
        timeout: Optional[int] = None
    ) -> ExecutionResult:
        """
        Execute AppleScript with guardrails.
        
        Args:
            script: The AppleScript code to execute
            timeout: Optional timeout in seconds (default: self.timeout)
        
        Returns:
            ExecutionResult with output or error
        """
        # Check guardrails first
        is_safe, violation_reason = self._check_guardrails(script)
        if not is_safe:
            return ExecutionResult(
                success=False,
                output="",
                error=violation_reason,
                blocked=True,
                blocked_reason=violation_reason
            )
        
        timeout = timeout or self.timeout
        
        try:
            # Execute using osascript
            process = await asyncio.create_subprocess_exec(
                "osascript", "-e", script,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=timeout
                )
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                return ExecutionResult(
                    success=False,
                    output="",
                    error=f"Script execution timed out after {timeout} seconds"
                )
            
            stdout_str = stdout.decode('utf-8').strip()
            stderr_str = stderr.decode('utf-8').strip()
            
            if process.returncode == 0:
                logger.info(f"AppleScript executed successfully: {script[:100]}...")
                return ExecutionResult(
                    success=True,
                    output=stdout_str or "Script executed successfully (no output)"
                )
            else:
                logger.error(f"AppleScript error: {stderr_str}")
                return ExecutionResult(
                    success=False,
                    output=stdout_str,
                    error=stderr_str or f"Script failed with exit code {process.returncode}"
                )
                
        except Exception as e:
            logger.error(f"AppleScript execution failed: {str(e)}")
            return ExecutionResult(
                success=False,
                output="",
                error=f"Execution error: {str(e)}"
            )
    
    async def execute_jxa(
        self,
        script: str,
        timeout: Optional[int] = None
    ) -> ExecutionResult:
        """
        Execute JavaScript for Automation (JXA) with guardrails.
        
        Args:
            script: The JXA code to execute
            timeout: Optional timeout in seconds
        
        Returns:
            ExecutionResult with output or error
        """
        # Check guardrails first
        is_safe, violation_reason = self._check_guardrails(script)
        if not is_safe:
            return ExecutionResult(
                success=False,
                output="",
                error=violation_reason,
                blocked=True,
                blocked_reason=violation_reason
            )
        
        timeout = timeout or self.timeout
        
        try:
            # Execute using osascript with -l JavaScript
            process = await asyncio.create_subprocess_exec(
                "osascript", "-l", "JavaScript", "-e", script,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=timeout
                )
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                return ExecutionResult(
                    success=False,
                    output="",
                    error=f"Script execution timed out after {timeout} seconds"
                )
            
            stdout_str = stdout.decode('utf-8').strip()
            stderr_str = stderr.decode('utf-8').strip()
            
            if process.returncode == 0:
                logger.info(f"JXA executed successfully: {script[:100]}...")
                return ExecutionResult(
                    success=True,
                    output=stdout_str or "Script executed successfully (no output)"
                )
            else:
                logger.error(f"JXA error: {stderr_str}")
                return ExecutionResult(
                    success=False,
                    output=stdout_str,
                    error=stderr_str or f"Script failed with exit code {process.returncode}"
                )
                
        except Exception as e:
            logger.error(f"JXA execution failed: {str(e)}")
            return ExecutionResult(
                success=False,
                output="",
                error=f"Execution error: {str(e)}"
            )
    
    async def execute_shell(
        self,
        command: str,
        timeout: Optional[int] = None
    ) -> ExecutionResult:
        """
        Execute shell command with guardrails.
        
        Args:
            command: The shell command to execute
            timeout: Optional timeout in seconds
        
        Returns:
            ExecutionResult with output or error
        """
        # Check guardrails first
        is_safe, violation_reason = self._check_guardrails(command)
        if not is_safe:
            return ExecutionResult(
                success=False,
                output="",
                error=violation_reason,
                blocked=True,
                blocked_reason=violation_reason
            )
        
        timeout = timeout or self.timeout
        
        try:
            process = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=timeout
                )
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                return ExecutionResult(
                    success=False,
                    output="",
                    error=f"Command execution timed out after {timeout} seconds"
                )
            
            stdout_str = stdout.decode('utf-8').strip()
            stderr_str = stderr.decode('utf-8').strip()
            
            if process.returncode == 0:
                logger.info(f"Shell command executed successfully: {command[:100]}...")
                return ExecutionResult(
                    success=True,
                    output=stdout_str or "Command executed successfully (no output)"
                )
            else:
                return ExecutionResult(
                    success=False,
                    output=stdout_str,
                    error=stderr_str or f"Command failed with exit code {process.returncode}"
                )
                
        except Exception as e:
            logger.error(f"Shell execution failed: {str(e)}")
            return ExecutionResult(
                success=False,
                output="",
                error=f"Execution error: {str(e)}"
            )
    
    def get_blocked_operations(self) -> list:
        """Return list of blocked operation categories."""
        return [
            "delete/remove/trash files or folders",
            "empty trash",
            "format or erase disks",
            "shutdown or restart system",
            "access keychain or passwords",
            "modify security settings",
            "destructive shell commands (rm, rmdir, etc.)"
        ]


# Singleton instance
mac_automation = MacAutomationService()
