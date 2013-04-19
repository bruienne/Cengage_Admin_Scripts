#!/bin/bash
############################################################################################
# Copyright 2011 Cengage Learning. All rights reserved.
#
#Redistribution and use in source and binary forms, with or without modification, are
#permitted provided that the following conditions are met:
#
#   1. Redistributions of source code must retain the above copyright notice, this list of
#      conditions and the following disclaimer.
#
#   2. Redistributions in binary form must reproduce the above copyright notice, this list
#      of conditions and the following disclaimer in the documentation and/or other materials
#      provided with the distribution.
#
#THIS SOFTWARE IS PROVIDED BY CENGAGE LEARNING ``AS IS'' AND ANY EXPRESS OR IMPLIED
#WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
#FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> OR
#CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
#SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
#ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#The views and conclusions contained in the software and documentation are those of the
#authors and should not be interpreted as representing official policies, either expressed
#or implied, of Cengage Learning.
############################################################################################

# Check for version and catalog arguments, error out if only one or none given.
if [[ $1 == "" || $2 == "" ]]; then
	echo "Usage: <scriptname> | [version] (e.g. 1.0 - required) | [catalog name] (e.g. printers - required) | [Print server name] (required) | [username] (required) | [password] (required) | [regex filter for queue name(s)] (optional)"
	exit 1
fi

OSX_VERS=$(sw_vers -productVersion | awk -F "." '{print $2}')

# Set the version passed from the command line.
version=$1

# Assign required and optional variables passed from the command line.
catalog=$2
server=$3
user=$4
pass=$5
filter=$6

if [ ${OSX_VERS} -lt 8 ]; then
	echo "We're on 10.7 or older, using smbclient..."
	SMB_TOOL="/usr/bin/smbclient -U ${user}%${pass} -L //${server}"
elif [ ${OSX_VERS} -eq 8 ]; then
	echo "We're on 10.8, using smbutil..."
	SMB_TOOL="/usr/bin/smbutil view //${user}:${pass}@${server}"
fi

# Loop through the input printer list file, this assumes output as given by smbclient -L for a given Windows print server, stripped of any leading tabs:
#	smbclient -U USER%PASSWORD -L //PRINT_SERVER/ | tr -d "\t" | sed "s/\ \{2,\}/\ /g"

# Configure the smbclient command for use with or without the optional printer name filter.
if [ ! ${filter} ];then
	SMBCLIENT='${SMB_TOOL} | tr -d "\t" | sed "s/\ \{2,\}/\ /g"'
else
	SMBCLIENT='${SMB_TOOL} | tr -d "\t" | sed "s/\ \{2,\}/\ /g" | egrep -i "${filter}"'
fi

# Run the command, this is the main routine.
eval ${SMBCLIENT} | while read line; do
	# Initialize $requires which is set if a print queue requires a non-standard PPD and initialize $printer, $location and $description
	#	by parsing the input line. The latter three are used when lpadmin runs from the PKG's postflight.
	requires=""
	printer=`echo "${line}" | awk -F" Printer " '{print $1}'`
	location=`echo "${printer}" | sed 's/\([0-9]\)\([0-9]\{3\}\)\(.*\)/\1-\2/g'`
	description=`echo "${line}" | awk -F" Printer " '{print $2}'`

	echo "********* 1: Printer name: ${printer} ***********"

	# We set a number of file and path variables for use during the setup of the Makefile and postflight files. This is so we can
	#	easily change paths when needed. $BASE_PATH is set to an optional third command line absolute path argument, otherwise it is
	#	set to the parent dir of where the script resides.
#	if [[ $2 == "" ]]; then
		BASE_PATH="${server}"/"${printer}"
