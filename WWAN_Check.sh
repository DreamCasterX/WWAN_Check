#!/usr/bin/env bash


# CREATOR: mike.lu@hp.com
# CHANGE DATE: 2024/7/19
__version__="1.3"


# How To Use
# 1) Put this script to $HOME/Desktop
# 2) Run `bash WWAN_Check.sh` 
# 3) Run `cat Result.log` to check if the initial result of cycle #0 is good
# 4) Select suspend or reboot stress test to run
# 5) To stop the trace, turn off WWAN and select 'Clean' from the options


PING_URL=google.com
PING_IP=8.8.8.8
TEST_LOG=$HOME/Desktop/Result.log
NOW=$(date +"%Y/%m/%d - %H:%M:%S")
FILE_URL=http://ipv4.download.thinkbroadband.com/10MB.zip   
FILE_NAME=10MB.zip   
FILE_SIZE=10485760   # 10485760 (for 10MB)    20971520 (for 20MB)    31457280(for 30MB)
CYCLE=~/count
red='\e[41m'
nc='\e[0m'


# Restrict user account
[[ $EUID == 0 ]] && echo -e "⚠️ Please run as non-root user.\n" && exit


# CHECK THE LATEST VERSION
UpdateScript() {
	# wget -q --spider www.google.com > /dev/null
	# [[ $? != 0 ]] && echo -e "❌ No Internet connection! Check your network and retry.\n" && exit || :
	[[ ! -f /usr/bin/curl ]] && sudo apt update && sudo apt install curl -y 
	release_url=https://api.github.com/repos/DreamCasterX/WWAN_Check/releases/latest
	new_version=$(curl -s "${release_url}" | grep '"tag_name":' | awk -F\" '{print $4}')
	release_note=$(curl -s "${release_url}" | grep '"body":' | awk -F\" '{print $4}')
	tarball_url="https://github.com/DreamCasterX/WWAN_Check/archive/refs/tags/${new_version}.tar.gz"
	if [[ $new_version != $__version__ ]]; then
		echo -e "⭐️ New version found!\n\nVersion: $new_version\nRelease note:\n$release_note"
	  	sleep 2
	  	echo -e "\nDownloading update..."
	  	pushd "$PWD" > /dev/null 2>&1
	  	curl --silent --insecure --fail --retry-connrefused --retry 3 --retry-delay 2 --location --output ".WWAN_Check.tar.gz" "${tarball_url}"
	  	if [[ -e ".WWAN_Check.tar.gz" ]]; then
			tar -xf .WWAN_Check.tar.gz -C "$PWD" --strip-components 1 > /dev/null 2>&1
			rm -f .WWAN_Check.tar.gz
			rm -f README.md
			popd > /dev/null 2>&1
			sleep 3
			sudo chmod 755 WWAN_Check.sh
			echo -e "Successfully updated! Please run WWAN_Check.sh again.\n\n" ; exit 1
	    	else
			echo -e "\n❌ Error occured while downloading" ; exit 1
	    	fi 
	fi
}

UpdateScript

######################################### [Configuration] ###################################################

# Create cron job to run script  (start time: 02:40)
RunScript() {
    echo "*/2 * * * * sleep 40 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron && rm -f mycron
}


# Create cron job to run script after reboot (start time: reboot + 30 sec)
RunScriptAfterReboot() {
    echo "@reboot sleep 30 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron && rm -f mycron
}


# Create cron job for S3 and resume (start time: 02:30)
RunS3() {
    sudo crontab -l > mycron 2> /dev/null
    grep -h "systemctl suspend" mycron 2> /dev/null
    if [[ $? != 0 ]]; then
        echo "*/2 * * * * sudo systemctl suspend && sudo rtcwake -m no -s 30" >> mycron 
        sudo crontab mycron && sudo rm -f mycron
    fi
}

# Create cron job for Reboot  (start time: 02:00)
RunReboot() {
    sudo crontab -l > mycron 2> /dev/null
    grep -h "shutdown -r" mycron 2> /dev/null
    if [[ $? != 0 ]]; then
        echo "*/2 * * * * sudo shutdown -r now" >> mycron
        sudo crontab mycron && sudo rm -f mycron
    fi
}

# Delete cron job
Clean() {
    rm -f $CYCLE
    crontab -r 2> /dev/null
    sudo crontab -r 2> /dev/null
    systemctl restart cron
    rm -f ~/$FILE_NAME 2> /dev/null
    sudo rm -f mycron ~/mycron
    # nmcli networking on
}


# Kill the previous instances of the script before running the same script
kill -9 $(pgrep -f ${BASH_SOURCE[0]} | grep -v $$) 2> /dev/null


######################################### [Test Case Execution] ###################################################

# Check if WWAN driver is loaded properly in dmesg
wwan_driver=`sudo lspci -k | grep -iEA3 wireless | grep 'Kernel driver in use:' | awk '{print $5}'`
sudo dmesg | grep $wwan_driver | grep "Invalid device status 0x1" 
if [[ $? = 0 ]]; then
	echo -e "Dmesg Check: ${red}[FAILED]${nc}" >> $TEST_LOG 
else
    echo -e "Dmesg Check: [PASSED]" >> $TEST_LOG
fi


# Check the presence of WWAN in IP command
[[ `ip a | grep 'wwan0'` ]] && echo "IP Check: [PASSED]" >> $TEST_LOG || echo -e "IP Check: ${red}[FAILED]${nc}" >> $TEST_LOG


# Check the presence of WWAN in Modem Manager
[[ `mmcli -m any` ]] && echo "ModemManager Check: [PASSED]" >> $TEST_LOG || echo -e "ModemManager Check: ${red}[FAILED]${nc}" >> $TEST_LOG


# Check cellular network connection and IP address in Network Manager (Fail condition =>  AP state: disconnected/unavailable    IP: null)
AP_STATE=$(nmcli device show wwan0mbim0 | grep GENERAL.STATE | cut -d "(" -f2 | cut -d ")" -f1)
IP=$(nmcli device show wwan0mbim0 | grep IP4.ADDRESS | cut -d " " -f26 | cut -d "/" -f1)
[[ $AP_STATE =~ ^(disconnected|unavailable)$ ]] && echo -e "AP State: ${red}[FAILED]${nc}" >> $TEST_LOG || echo "AP State: ${AP_STATE^}" >> $TEST_LOG
[[ -z "$IP" ]] && echo -e "IP: ${red}[FAILED]${nc}" >>  $TEST_LOG || echo "IP: $IP" >>  $TEST_LOG


# Get signal quality from Modem Manager (Fail condition => 0%/null)
SIGNAL=`mmcli -m any | grep 'signal quality' | awk -F ':' '{print $2}' | awk -F ' ' '{print $1}'` 
[[ -z $SIGNAL || $SIGNAL == "0%" ]] && echo -e "Signal Strength: ${red}[FAILED]${nc}" >> $TEST_LOG || echo "Signal Strength: $SIGNAL" >> $TEST_LOG


# Ping URL test
ping $PING_URL -c 10 | grep -w "0% packet loss" 
if [[ $? = 0 ]]; then
    echo "Ping Test: [PASSED]" >> $TEST_LOG 
else
    echo -e "Ping Test: ${red}[FAILED]${nc}" >> $TEST_LOG 
fi


# Download file test
rm -f ~/$FILE_NAME
wget $FILE_URL -P ~/
if [[ $(stat -c %s ~/$FILE_NAME 2> /dev/null) == "$FILE_SIZE" ]]; then
    echo "Download Test: [PASSED]" >> $TEST_LOG
else
    echo -e "Download Test: ${red}[FAILED]${nc}" >> $TEST_LOG
fi
rm -f ~/$FILE_NAME 2> /dev/null


# Output cycle and completion time to log
[ ! -f $CYCLE ] && echo -1 > $CYCLE
sed -i "s/$(cat $CYCLE)\$/`expr $(cat $CYCLE) + 1`/g" $CYCLE
fail_count=`grep 'FAILED' $TEST_LOG | wc -l`
fail_case=`grep 'FAILED' $TEST_LOG | awk -F ':' '{print $1}' | sort -u`
echo "" >> $TEST_LOG
echo "===============  Test cycle #$(cat $CYCLE) done on $NOW  ===============" >> $TEST_LOG
echo "*SUMMARY*  Total failure count:$fail_count   Failed cases:$fail_case" >> $TEST_LOG
echo "========================================================================" >> $TEST_LOG
echo "" >> $TEST_LOG


# Set cron job
sudo crontab -l > mycron 2> /dev/null
grep -h "WWAN_Check.sh" mycron 2> /dev/null
if [[ $? != 0 ]]; then
    read -p "Select an action: Suspend(s) or Reboot(r) or Clean(c): " POWER_STATE
        if [[ $POWER_STATE == [Ss] ]]; then
            RunScript
            RunS3
        fi
        if [[ $POWER_STATE == [Rr] ]]; then
            RunScriptAfterReboot
            RunReboot
        fi
        if [[ $POWER_STATE == [Cc] ]]; then
            Clean
        fi
        while [[ $POWER_STATE != [SsRrCc] ]]; do
          echo -e "Wrong input!\n"
          read -p "Select an action: Suspend(s) or Reboot(r) or Clean(c): " POWER_STATE
        done
fi


