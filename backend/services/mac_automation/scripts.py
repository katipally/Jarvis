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
            description="Set display brightness (0.0-1.0)",
            category=ScriptCategory.SYSTEM,
            script='''
do shell script "brightness {brightness_level}"
return "Brightness set to {brightness_level}"
''',
            language="applescript",
            parameters=["brightness_level"],
            examples=["Set brightness to 0.5", "Dim the screen", "Make screen brighter"]
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
    make new Finder window to folder "{path}"
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
            description="Create a new folder at specified location",
            category=ScriptCategory.FINDER,
            script='''
tell application "Finder"
    make new folder at folder "{location}" with properties {name:"{folder_name}"}
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
        
        # ============== BROWSER (Safari) ==============
        self._add_script(AutomationScript(
            id="safari_open_url",
            name="Open URL in Safari",
            description="Open a URL in Safari browser",
            category=ScriptCategory.BROWSER,
            script='''
tell application "Safari"
    activate
    open location "{url}"
end tell
return "Opened {url} in Safari"
''',
            language="applescript",
            parameters=["url"],
            examples=["Open google.com", "Go to GitHub", "Open this website"]
        ))
        
        self._add_script(AutomationScript(
            id="safari_get_url",
            name="Get Current Safari URL",
            description="Get the URL of the current Safari tab",
            category=ScriptCategory.BROWSER,
            script='''
tell application "Safari"
    return URL of front document
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What page am I on?", "Get current URL", "What website is this?"]
        ))
        
        self._add_script(AutomationScript(
            id="safari_get_title",
            name="Get Safari Page Title",
            description="Get the title of the current Safari page",
            category=ScriptCategory.BROWSER,
            script='''
tell application "Safari"
    return name of front document
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What's this page called?", "Get page title"]
        ))
        
        self._add_script(AutomationScript(
            id="safari_new_tab",
            name="New Safari Tab",
            description="Open a new tab in Safari",
            category=ScriptCategory.BROWSER,
            script='''
tell application "Safari"
    activate
    tell front window
        set newTab to make new tab
        set current tab to newTab
    end tell
end tell
return "Opened new Safari tab"
''',
            language="applescript",
            parameters=[],
            examples=["New tab in Safari", "Open new browser tab"]
        ))
        
        self._add_script(AutomationScript(
            id="safari_list_tabs",
            name="List Safari Tabs",
            description="Get list of all open Safari tabs",
            category=ScriptCategory.BROWSER,
            script='''
tell application "Safari"
    set tabList to ""
    repeat with w in windows
        repeat with t in tabs of w
            set tabList to tabList & name of t & " | "
        end repeat
    end repeat
    return tabList
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What tabs are open?", "List my Safari tabs"]
        ))
        
        # ============== BROWSER (Chrome) ==============
        self._add_script(AutomationScript(
            id="chrome_open_url",
            name="Open URL in Chrome",
            description="Open a URL in Google Chrome",
            category=ScriptCategory.BROWSER,
            script='''
tell application "Google Chrome"
    activate
    open location "{url}"
end tell
return "Opened {url} in Chrome"
''',
            language="applescript",
            parameters=["url"],
            examples=["Open google.com in Chrome", "Go to GitHub in Chrome"]
        ))
        
        self._add_script(AutomationScript(
            id="chrome_get_url",
            name="Get Current Chrome URL",
            description="Get the URL of the active Chrome tab",
            category=ScriptCategory.BROWSER,
            script='''
tell application "Google Chrome"
    return URL of active tab of front window
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What URL is in Chrome?", "Get Chrome URL"]
        ))
        
        # ============== MEDIA (Music) ==============
        self._add_script(AutomationScript(
            id="music_play",
            name="Play Music",
            description="Start playing music in Apple Music",
            category=ScriptCategory.MEDIA,
            script='''
tell application "Music"
    play
end tell
return "Music playing"
''',
            language="applescript",
            parameters=[],
            examples=["Play music", "Start music", "Resume playback"]
        ))
        
        self._add_script(AutomationScript(
            id="music_pause",
            name="Pause Music",
            description="Pause music in Apple Music",
            category=ScriptCategory.MEDIA,
            script='''
tell application "Music"
    pause
end tell
return "Music paused"
''',
            language="applescript",
            parameters=[],
            examples=["Pause music", "Stop music", "Pause playback"]
        ))
        
        self._add_script(AutomationScript(
            id="music_next",
            name="Next Track",
            description="Skip to the next track",
            category=ScriptCategory.MEDIA,
            script='''
tell application "Music"
    next track
end tell
return "Skipped to next track"
''',
            language="applescript",
            parameters=[],
            examples=["Next song", "Skip track", "Next track"]
        ))
        
        self._add_script(AutomationScript(
            id="music_previous",
            name="Previous Track",
            description="Go to the previous track",
            category=ScriptCategory.MEDIA,
            script='''
tell application "Music"
    previous track
end tell
return "Went to previous track"
''',
            language="applescript",
            parameters=[],
            examples=["Previous song", "Go back", "Last track"]
        ))
        
        self._add_script(AutomationScript(
            id="music_current_track",
            name="Get Current Track",
            description="Get info about the currently playing track",
            category=ScriptCategory.MEDIA,
            script='''
tell application "Music"
    if player state is playing then
        set trackName to name of current track
        set artistName to artist of current track
        set albumName to album of current track
        return "Now playing: " & trackName & " by " & artistName & " from " & albumName
    else
        return "No music currently playing"
    end if
end tell
''',
            language="applescript",
            parameters=[],
            examples=["What song is playing?", "What's this track?", "Current song"]
        ))
        
        self._add_script(AutomationScript(
            id="music_play_playlist",
            name="Play Playlist",
            description="Play a specific playlist by name",
            category=ScriptCategory.MEDIA,
            script='''
tell application "Music"
    play playlist "{playlist_name}"
end tell
return "Playing playlist: {playlist_name}"
''',
            language="applescript",
            parameters=["playlist_name"],
            examples=["Play my workout playlist", "Play 'Chill' playlist"]
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
            prepared = prepared.replace(placeholder, str(value))
        
        return prepared.strip()


# Singleton instance
script_kb = ScriptKnowledgeBase()
