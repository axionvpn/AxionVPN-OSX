#!/bin/bash
#
# Copyright (c) 2015 by Jonathan K. Bullard. All rights reserved.
#
# This file is part of Tunnelblick.
#
# Tunnelblick is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2
# as published by the Free Software Foundation.
#
# Tunnelblick is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING included with this
# distribution); if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/.
#
#
# This script is the final step in creating Tunnelblick. It creates AxionVPN.app and its disk image
# Touch the build folder to get it to the top of listings sorted by modification date
touch build

# If Xcode has built AxionVPN.app in somewhere unexpected, complain and quit
if [ ! -d "build/${CONFIGURATION}/${PROJECT_NAME}.app" ] ; then
  echo "error: An Xcode preference must be set to put build products in the 'tunnelblick/build' folder. Please set Xcode preference > Locations > Advanced to 'Legacy'"
  exit -1
fi

if [ "${CONFIGURATION}" = "Analyze ONLY" ]; then
  # Make sure we never use the binary
  rm -r -f "build/${CONFIGURATION}/${PROJECT_NAME}.app"
  exit 0
fi

# Index the help files
  hiutil -Caf "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/help/help.helpindex" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/help"

# Set the build number in Info.plist for the app and for the kexts
# Replaces all occurances of "TBBUILDNUMBER" in an Info.plist with the second argument
# If an "Unsigned" build, appends " Unsigned" to CFBundleShortVersionString, which is detected by the ")" after "TBBUILDNUMBER"
# If an "Debug" build,    appends " Debug"    to CFBundleShortVersionString, which is detected by the ")" after "TBBUILDNUMBER"
# @param String, path to Info.plist file that should be modified
# @param String, build number
setBuildNumber()
{
	if [ "${CONFIGURATION}" = "Unsigned Release" ]; then
		sed -e "s|TBBUILDNUMBER)|TBBUILDNUMBER) Unsigned|g" "${1}" | sed -e "s|TBBUILDNUMBER|${2}|g" > "${1}.tmp"
	elif [ "${CONFIGURATION}" = "Debug" ]; then
		sed -e "s|TBBUILDNUMBER)|TBBUILDNUMBER) Debug|g"    "${1}" | sed -e "s|TBBUILDNUMBER|${2}|g" > "${1}.tmp"
	else
		sed -e "s|TBBUILDNUMBER|${2}|g" "${1}" > "${1}.tmp"
	fi
	rm "${1}"
	mv "${1}.tmp" "${1}"
}
tbbn="$(cat TBBuildNumber.txt)"
setBuildNumber "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Info.plist" "${tbbn}"



# Create the openvpn directory structure:
# ...Contents/Resources/openvpn contains a folder for each version of OpenVPN.
# The folder for each vesion of OpenVPN is named "openvpn-x.x.x".
# Each "openvpn-x.x.x"folder contains the openvpn binary and the openvpn-down-root.so binary
mkdir -p "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn"
default_openvpn="z"
for d in `ls "../third_party/products/openvpn"`
do
  mkdir -p "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/${d}"
  cp "../third_party/products/openvpn/${d}/openvpn-executable" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/${d}/openvpn"
  cp "../third_party/products/openvpn/${d}/openvpn-down-root.so" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
  chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
  if [ "${d}" \< "${default_openvpn}" ] ; then
    default_openvpn="${d}"
  fi
done

if [ "${default_openvpn}" != "z" ] ; then
  rm -f "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/default"
  ln -s "${default_openvpn}/openvpn" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/default"
else
  echo "warning: Could not find a version of OpenVPN to use by default"
fi

# Remove extra files that are not needed

rm -f "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/TBBuildNumber.txt"

rm -f "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/ExternalBuildCleanScript.sh"

# Remove non-.png files in IconSets (but leave the "templates.png" file)
for d in `ls "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/IconSets"` ; do
  if [ -d "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/IconSets/${d}" ] ; then
    for f in `ls "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/IconSets/${d}"` ; do
      if [ "${f##*.}" != "png" ] ; then
        if [ "${f%.*}" != "templates" ] ; then
          if [ -d "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/IconSets/${d}/${f}" ] ; then
            rm -f -R "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/IconSets/${d}/${f}"
          else
            rm -f "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/IconSets/${d}/${f}"
          fi
        fi
      fi
    done
  else
    rm -f "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/IconSets/${d}"
  fi
