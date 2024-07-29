#!/usr/bin/env bash


# CREATOR: mike.lu@hp.com
# CHANGE DATE: 2024/7/29
__version__="1.3"


# How To Use
# 1) Run `./WWAN_Check.sh` 
# 3) Run `cat Result.log` to check if the initial result of cycle #0 is good
# 4) Select suspend or reboot stress test to continue
# 5) To stop the trace, disconnect network and select 'Clean' from the options


PING_IP=8.8.8.8
TEST_LOG=$HOME/Desktop/Result.log
NOW=$(date +"%Y/%m/%d - %H:%M:%S")
FILE_URL=http://ipv4.download.thinkbroadband.com/5MB.zip   
FILE_NAME=5MB.zip   
FILE_SIZE=5242880   # 5242880 (for 5MB)    10485760 (for 10MB)    20971520 (for 20MB)    31457280 (for 30MB)
CYCLE=~/count
red='\e[41m'
blue='\e[44m'
nc='\e[0m'


# Restrict user account
[[ $EUID == 0 ]] && echo -e "⚠️ Please run as non-root user.\n" && exit


# Put the script to the assigned path
script_path=$(realpath "${BASH_SOURCE[0]}")
if [[ ! "$script_path" =~ "$HOME/Desktop" ]]; then
	target_path="$HOME/Desktop/WWAN_Check.sh"
	mv "$script_path" "$target_path"
	if [[ $? == 0 ]]; then
		echo "Script moved to $HOME/Desktop for execution"
		script_path="$target_path"
	else
		echo "Failed to move script to $HOME/Desktop. Exiting..."
		exit 1
	fi
fi
cd $HOME/Desktop


# Update to the latest version
UpdateScript() {
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
			echo -e "\n❌ Error occured while downloading"
	    	fi 
	fi
}

nslookup google.com > /dev/null && UpdateScript 

######################################### [Configuration] ###################################################

# Create cron job to run script  (start time: 02:40 => resume from S3 + 10 sec)
RunScript() {
    echo "*/2 * * * * sleep 40 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron && rm -f mycron
}

# Create cron job for S3 and resume (start time: 02:00   resume: 30 sec)
RunS3() {
    sudo crontab -l > mycron 2> /dev/null
    grep -h "systemctl suspend" mycron 2> /dev/null
    if [[ $? != 0 ]]; then
        echo "*/2 * * * * sudo systemctl suspend && sudo rtcwake -m no -s 30" >> mycron 
        sudo crontab mycron && sudo rm -f mycron
    fi
}

# Create cron job to run script after reboot (start time: reboot + 1 min => for device initialization)
RunScriptAfterReboot() {
    echo "@reboot sleep 60 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron && rm -f mycron
}

# Create cron job for Reboot  (start time: 04:00)
RunReboot() {
    sudo crontab -l > mycron 2> /dev/null
    grep -h "shutdown -r" mycron 2> /dev/null
    if [[ $? != 0 ]]; then
        echo "*/4 * * * * sudo shutdown -r now" >> mycron
        sudo crontab mycron && sudo rm -f mycron
    fi
}

# Delete cron job and restore to default settings
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

# Case 1 - check if WWAN driver is loaded properly in dmesg
echo "Running case #1 - check dmesg"
wwan_driver=`sudo lspci -k | grep -iEA3 wireless | grep 'Kernel driver in use:' | awk '{print $5}'`  # WWAN => grep 'wireless'   WLAN => grep 'network'      
sudo dmesg | grep $wwan_driver | grep "Invalid device status 0x1" 
if [[ $? = 0 ]]; then
	echo -e "Dmesg Check: ${red}[FAILED]${nc}" >> $TEST_LOG 
else
    echo -e "Dmesg Check: [PASSED]" >> $TEST_LOG
fi


# Case 2 - check the presence of WWAN in IP command
echo "Running case #2 - check IP command"
[[ `ip a | grep 'wwan0'` ]] && echo "IP Check: [PASSED]" >> $TEST_LOG || echo -e "IP Check: ${red}[FAILED]${nc}" >> $TEST_LOG


