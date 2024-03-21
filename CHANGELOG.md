# CHANGELOG

## [Untagged]

No date

## [2.5.0]

21.03.2023

- Use applescript from [xirianlight/openToMoreInfo](https://github.com/xirianlight/openToMoreInfo) to open System Settings.
- System Settings is brought back to the foreground if users click to another app (seems to work for all apps excdept Terminal).
- Changed identifiers to `com.grahamrpugh`.
- Update for compatibility with swiftDialog 2.4.2.

## [2.4.1]

05.10.2023

- Force-close System Settings if open after the timeout period expires.
- Update for compatibility with swiftDialog 2.3.2.
- Reduce Software Update timeout from 60 to 15 minutes.

## [2.4]

23.06.2023

- If a user figures out the quit key and exits swiftDialog that way, this is treated the same as the Continue button.
- Dialog is no longer movable, so users cannot move it out of the way.
- If Software Update is left open for an hour, the dialog appears again, so users can't just minimise Software Update to avoid deferral count increases.
- Update for compatibility with swiftDialog 2.2.1.

## [2.3.1]

20.03.2023

- Update for compatibility with swiftDialog 2.1.

## [2.3]

09.01.2023

- Integrate with swiftDialog. jamfHelper is no longer used.
- Deferred updates are no longer listed (macOS 12+).
- Message changes.
- Package includes swiftDialog.

## [2.2]

30.08.2022

- Add `--include-config-data` to the `softwareupdate --list` command.

## [2.1]

21.04.2022

- Remove `softwareupdate` downloading stage as can cause unexpected installation.
- Bugfix for identifying updates that do not require a restart.
- New `/Library/Scripts/nice_updater_status.txt` file that can be read by a Jamf Extension Attribute for easy checking of run status.
- Changed default defer count to 8.
- Changed default wait after previous update to 7 days.
- Other minor bugfixes.

## [2.0.3]

21.05.2021

- Bugfix for issue #1

## [2.0.2]

12.05.2021

- Runs `jamfHelper` as the current user (this may not be necessary - was introduced to try and fix a problem where the tool was not showing though was running).
- Changed default defer count (back) to 10.

## [2.0.1]

30.04.2021

- The uninstaller script now forgets the package.
- A delay is introduced after a user closes the Software Update pane before bringing the dialog back. This is to primarily prevent the popup showing up while a restart is happening. (Ideally we would be able to check if the restart has been initiated, but that is not happening yet.)
- Added the CHANGELOG.md file.

## [2.0]

30.04.2021

This update removes the parts of the script that initiated `softwareupdate` for updates that require a restart. Instead, the Software Update pane is opened to prompt the user to perform the update themselves. If the user closes the Software Update pane, the prompt will reopen with one fewer chances to defer.

Due to this change, the on-demand logic has been removed.

## [1.8]

27.09.2019

The software updates that didn't need a restart were not running. This update fixes it.
Also, the last notification message no longer times out after 300s. It will stay open forever.

## [1.7]

27.08.2019

- Replaced StartInterval with StartCalendarInterval to ensure script starts regularly.
- Created an uninstaller script
- Created a post-install script for Jamf which will allow parameters to be overridden in a policy.

## [1.6]

15.08.2019

The deferral count will no longer reduce if there is no user response. We want to avoid a situation where an unattended machine restarts without intervention. The final alert will still timeout and perform the updates, however.

Also fixed the custom logo option.

Note that this version has the default of running every hour in `build.sh. The next version will return to once a day.

This version also includes our corporate logo.

## [1.5]

13.08.2019

A custom icon (any `.png`) can be added to a `custom_icons` folder. If so, this will be used in the `jamfHelper` message alert instead of the Software Updates icon.

The `currentUser` calculation was also changed to the `scutil` method to avoid python.

The build script no longer leaves the plists in binary format.

## [1.4]

13.08.2019

Changed the default button of the jamfHelper dialogs to Cancel, because after timeout, the update was running anyway since timeout induces whichever the default button is.

Also shortened the timeout to 82800 from 99999 seconds to prevent overlap of two days' dialogs.

[untagged]: https://github.com/grahampugh/nice-updater/compare/v2.5.0...HEAD
[2.5.0]: https://github.com/grahampugh/nice-updater/compare/v2.4.1...v2.5.0
[2.4.1]: https://github.com/grahampugh/nice-updater/compare/v2.4...v2.4.1
[2.4]: https://github.com/grahampugh/nice-updater/compare/v2.3.1...v2.4
[2.3.1]: https://github.com/grahampugh/nice-updater/compare/v2.3...v2.3.1
[2.3]: https://github.com/grahampugh/nice-updater/compare/v2.2...v2.3
[2.2]: https://github.com/grahampugh/nice-updater/compare/v2.1...v2.2
[2.1]: https://github.com/grahampugh/nice-updater/compare/v2.0.3...v2.1
[2.0.3]: https://github.com/grahampugh/nice-updater/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/grahampugh/nice-updater/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/grahampugh/nice-updater/compare/v2.0...v2.0.1
[2.0]: https://github.com/grahampugh/nice-updater/compare/1.8...v2.0
[1.8]: https://github.com/grahampugh/nice-updater/compare/1.7...1.8
[1.7]: https://github.com/grahampugh/nice-updater/compare/1.6...1.7
[1.6]: https://github.com/grahampugh/nice-updater/compare/1.5...1.6
[1.5]: https://github.com/grahampugh/nice-updater/compare/1.4...1.5
[1.4]: https://github.com/grahampugh/nice-updater/compare/1.0...1.4
