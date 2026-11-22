#!/bin/sh
# Zabbix agent helper for the "nut_ups template".
#   upsmon.sh ups.discovery        -> LLD JSON with {#UPSNAME} for every UPS NUT knows
#   upsmon.sh <ups> ups.status     -> status as a number (valuemap "UPS Battery Status")
#   upsmon.sh <ups> <nut variable> -> raw value from upsc
# Used by: UserParameter=upsmon[*],/etc/zabbix/scripts/upsmon.sh "$1" "$2"

if [ "$1" = "ups.discovery" ]; then
    first=1
    printf '['
    for ups in $(upsc -l 2>/dev/null); do
        [ "$first" -eq 1 ] || printf ','
        printf '{"{#UPSNAME}":"%s"}' "$ups"
        first=0
    done
    printf ']\n'
    exit 0
fi

ups="$1"
var="$2"

if [ "$var" = "ups.status" ]; then
    status=$(upsc "$ups@localhost" ups.status 2>/dev/null)
    # has FLAG: true if the NUT status contains that word (e.g. "OL CHRG" has OL and CHRG)
    has() { case " $status " in *" $1 "*) return 0 ;; esac; return 1; }
    if   [ -z "$status" ];             then echo 0   # no answer from NUT
    elif has LB;                       then echo 3   # low battery
    elif has OVER;                     then echo 10  # overloaded
    elif has BYPASS;                   then echo 7   # bypass active
    elif has OFF;                      then echo 9   # offline
    elif has CAL;                      then echo 8   # calibration
    elif has RB;                       then echo 4   # replace battery
    elif has OB && has DISCHRG;        then echo 14  # on battery, discharging
    elif has OB;                       then echo 2   # on battery
    elif has TRIM;                     then echo 11  # trimming voltage
    elif has BOOST;                    then echo 12  # boosting voltage
    elif has OL && has CHRG;           then echo 13  # on line, charging
    elif has DISCHRG;                  then echo 6   # discharging
    elif has CHRG;                     then echo 5   # charging
    elif has OL;                       then echo 1   # on line
    else                                    echo 0   # unknown
    fi
    exit 0
fi

upsc "$ups@localhost" "$var" 2>/dev/null
