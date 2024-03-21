#!/bin/bash

# Nice Updater 2
version="2.5.0"

# These variables will be automagically updated if you run build.sh, no need to modify them
preferenceFileFullPath="/Library/Preferences/com.grahamrpugh.nice_updater.prefs.plist"

###### Variables below this point are not intended to be modified #####
helperTitle=$(/usr/bin/defaults read "$preferenceFileFullPath" UpdateRequiredTitle)
helperDesc=$(/usr/bin/defaults read "$preferenceFileFullPath" UpdateRequiredMessage)
alertTimeout=$(/usr/bin/defaults read "$preferenceFileFullPath" AlertTimeout)
log=$(/usr/bin/defaults read "$preferenceFileFullPath" Log)
EAFile=$(/usr/bin/defaults read "$preferenceFileFullPath" EAFile)
afterFullUpdateDelayDayCount=$(/usr/bin/defaults read "$preferenceFileFullPath" AfterFullUpdateDelayDayCount)
afterEmptyUpdateDelayDayCount=$(/usr/bin/defaults read "$preferenceFileFullPath" AfterEmptyUpdateDelayDayCount)
maxNotificationCount=$(/usr/bin/defaults read "$preferenceFileFullPath" MaxNotificationCount)
iconCustomPath=$(/usr/bin/defaults read "$preferenceFileFullPath" IconCustomPath)
workdir="/Library/Scripts/"

scriptName=$(basename "$0")
current_user=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')

# swiftDialog tool
dialog_app="/Library/Application Support/Dialog/Dialog.app"
dialog_bin="/usr/local/bin/dialog"
dialog_log=$(/usr/bin/mktemp /var/tmp/dialog.XXX)

## FUNCTIONS

