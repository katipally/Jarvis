from typing import List, Dict, Any, Optional
from langchain_core.tools import tool
from core.chroma_client import chroma_client
from services.search_service import search_service
from services.file_processor import file_processor_factory
from services.mac_automation import mac_automation, script_kb
from pathlib import Path
from core.logger import setup_logger

logger = setup_logger(__name__)


def escape_applescript(text: str) -> str:
    """Escape special characters for AppleScript strings."""
    if not isinstance(text, str):
        return str(text)
    return text.replace("\\", "\\\\").replace('"', '\\"')


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
    
    Available script categories & IDs:
    
    - **SYSTEM**: system_get_info, system_get_battery, system_get_wifi, system_toggle_dark_mode, 
                  system_set_volume, system_mute, system_notification, system_say, system_sleep_display
    
    - **APPS**: app_open, app_quit, app_list_running, app_hide, app_get_frontmost
    
    - **BROWSER (Generic - works with Safari, Chrome, Arc, etc.)**: 
      - `browser_open_url` (params: app_name, url)
      - `browser_get_active_url` (params: app_name)
      - `browser_get_active_title` (params: app_name)
      - `browser_new_tab` (params: app_name)
    
    - **MEDIA (Generic - works with Music, Spotify, VLC, etc.)**: 
      - `media_play` (params: app_name)
      - `media_pause` (params: app_name)
      - `media_next` (params: app_name)
      - `media_previous` (params: app_name)
      - `media_get_info` (params: app_name)
    
    - **FINDER**: finder_new_window, finder_get_selection, finder_create_folder, finder_open_file
    
    - **PRODUCTIVITY**: 
      - `notes_create` (params: title, content)
      - `notes_search_recent` (params: days)
      - `notes_search_text` (params: query)
      - calendar_today_events, calendar_create_event, reminders_create, reminders_list
    
    - **COMMUNICATION**: mail_unread_count, mail_compose, messages_send
    - **UTILITIES**: clipboard_get, clipboard_set, terminal_new_tab, spotlight_search, window_minimize_all
    
    Args:
        script_id: The ID of the script to run (e.g., "media_play", "browser_open_url")
        parameters: Optional dict of parameters the script needs (e.g., {"app_name": "Spotify", "url": "google.com"})
    
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


# ============== ADVANCED INPUT SIMULATION TOOLS ==============

@tool
async def click_at_position(x: int, y: int, click_type: str = "single") -> str:
    """
    Click at a specific screen position using mouse simulation.
    
    Args:
        x: X coordinate on screen
        y: Y coordinate on screen
        click_type: Type of click - "single", "double", or "right"
    
    Returns:
        Result of the click action
    """
    try:
        if click_type == "double":
            script_id = "mouse_double_click"
        elif click_type == "right":
            script_id = "mouse_right_click"
        else:
            script_id = "mouse_click_at"
        
        prepared_script = script_kb.prepare_script(script_id, {"x": str(x), "y": str(y)})
        if not prepared_script:
            return f"Click script not available"
        
        result = await mac_automation.execute_applescript(prepared_script)
        if result.success:
            return f"✅ {click_type.capitalize()} clicked at ({x}, {y})"
        else:
            return f"❌ Click failed: {result.error}"
    except Exception as e:
        logger.error(f"Click error: {str(e)}")
        return f"Error clicking: {str(e)}"


@tool
async def type_text(text: str, use_clipboard: bool = False) -> str:
    """
    Type text using keyboard simulation.
    
    Args:
        text: The text to type
        use_clipboard: If True, paste from clipboard (faster for long text)
    
    Returns:
        Result of the typing action
    """
    try:
        safe_text = escape_applescript(text)
        if use_clipboard:
            # Use clipboard paste for faster input
            script = f'''
set the clipboard to "{safe_text}"
tell application "System Events"
    keystroke "v" using command down
end tell
return "Pasted text from clipboard"
'''
        else:
            # Direct keystroke
            script = f'''
tell application "System Events"
    keystroke "{safe_text}"
end tell
return "Typed: {safe_text}"
'''
        
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Typing failed: {result.error}"
    except Exception as e:
        logger.error(f"Type error: {str(e)}")
        return f"Error typing: {str(e)}"


