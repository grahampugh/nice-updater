#!/usr/bin/osascript

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
							if exists (button "More Infoð" of group 1 of window "Software Update" of application process "System Preferences" of application "System Events") then
								click button "More Infoð" of group 1 of window "Software Update" of application process "System Preferences" of application "System Events"
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