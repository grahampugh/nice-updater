#!/bin/bash

# The main identifier which everything hinges on
identifier="com.github.grahampugh.nice_updater"

# Default version of the build, you can leave this alone and specify as an argument like so: ./build.sh 1.7
version="2.2"

# The title of the message that is displayed when software updates are in progress and a user is logged in
updateRequiredTitle="macOS Software Updates Required"

# The message that is displayed when software updates are in progress and a user is logged in
updateRequiredMessage="Software updates are required to be installed on this Mac which require a restart. Please save your work and press Install Now from the Software Update panel to begin the installation."

# The title of the message that is displayed when software updates are in progress and a user is logged in
updateInProgressTitle="Software Update In Progress"

# The location of your log, keep in mind that if you nest the log into a folder that does not exist you'll need to mkdir -p the directory as well
log="/Library/Logs/Nice_Updater.log"

# The location of the status file, keep in mind that if the folder does not exist you'll need to mkdir -p the directory as well
EAFile="/Library/Scripts/nice_updater_status.txt"

# The number of days to check for updates after a full update has been performed
afterFullUpdateDelayDayCount="7"

# The number of days to check for updates after a updates were checked, but no updates were available
afterEmptyUpdateDelayDayCount="3"

# The number of times to alert a single user prior to forcibly installing updates
maxNotificationCount="8"

# Calendar based start interval - hours and minutes.
startIntervalHour="13"   # valid is 0-23. If left blank, daemon will launch every hour instead of once per day.
startIntervalMinute="0"  # valid is 0-59. Do not leave blank - set as 0

# The timeout length of the popup window. Should be less than the start interval so that two popups don't start at once.
alertTimeout="3540"

###### Variables below this point are not intended to be modified #####
mainDaemonPlist="/Library/LaunchDaemons/${identifier}.plist"
mainDaemonFileName="${mainDaemonPlist##*/}"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/${identifier}_on_demand.plist"
onDemandDaemonFileName="${mainOnDemandDaemonPlist##*/}"
onDemandDaemonIdentifier="${identifier}_on_demand"
watchPathsPlist="/Library/Preferences/${identifier}.trigger.plist"
preferenceFileFullPath="/Library/Preferences/${identifier}.prefs.plist"
preferenceFileName="${preferenceFileFullPath##*/}"

if [[ -n "$1" ]]; then
    version="$1"
    echo "Version set to $version"
else
    echo "No version passed, using version $version"
fi

# Update the variables in the various files of the project
# If you know of a more elegant/efficient way to do this please create a PR
sed -i '' "s#mainDaemonPlist=.*#mainDaemonPlist=\"$mainDaemonPlist\"#" "$PWD/postinstall.sh"
sed -i '' "s#mainDaemonPlist=.*#mainDaemonPlist=\"$mainDaemonPlist\"#" "$PWD/preinstall.sh"
sed -i '' "s#mainOnDemandDaemonPlist=.*#mainOnDemandDaemonPlist=\"$mainOnDemandDaemonPlist\"#" "$PWD/postinstall.sh"
sed -i '' "s#mainOnDemandDaemonPlist=.*#mainOnDemandDaemonPlist=\"$mainOnDemandDaemonPlist\"#" "$PWD/preinstall.sh"
sed -i '' "s#mainOnDemandDaemonPlist=.*#mainOnDemandDaemonPlist=\"$mainOnDemandDaemonPlist\"#" "$PWD/nice_updater.sh"
sed -i '' "s#watchPathsPlist=.*#watchPathsPlist=\"$watchPathsPlist\"#" "$PWD/preinstall.sh"
sed -i '' "s#watchPathsPlist=.*#watchPathsPlist=\"$watchPathsPlist\"#" "$PWD/nice_updater.sh"
sed -i '' "s#preferenceFileFullPath=.*#preferenceFileFullPath=\"$preferenceFileFullPath\"#" "$PWD/postinstall.sh"
sed -i '' "s#preferenceFileFullPath=.*#preferenceFileFullPath=\"$preferenceFileFullPath\"#" "$PWD/nice_updater.sh"

# Create clean temp build directories
find /private/tmp/nice_updater -mindepth 1 -delete &> /dev/null
mkdir -p /private/tmp/nice_updater/files/Library/LaunchDaemons
mkdir -p /private/tmp/nice_updater/files/Library/Preferences
mkdir -p /private/tmp/nice_updater/files/Library/Scripts/
mkdir -p /private/tmp/nice_updater/scripts
mkdir -p "$PWD/build"

# Create/modify the main Daemon plist
[[ -e "$PWD/$mainDaemonFileName" ]] && /usr/libexec/PlistBuddy -c Clear "$PWD/$mainDaemonFileName" &> /dev/null
defaults write "$PWD/$mainDaemonFileName" Label -string "$identifier"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PWD/$mainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.0 -string "/bin/bash" "$PWD/$mainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.1 -string "/Library/Scripts/nice_updater.sh" "$PWD/$mainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.2 -string "main" "$PWD/$mainDaemonFileName"
if [[ "$startInterval" ]]; then
    defaults write "$PWD/$mainDaemonFileName" StartInterval -int "$startInterval"
else
    if [[ $startIntervalHour || $startIntervalMinute ]]; then
        /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval dict" "$PWD/$mainDaemonFileName"
        [[ $startIntervalHour ]] && /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Hour integer '$startIntervalHour'" "$PWD/$mainDaemonFileName"
        [[ $startIntervalMinute ]] && /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Minute integer '$startIntervalMinute'" "$PWD/$mainDaemonFileName"
    fi