@tool
async def press_keyboard_shortcut(key: str, modifiers: str = "") -> str:
    """
    Press a keyboard shortcut combination.
    
    Args:
        key: The key to press (e.g., "c", "v", "s", "return", "escape", "tab")
        modifiers: Comma-separated modifiers (e.g., "command", "command,shift", "control,option")
    
    Returns:
        Result of the shortcut action
    
    Examples:
        - Copy: key="c", modifiers="command"
        - Paste: key="v", modifiers="command"
        - Save: key="s", modifiers="command"
        - Undo: key="z", modifiers="command"
        - Redo: key="z", modifiers="command,shift"
        - Select All: key="a", modifiers="command"
    """
    try:
        # Handle special keys
        key_code_map = {
            "return": "key code 36",
            "enter": "key code 36",
            "escape": "key code 53",
            "tab": "key code 48",
            "space": "key code 49",
            "delete": "key code 51",
            "backspace": "key code 51",
            "up": "key code 126",
            "down": "key code 125",
            "left": "key code 123",
            "right": "key code 124",
            "f1": "key code 122",
            "f2": "key code 120",
            "f3": "key code 99",
            "f4": "key code 118",
            "f5": "key code 96",
            "f11": "key code 103",
            "f12": "key code 111",
        }
        
        # Build modifier string
        mod_list = []
        if modifiers:
            for mod in modifiers.split(","):
                mod = mod.strip().lower()
                if mod == "command" or mod == "cmd":
                    mod_list.append("command down")
                elif mod == "shift":
                    mod_list.append("shift down")
                elif mod == "option" or mod == "alt":
                    mod_list.append("option down")
                elif mod == "control" or mod == "ctrl":
                    mod_list.append("control down")
        
        modifier_str = "{" + ", ".join(mod_list) + "}" if mod_list else ""
        
        # Build the script
        key_lower = key.lower()
        if key_lower in key_code_map:
            if modifier_str:
                script = f'''
tell application "System Events"
    {key_code_map[key_lower]} using {modifier_str}
end tell
return "Pressed {key} with modifiers"
'''
            else:
                script = f'''
tell application "System Events"
    {key_code_map[key_lower]}
end tell
return "Pressed {key}"
'''
        else:
            if modifier_str:
                script = f'''
tell application "System Events"
    keystroke "{key}" using {modifier_str}
end tell
return "Pressed {modifiers}+{key}"
'''
            else:
                script = f'''
tell application "System Events"
    keystroke "{key}"
end tell
return "Pressed {key}"
'''
        
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Shortcut failed: {result.error}"
    except Exception as e:
        logger.error(f"Shortcut error: {str(e)}")
        return f"Error pressing shortcut: {str(e)}"


@tool
async def run_shortcut(shortcut_name: str, input_text: Optional[str] = None) -> str:
    """
    Run a macOS Shortcuts workflow by name.
    
    Args:
        shortcut_name: The name of the shortcut to run
        input_text: Optional text input to pass to the shortcut
    
    Returns:
        Result of running the shortcut
    """
    try:
        if input_text:
            script_id = "shortcuts_run_with_input"
            params = {"shortcut_name": shortcut_name, "input_text": input_text}
        else:
            script_id = "shortcuts_run"
            params = {"shortcut_name": shortcut_name}
        
        prepared_script = script_kb.prepare_script(script_id, params)
        if not prepared_script:
            return f"Shortcuts script not available"
        
        result = await mac_automation.execute_applescript(prepared_script)
        if result.success:
            return f"✅ Ran shortcut '{shortcut_name}'"
        else:
            return f"❌ Shortcut failed: {result.error}"
    except Exception as e:
        logger.error(f"Shortcut error: {str(e)}")
        return f"Error running shortcut: {str(e)}"


@tool
async def list_shortcuts() -> str:
    """
    List all available macOS Shortcuts on this Mac.
    
    Returns:
        List of available shortcut names
    """
    try:
        prepared_script = script_kb.prepare_script("shortcuts_list", {})
        if not prepared_script:
            return "Shortcuts list script not available"
        
        result = await mac_automation.execute_applescript(prepared_script)
        if result.success:
            return f"## Available Shortcuts:\n\n{result.output}"
        else:
            return f"❌ Failed to list shortcuts: {result.error}"
    except Exception as e:
        logger.error(f"List shortcuts error: {str(e)}")
        return f"Error listing shortcuts: {str(e)}"


