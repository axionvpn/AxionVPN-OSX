#!/bin/bash
#
# tunnelblick-uninstaller.sh
#
# Copyright © 2013, 2015 Jonathan K. Bullard. All rights reserved

####################################################################################
#
# This script must be run as root via the sudo command.
#
# This script does everything to uninstall Tunnelblick or a rebranded version of Tunnelblick:
#
#    1. Removes the following files and folders:
#          /Applications/Tunnelblick.app (or other copy of Tunnelblick)
#          /Library/Application Support/Tunnelblick
#          /Library/Logs/CrashReporter/Tunnelblick_*.crash
#          /Library/Logs/CrashReporter/openvpnstart_*.crash
#		   /Library/LaunchDaemons/net.tunnelblick.startup.* (ONLY IF uninstalling a NON-REBRANDED version of Tunnelblick)
#		   /Library/LaunchDaemons/net.tunnelblick.tunnelblick.startup.* (unloaded using launchctl before being removed)
#		   /Library/LaunchDaemons/net.tunnelblick.tunnelblick.tunnelblickd.plist (unloaded using launchctl before being removed)
#          /var/logs/Tunnelblick
#          /tmp/TunnelblickAuthIcon.png
#
#    2. Removes the following for each user:
#          Login items
#          Keychain items
#		   ~/Library/Application Support/Tunnelblick
#		   ~/Library/Preferences/net.tunnelblick.tunnelblick.plist.lock
#		   ~/Library/Preferences/net.tunnelblick.tunnelblick.plist
#          ~/Library/Caches/net.tunnelblick.tunnelblick
#		   ~/Library/Preferences/com.openvpn.tunnelblick.plist
#		   ~/Library/openvpn
#		   ~/Library/Logs/CrashReporter/Tunnelblick_*.crash
#		   ~/Library/Logs/CrashReporter/openvpnstart_*.crash
#
#
# For a usage message, run this script with no arguments.
#
####################################################################################


####################################################################################
#
# Routine that trims leading/trailing spaces from its arguments
#
# Arguments: content to be trimmed
#
####################################################################################
uninstall_tb_trim()
{
  echo ${@}
}


####################################################################################
#
# Routine that removes a file or folder
#
# Argument: path to item that is to be removed
#
# DOES NOT complain if item does not exist
#
####################################################################################
uninstall_tb_remove_item_at_path()
{
  if [ -e "$1" ] ; then
    if [ -d "$1" ] ; then
      recursive="-R"
    else
      recursive=""
    fi
    if [ "${uninstall_remove_data}" = "true" ] ; then
      rm -f -P ${recursive} "$1"
      status=$?
    else
      status="0"
    fi
    if [ "${status}" = "0" ]; then
      echo "Removed $1"
    else
      echo "Problem: an error was returned by 'rm -f -P ${recursive} \"$1\"'"
      echo "Output from 'ls ${recursive} -@ -A -b -e -l -O "$1"':"
      echo "$(ls ${recursive} -@ -A -b -e -l -O "$1")"
      if [ "${$1:0:7}" = "/Users/" ] ; then
        echo "If the user's home folder is on a network drive, that could be the cause of the problem. (Tunnelblick cannot be installed or uninstalled if the user's home folder is on a network drive.)"
      fi
    fi
  fi
}

####################################################################################
#
# Routine that uninstalls per-user data
#
# THIS ROUTINE MUST BE RUN VIA 'su user'
#
# Arguments: (none)
#
# Uses the following environment variables:
#      uninstall_tb_remove_item_at_path()
#      uninstall_remove_data
#      uninstall_tb_app_name

