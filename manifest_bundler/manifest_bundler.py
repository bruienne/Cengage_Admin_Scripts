#!/usr/bin/env python
# encoding: utf-8

import sys
sys.path.append("/usr/local/munki/munkilib")
import munkicommon
import FoundationPlist
import os
import re
from pkg_resources import parse_version
from optparse import OptionParser

# Setup option parsing
parser = OptionParser()

# Check for a file path from sys.argv
if len(sys.argv) < 2:
    sys.exit( "Usage: manifest_bundler.py [PATHNAME] [-o | --optional] [-n | --nested]")
elif not os.path.isfile(sys.argv[1]):
    sys.exit("Supplied option \"" + sys.argv[1] + "\" is not a file.")
else:
    manifestpath = sys.argv[1]
    print "Processing manifest from " + manifestpath + "\n"


# Parse our program arguments
parser.add_option("-o", "--process-optional",
                    action="store_true", dest="optional", default=False,
                    help="Also process the optional installs in the manifest")
# Process nested manifests
parser.add_option("-n", "--process-nested",
                    action="store_true", dest="nested", default=False,
                    help="Process nested manifests as well")

parser.add_option("-u", "--upload",
                    action="store_true", dest="upload", default=False,
                    help="Upload to Munkiserver")

(options, args) = parser.parse_args()

# Setup variables for various paths and files using user options:
#
#  manifestpath = absolute path to our manifest to process
#  manifest = the manifest name only
#  basedir = absolute path to the Munki repo's base dir
#  pkgsinfodir = absolute path to the Munki repo's pkgsinfo dir
#  pkgsdir = absolute path to the Munki repo's pkgs dir
#  itemstobundle = one or more keys from the manifest to bundle (single argument right now)

manifest = os.path.basename(manifestpath)
basedir = os.path.dirname(manifestpath).split("manifests")[0]
manifestdir = os.path.dirname(manifestpath)
pkgsinfodir = os.path.join(basedir, "pkgsinfo")
pkgsdir = os.path.join(basedir, "pkgs")
processoptional = options.optional
processnested = options.nested
upload = options.upload
managedinstalls = ""

if processoptional:
    print "Processing Optional Software..."

if processnested:
    print "Processing nested manifests...\n"

def uploadToMunkiserver(pkginfo, pkg):
    """docstring for uploadToMunkiserver"""
    
    s = requests.Session()
    # s.params = {'autoconfig':'true'}

    url = 'http://localhost:3000/default/packages/batch'

    files = {'package_file': open(pkg, 'rb'), 'pkginfo_file': open(pkginfo, 'rb')}

    result = s.post(url, files=files)
    # print result.text
    print result.status_code
        
    # pass

def processManifest(manifestpath, nested=False):
    """docstring for processManifest"""
    # Define our manifest to process
    if os.path.isfile(manifestpath):
        plist = FoundationPlist.readPlist(manifestpath)

        # Get the requested manifest items from the manifest
        managedinstalls = plist.get("managed_installs")

        if processoptional:
            optionalinstalls = plist.get("optional_installs")
            managedinstalls = managedinstalls + optionalinstalls
        if processnested:
            nestedmanifests = plist.get("included_manifests")
            # print nestedmanifests
            for thismanifest in nestedmanifests:
                managedinstalls = managedinstalls + processManifest(os.path.join(manifestdir, thismanifest), nested=True)

    else:
        print "Not a file: " + options.manifestpath
    return managedinstalls

# Takes a pkginfo name and a path and looks up the corresponding install_item_location (i.e. the installer)
def findInstallerItem(thispkginfo,thispath):
    
    # Basic test of file suitability, is it a file?
    if os.path.isfile(thispath + "/" + thispkginfo):
        
        # It's a file so parse it as a plist and retrieve the installer_item_location value
        #  TODO: Should test for a valid plist as well
        thisplist = FoundationPlist.readPlist(thispath + "/" + thispkginfo)
        thisitemlocation = thisplist.get("installer_item_location")
        
        # Create the full paths to installer_item_location and the pkginfo
        pkginfo = pkgsdir + "/" + thisitemlocation
        pkg = thispath + "/" + thispkginfo
        
        # Verify that the pkginfo is a file
        if os.path.isfile(pkginfo):
            # Do stuff. For now we just print the result.
            print pkginfo
        else:
            print "The pkginfo " + pkginfo + " was not found."
        # Verify that the pkg is a file
        if os.path.isfile(pkg):
            # Do stuff. For now we just print the result.
            print pkg
        else:
            print "The pkg " + pkginfo + " was not found."

    else:
        # This isn't a file so print thispkginfo and bail
        print "Something else: " + thispkginfo
    
    return pkg, pkginfo
    
def getHighestVersion(thisapp):

    # Initialize version to keep a running tally of the highest version as we iterate
    version="0.0"
    
    # Iterate over thisapp and extract the app name and version separately
    for i in [os.path.splitext(x)[0] for x in thisapp]:
        currentapp = munkicommon.nameAndVersion(i)[0]
        thisversion = munkicommon.nameAndVersion(i)[1]

        # Check whether the current iteration's version is higher than our running tally
        if parse_version(thisversion) > parse_version(version):

            # It's higher, so update the version now
            version = thisversion
            pkginfo = i + ".plist"
            
    return pkginfo
        
def bundleItems(pkgsinfodir, thismanagedinstalls):
    # Iterate over the given directory and get all filenames
    for (path, dirs, files) in os.walk(pkgsinfodir):
    
        # Now iterate over the managedinstalls items
        for item in thismanagedinstalls:
            # Create an empty list in case we encounter multiple versions of an app
            thisapp=[]
            explicitversion = ""
        
            # Catch managed_installs items with explicit versions so we can honor them
            if re.search('\-[0-9]', item):
                itemandversion = item.split('-')
                item = itemandversion[0]
                explicitversion = itemandversion[1]
        
            # Now we iterate over the files found in the directory with os.walk
            for thisfile in files:

                # Check whether the current file matches the current item from thismanagedinstalls
                # If it matches append the filename to the thisapp list
                if thisfile.startswith(item + "-"):
                    thisapp.append(thisfile)
                
            # After iterating and finding one or more versions of the current thismanagedinstalls item
            #  we move on to figuring out the newest version of the app - we don't want older ones.
            if len(thisapp) > 1:
                pkginfo = getHighestVersion(thisapp)
                findInstallerItem(pkginfo,path)
            
            # If there's only one version found just run findInstallerItem
            elif len(thisapp) == 1 and not explicitversion:
                pkginfo = thisapp[0]
                findInstallerItem(pkginfo,path)

def main():
    
    # Run it
    itemstobundle = processManifest(manifestpath)
    pkg, pkginfo = bundleItems(pkgsinfodir, itemstobundle)
    if upload:
        print 'Attempting to upload files...'
        uploadToMunkiserver(pkg, pkginfo)
    
    
if __name__ == '__main__':
    main()
