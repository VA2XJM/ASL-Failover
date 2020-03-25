#!/usr/bin/env bash

###########################################
#######                             #######
####### VA2XJM - ASL Server Monitor #######
#######                             #######
###########################################
# Ping & validate connection to two ASL   #
# Internet linked nodes. Connect to       #
# PRIMARY or failover to SECONDARY        #
###########################################

###########################################
#               Instructions              #
# 1) Place the script on ASL system and   #
#    edit settings below.                 #
# 2) chmod +x the script.                 #
# 3) Set a cronjob to run it for you      #
# 4) Now enjoy :)                         #
###########################################

###
#### Settings
###

# Status File (0=Disconnected, 1=Primary, 2=Failover)
STATUS_FILE="/tmp/asl_failover.status"

# Local node
NODE="1999"

# Primary remote node
NODE_PRIM="2000"
NODE_PRIM_H=$NODE_PRIM".nodes.allstarlink.org"

# Secondary remote node
NODE_SEC="2001"
NODE_SEC_H=$NODE_SEC".nodes.allstarlink.org"

###
#### /Settings
###

###
#### Check if Internet is avail
###
if ! ping -c1 google.com &>/dev/null; then
        echo "-> Internet not available."
	echo "0" > $STATUS_FILE
        exit
fi

###
#### Retrieve actual connected node
###

ACTION="GO"
STATUS="0"
NODE_PRIM_T=$NODE_PRIM"T"
NODE_SEC_T=$NODE_SEC"T"
NODE_PRIM_C=$NODE_PRIM"C"
NODE_SEC_C=$NODE_SEC"C"

#-> Validate Status
##-> Primary
LINK_P=`asterisk -rx "rpt lstats $NODE" | grep $NODE_PRIM`
if grep -q "ESTABLISHED" <<<"$LINK_P"; then
	echo "-> Connected to PRIMARY"
	STATUS="1"
	ACTION="EXIT"

elif grep -q "CONNECTING" <<<"$LINK_P"; then
	echo "-> Connecting to PRIMARY..."
	sleep 5
	LINK_P=`asterisk -rx "rpt lstats $NODE" | grep $NODE_PRIM`
	if grep -q "ESTABLISHED" <<<"$LINK_P"; then
		echo "-> Connected to primary"
		STATUS="1"
		ACTION="EXIT"
	else
		echo "-> Connection to PRIMARY not established. Going to FAILOVER"
		STATUS="0"
		ACTION="FAILOVER"
	fi

else
	echo "-> Not connected to PRIMARY."
fi

##-> Secondary
LINK_S=`asterisk -rx "rpt lstats $NODE" | grep $NODE_SEC`
if grep -q "ESTABLISHED" <<<"$LINK_S"; then
	echo "-> Connected to SECONDARY"
	STATUS="2"
	ACTION="CHECK"

elif grep -q "CONNECTING" <<<"$LINK_S"; then
	echo "-> Connecting to SECONDARY..."
	sleep 5
	LINK_S=`asterisk -rx "rpt lstats $NODE" | grep $NODE_SEC`
	if grep -q "ESTABLISHED" <<<"$LINK_S"; then
		echo "-> Connected to SECONDARY"
		STATUS="2"
		ACTION="EXIT"
	else
		echo "-> Connection to SECONDARY not established. FAILOVER failed."
		STATUS="0"
		ACTION="FAILED"
	fi

else
	echo "-> Not connected to SECONDARY."
fi

#-> Taking Actions
##-> Return to PRIMARY
if [ "$ACTION" == "CHECK" ]; then
	echo "--> Trying to reconnect to PRIMARY."
	asterisk -rx "rpt cmd $NODE ilink 3 $NODE_PRIM"
	sleep 5
	LINKS=`asterisk -rx "rpt lstats $NODE" | grep $NODE_PRIM`
	if grep -q "ESTABLISHED" <<<"$LINKS"; then
		echo "--> Connected to PRIMARY"
		asterisk -rx "rpt cmd $NODE ilink 1 $NODE_SEC"
		STATUS="1"
		ACTION="EXIT"
	else
		echo "--> Cannot connect to PRIMARY. Remain in failover mode."
		asterisk -rx "rpt cmd $NODE ilink 1 $NODE_PRIM"
		STATUS="2"
		ACTION="EXIT"
	fi
fi

##-> Go to SECONDARY
if [ "$ACTION" == "FAILOVER" ]; then
	echo "--> Connecting to SECONDARY"
	asterisk -rx "rpt cmd $NODE ilink 3 $NODE_SEC"
	sleep 5
	LINKS=`asterisk -rx "rpt lstats $NODE" | grep $NODE_SEC`
	if grep -q "ESTABLISHED" <<<"$LINKS"; then
		echo "--> Connected to SECONDARY"
		asterisk -rx "rpt cmd $NODE ilink 1 $NODE_PRIM"
		STATUS="2"
		ACTION="EXIT"
	else
		echo "--> Cannot connect to SECONDARY."
		asterisk -rx "rpt cmd $NODE ilink 1 $NODE_SEC"
		STATUS="0"
		ACTION="EXIT"
	fi
fi

##-> Return to PRIMARY
if [ "$ACTION" == "FAILED" ]; then
	asterisk -rx "rpt cmd $NODE ilink 3 $NODE_PRIM"
	asterisk -rx "rpt cmd $NODE ilink 1 $NODE_SEC"
	echo "--> Failover failed. Return to PRIMARY."
	ACTION="EXIT"
fi

##-> Ensure no loop are operated
if [ ! "$LINK_P" == "" ] && [ ! "$LINK_S" == "" ]; then
	asterisk -rx "rpt cmd $NODE ilink 1 $NODE_SEC"
	STATUS="1"
fi

##-> Write status to file.
echo $STATUS > $STATUS_FILE

##-> EXIT
if [ "$ACTION" == "EXIT" ]; then
	echo "DONE."
	exit
fi

echo "-end"