done

# Remove extended attributes
for f in build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/*
do
  xattr -d "com.apple.FinderInfo" ${f} 2> /dev/null
done

# Remove NeedsTranslation.strings and Removed.strings from all .lproj folders
shopt -s nullglob
for f in build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/*.lproj
do
  if test -f "${f}/NeedsTranslation.strings"
  then
    rm "${f}/NeedsTranslation.strings"
  fi
  if test -f "${f}/Removed.strings"
  then
    rm "${f}/Removed.strings"
  fi 
done

# Change permissions from 755 to 744 on many executables in Resources (openvpn-down-root.so permissions were changed when setting up the OpenVPN folder structure)
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/atsystemstart"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/installer"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/leasewatch"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/leasewatch3"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/process-network-changes"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/standardize-scutil-output"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/tunnelblickd"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.up.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.down.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.route-pre-down.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.1.up.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.1.down.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.2.up.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.2.down.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.3.up.tunnelblick.sh"
chmod 744 "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/client.3.down.tunnelblick.sh"

SIGNING_IDENTITY="3P4L4LZ5DK"

# Sign the app and its tools if Release
if [ "${CONFIGURATION}" = "Release" ]; then
  # Sign the binary tools and the Tunnelblick application itself


   codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.7/openvpn"
   codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.7/openvpn-down-root.so"

    codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.7txp/openvpn"
    codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.7txp/openvpn-down-root.so"

    codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.8/openvpn"
    codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.8/openvpn-down-root.so"

    codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.8txp/openvpn"
    codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Resources/openvpn/openvpn-2.3.8txp/openvpn-down-root.so"




# codesign -s "3P4L4LZ5DK" "build/${CONFIGURATION}/${PROJECT_NAME}.app/Contents/Frameworks/Sparkle.framework/Versions/A"
    codesign -s "Developer ID Application: Global VPN B.V" "build/${CONFIGURATION}/${PROJECT_NAME}.app"

fi

# Create the Tunnelblick .dmg and the Uninstaller .dmg except if Debug
if [ "${CONFIGURATION}" != "Debug" ]; then

	# Staging folder
	TMPDMG="build/${CONFIGURATION}/${PROJECT_NAME}"

	# Folder with files for the .dmg (.DS_Store and background folder which contains background.png background image)
	DMG_FILES="dmgFiles"

	# Remove the existing "staging" folder and copy the application into it
	rm -r -f "$TMPDMG"
	mkdir -p "$TMPDMG"
	cp -p -R "build/${CONFIGURATION}/${PROJECT_NAME}.app" "$TMPDMG"

	# Copy link to documentation to the staging folder
    #cp -p "Online Documentation.webloc" "$TMPDMG"

	# Copy the background folder and its background.png file to the staging folder and make the background folder invisible in the Finder
	cp -p -R "$DMG_FILES/background" "$TMPDMG"
	setfile -a V "$TMPDMG/background"

	# Copy dotDS_Store to .DS_Store and make it invisible in the Finder
	cp -p -R "$DMG_FILES/dotDS_Store" "$TMPDMG/.DS_Store"
	setfile -a V "$TMPDMG/.DS_Store"

	# Remove any existing .dmg and create a new one. Specify "-noscrub" so that .DS_Store is copied to the image
	rm -r -f "build/${CONFIGURATION}/${PROJECT_NAME}.dmg"
	hdiutil create -noscrub -srcfolder "$TMPDMG" "build/${CONFIGURATION}/${PROJECT_NAME}.dmg"

	# Leave the staging folder so customized .dmgs can be easily created

		# Remove the existing "staging" folder and copy the uninstaller into it
	rm -r -f "$TMPDMG"
	    touch "build/${CONFIGURATION}/${PROJECT_NAME}.dmg"
fi


touch "build/${CONFIGURATION}/${PROJECT_NAME}.app"