@tool
async def click_ui_element(app_name: str, element_type: str, element_name: str) -> str:
    """
    Click a UI element in an application using Accessibility APIs.
    
    Args:
        app_name: Name of the application (e.g., "Safari", "Finder")
        element_type: Type of element - "button", "menu_item", "checkbox", "text_field"
        element_name: Name or label of the element to click
    
    Returns:
        Result of the click action
    """
    try:
        safe_app = escape_applescript(app_name)
        safe_element = escape_applescript(element_name)
        
        if element_type == "button":
            script = f'''
tell application "System Events"
    tell process "{safe_app}"
        set frontmost to true
        try
            click button "{safe_element}" of front window
            return "Clicked button: {safe_element}"
        on error
            try
                click button "{safe_element}" of group 1 of front window
                return "Clicked button: {safe_element}"
            on error errMsg
                return "Could not find button '{safe_element}': " & errMsg
            end try
        end try
    end tell
end tell
'''
        elif element_type == "menu_item":
            # Parse menu path (e.g., "File > Save")
            parts = element_name.split(">")
            if len(parts) >= 2:
                menu_name = escape_applescript(parts[0].strip())
                menu_item = escape_applescript(parts[1].strip())
                script = f'''
tell application "System Events"
    tell process "{safe_app}"
        set frontmost to true
        click menu item "{menu_item}" of menu "{menu_name}" of menu bar 1
        return "Clicked menu: {menu_name} > {menu_item}"
    end tell
end tell
'''
            else:
                return "Menu item format should be 'Menu > Item' (e.g., 'File > Save')"
        elif element_type == "checkbox":
            script = f'''
tell application "System Events"
    tell process "{safe_app}"
        set frontmost to true
        click checkbox "{safe_element}" of front window
        return "Toggled checkbox: {safe_element}"
    end tell
end tell
'''
        elif element_type == "text_field":
            script = f'''
tell application "System Events"
    tell process "{safe_app}"
        set frontmost to true
        set focused of text field 1 of front window to true
        return "Focused text field in {safe_app}"
    end tell
end tell
'''
        else:
            return f"Unknown element type: {element_type}. Supported: button, menu_item, checkbox, text_field"
        
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed: {result.error}"
    except Exception as e:
        logger.error(f"UI click error: {str(e)}")
        return f"Error clicking element: {str(e)}"


@tool
async def get_ui_elements(app_name: Optional[str] = None) -> str:
    """
    Get list of UI elements in an application for accessibility automation.
    
    Args:
        app_name: Name of the application (if None, uses frontmost app)
    
    Returns:
        List of UI elements with their types and names
    """
    try:
        if app_name:
            script = f'''
tell application "{app_name}" to activate
delay 0.3
tell application "System Events"
    tell process "{app_name}"
        set elementInfo to "UI Elements in {app_name}:" & linefeed
        try
            set frontWin to front window
            set allButtons to name of every button of frontWin
            set allTextFields to count of every text field of frontWin
            set elementInfo to elementInfo & "Buttons: " & (allButtons as text) & linefeed
            set elementInfo to elementInfo & "Text Fields: " & allTextFields & linefeed
            try
                set allCheckboxes to name of every checkbox of frontWin
                set elementInfo to elementInfo & "Checkboxes: " & (allCheckboxes as text) & linefeed
            end try
            try
                set allPopups to description of every pop up button of frontWin
                set elementInfo to elementInfo & "Popups: " & (allPopups as text) & linefeed
            end try
        on error errMsg
            set elementInfo to elementInfo & "Error getting elements: " & errMsg
        end try
        return elementInfo
    end tell
end tell
'''
        else:
            script = '''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set appName to name of frontApp
    set elementInfo to "UI Elements in " & appName & ":" & linefeed
    try
        set frontWin to front window of frontApp
        set allButtons to name of every button of frontWin
        set allTextFields to count of every text field of frontWin
        set elementInfo to elementInfo & "Buttons: " & (allButtons as text) & linefeed
        set elementInfo to elementInfo & "Text Fields: " & allTextFields & linefeed
    on error errMsg
        set elementInfo to elementInfo & "Limited access: " & errMsg
    end try
    return elementInfo
end tell
'''
        
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"## UI Elements:\n\n{result.output}"
        else:
            return f"❌ Failed to get elements: {result.error}"
    except Exception as e:
        logger.error(f"Get UI elements error: {str(e)}")
        return f"Error getting UI elements: {str(e)}"


