from typing import List, Dict, Any, Optional
from langchain_core.tools import tool
from core.chroma_client import chroma_client
from services.search_service import search_service
from services.file_processor import file_processor_factory
from services.mac_automation import mac_automation, script_kb
from pathlib import Path
from core.logger import setup_logger

logger = setup_logger(__name__)


@tool
async def search_knowledge_base(query: str, top_k: int = 5) -> str:
    """
    Search the knowledge base for relevant documents.
    
    Args:
        query: The search query
        top_k: Number of results to return
    
    Returns:
        Formatted string with search results
    """
    try:
        results = await chroma_client.search(query, top_k)
        
        if not results:
            return "No relevant documents found in the knowledge base."
        
        formatted = "## Knowledge Base Results:\n\n"
        for i, result in enumerate(results, 1):
            formatted += f"{i}. {result['document'][:200]}...\n"
            formatted += f"   (Relevance: {1 - result['distance']:.2f})\n\n"
        
        return formatted
    
    except Exception as e:
        logger.error(f"Knowledge base search error: {str(e)}")
        return f"Error searching knowledge base: {str(e)}"


@tool
async def web_search(query: str, max_results: int = 5) -> str:
    """
    Search the internet using DuckDuckGo.
    
    Args:
        query: The search query
        max_results: Maximum number of results
    
    Returns:
        Formatted string with search results
    """
    try:
        results = await search_service.search(query, max_results)
        
        if not results:
            return "No search results found."
        
        formatted = "## Web Search Results:\n\n"
        for i, result in enumerate(results, 1):
            formatted += f"{i}. **{result['title']}**\n"
            formatted += f"   {result['snippet']}\n"
            formatted += f"   URL: {result['url']}\n\n"
        
        return formatted
    
    except Exception as e:
        logger.error(f"Web search error: {str(e)}")
        return f"Error performing web search: {str(e)}"


@tool
async def process_uploaded_file(file_id_or_path: str) -> str:
    """
    Get content from an uploaded file using its file_id or path.
    
    Args:
        file_id_or_path: The file ID (UUID) or file path
    
    Returns:
        The file content extracted from the knowledge base
    """
    try:
        import os
        from core.config import settings
        
        # Check if it's a UUID (file_id) - try to get from ChromaDB first
        try:
            results = await chroma_client.get_documents_by_file_ids([file_id_or_path])
            if results and results.get(file_id_or_path):
                chunks = results[file_id_or_path]
                if chunks:
                    content = "## File Content:\n\n"
                    file_name = chunks[0]["metadata"].get("file_name", file_id_or_path)
                    content += f"**File:** {file_name}\n\n"
                    for i, chunk in enumerate(chunks[:10]):  # Max 10 chunks
                        content += f"**Section {i+1}:**\n{chunk['content']}\n\n"
                    return content
        except Exception as e:
            logger.warning(f"ChromaDB lookup failed: {e}")
        
        # Try as file path - check uploads directory
        upload_dir = Path(settings.UPLOAD_DIR)
        
        # Try to find file by ID in uploads
        for ext in ['.pdf', '.txt', '.png', '.jpg', '.jpeg', '.md']:
            potential_path = upload_dir / f"{file_id_or_path}{ext}"
            if potential_path.exists():
                result = await file_processor_factory.process_file(potential_path)
                if result['success']:
                    return f"## File Content:\n\n**File:** {result['metadata']['file_name']}\n\n{result['text'][:2000]}"
        
        # Try as direct path
        path = Path(file_id_or_path)
        if path.exists():
            result = await file_processor_factory.process_file(path)
            if result['success']:
                return f"## File Content:\n\n**File:** {result['metadata']['file_name']}\n\n{result['text'][:2000]}"
        
        return f"File not found. The file with ID '{file_id_or_path}' may have been uploaded but not yet indexed. Please try asking about the file content directly - it should be available in the context."
    
    except Exception as e:
        logger.error(f"File processing error: {str(e)}")
        return f"Error accessing file: {str(e)}"


# ============== MAC AUTOMATION TOOLS ==============