####################################################################################
uninstall_tb_per_user_data()
{
  if [ "$EUID" != "" ] ; then
	if [ "$EUID" = "0" ] ; then
	  echo "Error: uninstall_tb_per_user_data must not be run as root"
	  exit 0
	fi
  else
	if [ "$(id -u)" != "" ]; then
	  if [ "$(id -u)" = "0" ]; then
		echo "Error: uninstall_tb_per_user_data must not be run as root"
		exit 0
	  fi
	else
	  echo "Error: uninstall_tb_per_user_data must not be run as root. Unable to determine if it is running as root"
	  exit 0
	fi
  fi

  # Remove any and all items stored by Tunnelblick in all of the current user's Keychains
  #
  # Note: It is possible, although unlikely, that a non-Tunnelblick Keychain item would be deleted
  #       if its name starts with 'Tunnelblick-Auth-'. This is because the script assumes that any item
  #       if its 'Service' begins with 'Tunnelblick-Auth-' has been stored by Tunnelblick.

  if [ "${uninstall_tb_app_name}" != "" ] ; then

    # keychain_list is a list of all the user's keychains, separated by spaces
    readonly keychain_list="$(uninstall_tb_trim "$(security list-keychains | grep login.keychain | tr '\n' ' ' | tr -d '"')")"

    for keychain in ${keychain_list} ; do

      # keychain_contents is the dumped contents of the keychain (for security reasons we don't
      #                   use the "-d" option, thus decrypted passwords are not included in the dump)
      keychain_contents="$(security dump-keychain ${keychain})"

      # tb_service_list is a list, one per line, of the names of services in the contents whose names
      #                 begin with "Tunnelblick-Auth-"
      #                 Notes:
      #                      1. Each service name may be duplicated several times
      #                      2. Each service name is enclosed in double-quotes and may contain spaces
      tb_service_list="$(echo "${keychain_contents}" | grep "=\"${uninstall_tb_app_name}-Auth-" |  sed -e 's/.*<blob>=//' | tr -d '"')"

      # tb_service_array is an array containing the service list
      # (Temporarily change the token separator to consider only newlines as separators while reading from tb_service_list)
      saved_IFS=${IFS}
      IFS=$'\n'
      tb_service_array=(${tb_service_list})
      IFS=${saved_IFS}
  
      # Loop through the array, processing each different service only once

      # last_service is the name of the last service processed. It is used to process each service only once
      last_service="''"

      for service in "${tb_service_array[@]}" ; do
        if [ "${service}" != "${last_service}" ] ; then

          # Process any privateKey, username, or password accounts for the service
          for account in privateKey username password ; do

            # If an item for the account exists, delete that keychain item
            item="$(security find-generic-password -s "${service}" -a "${account}" 2> /dev/null)"
            if [ "${item}" != "" ] ; then
              if [ "${uninstall_remove_data}" = "true" ] ; then
                security delete-generic-password -s "${service}" -a "${account}" > /dev/null
                status=$?
              else
                status="0"
              fi
              if [ "${status}" = "0" ]; then
                echo "Removed ${USER}'s Keychain entry: '${account}' for '${service}'"
              else
                echo "Problem: Could not remove ${USER}'s Keychain entry: '${account}' for '${service}'"
              fi
            fi
          done
          last_service="${service}"
        fi
      done
      
    done

  fi

}


####################################################################################
#
# Start of script
#
####################################################################################

