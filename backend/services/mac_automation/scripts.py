"""
Script Knowledge Base - Pre-built AppleScript/JXA automation recipes.

This module contains a comprehensive library of macOS automation scripts
that the AI can use to control the Mac. Scripts are categorized and
include metadata for intelligent selection.
"""

from typing import Dict, List, Optional, Any
from dataclasses import dataclass
from enum import Enum


class ScriptCategory(Enum):
    SYSTEM = "system"
    APPS = "apps"
    FINDER = "finder"
    BROWSER = "browser"
    MEDIA = "media"
    COMMUNICATION = "communication"
    PRODUCTIVITY = "productivity"
    UTILITIES = "utilities"
    INFORMATION = "information"


@dataclass
class AutomationScript:
    """Pre-defined automation script."""
    id: str
    name: str
    description: str
    category: ScriptCategory
    script: str
    language: str  # "applescript" or "javascript"
    parameters: List[str]  # List of parameter names that can be substituted
    examples: List[str]  # Example use cases


class ScriptKnowledgeBase:
    """
    Knowledge base of pre-built macOS automation scripts.
    
    The AI uses this to find appropriate scripts for user requests
    without hallucinating AppleScript syntax.
    """
    
    def __init__(self):
        self.scripts: Dict[str, AutomationScript] = {}
        self._load_scripts()
    
    def _load_scripts(self):
        """Load all pre-built scripts."""
        
        # ============== SYSTEM INFORMATION ==============
        self._add_script(AutomationScript(
            id="system_get_info",
            name="Get System Information",
            description="Get basic system information including computer name, OS version, and user",
            category=ScriptCategory.SYSTEM,
            script='''
tell application "System Events"
    set compName to computer name of (system info)
    set osVer to system version of (system info)
    set userName to short user name of (system info)
    return "Computer: " & compName & ", macOS: " & osVer & ", User: " & userName
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What's my computer name?", "What macOS version am I running?"]
        ))
        
        self._add_script(AutomationScript(
            id="system_get_battery",
            name="Get Battery Status",
            description="Get current battery level and charging status",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "pmset -g batt | grep -Eo '[0-9]+%' | head -1"
''',
            language="applescript",
            parameters=[],
            examples=["What's my battery level?", "How much battery do I have?"]
        ))
        
        self._add_script(AutomationScript(
            id="system_get_wifi",
            name="Get WiFi Network",
            description="Get the name of the currently connected WiFi network",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '/ SSID/ {print substr($0, index($0, $2))}'"
''',
            language="applescript",
            parameters=[],
            examples=["What WiFi am I connected to?", "What's my network name?"]
        ))
        
        self._add_script(AutomationScript(
            id="system_get_disk_space",
            name="Get Disk Space",
            description="Get available disk space on the main drive",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "df -h / | tail -1 | awk '{print \"Total: \" $2 \", Used: \" $3 \", Available: \" $4 \", Usage: \" $5}'"
''',
            language="applescript",
            parameters=[],
            examples=["How much disk space do I have?", "Is my disk full?"]
        ))
        
        self._add_script(AutomationScript(
            id="system_get_uptime",
            name="Get System Uptime",
            description="Get how long the Mac has been running",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "uptime | sed 's/.*up /Up /' | sed 's/,.*//' "
''',
            language="applescript",
            parameters=[],
            examples=["How long has my Mac been on?", "What's my uptime?"]
        ))
        
        self._add_script(AutomationScript(
            id="system_get_memory",
            name="Get Memory Usage",
            description="Get current RAM usage",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "top -l 1 -s 0 | grep PhysMem | sed 's/PhysMem: //'"
''',
            language="applescript",
            parameters=[],
            examples=["How much RAM am I using?", "What's my memory usage?"]
        ))
        
        self._add_script(AutomationScript(
            id="system_get_cpu",
            name="Get CPU Usage",
            description="Get current CPU usage percentage",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "top -l 1 -s 0 | grep 'CPU usage' | sed 's/CPU usage: //'"
''',
            language="applescript",
            parameters=[],
            examples=["What's my CPU usage?", "How hard is my processor working?"]
        ))
        
        # ============== SYSTEM CONTROLS ==============
        self._add_script(AutomationScript(
            id="system_toggle_dark_mode",
            name="Toggle Dark Mode",
            description="Toggle between light and dark mode",
            category=ScriptCategory.SYSTEM,
            script='''
tell application "System Events"
    tell appearance preferences
        set dark mode to not dark mode
        if dark mode then
            return "Dark mode enabled"
        else
            return "Light mode enabled"
        end if
    end tell
end tell
''',
            language="applescript",
            parameters=[],
            examples=["Toggle dark mode", "Switch to dark mode", "Enable light mode"]
        ))
        
        self._add_script(AutomationScript(
            id="system_set_volume",
            name="Set System Volume",
            description="Set the system volume to a specific level (0-100)",
            category=ScriptCategory.SYSTEM,
            script='''
set volume output volume {volume_level}
return "Volume set to {volume_level}%"
''',
            language="applescript",
            parameters=["volume_level"],
            examples=["Set volume to 50", "Turn volume up to 80", "Mute the volume"]
        ))
        
        self._add_script(AutomationScript(
            id="system_get_volume",
            name="Get System Volume",
            description="Get current system volume level",
            category=ScriptCategory.SYSTEM,
            script='''
output volume of (get volume settings)
''',
            language="applescript",
            parameters=[],
            examples=["What's the current volume?", "How loud is my Mac?"]
        ))
        
        self._add_script(AutomationScript(
            id="system_mute",
            name="Mute/Unmute System",
            description="Toggle system mute",
            category=ScriptCategory.SYSTEM,
            script='''
set currentMute to output muted of (get volume settings)
set volume with output muted (not currentMute)
if currentMute then
    return "Sound unmuted"
else
    return "Sound muted"
end if
''',
            language="applescript",
            parameters=[],
            examples=["Mute my Mac", "Unmute sound", "Toggle mute"]
        ))
        
        self._add_script(AutomationScript(
            id="system_set_brightness",
            name="Set Display Brightness",
            description="Set display brightness (0.0-1.0). Note: Requires brightness CLI tool or uses keyboard simulation",
            category=ScriptCategory.SYSTEM,
            script='''
tell application "System Events"
    -- Use keyboard brightness keys as fallback
    repeat {brightness_steps} times
        key code 145 -- Brightness down key
    end repeat
end tell
return "Adjusted brightness"
''',
            language="applescript",
            parameters=["brightness_steps"],
            examples=["Dim the screen by 5 steps", "Make screen brighter"]
        ))
        
        self._add_script(AutomationScript(
            id="system_notification",
            name="Show Notification",
            description="Display a macOS notification",
            category=ScriptCategory.SYSTEM,
            script='''
display notification "{message}" with title "{title}"
return "Notification sent"
''',
            language="applescript",
            parameters=["title", "message"],
            examples=["Send me a notification", "Remind me with a popup"]
        ))
        
        self._add_script(AutomationScript(
            id="system_say",
            name="Text to Speech",
            description="Make the Mac speak text aloud",
            category=ScriptCategory.SYSTEM,
            script='''
say "{text}"
return "Spoke: {text}"
''',
            language="applescript",
            parameters=["text"],
            examples=["Say hello", "Read this aloud", "Speak this text"]
        ))
        
        self._add_script(AutomationScript(
            id="system_sleep_display",
            name="Sleep Display",
            description="Turn off the display (sleep)",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "pmset displaysleepnow"
return "Display sleeping"
''',
            language="applescript",
            parameters=[],
            examples=["Turn off the screen", "Sleep display", "Black out monitor"]
        ))
        
        self._add_script(AutomationScript(
            id="system_caffeine",
            name="Prevent Sleep",
            description="Prevent Mac from sleeping for a duration",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "caffeinate -d -t {seconds} &"
return "Preventing sleep for {seconds} seconds"
''',
            language="applescript",
            parameters=["seconds"],
            examples=["Keep Mac awake for 1 hour", "Don't let Mac sleep", "Caffeinate"]
        ))
        
        # ============== APPLICATION CONTROL ==============
        self._add_script(AutomationScript(
            id="app_open",
            name="Open Application",
            description="Open/launch a macOS application",
            category=ScriptCategory.APPS,
            script='''
tell application "{app_name}"
    activate
end tell
return "Opened {app_name}"
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Open Safari", "Launch Finder", "Start Music app"]
        ))
        
        self._add_script(AutomationScript(
            id="app_quit",
            name="Quit Application",
            description="Quit/close an application (safe - only quits, doesn't delete)",
            category=ScriptCategory.APPS,
            script='''
tell application "{app_name}"
    quit
end tell
return "Quit {app_name}"
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Quit Safari", "Close Finder", "Exit Music"]
        ))
        
        self._add_script(AutomationScript(
            id="app_list_running",
            name="List Running Apps",
            description="Get list of currently running applications",
            category=ScriptCategory.APPS,
            script='''
tell application "System Events"
    set appNames to name of every application process whose background only is false
    set AppleScript's text item delimiters to ", "
    return appNames as text
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What apps are running?", "Show open applications", "List active apps"]
        ))
        
        self._add_script(AutomationScript(
            id="app_hide",
            name="Hide Application",
            description="Hide an application window",
            category=ScriptCategory.APPS,
            script='''
tell application "System Events"
    set visible of process "{app_name}" to false
end tell
return "Hidden {app_name}"
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Hide Safari", "Minimize Finder"]
        ))
        
        self._add_script(AutomationScript(
            id="app_get_frontmost",
            name="Get Frontmost App",
            description="Get the name of the currently active application",
            category=ScriptCategory.APPS,
            script='''
tell application "System Events"
    return name of first application process whose frontmost is true
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What app is active?", "Which app am I using?"]
        ))
        
        # ============== FINDER ==============
        self._add_script(AutomationScript(
            id="finder_new_window",
            name="Open New Finder Window",
            description="Open a new Finder window at a specific location",
            category=ScriptCategory.FINDER,
            script='''
tell application "Finder"
    activate
    set targetPath to POSIX file "{path}" as alias
    make new Finder window to targetPath
end tell
return "Opened Finder at {path}"
''',
            language="applescript",
            parameters=["path"],
            examples=["Open Finder in Documents", "Show Downloads folder", "Open home folder"]
        ))
        
        self._add_script(AutomationScript(
            id="finder_get_selection",
            name="Get Finder Selection",
            description="Get the currently selected files/folders in Finder",
            category=ScriptCategory.FINDER,
            script='''
tell application "Finder"
    set theSelection to selection
    if theSelection is {} then
        return "No items selected"
    end if
    set itemList to ""
    repeat with anItem in theSelection
        set itemList to itemList & (name of anItem) & ", "
    end repeat
    return "Selected: " & text 1 thru -3 of itemList
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What's selected in Finder?", "What files are highlighted?"]
        ))
        
        self._add_script(AutomationScript(
            id="finder_create_folder",
            name="Create New Folder",
            description="Create a new folder at specified location (use POSIX path like /Users/username/Desktop)",
            category=ScriptCategory.FINDER,
            script='''
tell application "Finder"
    set targetPath to POSIX file "{location}" as alias
    make new folder at targetPath with properties {name:"{folder_name}"}
end tell
return "Created folder '{folder_name}' at {location}"
''',
            language="applescript",
            parameters=["location", "folder_name"],
            examples=["Create a folder on Desktop", "Make new project folder"]
        ))
        
        self._add_script(AutomationScript(
            id="finder_get_current_folder",
            name="Get Current Finder Location",
            description="Get the path of the frontmost Finder window",
            category=ScriptCategory.FINDER,
            script='''
tell application "Finder"
    if (count of Finder windows) > 0 then
        return POSIX path of (target of front Finder window as alias)
    else
        return "No Finder window open"
    end if
end tell
''',
            language="applescript",
            parameters=[],
            examples=["Where am I in Finder?", "What folder is open?"]
        ))
        
        self._add_script(AutomationScript(
            id="finder_open_file",
            name="Open File",
            description="Open a file with its default application",
            category=ScriptCategory.FINDER,
            script='''
tell application "Finder"
    open POSIX file "{file_path}"
end tell
return "Opened {file_path}"
''',
            language="applescript",
            parameters=["file_path"],
            examples=["Open this document", "Open my resume.pdf"]
        ))
        
        self._add_script(AutomationScript(
            id="finder_reveal_file",
            name="Reveal File in Finder",
            description="Show a file or folder in Finder",
            category=ScriptCategory.FINDER,
            script='''
tell application "Finder"
    reveal POSIX file "{file_path}"
    activate
end tell
return "Revealed {file_path} in Finder"
''',
            language="applescript",
            parameters=["file_path"],
            examples=["Show this file in Finder", "Reveal in Finder"]
        ))
        
        # ============== BROWSER (Generic) ==============
        self._add_script(AutomationScript(
            id="browser_open_url",
            name="Open URL",
            description="Open a URL in any browser (Safari, Chrome, Arc, Firefox, etc.)",
            category=ScriptCategory.BROWSER,
            script='''
tell application "{app_name}"
    activate
    try
        open location "{url}"
    on error
        -- Fallback for browsers that might not support 'open location' directly in tell block
        tell application "System Events" to open location "{url}"
    end try
end tell
return "Opened {url} in {app_name}"
''',
            language="applescript",
            parameters=["app_name", "url"],
            examples=["Open google.com in Safari", "Open github.com in Arc", "Go to website in Chrome"]
        ))
        
        self._add_script(AutomationScript(
            id="browser_get_active_url",
            name="Get Active URL",
            description="Get the URL of the active tab in any browser",
            category=ScriptCategory.BROWSER,
            script='''
set appName to "{app_name}"
tell application appName
    try
        if appName contains "Chrome" or appName contains "Brave" or appName contains "Arc" or appName contains "Edge" then
            return URL of active tab of front window
        else if appName contains "Safari" or appName contains "Orion" then
            return URL of front document
        else
            -- Try generic 'URL' property which many scriptable apps support
            return URL of front document
        end if
    on error errMsg
        return "Could not get URL from " & appName & ": " & errMsg
    end try
end tell
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Get URL from Safari", "What page is open in Chrome?", "Get current link in Arc"]
        ))
        
        self._add_script(AutomationScript(
            id="browser_get_active_title",
            name="Get Page Title",
            description="Get the title of the active tab in any browser",
            category=ScriptCategory.BROWSER,
            script='''
set appName to "{app_name}"
tell application appName
    try
        if appName contains "Chrome" or appName contains "Brave" or appName contains "Arc" or appName contains "Edge" then
            return title of active tab of front window
        else
            return name of front document
        end if
    on error
        return "Could not get title from " & appName
    end try
end tell
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Get page title in Safari", "What is the tab name in Chrome?"]
        ))
        
        self._add_script(AutomationScript(
            id="browser_new_tab",
            name="New Browser Tab",
            description="Open a new tab in any browser",
            category=ScriptCategory.BROWSER,
            script='''
set appName to "{app_name}"
tell application appName
    activate
    try
        if appName contains "Safari" then
            tell front window to set current tab to (make new tab)
        else if appName contains "Chrome" or appName contains "Brave" or appName contains "Arc" then
            make new tab at end of tabs of front window
        else
            -- Fallback to keyboard shortcut Cmd+T
            tell application "System Events" to keystroke "t" using command down
        end if
    on error
        tell application "System Events" to keystroke "t" using command down
    end try
end tell
return "Opened new tab in " & appName
''',
            language="applescript",
            parameters=["app_name"],
            examples=["New tab in Safari", "Open empty tab in Chrome"]
        ))
        
        # ============== MEDIA (Generic) ==============
        self._add_script(AutomationScript(
            id="media_play",
            name="Play Media",
            description="Start playing in any media app (Music, Spotify, VLC)",
            category=ScriptCategory.MEDIA,
            script='''
tell application "{app_name}"
    play
end tell
return "{app_name} playing"
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Play Music", "Start Spotify", "Resume VLC"]
        ))
        
        self._add_script(AutomationScript(
            id="media_pause",
            name="Pause Media",
            description="Pause playback in any media app",
            category=ScriptCategory.MEDIA,
            script='''
tell application "{app_name}"
    pause
end tell
return "{app_name} paused"
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Pause Music", "Stop Spotify", "Pause playback"]
        ))
        
        self._add_script(AutomationScript(
            id="media_next",
            name="Next Track",
            description="Skip to next track in any media app",
            category=ScriptCategory.MEDIA,
            script='''
tell application "{app_name}"
    next track
end tell
return "Skipped to next track in {app_name}"
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Next song in Music", "Skip track in Spotify"]
        ))
        
        self._add_script(AutomationScript(
            id="media_previous",
            name="Previous Track",
            description="Go to previous track in any media app",
            category=ScriptCategory.MEDIA,
            script='''
tell application "{app_name}"
    previous track
end tell
return "Previous track in {app_name}"
''',
            language="applescript",
            parameters=["app_name"],
            examples=["Previous song in Music", "Go back in Spotify"]
        ))
        
        self._add_script(AutomationScript(
            id="media_get_info",
            name="Get Media Info",
            description="Get info about currently playing track",
            category=ScriptCategory.MEDIA,
            script='''
set appName to "{app_name}"
tell application appName
    try
        if player state is playing then
            set trackName to name of current track
            set trackArtist to artist of current track
            return "Now playing in " & appName & ": " & trackName & " by " & trackArtist
        else
            return appName & " is not playing."
        end if
    on error
        return "Could not get track info from " & appName
    end try
end tell
''',
            language="applescript",
            parameters=["app_name"],
            examples=["What's playing in Spotify?", "Current song in Music"]
        ))
        
        # ============== CALENDAR ==============
        self._add_script(AutomationScript(
            id="calendar_today_events",
            name="Get Today's Events",
            description="Get calendar events for today",
            category=ScriptCategory.PRODUCTIVITY,
            script='''
tell application "Calendar"
    set today to current date
    set todayStart to today - (time of today)
    set todayEnd to todayStart + (1 * days)
    set eventList to ""
    repeat with cal in calendars
        set theEvents to (every event of cal whose start date ≥ todayStart and start date < todayEnd)
        repeat with evt in theEvents
            set eventList to eventList & (summary of evt) & " at " & time string of (start date of evt) & "\\n"
        end repeat
    end repeat
    if eventList is "" then
        return "No events today"
    else
        return "Today's events:\\n" & eventList
    end if
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What's on my calendar today?", "Do I have meetings today?", "Today's schedule"]
        ))
        
        self._add_script(AutomationScript(
            id="calendar_create_event",
            name="Create Calendar Event",
            description="Create a new calendar event",
            category=ScriptCategory.PRODUCTIVITY,
            script='''
tell application "Calendar"
    tell calendar "Calendar"
        set theEvent to make new event with properties {summary:"{title}", start date:date "{start_date}", end date:date "{end_date}"}
    end tell
end tell
return "Created event: {title}"
''',
            language="applescript",
            parameters=["title", "start_date", "end_date"],
            examples=["Create meeting tomorrow at 2pm", "Add event to calendar"]
        ))
        
        # ============== REMINDERS ==============
        self._add_script(AutomationScript(
            id="reminders_create",
            name="Create Reminder",
            description="Create a new reminder",
            category=ScriptCategory.PRODUCTIVITY,
            script='''
tell application "Reminders"
    tell list "Reminders"
        make new reminder with properties {name:"{reminder_text}"}
    end tell
end tell
return "Created reminder: {reminder_text}"
''',
            language="applescript",
            parameters=["reminder_text"],
            examples=["Remind me to buy milk", "Create reminder", "Add to my todo"]
        ))
        
        self._add_script(AutomationScript(
            id="reminders_list",
            name="List Reminders",
            description="Get list of incomplete reminders",
            category=ScriptCategory.PRODUCTIVITY,
            script='''
tell application "Reminders"
    set reminderList to ""
    set incompleteReminders to (reminders whose completed is false)
    repeat with r in incompleteReminders
        set reminderList to reminderList & "• " & (name of r) & "\\n"
    end repeat
    if reminderList is "" then
        return "No pending reminders"
    else
        return "Reminders:\\n" & reminderList
    end if
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What are my reminders?", "Show my todos", "List reminders"]
        ))
        
        # ============== NOTES ==============
        self._add_script(AutomationScript(
            id="notes_create",
            name="Create Note",
            description="Create a new note in Apple Notes",
            category=ScriptCategory.PRODUCTIVITY,
            script='''
tell application "Notes"
    make new note at folder "Notes" with properties {name:"{title}", body:"{content}"}
end tell
return "Created note: {title}"
''',
            language="applescript",
            parameters=["title", "content"],
            examples=["Create a note", "Make new note", "Save this as a note"]
        ))

        self._add_script(AutomationScript(
            id="notes_search_recent",
            name="Search Recent Notes",
            description="Search for notes modified in the last X days",
            category=ScriptCategory.PRODUCTIVITY,
            script='''
tell application "Notes"
    set d to current date
    set searchDate to d - ({days} * days)
    set results to ""
    try
        set recentNotes to (every note whose modification date > searchDate)
        repeat with n in recentNotes
            set noteTitle to name of n
            set noteBody to body of n
            set results to results & "Title: " & noteTitle & "\\nContent: " & noteBody & "\\n---\\n"
        end repeat
    on error
        return "Error searching notes"
    end try
    
    if results is "" then
        return "No notes found modified in the last {days} days."
    else
        return results
    end if
end tell
''',
            language="applescript",
            parameters=["days"],
            examples=["Show notes from last 7 days", "Recent notes", "What did I write this week?"]
        ))

        self._add_script(AutomationScript(
            id="notes_search_text",
            name="Search Notes by Text",
            description="Search for notes containing specific text",
            category=ScriptCategory.PRODUCTIVITY,
            script='''
tell application "Notes"
    set results to ""
    try
        set foundNotes to (every note whose body contains "{query}" or name contains "{query}")
        repeat with n in foundNotes
            set noteTitle to name of n
            set results to results & "Title: " & noteTitle & "\\n---\\n"
        end repeat
    on error
        return "Error searching notes"
    end try
    
    if results is "" then
        return "No notes found containing '{query}'."
    else
        return results
    end if
end tell
''',
            language="applescript",
            parameters=["query"],
            examples=["Find notes about 'meeting'", "Search notes for 'budget'"]
        ))
        
        # ============== MAIL ==============
        self._add_script(AutomationScript(
            id="mail_unread_count",
            name="Get Unread Mail Count",
            description="Get the number of unread emails",
            category=ScriptCategory.COMMUNICATION,
            script='''
tell application "Mail"
    return (count of (messages of inbox whose read status is false)) & " unread emails"
end tell
''',
            language="applescript",
            parameters=[],
            examples=["How many unread emails?", "Do I have new mail?", "Check email"]
        ))
        
        self._add_script(AutomationScript(
            id="mail_compose",
            name="Compose New Email",
            description="Open a new email composition window",
            category=ScriptCategory.COMMUNICATION,
            script='''
tell application "Mail"
    activate
    set newMessage to make new outgoing message with properties {subject:"{subject}", content:"{body}"}
    tell newMessage
        make new to recipient at end of to recipients with properties {address:"{to_address}"}
    end tell
    set visible of newMessage to true
end tell
return "Opened email draft to {to_address}"
''',
            language="applescript",
            parameters=["to_address", "subject", "body"],
            examples=["Compose email to john@example.com", "Draft new email"]
        ))
        
        # ============== MESSAGES ==============
        self._add_script(AutomationScript(
            id="messages_send",
            name="Send iMessage",
            description="Send an iMessage to a contact",
            category=ScriptCategory.COMMUNICATION,
            script='''
tell application "Messages"
    set targetService to 1st account whose service type = iMessage
    set targetBuddy to participant "{recipient}" of targetService
    send "{message}" to targetBuddy
end tell
return "Sent message to {recipient}"
''',
            language="applescript",
            parameters=["recipient", "message"],
            examples=["Send message to John", "Text Mom"]
        ))
        
        # ============== CLIPBOARD ==============
        self._add_script(AutomationScript(
            id="clipboard_get",
            name="Get Clipboard Content",
            description="Get the current clipboard contents",
            category=ScriptCategory.UTILITIES,
            script='''
the clipboard
''',
            language="applescript",
            parameters=[],
            examples=["What's in my clipboard?", "Show clipboard", "Paste contents"]
        ))
        
        self._add_script(AutomationScript(
            id="clipboard_set",
            name="Set Clipboard Content",
            description="Copy text to the clipboard",
            category=ScriptCategory.UTILITIES,
            script='''
set the clipboard to "{text}"
return "Copied to clipboard: {text}"
''',
            language="applescript",
            parameters=["text"],
            examples=["Copy this to clipboard", "Put this in clipboard"]
        ))
        
        # ============== TERMINAL ==============
        self._add_script(AutomationScript(
            id="terminal_new_tab",
            name="Open Terminal Tab",
            description="Open a new Terminal tab and optionally run a command",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "Terminal"
    activate
    do script "{command}"
end tell
return "Opened Terminal with command: {command}"
''',
            language="applescript",
            parameters=["command"],
            examples=["Open terminal and run ls", "Open new terminal", "Run command in terminal"]
        ))
        
        # ============== SPOTLIGHT ==============
        self._add_script(AutomationScript(
            id="spotlight_search",
            name="Open Spotlight Search",
            description="Open Spotlight with a search query",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    keystroke space using command down
    delay 0.3
    keystroke "{query}"
end tell
return "Searching Spotlight for: {query}"
''',
            language="applescript",
            parameters=["query"],
            examples=["Search for file", "Find application", "Spotlight search"]
        ))
        
        # ============== WINDOW MANAGEMENT ==============
        self._add_script(AutomationScript(
            id="window_minimize_all",
            name="Minimize All Windows",
            description="Minimize all windows of the frontmost app",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    set frontApp to name of first application process whose frontmost is true
    tell process frontApp
        set miniaturized of windows to true
    end tell
end tell
return "Minimized all windows"
''',
            language="applescript",
            parameters=[],
            examples=["Minimize all windows", "Hide windows", "Clear desktop"]
        ))
        
        self._add_script(AutomationScript(
            id="window_get_all",
            name="Get All Windows",
            description="List all open windows",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    set windowList to ""
    repeat with p in (application processes whose background only is false)
        set appName to name of p
        set appWindows to name of windows of p
        if (count of appWindows) > 0 then
            set windowList to windowList & appName & ": " & (appWindows as text) & "\\n"
        end if
    end repeat
    return windowList
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What windows are open?", "List all windows", "Show open windows"]
        ))
        
        # ============== DATE/TIME ==============
        self._add_script(AutomationScript(
            id="datetime_current",
            name="Get Current Date/Time",
            description="Get the current date and time",
            category=ScriptCategory.INFORMATION,
            script='''
set currentDate to current date
return "Current date and time: " & (currentDate as text)
''',
            language="applescript",
            parameters=[],
            examples=["What time is it?", "What's today's date?", "Current time"]
        ))
        
        self._add_script(AutomationScript(
            id="datetime_timer",
            name="Set Timer",
            description="Set a timer that speaks when done",
            category=ScriptCategory.UTILITIES,
            script='''
delay {seconds}
say "Timer complete!"
display notification "Your {seconds} second timer is complete" with title "Timer Done"
return "Timer completed after {seconds} seconds"
''',
            language="applescript",
            parameters=["seconds"],
            examples=["Set a 5 minute timer", "Timer for 30 seconds", "Start countdown"]
        ))
        
        # ============== SCREEN CAPTURE & VISION ==============
        self._add_script(AutomationScript(
            id="screen_capture_full",
            name="Capture Full Screen",
            description="Capture a screenshot of the entire screen and save to Desktop",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "screencapture -x ~/Desktop/jarvis_screenshot_$(date +%Y%m%d_%H%M%S).png"
set screenshotPath to do shell script "ls -t ~/Desktop/jarvis_screenshot_*.png | head -1"
return "Screenshot saved to: " & screenshotPath
''',
            language="applescript",
            parameters=[],
            examples=["Take a screenshot", "Capture my screen", "Screenshot the display"]
        ))
        
        self._add_script(AutomationScript(
            id="screen_capture_window",
            name="Capture Front Window",
            description="Capture a screenshot of the frontmost window",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "screencapture -x -w ~/Desktop/jarvis_window_$(date +%Y%m%d_%H%M%S).png"
set screenshotPath to do shell script "ls -t ~/Desktop/jarvis_window_*.png | head -1"
return "Window screenshot saved to: " & screenshotPath
''',
            language="applescript",
            parameters=[],
            examples=["Screenshot this window", "Capture front window", "Screenshot active window"]
        ))
        
        self._add_script(AutomationScript(
            id="screen_capture_to_clipboard",
            name="Capture Screen to Clipboard",
            description="Capture a screenshot and copy to clipboard for immediate use",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "screencapture -x -c"
return "Screenshot copied to clipboard"
''',
            language="applescript",
            parameters=[],
            examples=["Screenshot to clipboard", "Copy screen to clipboard"]
        ))
        
        self._add_script(AutomationScript(
            id="screen_capture_selection",
            name="Capture Screen Selection",
            description="Capture a selected area of the screen (interactive)",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "screencapture -x -i ~/Desktop/jarvis_selection_$(date +%Y%m%d_%H%M%S).png"
set screenshotPath to do shell script "ls -t ~/Desktop/jarvis_selection_*.png 2>/dev/null | head -1"
if screenshotPath is "" then
    return "Selection cancelled"
else
    return "Selection screenshot saved to: " & screenshotPath
end if
''',
            language="applescript",
            parameters=[],
            examples=["Screenshot a selection", "Capture part of screen"]
        ))
        
        self._add_script(AutomationScript(
            id="screen_capture_specific_display",
            name="Capture Specific Display",
            description="Capture screenshot of a specific display (by number: 1, 2, etc.)",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "screencapture -x -D {display_number} ~/Desktop/jarvis_display{display_number}_$(date +%Y%m%d_%H%M%S).png"
set screenshotPath to do shell script "ls -t ~/Desktop/jarvis_display{display_number}_*.png | head -1"
return "Display {display_number} screenshot saved to: " & screenshotPath
''',
            language="applescript",
            parameters=["display_number"],
            examples=["Screenshot display 2", "Capture second monitor", "Screenshot external display"]
        ))
        
        self._add_script(AutomationScript(
            id="screen_get_displays",
            name="Get Connected Displays",
            description="Get information about all connected displays",
            category=ScriptCategory.INFORMATION,
            script='''
do shell script "system_profiler SPDisplaysDataType | grep -E '(Display Type|Resolution|Main Display|Mirror|Online)' | head -20"
''',
            language="applescript",
            parameters=[],
            examples=["How many monitors?", "What displays are connected?", "Show display info"]
        ))
        
        # ============== ACCESSIBILITY & UI INSPECTION ==============
        self._add_script(AutomationScript(
            id="accessibility_get_frontmost_window_info",
            name="Get Frontmost Window Details",
            description="Get detailed information about the frontmost window including title, size, position",
            category=ScriptCategory.INFORMATION,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set appName to name of frontApp
    set windowInfo to ""
    try
        set frontWindow to front window of frontApp
        set winName to name of frontWindow
        set winPos to position of frontWindow
        set winSize to size of frontWindow
        set windowInfo to "App: " & appName & ", Window: " & winName & ", Position: " & (item 1 of winPos) & "," & (item 2 of winPos) & ", Size: " & (item 1 of winSize) & "x" & (item 2 of winSize)
    on error
        set windowInfo to "App: " & appName & " (no accessible window)"
    end try
    return windowInfo
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What window is active?", "Get window info", "Window details"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_get_ui_elements",
            name="Get UI Elements of Front App",
            description="Get list of UI elements (buttons, text fields, etc.) in the frontmost application",
            category=ScriptCategory.INFORMATION,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set appName to name of frontApp
    set elementInfo to "UI Elements in " & appName & ":\\n"
    try
        set frontWindow to front window of frontApp
        set allButtons to name of every button of frontWindow
        set allTextFields to every text field of frontWindow
        set allStaticTexts to value of every static text of frontWindow
        set elementInfo to elementInfo & "Buttons: " & (allButtons as text) & "\\n"
        set elementInfo to elementInfo & "Text Fields: " & (count of allTextFields) & "\\n"
        set elementInfo to elementInfo & "Static Texts: " & (allStaticTexts as text)
    on error errMsg
        set elementInfo to elementInfo & "Limited access - " & errMsg
    end try
    return elementInfo
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What buttons are visible?", "Get UI elements", "List interface elements"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_get_focused_element",
            name="Get Focused UI Element",
            description="Get information about the currently focused UI element (text field, button, etc.)",
            category=ScriptCategory.INFORMATION,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    try
        set focusedElem to focused UI element of frontApp
        set elemRole to role of focusedElem
        set elemDesc to description of focusedElem
        try
            set elemValue to value of focusedElem
        on error
            set elemValue to "N/A"
        end try
        return "Focused: " & elemRole & " - " & elemDesc & ", Value: " & elemValue
    on error
        return "No focused element accessible"
    end try
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What's focused?", "Current input field", "Focused element"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_get_menu_bar_items",
            name="Get Menu Bar Items",
            description="Get list of menu bar items for the frontmost application",
            category=ScriptCategory.INFORMATION,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set appName to name of frontApp
    try
        set menuItems to name of every menu bar item of menu bar 1 of frontApp
        return "Menu items for " & appName & ": " & (menuItems as text)
    on error
        return "Could not access menu bar for " & appName
    end try
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What menus are available?", "List menu items", "Get menu bar"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_click_button",
            name="Click Button by Name",
            description="Click a button in the frontmost window by its name",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    tell frontApp
        try
            click button "{button_name}" of front window
            return "Clicked button: {button_name}"
        on error
            -- Try finding in groups or other containers
            try
                click button "{button_name}" of group 1 of front window
                return "Clicked button: {button_name}"
            on error errMsg
                return "Could not find or click button '{button_name}': " & errMsg
            end try
        end try
    end tell
end tell
''',
            language="applescript",
            parameters=["button_name"],
            examples=["Click OK button", "Press Cancel", "Click Submit"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_type_text",
            name="Type Text into Focused Field",
            description="Type text into the currently focused text field",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    keystroke "{text}"
end tell
return "Typed: {text}"
''',
            language="applescript",
            parameters=["text"],
            examples=["Type hello", "Enter text", "Type this message"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_press_key",
            name="Press Keyboard Key",
            description="Press a keyboard key or key combination",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    keystroke "{key}" using {modifiers}
end tell
return "Pressed: {key} with {modifiers}"
''',
            language="applescript",
            parameters=["key", "modifiers"],
            examples=["Press Enter", "Press Cmd+C", "Press Tab"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_get_all_windows",
            name="Get All Windows Info",
            description="Get information about all open windows across all applications",
            category=ScriptCategory.INFORMATION,
            script='''
tell application "System Events"
    set windowList to ""
    repeat with proc in (application processes whose background only is false)
        set appName to name of proc
        try
            set appWindows to windows of proc
            repeat with win in appWindows
                try
                    set winName to name of win
                    set winPos to position of win
                    set windowList to windowList & appName & ": " & winName & " at " & (item 1 of winPos) & "," & (item 2 of winPos) & "\\n"
                end try
            end repeat
        end try
    end repeat
    return windowList
end tell
''',
            language="applescript",
            parameters=[],
            examples=["List all windows", "What windows are open?", "Show all open windows"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_get_screen_bounds",
            name="Get Screen Bounds",
            description="Get the bounds and position of all screens/displays",
            category=ScriptCategory.INFORMATION,
            script='''
tell application "Finder"
    set screenBounds to bounds of window of desktop
    return "Main screen bounds: " & (item 1 of screenBounds) & "," & (item 2 of screenBounds) & " to " & (item 3 of screenBounds) & "," & (item 4 of screenBounds)
end tell
''',
            language="applescript",
            parameters=[],
            examples=["Screen size", "Display bounds", "Monitor dimensions"]
        ))
        
        self._add_script(AutomationScript(
            id="accessibility_get_selected_text",
            name="Get Selected Text",
            description="Get the currently selected text in any application",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    keystroke "c" using command down
end tell
delay 0.1
set selectedText to the clipboard
return "Selected text: " & selectedText
''',
            language="applescript",
            parameters=[],
            examples=["What text is selected?", "Get selection", "Copy selected text"]
        ))
        
        # ============== DESKTOP & SPACES ==============
        self._add_script(AutomationScript(
            id="desktop_get_current_space",
            name="Get Current Desktop Space",
            description="Get information about the current desktop space/virtual desktop",
            category=ScriptCategory.INFORMATION,
            script='''
do shell script "defaults read com.apple.spaces spans-displays"
set spaceInfo to result
tell application "System Events"
    set desktopCount to count of desktops
end tell
return "Desktop spaces: " & desktopCount & ", Spans displays: " & spaceInfo
''',
            language="applescript",
            parameters=[],
            examples=["What desktop am I on?", "How many spaces?", "Virtual desktop info"]
        ))
        
        self._add_script(AutomationScript(
            id="desktop_switch_space",
            name="Switch Desktop Space",
            description="Switch to a different desktop space using keyboard shortcut",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    key code 124 using control down -- Right arrow with Control = next space
end tell
return "Switched to next desktop space"
''',
            language="applescript",
            parameters=[],
            examples=["Next desktop", "Switch space", "Go to next virtual desktop"]
        ))
        
        # ============== MOUSE & KEYBOARD SIMULATION ==============
        self._add_script(AutomationScript(
            id="mouse_click_at",
            name="Click at Screen Position",
            description="Perform a mouse click at specific screen coordinates",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "cliclick c:{x},{y}"
return "Clicked at position ({x}, {y})"
''',
            language="applescript",
            parameters=["x", "y"],
            examples=["Click at 500,300", "Mouse click at position", "Click coordinates"]
        ))
        
        self._add_script(AutomationScript(
            id="mouse_double_click",
            name="Double Click at Position",
            description="Perform a double click at specific screen coordinates",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "cliclick dc:{x},{y}"
return "Double clicked at position ({x}, {y})"
''',
            language="applescript",
            parameters=["x", "y"],
            examples=["Double click at 500,300", "Double click position"]
        ))
        
        self._add_script(AutomationScript(
            id="mouse_right_click",
            name="Right Click at Position",
            description="Perform a right click at specific screen coordinates",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "cliclick rc:{x},{y}"
return "Right clicked at position ({x}, {y})"
''',
            language="applescript",
            parameters=["x", "y"],
            examples=["Right click at 500,300", "Context menu at position"]
        ))
        
        self._add_script(AutomationScript(
            id="mouse_move_to",
            name="Move Mouse to Position",
            description="Move the mouse cursor to specific screen coordinates",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "cliclick m:{x},{y}"
return "Moved mouse to position ({x}, {y})"
''',
            language="applescript",
            parameters=["x", "y"],
            examples=["Move mouse to 500,300", "Position cursor"]
        ))
        
        self._add_script(AutomationScript(
            id="mouse_drag",
            name="Drag from Point to Point",
            description="Drag the mouse from one position to another",
            category=ScriptCategory.UTILITIES,
            script='''
do shell script "cliclick dd:{start_x},{start_y} du:{end_x},{end_y}"
return "Dragged from ({start_x}, {start_y}) to ({end_x}, {end_y})"
''',
            language="applescript",
            parameters=["start_x", "start_y", "end_x", "end_y"],
            examples=["Drag from 100,100 to 500,500", "Move element by dragging"]
        ))
        
        self._add_script(AutomationScript(
            id="keyboard_type_text",
            name="Type Text String",
            description="Type a text string as keyboard input",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    keystroke "{text}"
end tell
return "Typed text: {text}"
''',
            language="applescript",
            parameters=["text"],
            examples=["Type hello world", "Enter text", "Type this string"]
        ))
        
        self._add_script(AutomationScript(
            id="keyboard_shortcut",
            name="Press Keyboard Shortcut",
            description="Press a keyboard shortcut combination (e.g., command+c for copy)",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    keystroke "{key}" using {{{modifiers}}}
end tell
return "Pressed shortcut: {modifiers} + {key}"
''',
            language="applescript",
            parameters=["key", "modifiers"],
            examples=["Press Cmd+C", "Copy shortcut", "Press Cmd+V to paste"]
        ))
        
        self._add_script(AutomationScript(
            id="keyboard_press_return",
            name="Press Return/Enter Key",
            description="Press the Return/Enter key",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    key code 36
end tell
return "Pressed Return key"
''',
            language="applescript",
            parameters=[],
            examples=["Press Enter", "Submit form", "Press Return"]
        ))
        
        self._add_script(AutomationScript(
            id="keyboard_press_escape",
            name="Press Escape Key",
            description="Press the Escape key",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    key code 53
end tell
return "Pressed Escape key"
''',
            language="applescript",
            parameters=[],
            examples=["Press Escape", "Cancel dialog", "Close popup"]
        ))
        
        self._add_script(AutomationScript(
            id="keyboard_press_tab",
            name="Press Tab Key",
            description="Press the Tab key to move focus",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    key code 48
end tell
return "Pressed Tab key"
''',
            language="applescript",
            parameters=[],
            examples=["Press Tab", "Next field", "Move focus"]
        ))
        
        self._add_script(AutomationScript(
            id="keyboard_arrow_key",
            name="Press Arrow Key",
            description="Press an arrow key (direction: up, down, left, right)",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    key code {key_code}
end tell
return "Pressed {direction} arrow key"
''',
            language="applescript",
            parameters=["direction", "key_code"],
            examples=["Press up arrow", "Arrow down", "Navigate left"]
        ))
        
        # ============== SHORTCUTS INTEGRATION ==============
        self._add_script(AutomationScript(
            id="shortcuts_list",
            name="List Available Shortcuts",
            description="Get a list of all available Shortcuts on this Mac",
            category=ScriptCategory.INFORMATION,
            script='''
tell application "Shortcuts Events"
    set shortcutNames to name of every shortcut
    set output to ""
    repeat with sName in shortcutNames
        set output to output & sName & ", "
    end repeat
    return output
end tell
''',
            language="applescript",
            parameters=[],
            examples=["List my shortcuts", "What shortcuts are available?", "Show shortcuts"]
        ))
        
        self._add_script(AutomationScript(
            id="shortcuts_run",
            name="Run Shortcut by Name",
            description="Run a Shortcut workflow by its name",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "Shortcuts Events"
    run shortcut "{shortcut_name}"
end tell
return "Ran shortcut: {shortcut_name}"
''',
            language="applescript",
            parameters=["shortcut_name"],
            examples=["Run Morning Routine shortcut", "Execute my workflow", "Run shortcut"]
        ))
        
        self._add_script(AutomationScript(
            id="shortcuts_run_with_input",
            name="Run Shortcut with Input",
            description="Run a Shortcut workflow with text input",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "Shortcuts Events"
    run shortcut "{shortcut_name}" with input "{input_text}"
end tell
return "Ran shortcut '{shortcut_name}' with input"
''',
            language="applescript",
            parameters=["shortcut_name", "input_text"],
            examples=["Run shortcut with data", "Execute workflow with input"]
        ))
        
        self._add_script(AutomationScript(
            id="shortcuts_open_app",
            name="Open Shortcuts App",
            description="Open the Shortcuts application",
            category=ScriptCategory.APPS,
            script='''
tell application "Shortcuts"
    activate
end tell
return "Opened Shortcuts app"
''',
            language="applescript",
            parameters=[],
            examples=["Open Shortcuts", "Launch Shortcuts app"]
        ))
        
        # ============== UI ELEMENT CLICKING ==============
        self._add_script(AutomationScript(
            id="ui_click_menu_item",
            name="Click Menu Item",
            description="Click a menu item in the frontmost application's menu bar",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    tell process "{app_name}"
        set frontmost to true
        click menu item "{menu_item}" of menu "{menu_name}" of menu bar 1
    end tell
end tell
return "Clicked menu: {menu_name} > {menu_item}"
''',
            language="applescript",
            parameters=["app_name", "menu_name", "menu_item"],
            examples=["Click File > Save", "Open Edit menu Copy", "Click menu item"]
        ))
        
        self._add_script(AutomationScript(
            id="ui_click_toolbar_button",
            name="Click Toolbar Button",
            description="Click a button in the toolbar of the frontmost window",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    tell process "{app_name}"
        click button "{button_name}" of toolbar 1 of front window
    end tell
end tell
return "Clicked toolbar button: {button_name}"
''',
            language="applescript",
            parameters=["app_name", "button_name"],
            examples=["Click toolbar button", "Press toolbar item"]
        ))
        
        self._add_script(AutomationScript(
            id="ui_set_text_field",
            name="Set Text Field Value",
            description="Set the value of a text field in the frontmost window",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    tell process "{app_name}"
        set value of text field {field_index} of front window to "{value}"
    end tell
end tell
return "Set text field {field_index} to: {value}"
''',
            language="applescript",
            parameters=["app_name", "field_index", "value"],
            examples=["Set search field", "Enter text in field", "Fill form field"]
        ))
        
        self._add_script(AutomationScript(
            id="ui_click_checkbox",
            name="Click Checkbox",
            description="Toggle a checkbox in the frontmost window",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    tell process "{app_name}"
        click checkbox "{checkbox_name}" of front window
    end tell
end tell
return "Toggled checkbox: {checkbox_name}"
''',
            language="applescript",
            parameters=["app_name", "checkbox_name"],
            examples=["Toggle checkbox", "Check option", "Uncheck setting"]
        ))
        
        self._add_script(AutomationScript(
            id="ui_select_popup",
            name="Select Popup Menu Item",
            description="Select an item from a popup button/menu",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    tell process "{app_name}"
        click pop up button 1 of front window
        click menu item "{item_name}" of menu 1 of pop up button 1 of front window
    end tell
end tell
return "Selected popup item: {item_name}"
''',
            language="applescript",
            parameters=["app_name", "item_name"],
            examples=["Select from dropdown", "Choose popup option"]
        ))
        
        # ============== WINDOW MANAGEMENT ==============
        self._add_script(AutomationScript(
            id="window_move",
            name="Move Window to Position",
            description="Move the frontmost window to a specific position",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set position of front window of frontApp to {{{x}, {y}}}
end tell
return "Moved window to position ({x}, {y})"
''',
            language="applescript",
            parameters=["x", "y"],
            examples=["Move window to 0,0", "Position window", "Move window top left"]
        ))
        
        self._add_script(AutomationScript(
            id="window_resize",
            name="Resize Window",
            description="Resize the frontmost window to specific dimensions",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set size of front window of frontApp to {{{width}, {height}}}
end tell
return "Resized window to {width}x{height}"
''',
            language="applescript",
            parameters=["width", "height"],
            examples=["Resize window to 1200x800", "Make window bigger", "Set window size"]
        ))
        
        self._add_script(AutomationScript(
            id="window_maximize",
            name="Maximize Window",
            description="Maximize the frontmost window to fill the screen",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    set frontmost of frontApp to true
    keystroke "f" using {control down, command down}
end tell
return "Maximized window"
''',
            language="applescript",
            parameters=[],
            examples=["Maximize window", "Full screen", "Make window fullscreen"]
        ))
        
        self._add_script(AutomationScript(
            id="window_arrange_side_by_side",
            name="Arrange Windows Side by Side",
            description="Arrange the two frontmost windows side by side",
            category=ScriptCategory.UTILITIES,
            script='''
tell application "System Events"
    set screenWidth to (do shell script "system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $2}'") as number
    set screenHeight to (do shell script "system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $4}'") as number
    set halfWidth to screenWidth / 2
    
    set allProcs to (application processes whose background only is false)
    set visibleWindows to {}
    repeat with proc in allProcs
        try
            set wins to windows of proc
            repeat with w in wins
                set end of visibleWindows to {proc, w}
            end repeat
        end try
    end repeat
    
    if (count of visibleWindows) >= 2 then
        set {proc1, win1} to item 1 of visibleWindows
        set {proc2, win2} to item 2 of visibleWindows
        set position of win1 to {0, 25}
        set size of win1 to {halfWidth, screenHeight - 25}
        set position of win2 to {halfWidth, 25}
        set size of win2 to {halfWidth, screenHeight - 25}
    end if
end tell
return "Arranged windows side by side"
''',
            language="applescript",
            parameters=[],
            examples=["Split screen", "Side by side windows", "Tile windows"]
        ))
    
    def _add_script(self, script: AutomationScript):
        """Add a script to the knowledge base."""
        self.scripts[script.id] = script
    
    def get_script(self, script_id: str) -> Optional[AutomationScript]:
        """Get a script by ID."""
        return self.scripts.get(script_id)
    
    def search_scripts(self, query: str) -> List[AutomationScript]:
        """Search for scripts matching a query."""
        query_lower = query.lower()
        results = []
        for script in self.scripts.values():
            # Check name, description, and examples
            if (query_lower in script.name.lower() or
                query_lower in script.description.lower() or
                any(query_lower in ex.lower() for ex in script.examples)):
                results.append(script)
        return results
    
    def get_scripts_by_category(self, category: ScriptCategory) -> List[AutomationScript]:
        """Get all scripts in a category."""
        return [s for s in self.scripts.values() if s.category == category]
    
    def get_all_scripts_summary(self) -> str:
        """Get a summary of all available scripts for the AI."""
        summary = "## Available Mac Automation Scripts:\n\n"
        
        # Group by category
        categories: Dict[ScriptCategory, List[AutomationScript]] = {}
        for script in self.scripts.values():
            if script.category not in categories:
                categories[script.category] = []
            categories[script.category].append(script)
        
        for category, scripts in sorted(categories.items(), key=lambda x: x[0].value):
            summary += f"### {category.value.upper()}\n"
            for script in scripts:
                params = f" (params: {', '.join(script.parameters)})" if script.parameters else ""
                summary += f"- **{script.id}**: {script.name}{params} - {script.description}\n"
            summary += "\n"
        
        return summary
    
    def _escape_applescript_string(self, text: Any) -> str:
        """Escape special characters for AppleScript strings."""
        if text is None:
            return ""
        if isinstance(text, bool):
            return "true" if text else "false"
        if isinstance(text, (list, tuple)):
            # Recursively escape items and join with comma
            # This is a best-effort guess for list parameters
            return ", ".join(self._escape_applescript_string(item) for item in text)
            
        text_str = str(text)
        # Escape backslashes first, then double quotes
        return text_str.replace("\\", "\\\\").replace('"', '\\"')

    def prepare_script(self, script_id: str, parameters: Dict[str, Any]) -> Optional[str]:
        """
        Prepare a script for execution by substituting parameters.
        
        Args:
            script_id: The ID of the script to prepare
            parameters: Dictionary of parameter values to substitute
        
        Returns:
            The prepared script string, or None if script not found
        """
        script = self.get_script(script_id)
        if not script:
            return None
        
        prepared = script.script
        for param, value in parameters.items():
            placeholder = "{" + param + "}"
            # Escape the value before substitution to prevent syntax errors
            escaped_value = self._escape_applescript_string(str(value))
            prepared = prepared.replace(placeholder, escaped_value)
        
        return prepared.strip()


# Singleton instance
script_kb = ScriptKnowledgeBase()