@tool
async def manage_window(action: str, x: Optional[int] = None, y: Optional[int] = None, 
                       width: Optional[int] = None, height: Optional[int] = None) -> str:
    """
    Manage the frontmost window - move, resize, maximize, or arrange.
    
    Args:
        action: Action to perform - "move", "resize", "maximize", "minimize", "side_by_side"
        x: X position for move action
        y: Y position for move action
        width: Width for resize action
        height: Height for resize action
    
    Returns:
        Result of the window action
    """
    try:
        if action == "move":
            if x is None or y is None:
                return "Move action requires x and y coordinates"
            script_id = "window_move"
            params = {"x": str(x), "y": str(y)}
        elif action == "resize":
            if width is None or height is None:
                return "Resize action requires width and height"
            script_id = "window_resize"
            params = {"width": str(width), "height": str(height)}
        elif action == "maximize":
            script_id = "window_maximize"
            params = {}
        elif action == "minimize":
            script_id = "window_minimize_all"
            params = {}
        elif action == "side_by_side":
            script_id = "window_arrange_side_by_side"
            params = {}
        else:
            return f"Unknown action: {action}. Supported: move, resize, maximize, minimize, side_by_side"
        
        prepared_script = script_kb.prepare_script(script_id, params)
        if not prepared_script:
            return f"Window script '{script_id}' not available"
        
        result = await mac_automation.execute_applescript(prepared_script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Window action failed: {result.error}"
    except Exception as e:
        logger.error(f"Window management error: {str(e)}")
        return f"Error managing window: {str(e)}"


# ============== APP LIFECYCLE & SYSTEM MONITORING TOOLS ==============

@tool
async def get_running_apps() -> str:
    """
    Get list of all currently running applications.
    
    Returns:
        List of running apps with their names and bundle identifiers
    """
    try:
        script = '''
tell application "System Events"
    set appList to ""
    repeat with proc in (application processes whose background only is false)
        set appName to name of proc
        try
            set bundleID to bundle identifier of proc
        on error
            set bundleID to "unknown"
        end try
        set appList to appList & appName & " (" & bundleID & ")" & linefeed
    end repeat
    return appList
end tell
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"## Running Applications:\n\n{result.output}"
        else:
            return f"❌ Failed to get running apps: {result.error}"
    except Exception as e:
        logger.error(f"Get running apps error: {str(e)}")
        return f"Error getting running apps: {str(e)}"


@tool
async def get_frontmost_app() -> str:
    """
    Get the currently frontmost (active) application.
    
    Returns:
        Name and details of the frontmost application
    """
    try:
        script = '''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set appName to name of frontApp
    try
        set bundleID to bundle identifier of frontApp
    on error
        set bundleID to "unknown"
    end try
    try
        set winName to name of front window of frontApp
    on error
        set winName to "No window"
    end try
    return "App: " & appName & ", Bundle: " & bundleID & ", Window: " & winName
end tell
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed: {result.error}"
    except Exception as e:
        logger.error(f"Get frontmost app error: {str(e)}")
        return f"Error: {str(e)}"


@tool
async def launch_app(app_name: str, activate: bool = True) -> str:
    """
    Launch an application by name.
    
    Args:
        app_name: Name of the application to launch
        activate: Whether to bring the app to front (default: True)
    
    Returns:
        Result of the launch operation
    """
    try:
        safe_app = escape_applescript(app_name)
        if activate:
            script = f'''
tell application "{safe_app}"
    activate
end tell
return "Launched and activated {safe_app}"
'''
        else:
            script = f'''
tell application "{safe_app}"
    launch
end tell
return "Launched {safe_app} in background"
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed to launch {app_name}: {result.error}"
    except Exception as e:
        logger.error(f"Launch app error: {str(e)}")
        return f"Error launching app: {str(e)}"


@tool
async def quit_app(app_name: str, force: bool = False) -> str:
    """
    Quit an application by name.
    
    Args:
        app_name: Name of the application to quit
        force: Whether to force quit (default: False)
    
    Returns:
        Result of the quit operation
    """
    try:
        safe_app = escape_applescript(app_name)
        if force:
            script = f'''
tell application "System Events"
    set targetProc to first application process whose name is "{safe_app}"
    do shell script "kill -9 " & (unix id of targetProc)
end tell
return "Force quit {safe_app}"
'''
        else:
            script = f'''
tell application "{safe_app}"
    quit
end tell
return "Quit {safe_app}"
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed to quit {app_name}: {result.error}"
    except Exception as e:
        logger.error(f"Quit app error: {str(e)}")
        return f"Error quitting app: {str(e)}"


@tool
async def hide_app(app_name: str) -> str:
    """
    Hide an application.
    
    Args:
        app_name: Name of the application to hide
    
    Returns:
        Result of the hide operation
    """
    try:
        safe_app = escape_applescript(app_name)
        script = f'''
tell application "System Events"
    set visible of process "{safe_app}" to false
end tell
return "Hidden {safe_app}"
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed to hide {app_name}: {result.error}"
    except Exception as e:
        logger.error(f"Hide app error: {str(e)}")
        return f"Error hiding app: {str(e)}"


@tool
async def get_system_state() -> str:
    """
    Get current system state including display, power, and network status.
    
    Returns:
        Comprehensive system state information
    """
    try:
        script = '''
set stateInfo to ""

-- Battery/Power
try
    set batteryInfo to do shell script "pmset -g batt | grep -o '[0-9]*%'"
    set stateInfo to stateInfo & "Battery: " & batteryInfo & linefeed
on error
    set stateInfo to stateInfo & "Battery: Desktop (no battery)" & linefeed
end try

-- Power Source
try
    set powerSource to do shell script "pmset -g batt | head -1 | grep -o \"'.*'\" | tr -d \"'\""
    set stateInfo to stateInfo & "Power Source: " & powerSource & linefeed
on error
    set stateInfo to stateInfo & "Power Source: Unknown" & linefeed
end try

-- WiFi
try
    set wifiNetwork to do shell script "networksetup -getairportnetwork en0 | cut -d: -f2 | xargs"
    set stateInfo to stateInfo & "WiFi: " & wifiNetwork & linefeed
on error
    set stateInfo to stateInfo & "WiFi: Not connected" & linefeed
end try

-- Bluetooth
try
    set btState to do shell script "system_profiler SPBluetoothDataType | grep 'State:' | head -1 | awk '{print $2}'"
    set stateInfo to stateInfo & "Bluetooth: " & btState & linefeed
on error
    set stateInfo to stateInfo & "Bluetooth: Unknown" & linefeed
end try

-- Volume
try
    set volumeLevel to output volume of (get volume settings)
    set muteState to output muted of (get volume settings)
    if muteState then
        set stateInfo to stateInfo & "Volume: Muted (" & volumeLevel & "%)" & linefeed
    else
        set stateInfo to stateInfo & "Volume: " & volumeLevel & "%" & linefeed
    end if
end try

-- Dark Mode
try
    tell application "System Events"
        set isDark to dark mode of appearance preferences
        if isDark then
            set stateInfo to stateInfo & "Appearance: Dark Mode" & linefeed
        else
            set stateInfo to stateInfo & "Appearance: Light Mode" & linefeed
        end if
    end tell
end try

-- Screen Count
try
    set screenCount to do shell script "system_profiler SPDisplaysDataType | grep -c 'Resolution:'"
    set stateInfo to stateInfo & "Displays: " & screenCount & linefeed
end try

return stateInfo
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"## System State:\n\n{result.output}"
        else:
            return f"❌ Failed to get system state: {result.error}"
    except Exception as e:
        logger.error(f"Get system state error: {str(e)}")
        return f"Error getting system state: {str(e)}"


@tool
async def open_file_or_url(path_or_url: str, with_app: Optional[str] = None) -> str:
    """
    Open a file or URL, optionally with a specific application.
    
    Args:
        path_or_url: File path or URL to open
        with_app: Optional application to open with
    
    Returns:
        Result of the open operation
    """
    try:
        safe_path = escape_applescript(path_or_url)
        if with_app:
            safe_app = escape_applescript(with_app)
            script = f'''
tell application "{safe_app}"
    activate
    open "{safe_path}"
end tell
return "Opened with {safe_app}"
'''
        else:
            if path_or_url.startswith("http://") or path_or_url.startswith("https://"):
                script = f'''
open location "{safe_path}"
return "Opened URL in default browser"
'''
            else:
                script = f'''
tell application "Finder"
    open POSIX file "{safe_path}"
end tell
return "Opened file"
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed to open: {result.error}"
    except Exception as e:
        logger.error(f"Open file/URL error: {str(e)}")
        return f"Error opening: {str(e)}"


@tool
async def reveal_in_finder(path: str) -> str:
    """
    Reveal a file or folder in Finder.
    
    Args:
        path: Path to the file or folder
    
    Returns:
        Result of the reveal operation
    """
    try:
        safe_path = escape_applescript(path)
        script = f'''
tell application "Finder"
    reveal POSIX file "{safe_path}"
    activate
end tell
return "Revealed in Finder: {safe_path}"
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed to reveal: {result.error}"
    except Exception as e:
        logger.error(f"Reveal in Finder error: {str(e)}")
        return f"Error revealing: {str(e)}"


@tool
async def get_current_media_info() -> str:
    """
    Get information about currently playing media (Music/Spotify).
    
    Returns:
        Current track, artist, album, and playback state
    """
    try:
        script = '''
set mediaInfo to ""

-- Try Apple Music first
try
    tell application "Music"
        if player state is playing then
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set mediaInfo to "Music: " & trackName & " by " & trackArtist & " (" & trackAlbum & ") - Playing"
        else if player state is paused then
            set trackName to name of current track
            set trackArtist to artist of current track
            set mediaInfo to "Music: " & trackName & " by " & trackArtist & " - Paused"
        end if
    end tell
end try

-- Try Spotify if Music not playing
if mediaInfo is "" then
    try
        tell application "Spotify"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set mediaInfo to "Spotify: " & trackName & " by " & trackArtist & " (" & trackAlbum & ") - Playing"
            else if player state is paused then
                set trackName to name of current track
                set trackArtist to artist of current track
                set mediaInfo to "Spotify: " & trackName & " by " & trackArtist & " - Paused"
            end if
        end tell
    end try
end if

if mediaInfo is "" then
    return "No media currently playing"
else
    return mediaInfo
end if
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"🎵 {result.output}"
        else:
            return f"❌ Failed to get media info: {result.error}"
    except Exception as e:
        logger.error(f"Get media info error: {str(e)}")
        return f"Error getting media info: {str(e)}"


@tool
async def send_system_notification(title: str, message: str, sound: bool = True) -> str:
    """
    Send a system notification.
    
    Args:
        title: Notification title
        message: Notification message
        sound: Whether to play a sound (default: True)
    
    Returns:
        Result of sending the notification
    """
    try:
        safe_title = escape_applescript(title)
        safe_message = escape_applescript(message)
        if sound:
            script = f'''
display notification "{safe_message}" with title "{safe_title}" sound name "default"
return "Sent notification with sound"
'''
        else:
            script = f'''
display notification "{safe_message}" with title "{safe_title}"
return "Sent notification"
'''
        result = await mac_automation.execute_applescript(script)
        if result.success:
            return f"✅ {result.output}"
        else:
            return f"❌ Failed to send notification: {result.error}"
    except Exception as e:
        logger.error(f"Send notification error: {str(e)}")
        return f"Error sending notification: {str(e)}"


def get_tools():
    """Return list of available tools."""
    return [
        # Knowledge & Search
        search_knowledge_base, 
        web_search, 
        process_uploaded_file,
        # Mac Automation - Basic
        run_mac_script,
        execute_applescript,
        execute_shell_command,
        get_available_mac_scripts,
        # Mac Automation - Advanced Input
        click_at_position,
        type_text,
        press_keyboard_shortcut,
        # Mac Automation - Shortcuts
        run_shortcut,
        list_shortcuts,
        # Mac Automation - UI Accessibility
        click_ui_element,
        get_ui_elements,
        # Mac Automation - Window Management
        manage_window,
        # Mac Automation - App Lifecycle
        get_running_apps,
        get_frontmost_app,
        launch_app,
        quit_app,
        hide_app,
        # Mac Automation - System State
        get_system_state,
        open_file_or_url,
        reveal_in_finder,
        get_current_media_info,
        send_system_notification,
    ]