usage_message="Usage:

      tunnelblick-uninstaller.sh  [ -u | -t ]   app-name bundle-id [app-path]

           -t:        Causes the script to perform a TEST, or \"dry run\": the program logs to
                      stdout what it would do if run with the -u option, but NO DATA IS REMOVED.

           -u:        Causes the script to perform an UNINSTALL, REMOVING DATA; the program logs
                      to stdout what it has done.

           app-name:  The name of the application (e.g., \"Tunnelblick\").

           bundle-id: The CFBundleIdentifier for the application (e.g., \"net.tunnelblick.tunnelblick\").

           app-path:  The path to the application. If specified, the item at that path will be deleted.

     If neither the -u option nor the -t option is specified, this usage message is displayed.

     Note: This command returns indicating success even if there were errors; errors are indicated in
           the stdout output.

     Examples:

     ./tunnelblick-uninstaller.sh -u   Tunnelblick   net.tunnelblick.tunnelblick   /Applications/Tunnelblick.app
     This is the normal use. It will remove the application and all files and folders associated with it.

     ./tunnelblick-uninstaller.sh -u   Tunnelblick   net.tunnelblick.tunnelblick
     This can be used if the application is not available (for example, it has been put in the Trash).
     It will remove files and folders associated with Tunnelblick and net.tunnelblick.tunnelblick, but will not
     remove the application itself.

     ./tunnelblick-uninstaller.sh -t   RebrandedTB   com.example.rebrandedtb /Applications/RebrandedTB.app
     This will test the removal of a \"rebranded\" Tunnelblick which is named \"RebrandedTB\", has
	 CFBundleIdentifier \"com.example.rebrandedtb\", and is located at \"/Applications/RebrandedTB.app\"
"

show_usage_message="false"

# Complain and exit if not running as root
if [ "$EUID" != "" ] ; then
  if [ "$EUID" != "0" ] ; then
    echo "Error: This program must be run as root"
    exit 0
  fi
else
  if [ "$(id -u)" != "" ]; then
    if [ "$(id -u)" != "0" ]; then
      echo "Error: This program must be run as root"
      exit 0
    fi
  else
    echo "Error: This program must be run as root. Unable to determine if it is running as root"
    exit 0
  fi
fi

####################################################################################
#
# Process options and set uninstall_remove_data to either "true" or "false" ( for -u or -t, respectively)
#
####################################################################################

if [ $# != 0 ] ; then
  while [ "${1:0:1}" = "-" ] ; do

    if [ "$1" = "-u" ] ; then
      if [ "${uninstall_remove_data}" = "" ] ; then
        readonly uninstall_remove_data="true"
      else
        echo "Only one -t or -u option may be specified"
        show_usage_message="true"
      fi
    else
      if [ "$1" = "-t" ] ; then
        if [ "${uninstall_remove_data}" = "" ] ; then
          readonly uninstall_remove_data="false"
        else
        echo "Only one -t or -u option may be specified"
          show_usage_message="true"
        fi
      else
        echo "Unknown option: ${1}"
        show_usage_message="true"
      fi
    fi
  
    shift
    
  done

fi

if [ "${uninstall_remove_data}" = "" ] ; then
  echo "One of -u or -t is required"
  show_usage_message="true"
fi


if [ "$#" -gt "3" ] ; then
  echo "Too many arguments"
  show_usage_message="true"
fi

####################################################################################
#
# Process arguments and set up three variables:
#
#     uninstall_tb_app_name:  The name of the application.
#
#     uninstall_tb_bundle_identifier: The CFBundleIdentifier to use.
#
#     uninstall_tb_app_path: The path to the file that contains the application (or an empty string if no path was specified).
#
####################################################################################

readonly uninstall_tb_app_name="${1}"
readonly uninstall_tb_bundle_identifier="${2}"
readonly uninstall_tb_app_path="${3}"

# The path can be empty (e.g., if the application has already been Trashed, for example),
# but the name and bundle ID must be provided
if [ "${uninstall_tb_app_name}" == "" -o "${uninstall_tb_bundle_identifier}" == "" ] ; then
  echo "You must include the application name and the bundle identifier"
  show_usage_message="true"
fi

if [ "${uninstall_tb_app_path}" != "" -a ! -e "${uninstall_tb_app_path}" ] ; then
  echo "Nothing at '${uninstall_tb_app_path}'"
  show_usage_message="true"
fi

if [ "${show_usage_message}" != "false" ] ; then
  echo "${usage_message}"
  exit 0
fi

####################################################################################
#
# Finished processing arguments. Make sure no process exists that contains the name of
# the application or 'openvpn' (including 'openvpnstart')
#
####################################################################################

readonly app_instances="$(ps -x | grep ".app/Contents/MacOS/${uninstall_tb_app_name}" | grep -x grep)"
if [ "${app_instances}" != "" ] ; then
  echo "Error: ${uninstall_tb_app_name} cannot be uninstalled while it is running"
  exit 0
fi

readonly openvpn_instances="$(ps -x | grep "openvpn" | grep -x grep)"
if [ "${openvpn_instances}" != "" ] ; then
  echo "Error: ${uninstall_tb_app_name} cannot be uninstalled while OpenVPN is running"
  exit 0
fi

# Output initial messages
echo "$(date '+%a %b %e %T %Y') Tunnelblick Uninstaller:"
echo ""
echo "     Uninstalling '${uninstall_tb_app_name}'"
echo "     with bundle ID '${uninstall_tb_bundle_identifier}'"

if [ "${uninstall_tb_app_path}" != "" ] ; then
  echo "     at ${uninstall_tb_app_path}"
fi

if [ "${uninstall_remove_data}" != "true" ] ; then
  echo ""
  echo "Testing only -- NOT removing or unloading anything"
  echo ""
fi

####################################################################################
#
# Remove non-per-user files and folders
#
####################################################################################

# Remove the Application Support folder
uninstall_tb_remove_item_at_path  "/Library/Application Support/${uninstall_tb_app_name}"

# Remove Tunnelblick LaunchDaemons

# Special-case old startup launch daemons that use net.tunnelblick.startup as the prefix when removing a NON-REBRANDED Tunnelblick
# (Create tbBundleId variable so it does _not_ get changed by rebranding
tempTbBundleId="net.tunnelblick"
tempTbBundleId="${tbBundleId}.tunnelblick"
if [ "${uninstall_tb_bundle_identifier}" == "${tempTbBundleId}" ] ; then
  for path in `ls /Library/LaunchDaemons/net.tunnelblick.startup.* 2> /dev/null` ; do
    if [ "${uninstall_remove_data}" = "true" ] ; then
      launchctl unload "${path}"
    fi
    echo "Unloaded ${path}"
    uninstall_tb_remove_item_at_path "${path}"
  done
fi

# Remove new startup launch daemons that use the (possibly rebranded) CFBundleIdentifier as the prefix
for path in `ls /Library/LaunchDaemons/${uninstall_tb_bundle_identifier}.startup.* 2> /dev/null` ; do
  if [ "${uninstall_remove_data}" = "true" ] ; then
    launchctl unload "${path}"
  fi
  echo "Unloaded ${path}"
  uninstall_tb_remove_item_at_path "${path}"
done

# Remove tunnelblickd launch daemon: unload, remove the .plist, and remove the socket
path="/Library/LaunchDaemons/${uninstall_tb_bundle_identifier}.tunnelblickd.plist"
if [ -f "${path}" ] ; then
  if [ "${uninstall_remove_data}" = "true" ] ; then
    launchctl unload "${path}"
  fi
  echo "Unloaded ${path}"
  uninstall_tb_remove_item_at_path "${path}"
fi
path="/var/run/${uninstall_tb_bundle_identifier}.tunnelblickd.socket"
uninstall_tb_remove_item_at_path "${path}"

# Remove tunnelblickd log(s)
uninstall_tb_remove_item_at_path "/var/log/${uninstall_tb_app_name}"

# Remove the installer log
uninstall_tb_remove_item_at_path "/tmp/tunnelblick-installer-log.txt"

# Remove the temporary authorization icon
uninstall_tb_remove_item_at_path "/tmp/${uninstall_tb_app_name}AuthIcon.png"

# Remove non-per-user CrashReporter files for the application, openvpn, openvpnstart, and tunnelblickd
for path in `ls /Library/Logs/CrashReporter/${uninstall_tb_app_name}_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

for path in `ls /Library/Logs/DiagnosticReports/${uninstall_tb_app_name}_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

for path in `ls /Library/Logs/CrashReporter/openvpn_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

for path in `ls /Library/Logs/DiagnosticReports/openvpn_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

for path in `ls /Library/Logs/CrashReporter/tunnelblickd_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

for path in `ls /Library/Logs/DiagnosticReports/tunnelblickd_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

####################################################################################
#
# Remove per-user files and folders
#
####################################################################################

export -f uninstall_tb_trim
export -f uninstall_tb_remove_item_at_path
export -f uninstall_tb_per_user_data

export    uninstall_remove_data
export    uninstall_tb_app_path
export    uninstall_tb_app_name
export    uninstall_tb_bundle_identifier

for user in `dscl . list /users` ; do
  if [ "${user:0:1}" != "_" -a -e "/Users/${user}" ] ; then

    # Remove old preferences and configurations folder or symlink to the configurations folder
    uninstall_tb_remove_item_at_path "/Users/${user}/Library/Preferences/com.openvpn.tunnelblick.plist"
    uninstall_tb_remove_item_at_path "/Users/${user}/Library/openvpn"

    if [ "${uninstall_tb_app_name}" != "" ] ; then
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Application Support/${uninstall_tb_app_name}"
    fi

    if [ "${uninstall_tb_bundle_identifier}" != "" ] ; then
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Preferences/${uninstall_tb_bundle_identifier}.plist.lock"
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Preferences/${uninstall_tb_bundle_identifier}.plist"
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Caches/${uninstall_tb_bundle_identifier}"
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/LaunchAgents/${uninstall_tb_bundle_identifier}.LaunchAtLogin.plist"
    fi

	# Remove per-user CrashReporter files
    if [ "${uninstall_tb_app_name}" != "" ] ; then
      for path in `ls /Users/${user}/Library/Logs/DiagnosticReports/${uninstall_tb_app_name}_*.crash 2> /dev/null` ; do
        uninstall_tb_remove_item_at_path "${path}"
      done

      for path in `ls /Users/${user}/Library/Logs/CrashReporter/${uninstall_tb_app_name}_*.crash 2> /dev/null` ; do
        uninstall_tb_remove_item_at_path "${path}"
      done
    fi

    for path in `ls /Users/${user}/Library/Logs/DiagnosticReports/openvpnstart_*.crash 2> /dev/null` ; do
      uninstall_tb_remove_item_at_path "${path}"
    done

    for path in `ls /Users/${user}/Library/Logs/CrashReporter/openvpnstart_*.crash 2> /dev/null` ; do
      uninstall_tb_remove_item_at_path "${path}"
    done

	# run the per-user routine to delete keychain items
    output="$(/usr/bin/su "${user}" -c "/bin/bash -c uninstall_tb_per_user_data")"
    if [ "${output}" != "" ] ; then
	  echo "${output}"
      if [ "${output:0:7}" = "Error: " ] ; then
        exit 0
      fi
    fi

  fi

done

# delete login items for this user only
if [ "{uninstall_remove_data}" = "true" ] ; then
  output=$(/usr/bin/su ${USER} -c "osascript -e 'set n to 0' -e 'tell application \"System Events\"' -e 'set login_items to the name of every login item whose name is \"${uninstall_tb_app_name}\"' -e 'tell me to set n to the number of login_items' -e 'repeat (the number of login_items) times' -e 'remove login item \"${uninstall_tb_app_name}\"' -e 'end repeat' -e 'end tell' -e 'n'")
else
  output=$(/usr/bin/su ${USER} -c "osascript -e 'set n to 0' -e 'tell application \"System Events\"' -e 'set login_items to the name of every login item whose name is \"${uninstall_tb_app_name}\"' -e 'tell me to set n to the number of login_items' -e 'end tell' -e 'n'")
fi
if [ "${output}" != "0" ] ; then
  echo "Removed ${output} of  ${USER}'s login items"
fi

# Remove the application itself
if [ "${uninstall_tb_app_path}" != "" ] ; then
  uninstall_tb_remove_item_at_path "${uninstall_tb_app_path}"
fi

if [ "${uninstall_remove_data}" != "true" ] ; then
  echo ""
  echo "Note:  NOTHING WAS REMOVED OR UNLOADED -- this was a test"
fi

exit 0