# Case 3 - check the presence of WWAN in Modem Manager
echo "Running case #3 - check modem manager"
[[ `mmcli -m any` ]] && echo "ModemManager Check: [PASSED]" >> $TEST_LOG || echo -e "ModemManager Check: ${red}[FAILED]${nc}" >> $TEST_LOG


# Case 4 - check cellular network connection state in Network Manager (Fail condition =>  disconnected/unavailable)
echo "Running case #4 - check connection state"
AP_STATE=$(nmcli device show wwan0mbim0 | grep GENERAL.STATE | cut -d "(" -f2 | cut -d ")" -f1)
[[ $AP_STATE =~ ^(disconnected|unavailable)$ ]] && echo -e "AP State: ${red}[FAILED]${nc}" >> $TEST_LOG || echo "AP State: ${AP_STATE^}" >> $TEST_LOG


# Case 5 - check IP address in Network Manager (Fail condition => null)
echo "Running case #5 - get IP address"
IP=$(nmcli device show wwan0mbim0 | grep IP4.ADDRESS | cut -d " " -f26 | cut -d "/" -f1)
[[ -z "$IP" ]] && echo -e "IP Addr: ${red}[FAILED]${nc}" >>  $TEST_LOG || echo "IP Addr: $IP" >>  $TEST_LOG


# Case 6 - get signal quality from Modem Manager (Fail condition => 0%/null)
echo "Running case #6 - get signal quality"
SIGNAL=`mmcli -m any | grep 'signal quality' | awk -F ':' '{print $2}' | awk -F ' ' '{print $1}'` 
[[ -z $SIGNAL || $SIGNAL == "0%" ]] && echo -e "Signal Strength: ${red}[FAILED]${nc}" >> $TEST_LOG || echo "Signal Strength: $SIGNAL" >> $TEST_LOG


# Case 7 - ping test (Fail condition => any packet loss)
echo "Running case #7 - ping test"
ping $PING_IP -c 6 | grep -w "0% packet loss"
if [[ $? = 0 ]]; then
    echo "Ping Test: [PASSED]" >> $TEST_LOG 
else
    echo -e "Ping Test: ${red}[FAILED]${nc}" >> $TEST_LOG 
fi


# Case 8 - download file test
echo -e "\nRunning case #8 - download file"
rm -f ~/$FILE_NAME
wget $FILE_URL -P ~/
if [[ $(stat -c %s ~/$FILE_NAME 2> /dev/null) == "$FILE_SIZE" ]]; then
    echo "Download Test: [PASSED]" >> $TEST_LOG
else
    echo -e "Download Test: ${red}[FAILED]${nc}" >> $TEST_LOG
fi
rm -f ~/$FILE_NAME 2> /dev/null


######################################### [Test log collection] ###################################################

# Output the current cycle, completion time and test summary to Result.log
[ ! -f $CYCLE ] && echo -1 > $CYCLE
sed -i "s/$(cat $CYCLE)\$/`expr $(cat $CYCLE) + 1`/g" $CYCLE
echo -e "\n===============  Test cycle #$(cat $CYCLE) done on $NOW  ===============" >> $TEST_LOG
fail_count=`grep 'FAILED' $TEST_LOG -A9 | awk -F 'cycle' '{print $2}'| sed -n '/./p' | wc -l`
[[ $fail_count != 0 ]] && fail_cycle="(`grep 'FAILED' $TEST_LOG -A9 | awk -F 'cycle' '{print $2}'| sed -n '/./p' | cut -d ' ' -f2 | awk 'BEGIN{ORS=", "}'1 | sed 's/, $//g'`)"
[[ $fail_count != 0 ]] && fail_case=`grep 'FAILED' $TEST_LOG | awk -F ':' '{print $1}' | sort -u | awk 'BEGIN{ORS=" / "}'1 | sed 's/\/ $//g'` || fail_case='n/a'
echo -e "${blue}*SUMMARY*   Total failures: $fail_count $fail_cycle       Failed cases: $fail_case${nc}" >> $TEST_LOG
echo -e "==============================================================================\n" >> $TEST_LOG


# Run test based on user input
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


