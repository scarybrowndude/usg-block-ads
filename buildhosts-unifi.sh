#!/bin/sh
##START buildhosts
#   This script gets various anti-ad hosts files, merges, sorts, and uniques, then installs.
#   Run from cron once a week.
#
#   Copyright © 2017 Matthew Headlee <mmh@matthewheadlee.com> (http://matthewheadlee.com/).
#
#   This file is buildhosts.
#
#   buildhosts is free software: you can redistribute
#   it and/or modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 3 of the License,
#   or (at your option) any later version.
#
#   buildhosts is distributed in the hope that it will
#   be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
#   Public License for more details.
#
#   You should have received a copy of the GNU General Public License along with
#   buildhosts.  If not, see
#   <http://www.gnu.org/licenses/>.

declare -i iBlackListCount=0

#Variables for the indefensible use of colors.
readonly cRed="$(tput setaf 1)"
readonly cGreen="$(tput setaf 2)"
readonly cYellow="$(tput setaf 3)"
readonly cUline="$(tput smul)"
readonly cBold="$(tput bold)"
readonly cReset="$(tput sgr0)"

function cleanup() {
    #Removes temporary files created during this scripts execution.
    echo -e "[${cYellow}${cUline} State ${cReset}] Purging temporary files..." >&2
    rm -f "${sTmpNewHosts}" "${sTmpAdHosts}"
}

function control_c() {
    echo -e "[${cRed}${cBold}Aborted${cReset}] Script canceled.\e[0K"
    cleanup
    exit 4
}

#Used for cleanup on ctrl-c / ensure this script exit cleanly.
trap 'control_c' HUP INT QUIT TERM

#Sanity check to ensure all script dependencies are met.
for cmd in cat curl date mktemp pkill rm sed sort uniq; do
    if ! type "${cmd}" &> /dev/null; then
        bError=true
        echo -e "[${cRed}${cBold}Failure${cReset}] This script requires the command '${cBold}${cmd}${cReset}' to run. Install '${cmd}', make it available in \$PATH and try again." >&2
    fi
done
${bError:-false} && exit 1

#Temporary files to hold the new hosts and cleaned up hosts
readonly sTmpNewHosts="$(mktemp "/tmp/tmp.newhosts.XXXXXX")"
readonly sTmpAdHosts="$(mktemp "/tmp/tmp.adhosts.XXXXXX")"
if [ ! -w "${sTmpNewHosts}" -o ! -w "${sTmpAdHosts}" ]; then
    echo -e "[${cRed}${cBold}Failure${cReset}] Failed to create temporary file ${sTmpNewHosts} or ${sTmpAdHosts}" >&2
    echo -e "[${cRed}${cBold}Details${cReset}] This probably means the filesystem is full or read-only." >&2
    cleanup
    exit 2
fi

#Download and merge multiple hosts files to ${sTmpNewHosts}
#CAUTION: If any host list providers are removed from this section
#         pay attention to the variable and iBlackListCount and
#         the sanity check which is performed below.
echo -e "[${cYellow}${cUline} State ${cReset}] Downloading host blacklists..." >&2

#TODO: If we wanted to be fancy we could do this in a loop for the download/parsing on
#      a list-by-list basis and rule out indivdual failures while keeping good results.
curl --progress-bar 'http://winhelp2002.mvps.org/hosts.txt' \
                    'https://adaway.org/hosts.txt' \
                    'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&mimetype=plaintext' \
                    'https://raw.githubusercontent.com/ookangzheng/dbl-oisd-nl/master/dblzero.txt' > "${sTmpNewHosts}" \
                    'https://raw.githubusercontent.com/notracking/hosts-blocklists/master/hostnames.txt' >> "${sTmpNewHosts}"

#Convert hosts text to the UNIX format. Strip comments, blanklines, and invalid characters.
#Replaces tabs/spaces with a single space, remove localhost entries.
echo -e "[${cYellow}${cUline} State ${cReset}] Sanitizing downloaded blacklists..." >&2
exec 3>"${sTmpAdHosts}"
echo '#### BEGIN AD SERVER BLACKLIST ####' >&3
echo "#### Last update: $(date) ####" >&3
sed -r -e "s/$(echo -en '\r')//g" \
       -e '/^#/d' \
       -e 's/#.*//g' \
       -e 's/[^a-zA-Z0-9\.\_\t \-]//g' \
       -e 's/(\t| )+/ /g' \
       -e 's/^127\.0\.0\.1/0.0.0.0/' \
       -e '/ localhost( |$)/d' \
       -e '/^ *$/d' \
       -e '/^0\.0\.0\.0 $/d' \
       "${sTmpNewHosts}" | \
 sort | uniq >&3
echo '####  END AD SERVER BLACKLIST  ####' >&3
exec 3>&-

#Verify parsing of the hostlist succeeded, at least 40,000 blacklist entries are expected.
iBlackListCount="$(wc -l "${sTmpAdHosts}" | cut -d ' ' -f 1)"
if [ "${iBlackListCount}" -lt "40000" ]; then
    echo -e "[${cRed}${cBold}Failure${cReset}] Only ${iBlackListCount} advertisement servers discovered. Minimum of 40,000 required. Aborting." >&2
    cleanup
    exit 3
fi

#Remove all previously blocked ad servers.
#echo -e "[${cYellow}${cUline} State ${cReset}] Removing old blacklist from /etc/hosts..." >&2
#sed -r -i '/#### BEGIN AD SERVER BLACKLIST ####/,/####  END AD SERVER BLACKLIST  ####/d' /etc/hosts

#Append ad servers to /etc/hosts.
#echo -e "[${cYellow}${cUline} State ${cReset}] Appending new blacklist to /etc/hosts..." >&2
#cat "${sTmpAdHosts}" >> /etc/hosts

echo -e "[${cYellow}${cUline} State ${cReset}] Writing new blacklist host file..." >&2
cat "${sTmpAdHosts}" > /etc/hosts-blacklist
echo "addn-hosts=/etc/hosts-blacklist" > /etc/dnsmasq.d/buildhosts-blacklist.conf

#Up the number of records dnsmasq will cache, this number needs to be equal to or greater than
#  the number of entries in the /etc/hosts file, otherwise dnsmasq will re-read the file for
#  each dns request greatly impacting performance.
echo -e "[${cYellow}${cUline} State ${cReset}] Reconfiguring dnsmasq..." >&2
if [ "${iBlackListCount}" -lt "100000" ]; then
	iCacheSize=100000
else
	iCacheSize="${iBlackListCount}"
fi
sed -i '/^cache-size=.*$/d;' /etc/dnsmasq.conf
echo "cache-size=${iCacheSize}" >> /etc/dnsmasq.conf

#Tell dnsmasq to reread the updated hosts file.
echo -e "[${cYellow}${cUline} State ${cReset}] Signaling dnsmasq to reload configuration..." >&2
service dnsmasq restart
#pkill -1 -x dnsmasq

#Cleanup.
cleanup

echo -e "[${cGreen}${cBold}Success${cReset}] Complete. Now blocking ${iBlackListCount} advertisement servers." >&2
##END buildhosts
