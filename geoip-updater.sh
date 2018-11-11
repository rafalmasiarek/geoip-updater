#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin

logFile="/dev/null" # path to log file. Default is /dev/nul , but you can create own log file
tmpPath="/tmp" # temporary directory to which geoIP database will be downloaded
mainPath="/etc/nginx" # the path under which geoIP database will be copied after downloading

###############################################################################
# Core - please, do not modify anything below                                 #
###############################################################################

OPTS=`getopt -o hv --long post-hook:,pre-hook:,verbose,help,compare,version -n 'parse-options' -- "$@"`
eval set -- "$OPTS"

VERSION="0.0.2"

dFAIL=false
VERBOSE=false
COMPARE=false
GeoIPisUpToDate=false
GeoLiteCityisUpToDate=false

WGET_BIN=$(which wget)
GUNZIP_BIN=$(which gunzip)
MV_BIN=$(which mv)
ECHO_BIN=$(which echo)
RM_BIN=$(which rm)

display_version() {
    $ECHO_BIN "Version: $VERSION"
}

display_help() {
    $ECHO_BIN "Usage: $0 [option...] {--help|--post-hook|--pre-hook|--verbose|--version}"
    $ECHO_BIN ""
    $ECHO_BIN "   -h, --help              Display this help message. (don't shit sherlock :o)"
    $ECHO_BIN "   -v, --verbose           Run in verbose mode (for debug purposes), it means that he will put output to screen and log file."
    $ECHO_BIN "   --pre-hook              Run hook before script start"
    $ECHO_BIN "   --post-hook             Run hook after script end"
    $ECHO_BIN "   --version               Check script version"
    $ECHO_BIN "   --compare               Compare checksums and replaces only if they differ"
    $ECHO_BIN ""
    display_version
    $ECHO_BIN "Author: Rafal Masiarek <rafal@masiarek.pl>"
}

log() {
    if [ -n "$1" ] && [ -n "$2" ]; then
        local survey=$1
        local message=$2
    else
        local message=$@
    fi

    if [ $VERBOSE == "true" ]; then
        if [ -n "$survey" ]; then
            case $survey in
                "ERR" | "FAIL" | "ERROR" | "CRITICAL" ) local survey_c="\e[31m$survey\e[0m" ;;
                "INFO" ) local survey_c="\e[93m$survey\e[0m" ;;
                "OK" ) local survey_c="\e[32m$survey\e[0m" ;;
                * ) local survey_c=$survey ;;
            esac
            $ECHO_BIN -ne "[ $survey_c ] "
        fi
	$ECHO_BIN -ne "`date "+%Y-%m-%d %H:%M:%S"`: $message"
    fi

    if [ -n "$survey" ]; then
        $ECHO_BIN -ne "[ $survey ] " >> "$logFile"
    fi
    $ECHO_BIN -ne "`date "+%Y-%m-%d %H:%M:%S"`: $message" >> "$logFile"
}

function result {
    if [ "$1" -eq "0" ]; then
       if [ $VERBOSE == "true" ]; then
           $ECHO_BIN -e "	[ \e[32mOK\e[0m ]"
       fi
       $ECHO_BIN "   [ OK ]" >> "$logFile"
    else
       if [ $VERBOSE == "true" ]; then
           $ECHO_BIN -e "    [ \e[31mFAIL\e[0m ]"
       fi
       $ECHO_BIN "   [ FAIL ]" >> "$logFile"
       dFAIL=true
    fi
}

while true; do
    case "$1" in
        --help    | -h ) display_help; exit 0 ;;
        --version ) display_version; exit 0;;
        --post-hook ) POST_HOOK=$2; shift 2;;
        --pre-hook ) PRE_HOOK=$2; shift 2;;
        --verbose | -v ) VERBOSE=true; shift ;;
        --compare ) COMPARE=true; shift ;;
        -- ) shift; break ;;
    esac
done

if [ -n "$PRE_HOOK" ]; then
    log "INFO" "Running pre-hook: ${PRE_HOOK}..."
    $PRE_HOOK
    ret=$?
    result $ret
    if [ $ret -gt 0 ]; then
        log "CRITICAL" "something wrong with pre-hook, for security script ends here.\n"
        exit 1
    fi
