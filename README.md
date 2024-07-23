# A tool to validate WWAN or WLAN function with power transitions


### How To Use
+ Put this script to $HOME/Desktop
+ Run `./WWAN_Check.sh` 
+ Run `cat Result.log` to check if the initial result of cycle #0 is good
+ Select suspend or reboot stress test to run
+ To stop the trace, turn off WWAN and select 'Clean' from the options

### Test cases included
+ #1 - check if device driver is loaded properly in dmesg
+ #2 - check the presence of WWAN in IP command
+ #3 - check the presence of WWAN in Modem Manager
+ #4 - check cellular network connection state in Network Manager
+ #5 - check IP address in Network Manager
+ #6 - get signal quality from Modem Manager
+ #7 - ping test
+ #8 - download file test
