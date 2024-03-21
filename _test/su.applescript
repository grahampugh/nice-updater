#!/usr/bin/osascript
-- open the System Settings Software Update pane
try
    -- restart the target application (required to ensure we get to the Software Update pane)
    tell application "System Settings"
        quit
    end tell

    delay 1
    
    tell application "System Settings"
        activate
    end tell

    delay 2

    tell application "System Events"
        tell process "System Settings"
            tell menu bar 1
                tell menu bar item "View"
                    click menu item "General"
                    tell menu "View"
                        click menu item "Software Update"
                    end tell
                end tell
            end tell
        end tell
    end tell
end try