fi

# Create/modify the on_demand Daemon plist
[[ -e "$PWD/$onDemandDaemonFileName" ]] && /usr/libexec/PlistBuddy -c Clear "$PWD/$onDemandDaemonFileName" &> /dev/null
defaults write "$PWD/$onDemandDaemonFileName" Label -string "$onDemandDaemonIdentifier"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PWD/$onDemandDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.0 -string "/bin/bash" "$PWD/$onDemandDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.1 -string "/Library/Scripts/nice_updater.sh" "$PWD/$onDemandDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.2 -string "on_demand" "$PWD/$onDemandDaemonFileName"
/usr/libexec/PlistBuddy -c "Add :WatchPaths array" "$PWD/$onDemandDaemonFileName"
/usr/bin/plutil -insert WatchPaths.0 -string "$watchPathsPlist" "$PWD/$onDemandDaemonFileName"

# Create/modify the main preference file
[[ -e "$PWD/$preferenceFileName" ]] && /usr/libexec/PlistBuddy -c Clear "$PWD/$preferenceFileName" &> /dev/null
defaults write "$PWD/$preferenceFileName" UpdateRequiredTitle -string "$updateRequiredTitle"
defaults write "$PWD/$preferenceFileName" UpdateRequiredMessage -string "$updateRequiredMessage"
defaults write "$PWD/$preferenceFileName" UpdateInProgressTitle -string "$updateInProgressTitle"
defaults write "$PWD/$preferenceFileName" Log -string "$log"
defaults write "$PWD/$preferenceFileName" EAFile -string "$EAFile"
defaults write "$PWD/$preferenceFileName" AfterFullUpdateDelayDayCount -int "$afterFullUpdateDelayDayCount"
defaults write "$PWD/$preferenceFileName" AfterEmptyUpdateDelayDayCount -int "$afterEmptyUpdateDelayDayCount"
defaults write "$PWD/$preferenceFileName" MaxNotificationCount -int "$maxNotificationCount"
defaults write "$PWD/$preferenceFileName" AlertTimeout -int "$alertTimeout"

# Migrate preinstall and postinstall scripts to temp build directory
cp "$PWD/preinstall.sh" /private/tmp/nice_updater/scripts/preinstall
chmod +x /private/tmp/nice_updater/scripts/preinstall
cp "$PWD/postinstall.sh" /private/tmp/nice_updater/scripts/postinstall
chmod +x /private/tmp/nice_updater/scripts/postinstall

# Put the main script and uninstaller in place
cp "$PWD/nice_updater.sh" /private/tmp/nice_updater/files/Library/Scripts/nice_updater.sh
cp "$PWD/nice_updater_uninstall.sh" /private/tmp/nice_updater/files/Library/Scripts/nice_updater_uninstall.sh

# put a custom icon in place if present
if find "$PWD/custom_icon" -name "*.png" ; then
    icon_path=/Library/Scripts/nice_updater_custom_icon.png
    echo "Adding the icon to /private/tmp/nice_updater/files$icon_path"
    cp -f "$PWD/custom_icon/"*.png /private/tmp/nice_updater/files$icon_path
    defaults write "$PWD/$preferenceFileName" IconCustomPath -string "$icon_path"
else
    echo "Nothing found at $PWD/custom_icon/*.png"
    defaults write "$PWD/$preferenceFileName" IconCustomPath -string ""
fi

# Copy the LaunchDaemon plists to the temp build directory
cp "$PWD/$mainDaemonFileName" "/private/tmp/nice_updater/files/Library/LaunchDaemons/"
cp "$PWD/$onDemandDaemonFileName" "/private/tmp/nice_updater/files/Library/LaunchDaemons/"
cp "$PWD/$preferenceFileName" "/private/tmp/nice_updater/files/Library/Preferences/"

# Remove any unwanted .DS_Store files from the temp build directory
find "/private/tmp/nice_updater/" -name '*.DS_Store' -type f -delete

# Remove the default plists if the identifier has changed
if [[ ! "$identifier" = "com.github.ryangball.nice_updater" ]]; then
    rm "$PWD/com.github.ryangball.nice_updater.plist" &> /dev/null
    rm "$PWD/com.github.ryangball.nice_updater_on_demand.plist" &> /dev/null
    rm "$PWD/com.github.ryangball.nice_updater.prefs.plist" &> /dev/null
fi

# Remove any extended attributes (ACEs) from the temp build directory
/usr/bin/xattr -rc "/private/tmp/nice_updater"

echo "Building the .pkg in $PWD/build/"
/usr/bin/pkgbuild --quiet --root "/private/tmp/nice_updater/files/" \
    --install-location "/" \
    --scripts "/private/tmp/nice_updater/scripts/" \
    --identifier "$identifier" \
    --version "$version" \
    --ownership recommended \
    "$PWD/build/Nice_Updater_${version}.pkg"

# shellcheck disable=SC2181
if [[ "$?" == "0" ]]; then
    echo "Revealing Nice_Updater_${version}.pkg in Finder"
    open -R "$PWD/build/Nice_Updater_${version}.pkg"
else
    echo "Build failed."
fi

# using plutil is fine but it converts the plists to binary which is not good for readability. Let's convert them back.
/usr/bin/plutil -convert xml1 "$PWD/$preferenceFileName"
/usr/bin/plutil -convert xml1 "$PWD/$mainDaemonFileName"
/usr/bin/plutil -convert xml1 "$PWD/$onDemandDaemonFileName"
