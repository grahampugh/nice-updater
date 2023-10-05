#!/bin/bash

# Nice Updater 2
version="2.4.1"

# These variables will be automagically updated if you run build.sh, no need to modify them
preferenceFileFullPath="/Library/Preferences/com.github.grahampugh.nice_updater.prefs.plist"

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

# URL for downloading dialog (with tag version)
# This ensures a compatible dialog is used if not using the package installer
SWIFTDIALOG_URL="https://github.com/bartreardon/swiftDialog/releases/download/v2.3.2/dialog-2.3.2-4726.pkg"

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
        if /usr/bin/curl -L "$SWIFTDIALOG_URL" -o "$workdir/dialog.pkg" ; then
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

open_software_update() {
    /usr/bin/open -W /System/Library/PreferencePanes/SoftwareUpdate.prefPane &
    suPID=$!
    writelog "Opening Software Update with PID: $suPID"
    # While Software Update is open...
    timecount=0
    while kill -0 "$suPID" 2> /dev/null; do
        sleep 1
        # set a maximum time that Software Update can be open before killing System Settings and invoking another dialog
        ((timecount++))
        if [[ $timecount -ge 3600 ]]; then
            if pgrep "System Settings"; then
                pkill "System Settings"
            elif pgrep "System Preferences"; then
                pkill "System Preferences"
            fi
        fi
    done
    if [[ $timecount -ge 3600 ]]; then
        writelog "Software Update was open too long"
        write_status "Software Update was open too long"
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

    # See if we are blocking updates, if so exit
    updatesBlocked=$(/usr/libexec/PlistBuddy -c "Print :updates_blocked" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
    if [[ "$updatesBlocked" == "true" ]]; then
        writelog "Updates are blocked for this client at this time; exiting"
        write_status "Updates are blocked for this client at this time; exiting"
        finish 0
    fi

    # Check the last time we had a full successful update
    updatesAvailable=$(/usr/bin//usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastRecommendedUpdatesAvailable | /usr/bin/awk '{ if  (NF > 2) {print $1 " "  $2} else { print $0 }}')
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

"$@"
