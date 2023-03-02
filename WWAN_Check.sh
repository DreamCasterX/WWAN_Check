#!/usr/bin/env bash


# CREATOR: Mike Lu
# CHANGE DATE: 2023/3/1


URL=google.com
TEST_LOG=$HOME/Desktop/Result.log
NOW=$(date +"%Y/%m/%d - %H:%M:%S")
FILE_20MB=https://files.testfile.org/PDF%2F20MB-TESTFILE.ORG.pdf
FILE_SIZE=21408647
CYCLE=~/count


# Create cron job to run script  (start time: 02:40)
RunScript() {
    echo "*/2 * * * * sleep 40 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron
}


# Create cron job to run script after reboot (start time: reboot + 00:30)
RunScriptAfterReboot() {
    echo "@reboot sleep 30 && bash $HOME/Desktop/WWAN_Check.sh" >> mycron
    crontab mycron
}


# Create cron job for S3 and resume (start time: S3=02:00  resume=00:30)
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
}


####################################################################################


# Get WWAN connecntion status and IP
# echo "HW interface state: $(ip a | grep wwan0: | cut -d " " -f3 | cut -d "," -f3)" >> $TEST_LOG 
echo "State: $(ip a | grep wwan0: | cut -d " " -f9)" >> $TEST_LOG     
echo "IP: $(ip a | grep wwan0 -A 1| grep inet | cut -d " " -f6 | cut -d "/" -f1)" >>  $TEST_LOG  


# Ping URL test
ping $URL -c 10 | grep -w "0% packet loss" 
if [[ $? = 0 ]]; then
    echo "Ping URL: [PASSED]" >> $TEST_LOG 
else
    echo "Ping URL: [!!! FAILED !!!]" >> $TEST_LOG 
fi


# Download file test
rm -f ~/*TESTFILE.ORG.pdf
wget $FILE_20MB -P ~/
if [[ $(stat -c %s ~/*TESTFILE.ORG.pdf 2> /dev/null) == "$FILE_SIZE" ]]; then
    echo "Download file: [PASSED]" >> $TEST_LOG
else
    echo "Download file: [!!! FAILED !!!]" >> $TEST_LOG
fi
rm -f ~/*TESTFILE.ORG.pdf


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
        if [[ $POWER_STATE != [SsRrCc] ]]; then
          echo -e "\nWrong input!"
        fi
fi
rm -f mycron


