#!/usr/bin/env bash


# CREATOR: mike.lu@hp.com
# CHANGE DATE: 2024/4/1
__version__="1.0"


# How To Use
# 1) Put this script to Desktop
# 2) Run `bash WWAN_Check.sh` 


PING_URL=google.com
PING_IP=8.8.8.8
TEST_LOG=$HOME/Desktop/Result.log
NOW=$(date +"%Y/%m/%d - %H:%M:%S")
FILE_URL=http://ipv4.download.thinkbroadband.com/20MB.zip   
FILE_NAME=20MB.zip   
FILE_SIZE=20971520   # 20971520 (for 20MB)    31457280(for 30MB)
CYCLE=~/count
red='\033[0;31m'
nc='\033[0m'


# Restrict user account
[[ $EUID == 0 ]] && echo -e "⚠️ Please run as non-root user.\n" && exit


# Create cron job to run script  (start time: 02:40)
RunScript() {
    echo "*/2 * * * * sleep 40 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron
}


# Create cron job to run script after reboot (start time: reboot + 30 sec)
RunScriptAfterReboot() {
    echo "@reboot sleep 30 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron
}


# Create cron job for S3 and resume (start time: 02:30)
RunS3() {
    sudo crontab -l > mycron 2> /dev/null
    grep -h "systemctl suspend" mycron 2> /dev/null
    if [[ $? != 0 ]]; then
        echo "*/2 * * * * sudo systemctl suspend && sudo rtcwake -m no -s 30" >> mycron 
        sudo crontab mycron
    fi
}

# Create cron job for Reboot  (start time: 02:00)
RunReboot() {
    sudo crontab -l > mycron 2> /dev/null
    grep -h "shutdown -r" mycron 2> /dev/null
    if [[ $? != 0 ]]; then
        echo "*/2 * * * * sudo shutdown -r now" >> mycron
        sudo crontab mycron
    fi
}

# Delete cron job
Clean() {
    rm -f $CYCLE
    crontab -r 2> /dev/null
    sudo crontab -r 2> /dev/null
    systemctl restart cron
	rm -f ~/$FILE_NAME 2> /dev/null
    # nmcli networking on
}


# Kill the previous instances of the script before running the same script
kill -9 $(pgrep -f ${BASH_SOURCE[0]} | grep -v $$) 2> /dev/null


########################################################################################


# Check if Fibocom WWAN driver (mtk_t7xx) loaded porperly - Added on 2024/01/17
[[ ! `sudo dmesg | grep mtk_t7xx | grep "Invalid device status 0x1"` ]] && echo "Dmesg check: [PASSED]" >> $TEST_LOG || echo -e "Dmesg check: ${red}[FAILED]${nc}" >> $TEST_LOG


# Check the presence of WWAN in Modem Mnagaer
[[ `mmcli -m any` ]] && echo "ModemManager check: [PASSED]" >> $TEST_LOG || echo -e "ModemManager check: ${red}[FAILED]${nc}" >> $TEST_LOG


# Check the presence of WWAN in IP command
[[ `ip a | grep 'wwan0'` ]] && echo "IP command check: [PASSED]" >> $TEST_LOG || echo -e "IP command check: ${red}[FAILED]${nc}" >> $TEST_LOG


# Get WWAN operational state and IP (Using ip command)
echo "HW state: $(ip a | grep wwan0: | cut -d " " -f9)" >> $TEST_LOG
# echo "IP: $(ip a | grep wwan0 -A 1| grep inet | cut -d " " -f6 | cut -d "/" -f1)" >>  $TEST_LOG


# Get WWAN AP status and IP (Using nmcli command)
AP_STATE=$(nmcli device show wwan0mbim0 | grep GENERAL.STATE | cut -d "(" -f2 | cut -d ")" -f1)
echo "AP: ${AP_STATE^}" >> $TEST_LOG
echo "IP: $(nmcli device show wwan0mbim0 | grep IP4.ADDRESS | cut -d " " -f26 | cut -d "/" -f1)" >>  $TEST_LOG


# Ping URL test
ping $PING_URL -c 10 | grep -w "0% packet loss" 
if [[ $? = 0 ]]; then
    echo "Ping URL: [PASSED]" >> $TEST_LOG 
else
    echo -e "Ping URL: ${red}[FAILED]${nc}" >> $TEST_LOG 
fi


# Download file test
rm -f ~/$FILE_NAME
wget $FILE_URL -P ~/
if [[ $(stat -c %s ~/$FILE_NAME 2> /dev/null) == "$FILE_SIZE" ]]; then
    echo "Download file: [PASSED]" >> $TEST_LOG
else
    echo -e "Download file: ${red}[FAILED]${nc}" >> $TEST_LOG
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
rm -f mycron


