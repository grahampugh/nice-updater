# Nice Updater 2

![](https://img.shields.io/github/v/release/grahampugh/nice-updater)&nbsp;![](https://img.shields.io/github/downloads/grahampugh/nice-updater/latest/total)&nbsp;&nbsp;![](https://img.shields.io/github/downloads/grahampugh/nice-updater/total)&nbsp;![](https://img.shields.io/badge/macOS-11%2B-success)

A tool to faciliate the updating of macOS that (nicely) gives the user several reminders to update before becoming more annoying.

<img width="864" alt="nice_updater" src="https://user-images.githubusercontent.com/5802725/211634968-237b21d9-0989-4300-8728-d90f06b6e32b.png">

This fork uses swiftDialog instead of Yo.app. Additional configuration opportunities have also been added.

Version 2 removes the use of `softwareupdate` for installing updates that require a restart. Updates that can be carried out without a restart are still performed using `softwareupdate`. For those that require a restart, the Software Update pane is opened instead.

## See the [wiki](https://github.com/grahampugh/nice-updater/wiki) for more details.
