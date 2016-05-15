#!/bin/bash
#
# Checks age of an ftp folder using lftp
#
# Created by Johannes Dagemark <johannes@dagemark.com> 2016-05-12
#

# set up the basics
LFTPBIN=$(which lftp)
[[ -z $LFTPBIN ]] && echo "This plugin needs lftp" && print_usage && exit 3
AWKBIN=$(which awk)
[[ -z $AWKBIN ]] && echo "This plugin needs awk" && print_usage && exit 3


debug=0
timeout=10

function debug {
    if [ $debug -eq 1 ]
    then
        echo $1
    fi
}

function print_usage {
    echo "Allows checking the age of a file or directory on an FTP server"
    echo ""
    echo "Usage: check_ftp_age.sh -H <ftpserver> -u <user> -p <password> \\"
    echo "                        -F <pathtofile> | -D <pathtodirectory> \\"
    echo "                        -T <timedifference> -w <warning> -c <critical>"
    echo ""
    echo "Options:"
    echo " -h, --help"
    echo "    Print detailed help screen."
    echo " -H, --hostname"
    echo "    Ftp server hostname or ip address."
    echo " -u, --username"
    echo "    Username."
    echo " -p, --password"
    echo "    Password."
    echo " -F, --file"
    echo "    Path to file on ftp server, --file OR --directory is needed."
    echo " -D, --directory"
    echo "    Path to directory on ftp server, --file OR --directory is needed."
    echo " -T, --timedifference"
    echo "    If the ftp server is on another time zone, add time difference"
    echo "    in minutes."
    echo " -w, --warning"
    echo "    Warning threshold in minutes."
    echo " -c, --critical"
    echo "    Critical threshold in minutes."
    echo " -t, --timeout"
    echo "    Timeout in seconds."
    echo " -v, --verbose"
    echo "    Enable debug output."
    echo ""
    echo "Example:"
    echo "    ./check_ftp_age.sh -H 192.168.1.2 -u ftpuser -p secret -F /pub \\"
    echo "                       -T 120 -w 60 -c 120 -t 10"
    echo ""
}

# Make sure the correct number of command line
# arguments have been supplied

if [ $# -lt 1 ]; then
        echo "You forgot to specify variables."
        print_usage
        exit 3
fi

while test -n "$1"; do
    case "$1" in
        --help)
            print_usage
            exit 0
            ;;
        -h)
            print_usage
            exit 0
            ;;
        --hostname)
            FTPSERVER=$2
            shift
            ;;
        -H)
            FTPSERVER=$2
            shift
            ;;
        --username)
            USERNAME=$2
            shift
            ;;
        -u)
            USERNAME=$2
            shift
            ;;
        --password)
            PASSWORD=$2
            shift
            ;;
        -p)
            PASSWORD=$2
            shift
            ;;
        --directory)
            DIRECTORY=$2
            shift
            ;;
        -D)
            DIRECTORY=$2
            shift
            ;;
        --file)
            FILE=$2
            shift
            ;;
        -F)
            FILE=$2
            shift
            ;;
        --timedifference)
            TIMEDIFFERENCE=$(($2*60))
            shift
            ;;
        -T)
            TIMEDIFFERENCE=$(($2*60))
            shift
            ;;
        --warning)
            WARNING=$2
            shift
            ;;
        -w)
            WARNING=$2
            shift
            ;;
        --critical)
            CRITICAL=$2
            shift
            ;;
        -c)
            CRITICAL=$2
            shift
            ;;
        --timeout)
            TIMEOUT=$2
            shift
            ;;
        -t)
            TIMEOUT=$2
            shift
            ;;
        --verbose)
            debug=1
            shift
            ;;
        -v)
            debug=1
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            print_usage
            exit 3
            ;;
    esac
    shift
done

# make sure $TIMEDIFFERENCE is allways set to not mess up the calculations later.
if [ -z $TIMEDIFFERENCE ] ; then TIMEDIFFERENCE="0"; fi

