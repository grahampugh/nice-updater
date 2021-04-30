#!/bin/bash

# These variables will be automagically updated if you run build.sh, no need to modify them
preferenceFileFullPath="/Library/Preferences/com.github.grahampugh.nice_updater.prefs.plist"

###### Variables below this point are not intended to be modified #####
helperTitle=$(defaults read "$preferenceFileFullPath" UpdateRequiredTitle)
helperDesc=$(defaults read "$preferenceFileFullPath" UpdateRequiredMessage)
alertTimeout=$(defaults read "$preferenceFileFullPath" AlertTimeout)
log=$(defaults read "$preferenceFileFullPath" Log)
afterFullUpdateDelayDayCount=$(defaults read "$preferenceFileFullPath" AfterFullUpdateDelayDayCount)
afterEmptyUpdateDelayDayCount=$(defaults read "$preferenceFileFullPath" AfterEmptyUpdateDelayDayCount)
maxNotificationCount=$(defaults read "$preferenceFileFullPath" MaxNotificationCount)
iconCustomPath=$(defaults read "$preferenceFileFullPath" IconCustomPath)

scriptName=$(basename "$0")
JAMFHELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# set default icon if not included in build
system_build=$( /usr/bin/sw_vers -buildVersion )
major_version=${system_build:0:2}
if [[ -f "$iconCustomPath" ]]; then
    icon="$iconCustomPath"
elif [[ "$major_version" -le 16 ]]; then
    icon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"
elif [[ "$major_version" -ge 17 ]]; then
    icon="/System/Library/CoreServices/Install Command Line Developer Tools.app/Contents/Resources/SoftwareUpdate.icns"
fi