@tool
async def run_mac_script(script_id: str, parameters: Optional[Dict[str, Any]] = None) -> str:
    """
    Execute a pre-defined Mac automation script from the knowledge base.
    
    This is the PRIMARY tool for controlling macOS. Use script IDs from the knowledge base.
    
    Available script categories:
    - SYSTEM: system_get_info, system_get_battery, system_get_wifi, system_toggle_dark_mode, 
              system_set_volume, system_mute, system_notification, system_say, system_sleep_display
    - APPS: app_open, app_quit, app_list_running, app_hide, app_get_frontmost
    - FINDER: finder_new_window, finder_get_selection, finder_create_folder, finder_open_file
    - BROWSER: safari_open_url, safari_get_url, chrome_open_url, chrome_get_url
    - MEDIA: music_play, music_pause, music_next, music_previous, music_current_track, music_play_playlist
    - PRODUCTIVITY: calendar_today_events, calendar_create_event, reminders_create, reminders_list, notes_create
    - COMMUNICATION: mail_unread_count, mail_compose, messages_send
    - UTILITIES: clipboard_get, clipboard_set, terminal_new_tab, spotlight_search, window_minimize_all
    
    Args:
        script_id: The ID of the script to run (e.g., "music_play", "system_get_battery")
        parameters: Optional dict of parameters the script needs (e.g., {"volume_level": "50"})
    
    Returns:
        Result of the script execution
    """
    try:
        params = parameters or {}
        
        # Get and prepare the script
        prepared_script = script_kb.prepare_script(script_id, params)
        
        if not prepared_script:
            # List available scripts for this category
            available = [s.id for s in script_kb.scripts.values()]
            return f"Script '{script_id}' not found. Available scripts: {', '.join(available[:20])}..."
        
        # Check if any required parameters are missing
        script = script_kb.get_script(script_id)
        if script:
            for param in script.parameters:
                if param not in params:
                    return f"Missing required parameter '{param}' for script '{script_id}'. Required parameters: {script.parameters}"
        
        # Execute the script
        result = await mac_automation.execute_applescript(prepared_script)
        
        if result.blocked:
            return f"⚠️ Action blocked: {result.blocked_reason}"
        elif result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Error: {result.error}"
            
    except Exception as e:
        logger.error(f"Mac script execution error: {str(e)}")
        return f"Error executing script: {str(e)}"


@tool
async def execute_applescript(script: str) -> str:
    """
    Execute custom AppleScript code for advanced Mac automation.
    
    Use this ONLY when no pre-defined script in run_mac_script matches the need.
    The script must be valid AppleScript syntax.
    
    SAFETY: Scripts containing delete, remove, trash, or other destructive operations
    will be automatically blocked.
    
    Args:
        script: The AppleScript code to execute
    
    Returns:
        Result of the script execution
    
    Example scripts:
        - 'tell application "Finder" to get name of front window'
        - 'display dialog "Hello" buttons {"OK"}'
        - 'set volume output volume 50'
    """
    try:
        result = await mac_automation.execute_applescript(script)
        
        if result.blocked:
            return f"⚠️ Action blocked for safety: {result.blocked_reason}"
        elif result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Error: {result.error}"
            
    except Exception as e:
        logger.error(f"AppleScript execution error: {str(e)}")
        return f"Error executing AppleScript: {str(e)}"


@tool
async def execute_shell_command(command: str) -> str:
    """
    Execute a shell command on macOS.
    
    Use for system queries, getting information, or running safe terminal commands.
    
    SAFETY: Commands containing rm, delete, remove, or destructive operations
    will be automatically blocked.
    
    Args:
        command: The shell command to execute
    
    Returns:
        Command output or error message
    
    Example commands:
        - 'ls -la ~/Documents'
        - 'pwd'
        - 'whoami'
        - 'date'
        - 'df -h'
    """
    try:
        result = await mac_automation.execute_shell(command)
        
        if result.blocked:
            return f"⚠️ Command blocked for safety: {result.blocked_reason}"
        elif result.success:
            return f"```\n{result.output}\n```"
        else:
            return f"❌ Error: {result.error}"
            
    except Exception as e:
        logger.error(f"Shell command error: {str(e)}")
        return f"Error executing command: {str(e)}"


@tool
def get_available_mac_scripts(category: Optional[str] = None) -> str:
    """
    Get list of available Mac automation scripts.
    
    Use this to discover what automation scripts are available before running them.
    
    Args:
        category: Optional category filter (system, apps, finder, browser, media, 
                 productivity, communication, utilities, information)
    
    Returns:
        List of available scripts with descriptions
    """
    try:
        if category:
            from services.mac_automation.scripts import ScriptCategory
            try:
                cat = ScriptCategory(category.lower())
                scripts = script_kb.get_scripts_by_category(cat)
                if not scripts:
                    return f"No scripts found in category '{category}'"
                
                result = f"## {category.upper()} Scripts:\n\n"
                for s in scripts:
                    params = f" (params: {', '.join(s.parameters)})" if s.parameters else ""
                    result += f"- **{s.id}**{params}: {s.description}\n"
                return result
            except ValueError:
                return f"Invalid category '{category}'. Valid categories: system, apps, finder, browser, media, productivity, communication, utilities, information"
        else:
            return script_kb.get_all_scripts_summary()
            
    except Exception as e:
        logger.error(f"Error getting scripts: {str(e)}")
        return f"Error: {str(e)}"


def get_tools():
    """Return list of available tools."""
    return [
        # Knowledge & Search
        search_knowledge_base, 
        web_search, 
        process_uploaded_file,
        # Mac Automation
        run_mac_script,
        execute_applescript,
        execute_shell_command,
        get_available_mac_scripts,
    ]
