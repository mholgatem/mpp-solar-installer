# mpp-solar-installer
A bash installer for the [jblance/mpp-solar](https://github.com/jblance/mpp-solar) project

## About
This project was created to automate and simplify the steps for setting up a fresh instance of mpp-solar. This also includes the option to install and initialize the web services (MQTT/Grafana/Influx/Telegraf) with very little input from the user. 

## Installation
```
sudo apt install git
git clone https://github.com/mholgatem/mpp-solar-installer.git
cd mpp-solar-installer
bash ./install.sh
```
***\*Note:** The bash command should be run without sudo*

## What To Expect
1) The installer will add references to required repositories
2) The system will be updated
3) required files will be installed (Python3, Python3-pip, etc.)
4) an up-to-date copy of mpp-solar will be cloned and installed
5) the user will be asked if they want to install the web services
    - If *YES*, the user will have the option to install each service individually
6) The user will now be asked several questions about their inverter setup
    - Inverter Model
    - Number of inverters
    - Connection type (serial/direct)
7) Select the Inverter USB('s) from a list of connected devices
8) Udev rules will be set up for consistent access to your devices
    - ex. instead of /dev/hidraw[0-9] → /dev/mppsolar/direct/0
    - ex. instead of /dev/ttyUSB[0-9] → /dev/mppsolar/serial/0
8) Input inverter commands to auto-generate the mpp-solar-service config file
9) Finally, make any changes to the config file, save + exit
10) Reboot & Enjoy!
