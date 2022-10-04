#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VIP=$1
VPT=$2
RIP=$3
RPT=$4

cmd=`curl -I -s -A "pokemongo/1 CFNetwork/758.5.3 Darwin/15.6.0" -U proxyuser:proxypasswort -x ${RIP}:${RPT} https://pgorelease.nianticlabs.com/plfe/version 2>/dev/null | grep -e "HTTP/2 200" -e "HTTP/1.1 200 OK"`
exit ${?}
