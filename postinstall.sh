#!/bin/bash

# These variables will be automagically updated if you run build.sh, no need to modify them
mainDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater_on_demand.plist"
preferenceFileFullPath="/Library/Preferences/com.github.grahampugh.nice_updater.prefs.plist"

# Set permissions on LaunchDaemon and Script
chown root:wheel "$mainDaemonPlist"
chmod 644 "$mainDaemonPlist"
chown root:wheel "$preferenceFileFullPath"
chmod 644 "$preferenceFileFullPath"
chown root:wheel /Library/Scripts/nice_updater.sh
chmod 755 /Library/Scripts/nice_updater.sh
chown root:wheel /Library/Scripts/nice_updater_uninstall.sh
chmod 755 /Library/Scripts/nice_updater_uninstall.sh
if [[ -f /Library/Scripts/custom_icon.png ]]; then
    chown root:wheel /Library/Scripts/custom_icon.png
    chmod 644 /Library/Scripts/custom_icon.png
fi

# Start our LaunchDaemons
/bin/launchctl load -w "$mainDaemonPlist"
/bin/launchctl load -w "$mainOnDemandDaemonPlist"

/bin/launchctl start com.github.grahampugh.nice_updater