getSwiftDialogDownloadURL() {
    url="https://api.github.com/repos/swiftDialog/swiftDialog/releases"
    header="Accept: application/json"
    tag=${1:-"$(curl -sL -H "${header}" ${url}/latest | awk -F '"' '/tag_name/ { print $4; exit }')"}
    
    curl -sL -H "${header}" ${url}/tags/${tag} | awk -F '"' '/browser_download_url/ { print $4; exit }'
}

writelog() {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    echo "${1}"
    echo "$DATE" " $1" >> "$log"
}

write_status() {
    echo "$1" > "$EAFile"
}

finish() {
    writelog "======== Finished $scriptName ========"
    exit "$1"
}

# -----------------------------------------------------------------------------
# Download dialog if not present
# -----------------------------------------------------------------------------
check_for_dialog_app() {
    if [[ -d "$dialog_app" && -f "$dialog_bin" ]]; then
        writelog "   [check_for_dialog_app] dialog is installed ($dialog_app)"
    else
        writelog "   [check_for_dialog_app] Downloading swiftDialog.app..."
        if /usr/bin/curl -L "$dialog_download_url" -o "$workdir/dialog.pkg" ; then
            if ! /usr/sbin/installer -pkg "$workdir/dialog.pkg" -target / ; then
                writelog "   [check_for_dialog_app] dialog installation failed"
            fi
        else
            writelog "   [check_for_dialog_app] dialog download failed"
        fi
        # check it did actually get downloaded
        if [[ -d "$dialog_app" && -f "$dialog_bin" ]]; then
            writelog "   [check_for_dialog_app] dialog is installed"
            # quit an existing window
            echo "quit:" >> "$dialog_log"
        else
            writelog "   [check_for_dialog_app] Could not download dialog."
        fi
    fi
    # ensure log file is writable
    writelog "[check_for_dialog_app] Creating dialog log ($dialog_log)..."
    /usr/bin/touch "$dialog_log"
    /usr/sbin/chown "$current_user:wheel" "$dialog_log"
    /bin/chmod 666 "$dialog_log"
}

# -----------------------------------------------------------------------------
# Default dialog arguments
# -----------------------------------------------------------------------------
get_default_dialog_args() {
    # set the dialog command arguments
    # $1 - window type
    default_dialog_args=(
        "--ontop"
        "--json"
        "--ignorednd"
        "--position"
        "centre"
        "--quitkey"
        "C"
    )
    if [[ "$1" == "fullscreen" ]]; then
        echo "   [get_default_dialog_args] Invoking fullscreen dialog"
        default_dialog_args+=(
            "--blurscreen"
            "--width"
            "60%"
            "--button1disabled"
            "--iconsize"
            "256"
            "--centreicon"
            "--titlefont"
            "size=32"
            "--messagefont"
            "size=24"
            "--alignment"
            "centre"
        )
    elif [[ "$1" == "utility" ]]; then
        echo "   [get_default_dialog_args] Invoking utility dialog"
        default_dialog_args+=(
            "--width"
            "60%"
            "--titlefont"
            "size=20"
            "--messagefont"
            "size=14"
            "--alignment"
            "left"
            "--iconsize"
            "128"
        )
    fi
}

random_delay() {
    delay_time=$(( (RANDOM % 10)+1 ))
    writelog "Delaying software update check by ${delay_time}s"
    # sleep ${delay_time}
}

record_last_full_update() {
    writelog "Done with update process; recording last full update time"
    /usr/libexec/PlistBuddy -c "Delete :last_full_update_time" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :last_full_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath

    writelog "Clearing user alert data"
    /usr/libexec/PlistBuddy -c "Delete :users" $preferenceFileFullPath

    writelog "Clearing On-Demand Update Key"
    /usr/libexec/PlistBuddy -c "Delete :update_key" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :update_key array" $preferenceFileFullPath 2> /dev/null
}

get_system_version() {
    system_version=$( /usr/bin/sw_vers -productVersion )
    return "${system_version:0}"
}

open_software_update() {
    open_su_helper
    sleep 5
    suPID=$(pgrep "System Settings")
    writelog "Software Update open with PID: $suPID"

    # While Software Update is open...
    timecount=0
    while kill -0 "$suPID" 2> /dev/null; do
        sleep 1
        # ensure system settings is in the foreground
        /usr/bin/osascript <<APPLESCRIPT &
-- open the System Settings Software Update pane
try
    -- bring the target application to the front
    tell application "System Settings"
        activate
        try
            set miniaturized of windows to false
        end try
    end tell
end try
APPLESCRIPT
        # set a maximum time that Software Update can be open before killing System Settings and invoking another dialog
        ((timecount++))
        if [[ $timecount -ge 900 ]]; then
            break
        fi
    done
    if [[ $timecount -ge 900 ]]; then
        writelog "Software Update was open too long"
        write_status "Software Update was open too long"
        if pgrep "System Settings"; then
            pkill "System Settings"
        elif pgrep "System Preferences"; then
            pkill "System Preferences"
        fi
    else
        writelog "Software Update was closed"
        write_status "Software Update was closed"
    fi
    was_closed=1
}

compare_date() {
    then_unix="$(date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s)"  # convert date to unix timestamp
    now_unix="$(date +'%s')"    # Get timestamp from right now
    delta=$(( now_unix - then_unix ))   # Will get the amount of time in seconds between then and now
    daysAgo="$((delta / (60*60*24)))"   # Converts the seconds to days
    echo $daysAgo
    return
}

alert_user() {
    local subtitle="$1"
    [[ "$notificationsLeft" == "1" ]] && local subtitle="1 remaining deferral"
    [[ "$notificationsLeft" == "0" ]] && local subtitle="No deferrals remaining! Click on \"Install Now\" to proceed"

    message="**$subtitle**\n\nSoftware updates are available to be installed on this Mac which require a restart:\n\n"
    for ((i=0; i<"${#updatesRestart[@]}"; i++)); do
        message="$message""- ${updatesRestart[$i]}  \n"
    done
    message="$message\n"
    message="$message""$helperDesc"

    writelog "Notifying $loggedInUser of available updates..."
    if [[ "$notificationsLeft" == "0" ]]; then
        # quit any existing window
        echo "quit:" >> "$dialog_log"
        writelog "Opening utility dialog window without deferral button"
        # set the dialog command arguments
        get_default_dialog_args "utility"
        dialog_args=("${default_dialog_args[@]}")
        dialog_args+=(
            "--title"
            "$helperTitle"
            "--message"
            "$message"
            "--icon"
            "$icon"
            "--button1text"
            "Install Now"
        )
        # run the dialog command
        "$dialog_bin" "${dialog_args[@]}" & sleep 0.1

    else
        # quit any existing window
        echo "quit:" >> "$dialog_log"
        writelog "Opening utility dialog window with deferral button"
        # set the dialog command arguments
        get_default_dialog_args "utility"
        dialog_args=("${default_dialog_args[@]}")
        dialog_args+=(
            "--title"
            "$helperTitle"
            "--message"
            "$message"
            "--icon"
            "$icon"
            "--button1text"
            "Continue"
            "--button2text"
            "Defer for 24 hours"
            "--timer"
            "$alertTimeout"
            "--hidetimerbar"
        )
        # run the dialog command
        "$dialog_bin" "${dialog_args[@]}" & sleep 0.1
    fi

    # get the helper exit code
    dialogPID=$!
    wait $dialogPID
    helperExitCode=$?
    writelog "Dialog exit code: $helperExitCode"

    # all exit codes decrease the remaining deferrals except when the window times out without response
    if [[ $helperExitCode -eq 0 ]]; then
        writelog "User initiated installation"
        write_status "User initiated installation"
        open_software_update
    elif [[ $helperExitCode -eq 2 ]]; then
        writelog "User cancelled installation"
        write_status "User cancelled installation"
    elif [[ $helperExitCode -eq 10 ]]; then
        writelog "User quit dialog using the quit key"
        write_status "User quit dialog using the quit key"
        open_software_update
    else
        writelog "Alert timed out without response"
        write_status "Alert timed out without response"
        ((notificationCount--))
    fi

    /usr/libexec/PlistBuddy -c "Add :users dict" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Delete :users:$loggedInUser" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser dict" $preferenceFileFullPath
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser:alert_count integer $notificationCount" $preferenceFileFullPath
}

alert_logic() {
    was_closed=0
    notificationCount=$(/usr/libexec/PlistBuddy -c "Print :users:$loggedInUser:alert_count" $preferenceFileFullPath 2> /dev/null | xargs)
    if [[ "$notificationCount" -ge "$maxNotificationCount" ]]; then
        notificationsLeft="$((maxNotificationCount - notificationCount))"
        writelog "$loggedInUser has been notified $notificationCount times; not waiting any longer"
        alert_user "No remaining deferrals" "$notificationCount"
    else
        ((notificationCount++))
        notificationsLeft="$((maxNotificationCount - notificationCount))"
        writelog "$notificationsLeft remaining deferrals"
        alert_user "$notificationsLeft remaining deferrals" "$notificationCount"
    fi
}

update_check() {
    osVersion=$( /usr/bin/sw_vers -productVersion )
    writelog "Determining available Software Updates for macOS $osVersion..."
    update_file="/tmp/nice_updater_updates.txt"
    /usr/sbin/softwareupdate --list --include-config-data > "$update_file"

    # create list of updates that do not require a restart
    updatesNoRestart=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            updatesNoRestart+=("$line")
            writelog "Added '$line' to list of updates that do not require a restart"
        fi
    done <<< "$(grep -v restart "$update_file" | grep -v 'Deferred: YES' | grep -B1 'Recommended: YES' | grep -v -i Recommended | grep -v '\-\-' | sed 's|.*\* ||g' | sed 's|^Label: ||')"

    # create list of updates that do require a restart
    updatesRestart=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            updatesRestart+=("$line")
            writelog "Added '$line' to list of updates that require a restart"
        fi
    done <<< "$(grep -v 'Deferred: YES' "$update_file" | grep -B1 'Recommended: YES, Action: restart' | grep -v restart | grep -v '\-\-' | sed 's|.*\* ||g' | sed 's|^Label: ||')"

    updateCount=$(grep -c "Recommended: YES" "$update_file")

    if [[ "$updateCount" -gt "0" ]]; then
        # Download the updates
        # writelog "Downloading $updateCount update(s)..."
        # /usr/sbin/softwareupdate --download "${updatesNoRestart[@]}" | grep --line-buffered Downloaded | while read -r LINE; do writelog "$LINE"; done

        # install any updates that do not require a restart, as these do not require authentication.
        if [[ "${#updatesNoRestart[@]}" -gt 0 ]]; then
            writelog "Installing updates that DO NOT require a restart in the background..."
            /usr/sbin/softwareupdate --no-scan --install "${updatesNoRestart[@]}"
            /usr/sbin/softwareupdate --background --include-config
        fi

        # If the script moves past this point, a restart is required.
        if [[ "${#updatesRestart[@]}" -gt 0 ]]; then
            writelog "A restart is required for remaining updates"
            # Abort if no user is logged in. Check the user now as some time has past since the script began.
            loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
            if [[ "$loggedInUser" == "root" ]] || [[ -z "$loggedInUser" ]]; then
                writelog "No user logged in. Cannot proceed"
            else
                # Getting here means a user is logged in, alert them that they will need to install and restart
                alert_logic
                # repeat if software update was closed
                while [[ $was_closed = 1 ]]; do
                    random_delay
                    alert_logic
                done
            fi
        else
            record_last_full_update
            writelog "No updates that require a restart available; exiting"
            write_status "No updates that require a restart available; exiting"
            finish 0
        fi
    else
        writelog "No updates at this time; exiting"
        write_status "No updates at this time; exiting"
        /usr/libexec/PlistBuddy -c "Delete :last_empty_update_time" $preferenceFileFullPath 2> /dev/null
        /usr/libexec/PlistBuddy -c "Add :last_empty_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath
        /usr/libexec/PlistBuddy -c "Delete :users" $preferenceFileFullPath 2> /dev/null
        finish 0
    fi
}

main() {
    # This function is intended to be run from a LaunchDaemon at intervals

    writelog " "
    writelog "======== Starting $scriptName v$version ========"

    # URL for downloading dialog (with tag version)
    # This ensures a compatible dialog is used if not using the package installer
    swiftdialog_tag_required="v2.4.2"
    dialog_download_url=$(getSwiftDialogDownloadURL "${swiftdialog_tag_required}")
    echo "download url for tag version : ${dialog_download_url}"

    # set default icon if not included in build
    if [[ "$iconCustomPath" == "/Applications/Self Service.app" ]]; then
        # Create temporary icon from Self Service's custom icon (thanks, @meschwartz via @dan-snelson!)
        temp_icon_path="/var/tmp/overlayicon.icns"
        /usr/bin/xxd -p -s 260 "$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path)"/Icon$'\r'/..namedfork/rsrc | /usr/bin/xxd -r -p > "$temp_icon_path"
        icon="$temp_icon_path"
    elif [[ "$iconCustomPath" ]]; then
        icon="$iconCustomPath"
    else
        icon="/System/Library/PrivateFrameworks/SoftwareUpdate.framework/Versions/A/Resources/SoftwareUpdate.icns"
    fi

    # See if we are blocking updates, if so exit
    updatesBlocked=$(/usr/libexec/PlistBuddy -c "Print :updates_blocked" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
    if [[ "$updatesBlocked" == "true" ]]; then
        writelog "Updates are blocked for this client at this time; exiting"
        write_status "Updates are blocked for this client at this time; exiting"
        finish 0
    fi

    # Check the last time we had a full successful update
    updatesAvailable=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastRecommendedUpdatesAvailable | /usr/bin/awk '{ if  (NF > 2) {print $1 " "  $2} else { print $0 }}')
    if [[ "$updatesAvailable" -gt "0" ]]; then
        writelog "At least one recommended update was marked available from a previous check."
        random_delay
        update_check
    else
        lastFullUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_full_update_time" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
        lastEmptyUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_empty_update_time" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
        if [[ -n "$lastFullUpdateTime" ]]; then
            daysSinceLastFullUpdate="$(compare_date "$lastFullUpdateTime")"
            if [[ "$daysSinceLastFullUpdate" -ge "$afterFullUpdateDelayDayCount" ]]; then
                writelog "$afterFullUpdateDelayDayCount or more days have passed since last full update"
                # delay script's actions by up to 1 min to prevent all computers running software update at the same time
                random_delay
                update_check
            else
                writelog "Less than $afterFullUpdateDelayDayCount days since last full update; exiting"
                write_status "Less than $afterFullUpdateDelayDayCount days since last full update; exiting"
                finish 0
            fi
        elif [[ -n "$lastEmptyUpdateTime" ]]; then
            daysSinceLastEmptyUpdate="$(compare_date "$lastEmptyUpdateTime")"
            if [[ "$daysSinceLastEmptyUpdate" -ge "$afterEmptyUpdateDelayDayCount" ]]; then
                writelog "$afterEmptyUpdateDelayDayCount or more days have passed since last empty update check"
                # delay script's actions by up to 1 min to prevent all computers running software update at the same time
                random_delay
                update_check
            else
                writelog "Less than $afterEmptyUpdateDelayDayCount days since last empty update check; exiting"
                write_status "Less than $afterEmptyUpdateDelayDayCount days since last empty update check; exiting"
                finish 0
            fi
        else
            writelog "This device might not have performed a full update yet"
                # delay script's actions by up to 1 min to prevent all computers running software update at the same time
            random_delay
            update_check
        fi
    fi

    finish 0
}

open_su_helper() {
        /usr/bin/osascript <<APPLESCRIPT &
# Taken from https://github.com/xirianlight/openToMoreInfo

# This version of the script has multiple repeat loops at the end:
# Loop 1 - click "More Info" to bring up the list of updates
# Loop 2 - Click "Install Now" to begin the download/install
# Loop 3 - Approve the EULA for the update (Ventura logic now includes Xcode SDK EULA)
# Validated in macOS 11, 12, 13, 14, Intel & ARM
# Note: Sonoma logic clicks the Update Now button, as the "More Info" button continues to be inoperable

# Get Major OS
set _major to system attribute "sys1"

# Bailout if old version
if _major < 11 then
	log "Catalina or earlier detected"
	error number -128
end if

# Sonoma
if (_major = 14) then
	log "Sonoma detected"
	
	# Launch software Update preference pane
	do shell script "open x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
	
	# Wait for window to open
	tell application "System Events"
		repeat 60 times
			if exists (window 1 of process "System Settings") then
				delay 3
				exit repeat
			else
				delay 1
			end if
		end repeat
		
		if not (exists (window 1 of process "System Settings")) then
			return
		end if
	end tell
	
	# Click "Update Now" or "Restart Now" if present
	tell application "System Events"
		tell process "System Settings"
			repeat 60 times
				
				# Sonoma logic - interface now has three buttons. If 2 buttons exist, use old logic, if three exist, use new logic. 
				
				# 3-button logic - if button 3 exists (indicating both "Update Tonight" and "Restart Now" buttons are present) , click button 2 for "Restart Now"
				if exists (button 3 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events") then
					click button 2 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events"
					exit repeat
				end if
				
				# 2-button logic ("Update Now" and "More Info...")	- click "Update Now", because as of 14.1 beta 3, the "More Info" button is still not accepting synthetic click commands			
				if exists (button 1 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events") then
					click button 1 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events"
					exit repeat
				end if
				
				tell application "System Events"
					if application process "System Settings" exists then
						delay 0.5
					else
						exit repeat
					end if
				end tell
				
				delay 1
			end repeat
			
			
			# Approve EULA
			repeat 60 times
				
				# Insert code here to pause if Battery warning pops
				if exists (static text "Please connect to power before continuing updates." of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events") then
					delay 5
					
					# Nested loop to test for this text now being gone
					repeat 60 times
						if exists (static text "Please connect to power before continuing updates." of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events") then
							delay 5
						else
							# The power warning is gone, starting script over
							# This is just copying the first repeat statement of the script
							repeat 60 times
								
								
								if exists (button 1 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events") then
									click button 1 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events"
									exit repeat
								end if
								
								tell application "System Events"
									if application process "System Settings" exists then
										delay 0.5
									else
										exit repeat
									end if
								end tell
								
								delay 1
							end repeat
						end if
						
					end repeat #End of the battery warning loop
					
				end if
				
				# Proceed with actually agreeing to EULA
				if exists (button 2 of group 1 of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events") then
					click button 2 of group 1 of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events"
					exit repeat
				end if
				
				tell application "System Events"
					if application process "System Settings" exists then
						delay 0.5
					else
						exit repeat
					end if
				end tell
				
				delay 1
			end repeat
		end tell
	end tell
	
end if

# Ventura
if (_major = 13) then
	log "Ventura detected"
	# New bugs in Ventura - More Info button still not actionable through 13.5.2. If Ventura detected, click Upgrade now as far as you can, BUT if macOS upgrade banner detected, just scroll to the bottom
	
	# Launch software Update preference pane
	do shell script "open x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
	
	# Wait for window to open
	tell application "System Events"
		repeat 60 times
			if exists (window 1 of process "System Settings") then
				delay 3
				exit repeat
			else
				delay 1
			end if
		end repeat
		
		if not (exists (window 1 of process "System Settings")) then
			return
		end if
	end tell
	
	# Click "Update Now" or "Restart Now" if present
	tell application "System Events"
		tell process "System Settings"
			repeat 60 times
				
				# If macOS Banner detected along with available update, all we can do is scroll to it, we cannot click further. Do this and bail out
				set uiElems to entire contents of group 2 of splitter group 1 of group 1 of window "Software Update"
				#uiElems is generated as a LIST
				
				set var2 to "Sonoma"
				
				log "Now checking for Sonoma string"
				repeat with i in uiElems
					if class of i is static text then
						set R to value of i
						log "Value of static text is"
						log R
						if R contains "Sonoma" then
							log "Sonoma detected"
							set value of scroll bar 1 of scroll area 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events" to 1.0
							display dialog "To start your update, look for the 'Other Updates Available' section we've scrolled to and click the 'More Info...' button to begin the update." with title "Click the 'More Info' button to continue" buttons {"OK"} with icon POSIX file "/System/Library/PrivateFrameworks/OAHSoftwareUpdate.framework/Versions/A/Resources/SoftwareUpdate.icns" default button {"OK"}
							error number -128
						end if
					end if
				end repeat
				
				# Sonoma banner not detected, executing standard logic
				if exists (button 1 of group 2 of scroll area 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events") then
					click button 1 of group 2 of scroll area 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events"
					exit repeat
				end if
				
				tell application "System Events"
					if application process "System Settings" exists then
						delay 0.5
					else
						exit repeat
					end if
				end tell
				
				delay 1
			end repeat
			
			
			# Approve EULA
			repeat 60 times
				
				# Insert code here to pause if Battery warning pops
				if exists (static text "Please connect to power before continuing updates." of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events") then
					delay 5
					
					# Nested loop to test for this text now being gone
					repeat 60 times
						if exists (static text "Please connect to power before continuing updates." of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events") then
							delay 5
						else
							# The power warning is gone, starting script over
							# This is just copying the first repeat statement of the script
							repeat 60 times
								# In release, buttons changed from named identifiers to numbers
								# Commenting out this extra loop since both buttons now have same ID
								#if exists (button "Update Now" of group 2 of scroll area 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events") then
								#click button "Update Now" of group 2 of scroll area 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events"
								#exit repeat
								#end if
								
								if exists (button 1 of group 2 of scroll area 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events") then
									click button 1 of group 2 of scroll area 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Software Update" of application process "System Settings" of application "System Events"
									exit repeat
								end if
								
								tell application "System Events"
									if application process "System Settings" exists then
										delay 0.5
									else
										exit repeat
									end if
								end tell
								
								delay 1
							end repeat
						end if
						
					end repeat #End of the battery warning loop
					
				end if
				
				# Proceed with actually agreeing to EULA
				if exists (button 2 of group 1 of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events") then
					click button 2 of group 1 of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events"
					exit repeat
				end if
				
				tell application "System Events"
					if application process "System Settings" exists then
						delay 0.5
					else
						exit repeat
					end if
				end tell
				delay 1
			end repeat
			
			# NEW: Xcode SDK Agreement - same button layout as EULA
			# Give System Settings a few seconds to display second pane, then fire this once
			delay 4
			if exists (button 2 of group 1 of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events") then
				click button 2 of group 1 of sheet 1 of window "Software Update" of application process "System Settings" of application "System Events"
			end if
			
			tell application "System Events"
				if application process "System Settings" exists then
					delay 0.5
				end if
			end tell
		end tell
	end tell
	
end if

# Monterey and Big Sur
if _major < 13 then
	log "Monterey or Big Sur detected"
	do shell script "open /System/Library/PreferencePanes/SoftwareUpdate.prefPane"
	
	# Launch System Preferences
	tell application "System Events"
		repeat 60 times
			if exists (window 1 of process "System Preferences") then
				exit repeat
			else
				delay 1
			end if
		end repeat
		
		if not (exists (window 1 of process "System Preferences")) then
			return
		end if
		
		tell application id "com.apple.systempreferences"
			set the current pane to pane id "com.apple.preferences.softwareupdate"
		end tell
	end tell
	
	tell application "System Events"
		tell process "System Preferences"
			
			# Click More Info button
			repeat 60 times
				if exists (button 1 of group 1 of window "Software Update") then
					click button 1 of group 1 of window "Software Update"
					exit repeat
				end if
				
				tell application "System Events"
					if application process "System Preferences" exists then
						delay 0.5
					else
						exit repeat
					end if
				end tell
				delay 1
			end repeat
			# End Click More Info button
			# Click Install Now
			repeat 60 times
				if exists (button 1 of sheet 1 of window "Software Update") then
					click button 1 of sheet 1 of window "Software Update"
					exit repeat
				end if
				
				tell application "System Events"
					if application process "System Preferences" exists then
						delay 0.5
					else
						exit repeat
					end if
				end tell
				delay 1
			end repeat
			# End Click Install Now
			
			# Insert code here to pause if Battery warning pops
			delay 2
			if exists (static text "Please connect to power before continuing updates." of sheet 1 of window "Software Update" of application process "System Preferences" of application "System Events") then
				delay 5
				
				# Nested loop to test for this text now being gone
				repeat 60 times
					if exists (static text "Please connect to power before continuing updates." of sheet 1 of window "Software Update" of application process "System Preferences" of application "System Events") then
						delay 5
					else
						# The power warning is gone, starting script over
						# This is just copying the first repeat statement of the script
						
						# Click More Info button
						repeat 60 times
							if exists (button "More Info�" of group 1 of window "Software Update" of application process "System Preferences" of application "System Events") then
								click button "More Info�" of group 1 of window "Software Update" of application process "System Preferences" of application "System Events"
								exit repeat
							end if
							# Ensure app still open
							tell application "System Events"
								if application process "System Preferences" exists then
									delay 0.5
								else
									exit repeat
								end if
							end tell
							delay 1
						end repeat
						# End Click More Info button
						
						# Click Install Now
						repeat 60 times
							if exists (button "Install Now" of sheet 1 of window "Software Update" of application process "System Preferences" of application "System Events") then
								click button "Install Now" of sheet 1 of window "Software Update" of application process "System Preferences" of application "System Events"
								exit repeat
							end if
							
							tell application "System Events"
								if application process "System Preferences" exists then
									delay 0.5
								else
									exit repeat
								end if
							end tell
							delay 1
						end repeat
						# End Click Install Now	
					end if
					exit repeat
				end repeat #End of the battery warning loop
			end if # End of battery warning if statement
			
			# Accept EULA
			repeat 60 times
				if exists (button "Agree" of sheet 1 of window "Software Update" of application process "System Preferences" of application "System Events") then
					click button "Agree" of sheet 1 of window "Software Update" of application process "System Preferences" of application "System Events"
					exit repeat
				end if
				
				tell application "System Events"
					if application process "System Preferences" exists then
						delay 0.5
					else
						exit repeat
					end if
				end tell
				
				delay 1
			end repeat
		end tell
	end tell
	
end if
APPLESCRIPT
}

"$@"