#	else
#		BASE_PATH="${2}"/"${printer}"
#	fi

	MAKEFILE_TEMPLATE=./Makefile_template
	POSTFLIGHT_TEMPLATE=./postflight_template
	CONFIG_PATH="${BASE_PATH}"/"${printer}"-"${version}"
	MAKEFILE_PATH="${BASE_PATH}"/Makefile
	POSTFLIGHT_PATH="${BASE_PATH}"/postflight
	DMG_PATH="${CONFIG_PATH}".dmg
	PKGINFO_PATH="${CONFIG_PATH}".plist
	DMG_FILE="${printer}"-"${version}".dmg

	echo "********* 2: Printer name: ${printer} ***********"
	
	# Create a containing folder for the current printer's setup files if none exists, otherwise skip.
	if [[ ! -d "${BASE_PATH}" ]]; then
		echo "Creating new folder for ${printer}"
		mkdir -p "${BASE_PATH}"
	fi

	# Skip this printer if there's an existing DMG and the PPD has already been set in the postflight file, mostly to avoid doing
	#	extra work when we are just rerunning the script to process additional printers.
	if [[ -f  "${DMG_PATH}" && ! `grep "PPD_FILE" "${POSTFLIGHT_PATH}"` ]]; then
		echo "${printer} already processed, skipping..."
	else	

		echo "********* 3: Printer name: ${printer} ***********"

		# Main processing loop to create the Makefile and postflight files for the current printer based on the templates which live in the same directory as
		#	this script. Make sure to adjust paths in $MAKEFILE_TEMPLATE and $POSTFLIGHT_TEMPLATE when moving these two templates elsewhere.
		echo "Creating new Makefile and postflight files for ${printer}"
		sed -e "s#PRINTER_NAME#${printer}#g" < ${MAKEFILE_TEMPLATE} > ${MAKEFILE_PATH} -e "s/THIS_VERSION/${version}/g" < ${MAKEFILE_TEMPLATE} > ${MAKEFILE_PATH}

		# Match printer model name as given in print queue name to the appropriate PPD. Note this utterly fails if your print queues do not have a make/model listed.
		#	This could possibly be improved by creating a function to directly probe the print queue to determine the make and model but no attempts are made here to do that.
		case ${printer} in
			*HPCLJ4500*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP Color LaserJet 4500.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPCLJ4550*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP Color LaserJet 4550.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPCLJ4600*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#hp color LaserJet 4600.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPCLJ4650*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#hp color LaserJet 4650.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPCLJ4700*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP Color LaserJet 4700.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPCL*5550*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP Color LaserJet 5550.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPCL*5500*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#hp color LaserJet 5500.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ2100*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 2100 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ2200*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 2200.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ4000*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 4000 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ4015*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 4000 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ4025*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 4000 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ4100*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 4100 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ4*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 4MP.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ5000*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 5000 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ5200*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 5200.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HP*5SI*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 5Si.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ8000*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 8000 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ8100*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 8100 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJ8150*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet 8150 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJP4515*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet P4010_P4510 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJP4015*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet P4010_P4510 Series.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*HPLJP3005*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#HP LaserJet P3005.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*RICOH5001*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#RICOH Aficio MP 5001#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="Ricoh_Aficio_5001_PPD"
			;;
			*RICOHC5501*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#RICOH Aficio MP C5501#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="Ricoh_Aficio_C5501_PPD"
			;;
			*RICOHC6501*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#en.lproj/E-7200 PS US#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="Ricoh_Aficio_C6501_PPD"
			;;
			*RICOH3045*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#RICOH Aficio 3045#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="Ricoh Aficio Drivers"
			;;
			*XEROXWC*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#en.lproj/XRWCP255.PPD.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*XEROX7655*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#en.lproj/xrx7655.ppd.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*XEROX6130*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 6130N.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*XEROX7300*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 7300N.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH};;
			*XEROX3635*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 3635MFP.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="XeroxUniversalPrintDrivers"
			;;
			*XEROX8500*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 8500DN.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="XeroxPhaser8550"
			;;
			*XEROX8550*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 8550DP.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="XeroxPhaser8550"
			;;
			*XEROX8560*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 8560DN.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="XeroxPhaser8560"
			;;
			*XEROX5500*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 5500DN.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="XeroxPhaser5500"
			;;
			*XEROX7700*) sed -e "s#PRINTER_NAME#${printer}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#LOCATION#${location}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#DESCRIPTION#${description}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#PPD_FILE#Xerox Phaser 7700DN.gz#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH} -e "s#YOURPRINTSERVER#${server}#g" < ${POSTFLIGHT_TEMPLATE} > ${POSTFLIGHT_PATH}
			requires="XeroxPhaser7700"
			;;
			*)	echo "No matching PPD found for ${printer}, skipping..."
				break
			;;
		esac
		
		# All setups of Makefile and postflight are done so we move on to running The Luggage to create a payload-free package. To prevent running make for 
		#	unmatched printer make/models that lack a postflight file we test for both a Makefile and postflight.
		if [[ -f  "${POSTFLIGHT_PATH}" &&  -f  "${MAKEFILE_PATH}" ]]; then

			# Run make on the Luggage-based Makefile, using -C to cd into the current print queue's directory.
			make -C ${BASE_PATH}/ dmg
		
			# After The Luggage is done we run Munki's makepkginfo to create our pkginfo for this printer installer. After makepkginfo does its thing we add a few entries
			#	to the pkginfo file like the catalog name as given at the command line, the installer location in the Munki repo and the uninstall script. We're using
			#	Munki's "uninstall_script" uninstall_method vs. directly entering the one-line uninstall script as listed in the original Munki wiki article to allow for
			#	proper cleanup of the printer installer receipt which was not being done otherwise, leading to an inconsistent installed state after uninstallation.
			/usr/local/munki/makepkginfo ${BASE_PATH}/*.dmg > ${PKGINFO_PATH}
			/usr/libexec/PlistBuddy -c "Set :catalogs:0 ${catalog}" ${PKGINFO_PATH}
			/usr/libexec/PlistBuddy -c "Set :uninstall_method uninstall_script" ${PKGINFO_PATH}
			/usr/libexec/PlistBuddy -c "Set :installer_item_location printers/${DMG_FILE}" ${PKGINFO_PATH}
			/usr/libexec/PlistBuddy -c "Add :uninstall_script string" ${PKGINFO_PATH}
			/usr/libexec/PlistBuddy -c "Set :uninstall_script #!/bin/bash\n/etc/cups/printers_deployment/uninstalls/${printer}.sh\n/usr/sbin/pkgutil --forget com.cengage.${printer}\n" ${PKGINFO_PATH}

			# If the print queue PPD matching routine determined that a non-standard PPD is to be used this test will add the appropriate Munki installer item to the pkginfo
			#	as a "requires" key so that Munki will first install the PPD and then this printer installer pkg.
			if [[ ${requires} != "" ]]; then
				echo "Adding driver requirement ${requires} for printer ${printer}..."
				/usr/libexec/PlistBuddy -c "Add :requires array" ${PKGINFO_PATH}
				/usr/libexec/PlistBuddy -c "Add :requires:0 string ${requires}" ${PKGINFO_PATH}
			fi
		else
			echo "Missing postflight or Makefile, stopping here..."
		fi
	fi
done