debug "FTPSERVER = $FTPSERVER"
debug "USERNAME = $USERNAME"
debug "PASSWORD = $PASSWORD"
debug "DIRECTORY = $DIRECTORY"
debug "FILE = $FILE"
debug "TIMEDIFFERENCE = $TIMEDIFFERENCE"
debug "WARNING = $WARNING"
debug "CRITICAL = $CRITICAL"
debug "TIMEOUT = $TIMEOUT"

# Fetch data from ftp server
if [[ -n "$DIRECTORY" ]]
then
    temp=`$LFTPBIN << EOF
set net:timeout $TIMEOUT
set cmd:fail-exit
set dns:max-retries 1
set net:max-retries 1
open $FTPSERVER -u $USERNAME,$PASSWORD
ls -la $DIRECTORY
bye
EOF`
    if [ $? -ne 0 ]
    then
        echo "Failed to connect to $FTPSERVER and list $DIRECTORY"
        exit 2
    fi
    DATA=`echo $temp | $AWKBIN -F\. '{print $1}'`
    debug "DATA = $DATA"
elif [[ -n "$FILE" ]]
then
    DATA=`$LFTPBIN << EOF
set net:timeout $TIMEOUT
set cmd:fail-exit
set dns:max-retries 1
set net:max-retries 1
open $FTPSERVER -u $USERNAME,$PASSWORD
ls -la $FILE
bye
EOF`
    if [ $? -ne 0 ]
    then
        echo "Failed to connect to $FTPSERVER and list $FILE"
        exit 2
    fi
    debug "DATA = $DATA"
else
    echo "you need to speficy file or directory"
    print_usage
    exit 3
fi

# some ftp servers move the date field around a bit so lets account for that.
columns=`echo $DATA | wc | $AWKBIN '{print $2}'`
debug "columns = $columns"
if (( $columns >= 9 ))
then
    if [[ -n "$DIRECTORY" ]]
    then
        FTPDATE=`echo $DATA | $AWKBIN '{print $7 " " $8 " " $9}'`
    else
        FTPDATE=`echo $DATA | $AWKBIN '{print $6 " " $7 " " $8}'`
    fi
else
    if [[ -n "$DIRECTORY" ]]
    then
        FTPDATE=`echo $DATA | $AWKBIN '{print $6 " " $7 " " $8}'`
    else
        FTPDATE=`echo $DATA | $AWKBIN '{print $5 " " $6 " " $7}'`
    fi
fi
debug "FTPDATE = $FTPDATE"

# convert $FTPDATE to unixtime
FTPUNIXTIME=`date --date="$FTPDATE" +"%s"`
debug "FTPUNIXTIME = $FTPUNIXTIME"

LOCALUNIXTIME=`date +"%s"`
debug "LOCALUNIXTIME = $LOCALUNIXTIME"

# Calculate age of the file/dir
AGE=$((($LOCALUNIXTIME - ($FTPUNIXTIME + $TIMEDIFFERENCE))/60))
debug "AGE = $AGE"

# Calculate state and exit nicely
if (( $AGE >= $CRITICAL ))
then
    if [ -n "$FILE" ]
    then
        echo "The age of file $FILE is $AGE minutes | age=$AGE;$WARNING;$CRITICAL;0;;"
        debug "Exiting with critical file"
        exit 2
    else
        echo "The age of directory $DIRECTORY is $AGE minutes | age=$AGE;$WARNING;$CRITICAL;0;;"
        debug "Exiting with critical directory"
        exit 2
    fi
elif (( $AGE >= $WARNING ))
then
    if [ -n "$FILE" ]
    then
        echo "The age of file $FILE is $AGE minutes | age=$AGE;$WARNING;$CRITICAL;0;;"
        debug "Exiting with warning file"
        exit 1
    else
        echo "The age of directory $DIRECTORY is $AGE minutes | age=$AGE;$WARNING;$CRITICAL;0;;"
        debug "Exiting with warning directory"
        exit 1
    fi
else
    if [ -n "$FILE" ]
    then
        echo "The age of file $FILE is $AGE minutes | age=$AGE;$WARNING;$CRITICAL;0;;"
        debug "Exiting with ok file"
        exit 0
    else
        echo "The age of directory $DIRECTORY is $AGE minutes | age=$AGE;$WARNING;$CRITICAL;0;;"
        debug "Exiting with ok directory"
        exit 0
    fi
fi
