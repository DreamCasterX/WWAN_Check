#!/usr/bin/env bash


# CREATOR: mike.lu@hp.com
# CHANGE DATE: 2024/7/4
__version__="1.0"


# How To Use
# 1) Put this script to Desktop
# 2) Run `bash WWAN_Check.sh` 
# 3) Run `cat Result.log` to check if the output of cycle #0 is good
# 4) To stop the trace, select 'Clean' from the options


PING_URL=google.com
PING_IP=8.8.8.8
TEST_LOG=$HOME/Desktop/Result.log
NOW=$(date +"%Y/%m/%d - %H:%M:%S")
FILE_URL=http://ipv4.download.thinkbroadband.com/20MB.zip   
FILE_NAME=20MB.zip   
FILE_SIZE=20971520   # 10485760 (for 10MB)    20971520 (for 20MB)    31457280(for 30MB)
CYCLE=~/count
red='\e[41m'
nc='\e[0m'


# Restrict user account
[[ $EUID == 0 ]] && echo -e "⚠️ Please run as non-root user.\n" && exit


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


########################################################################################


# Check if WWAN driver loaded properly in dmesg
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


# Get connectivity state and IP address in Network Manager (Fail condition =>  AP state: disconnected    IP: null)
AP_STATE=$(nmcli device show wwan0mbim0 | grep GENERAL.STATE | cut -d "(" -f2 | cut -d ")" -f1)
IP=$(nmcli device show wwan0mbim0 | grep IP4.ADDRESS | cut -d " " -f26 | cut -d "/" -f1)
[[ $AP_STATE == "disconnected" ]] && echo -e "AP State: ${red}[FAILED]${nc}" >> $TEST_LOG || echo "AP State: ${AP_STATE^}" >> $TEST_LOG
[[ -z "$IP" ]] && echo -e "IP: ${red}[FAILED]${nc}" >>  $TEST_LOG || echo "IP: " >>  $TEST_LOG


# Get signal qulity from Modem Manager
SIGNAL=`mmcli -m any | grep 'signal quality' | awk -F ':' '{print $2}' | awk -F ' ' '{print $1}'` 
[[ $SIGNAL == "0%" ]] && echo -e "Signal Quality: ${red}[FAILED]${nc}" >> $TEST_LOG || echo "Signal Quality: $SIGNAL" >> $TEST_LOG


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
echo "" >> $TEST_LOG
echo "===============  Test cycle #$(cat $CYCLE) done on $NOW  ===============" >> $TEST_LOG	
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