fi

# Download GeoIP Database
log "INFO" "Downloading GeoIP.dat.gz from maxmind.com..."
$WGET_BIN --quiet https://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz -P $tmpPath
result $?

log "INFO" "Downloading GeoLiteCity.dat.gz from maxmind.com..."
$WGET_BIN --quiet https://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz -P $tmpPath
result $?

# uncompress databases
log "INFO" "ungzip downlaoded GeoIP.dat.gz to GeoIP.dat..."
$GUNZIP_BIN "$tmpPath/GeoIP.dat.gz"
result $?

log "INFO" "ungzip downlaoded GeoLiteCity.dat.gz to GeoLiteCity.dat..."
$GUNZIP_BIN "$tmpPath/GeoLiteCity.dat.gz"
result $?

# compare checksum
if [ "$COMPARE" == "true" ]; then
    CHECKSUM_BIN=$(which sha256sum)
    currentGeoIPFile=`$CHECKSUM_BIN "$mainPath/GeoIP.dat" | awk '{ print $1 }'`
    currentGeoLiteCityFile=`$CHECKSUM_BIN  "$mainPath/GeoLiteCity.dat" | awk '{ print $1 }'`
    downloadedGeoIPFile=`$CHECKSUM_BIN "$tmpPath/GeoIP.dat" | awk '{ print $1 }'`
    downloadedGeoLiteCityFile=`$CHECKSUM_BIN  "$tmpPath/GeoLiteCity.dat" | awk '{ print $1 }'`
    log "INFO" "Comparing checksum $mainPath/GeoIP.dat with $tmpPath/GeoIP.dat\n"
    if [ "$currentGeoIPFile" == "$downloadedGeoIPFile" ]; then
        log "DEBUG" "Files GeoIP.dat are identical, they will not be replaced\n"
        GeoIPisUpToDate="true"
        $RM_BIN -f "$tmpPath/GeoIP.dat"
    else
        log "DEBUG" "Checksum GeoIP.dat is different, files will be replaced\n"
    fi

    log "INFO" "Comparing checksum $mainPath/GeoLiteCity.dat with $tmpPath/GeoLiteCity.dat\n"
    if [ "$currentGeoLiteCityFile" == "$downloadedGeoLiteCityFile" ]; then
        log "DEBUG" "Files GeoLiteCity.dat are identical, they will not be replaced\n"
        GeoLiteCityisUpToDate="true"
        $RM_BIN -f "$tmpPath/GeoLiteCity.dat"
    else
       	log "DEBUG" "Checksum GeoLiteCity.dat is different, files will be replaced\n"
    fi
fi

# move databases
if [ "$GeoIPisUpToDate" == "false" ]; then
    log "INFO" "Moving new GeoIP.dat database from $tmpPath to directory ${mainPath}..."
    $MV_BIN -f "$tmpPath/GeoIP.dat" "$mainPath/GeoIP.dat"
    result $?
fi

if [ "$GeoLiteCityisUpToDate" == "false" ]; then
    log "INFO" "Moving new GeoLiteCity.dat database from $tmpPath to directory ${mainPath}..."
    $MV_BIN -f "$tmpPath/GeoLiteCity.dat" "$mainPath/GeoLiteCity.dat"
    result $?
fi

if [ -n "$POST_HOOK" ]; then
    if [ "$GeoIPisUpToDate" == "false"  ] && [ "$GeoLiteCityisUpToDate" == "false" ]; then
        if [ $dFAIL == "false" ]; then
            log "INFO"  "Running post-hook: ${POST_HOOK}..."
            $POST_HOOK
            result $?
        else
            log "CRITICAL" "something went wrong, did not launch post-hook!"
            exit 1
        fi
    else
       log "INFO" "All databases are up-to-date, also post-hook is unnecessary. Nothing to do.\n"
       exit 0
    fi
fi

if [ $dFAIL == "true" ]; then
    exit 1
else
    exit 0
fi