writelog() {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

finish() {
    writelog "======== Finished $scriptName ========"
    exit "$1"
}

random_delay() {
    delay_time=$(( (RANDOM % 60)+1 ))
    writelog "Delaying software update check by ${delay_time}s."
    sleep ${delay_time}s
}

record_last_full_update() {
    writelog "Done with update process; recording last full update time."
    /usr/libexec/PlistBuddy -c "Delete :last_full_update_time" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :last_full_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath

    writelog "Clearing user alert data."
    /usr/libexec/PlistBuddy -c "Delete :users" $preferenceFileFullPath

    writelog "Clearing On-Demand Update Key."
    /usr/libexec/PlistBuddy -c "Delete :update_key" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :update_key array" $preferenceFileFullPath 2> /dev/null
}

trigger_nonrestart_updates() {
    /usr/sbin/softwareupdate --install "$1" 
}

open_software_update() {
    /usr/bin/open -W /System/Library/PreferencePanes/SoftwareUpdate.prefPane &
    suPID=$!
    writelog "Software Update PID $suPID"
    # While Software Update is open...
    while kill -0 $suPID 2> /dev/null; do
        sleep 1
    done
    writelog "Software Update was closed"
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
    [[ "$notificationsLeft" == "1" ]] && local subtitle="1 remaining alert before auto-install."
    [[ "$notificationsLeft" == "0" ]] && local subtitle="No deferrals remaining! Click on \"Install Now\" to proceed"

    if /usr/bin/pgrep jamfHelper ; then
    writelog "Existing JamfHelper window running... killing"
        /usr/bin/pkill jamfHelper
        sleep 3
    fi

    writelog "Notifying $loggedInUser of available updates..."
    if [[ "$notificationsLeft" == "0" ]]; then
        helperExitCode=$( "$JAMFHELPER" -windowType utility -lockHUD -title "$helperTitle" -heading "$subtitle" -description "$helperDesc" -button1 "Install Now" -defaultButton 1 -icon "$icon" -iconSize 100 )
    else
        "$JAMFHELPER" -windowType utility -title "$helperTitle" -heading "$subtitle" -description "$helperDesc" -button1 "Install Now" -button2 "Cancel" -defaultButton 2 -cancelButton 2 -icon "$icon" -iconSize 100 &
        jamfHelperPID=$!
        # since the "cancel" exit code is the same as the timeout exit code, we
        # need to distinguish between the two. We use a while loop that checks
        # that the process exists every second. If so, count down 1 and check
        # again. If the process is gone, use `wait` to grab the exit code.
        timeLeft=$alertTimeout
        while [[ $timeLeft -gt 0 ]]; do
            if pgrep jamfHelper ; then
                # writelog "Waiting for timeout: $timeLeft remaining"
                sleep 1
                ((timeLeft--))
            else
                wait $jamfHelperPID
                helperExitCode=$?
                break
            fi
        done
        # if the process is still running, we need to kill it and give a fake
        # exit code
        if pgrep jamfHelper; then
            pkill jamfHelper
            helperExitCode=1
        else
            writelog "A button was pressed."
        fi
    fi

    # writelog "Response: $helperExitCode"
    if [[ $helperExitCode == 0 ]]; then
        writelog "User initiated installation."
        open_software_update
    elif [[ $helperExitCode == 2 ]]; then
        writelog "User cancelled installation."
    else
        writelog "Alert timed out without response."
        ((notificationCount--))
    fi

    /usr/libexec/PlistBuddy -c "Add :users dict" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Delete :users:$loggedInUser" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser dict" $preferenceFileFullPath
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser:alert_count integer $notificationCount" $preferenceFileFullPath

}

alert_logic() {
    notificationCount=$(/usr/libexec/PlistBuddy -c "Print :users:$loggedInUser:alert_count" $preferenceFileFullPath 2> /dev/null | xargs)
    if [[ "$notificationCount" -ge "$maxNotificationCount" ]]; then
        writelog "$loggedInUser has been notified $notificationCount times; not waiting any longer."
        alert_user "$notificationsLeft remaining alerts before auto-install." "$notificationCount"
    else
        ((notificationCount++))
        notificationsLeft="$((maxNotificationCount - notificationCount))"
        writelog "$notificationsLeft remaining alerts before auto-install."
        alert_user "$notificationsLeft remaining alerts before auto-install." "$notificationCount"
    fi
}

update_check() {
    osVersion=$( /usr/bin/sw_vers -productVersion )
    writelog "Determining available Software Updates for macOS $osVersion..."
    updates=$(/usr/sbin/softwareupdate -l)
    updatesNoRestart=$(echo "$updates" | grep -v restart | grep -B1 recommended | grep -v recommended | grep -v "\-\-" | sed 's|.*\* ||g')
    updatesRestart=$(echo "$updates" | grep -i restart | grep -v '\*' | cut -d , -f 1)
    updateCount=$(echo "$updates" | grep -i -c recommended)

    if [[ "$updateCount" -gt "0" ]]; then
        # Download the updates
        writelog "Downloading $updateCount update(s)..."
        /usr/sbin/softwareupdate --download --recommended | grep --line-buffered Downloaded | while read -r LINE; do writelog "$LINE"; done

        # Don't waste the user's time - install any updates that do not require a restart first.
        if [[ -n "$updatesNoRestart" ]]; then
            writelog "Installing updates that DO NOT require a restart in the background..."
            while IFS='' read -r line; do
                writelog "Updating: $line"
                trigger_nonrestart_updates "$line"
            done <<< "$updatesNoRestart"
        fi

        # If the script moves past this point, a restart is required.
        if [[ -n "$updatesRestart" ]]; then
            writelog "A restart is required for remaining updates."
            # If no user is logged in, just update and restart. Check the user now as some time has past since the script began.
            loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
            # loggedInUID=$(id -u "$loggedInUser")
            if [[ "$loggedInUser" == "root" ]] || [[ -z "$loggedInUser" ]]; then
                writelog "No user logged in. Cannot proceed."
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
            writelog "No updates that require a restart available; exiting."
            finish 0
        fi
    else
        writelog "No updates at this time; exiting."
        /usr/libexec/PlistBuddy -c "Delete :last_empty_update_time" $preferenceFileFullPath 2> /dev/null
        /usr/libexec/PlistBuddy -c "Add :last_empty_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath
        /usr/libexec/PlistBuddy -c "Delete :users" $preferenceFileFullPath 2> /dev/null
        finish 0
    fi
}

main() {
    # This function is intended to be run from a LaunchDaemon at intervals

    writelog " "
    writelog "======== Starting $scriptName ========"

    # See if we are blocking updates, if so exit
    updatesBlocked=$(/usr/libexec/PlistBuddy -c "Print :updates_blocked" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
    if [[ "$updatesBlocked" == "true" ]]; then
        writelog "Updates are blocked for this client at this time; exiting."
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
                writelog "$afterFullUpdateDelayDayCount or more days have passed since last full update."
                # delay script's actions by up to 1 min to prevent all computers running software update at the same time
                random_delay
                update_check
            else
                writelog "Less than $afterFullUpdateDelayDayCount days since last full update; exiting."
                finish 0
            fi
        elif [[ -n "$lastEmptyUpdateTime" ]]; then
            daysSinceLastEmptyUpdate="$(compare_date "$lastEmptyUpdateTime")"
            if [[ "$daysSinceLastEmptyUpdate" -ge "$afterEmptyUpdateDelayDayCount" ]]; then
                writelog "$afterEmptyUpdateDelayDayCount or more days have passed since last empty update check."
                # delay script's actions by up to 1 min to prevent all computers running software update at the same time
                random_delay
                update_check
            else
                writelog "Less than $afterEmptyUpdateDelayDayCount days since last empty update check; exiting."
                finish 0
            fi
        else
            writelog "This device might not have performed a full update yet."
                # delay script's actions by up to 1 min to prevent all computers running software update at the same time
            random_delay
            update_check
        fi
    fi

    finish 0
}

"$@"
