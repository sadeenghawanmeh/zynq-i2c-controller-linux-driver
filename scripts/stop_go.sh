#!/bin/bash

echo " I2C Expander Stop-Go Test "

echo out > /sys/kernel/i2c_expander/pin0/dir
echo out > /sys/kernel/i2c_expander/pin1/dir
echo in > /sys/kernel/i2c_expander/pin2/dir

echo on > /sys/kernel/i2c_expander/pin2/pullup

LED_A="/sys/kernel/i2c_expander/pin0/data"
LED_B="/sys/kernel/i2c_expander/pin1/data"
PB="/sys/kernel/i2c_expander/pin2/data"

PB_PREV=1        # PB 1-pulled-up
state=0       

while true
do
        PB_NOW=$(cat $PB)
        if [ "$PB_PREV" =  "high" ] && [ "$PB_NOW" = "low" ]; then
		if [ $state -eq 0 ]; then

	                echo low > $LED_A   # LED A OFF
               		echo high > $LED_B   # LED B ON
			state=1
		else       
               	 	echo high > $LED_A   # LED A ON
                	echo low > $LED_B   # LED B OFF
			state=0
        	fi
        	sleep 0.05
	fi
	PB_PREV=$PB_NOW
	sleep 0.01
done
