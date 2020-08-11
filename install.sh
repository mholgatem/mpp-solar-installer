#!/bin/bash
#get device data
#lsusb
#lsusb -D /dev/bus/usb/<bus#>/<device#>
#ex - lsusb -D /dev/bus/usb/001/002

#get script path
SCRIPT=$(readlink -f $0)
SCRIPTPATH=`dirname $SCRIPT`
cd $SCRIPTPATH

# read flags into array
flag_delimiter=":"
IFS=$':' read -r -a flags < <(echo "${*/'--'/':'}")
flags=( "${flags[@]/%/':'}" )
flags=( "${flags[@]/#/':'}" )
flags=( "${flags[@]//' :'/':'}" )

#set constants
IP="$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')"
NONE='\033[00m'
CYAN='\033[36m'
FUSCHIA='\033[35m'
UNDERLINE='\033[4m'

# run this section with un-elevated privileges
if [[ "${flags[@]}" =~ ":FINISH:" ]]; then

    echo
    echo
    echo -e "Do you want the mpp-solar utility to ${FUSCHIA}auto-run on startup?${NONE}"
    select mpp_choice in "Yes" "No"; do
        case $mpp_choice in
            Yes ) systemctl --user enable mpp-solar
                  sudo loginctl enable-linger $USER
                  break;;
            No )  break;;
        esac
    done

    clear
    echo -e "You can view information about starting/stopping the mpp-solar service at"
    echo -e "${CYAN}${UNDERLINE}https://github.com/jblance/mpp-solar/blob/master/daemon/README.md${NONE}"

    echo
    echo
    echo "Setup is now complete. Your system needs to restart for all changes to take affect."
    echo "After reboot, type your IP address into a web browser to access Grafana"
    echo -e "                         ${CYAN}$IP:3000${NONE}"
    echo -e "                       ${FUSCHIA}Login: admin${NONE}"
    echo -e "                    ${FUSCHIA}password: admin${NONE}"

    echo
    echo -e "${UNDERLINE}Would you like to restart now?${NONE}"
    select reboot_choice in "Yes" "No"; do
        case $reboot_choice in
            Yes ) sudo reboot
                  break;;
            No )  break;;
        esac
    done
    
    exit 1

fi

#if not root user, restart script as root
if [ "$(whoami)" != "root" ]; then
	echo "Getting root permissions..."
	sudo bash $SCRIPT $* && bash $SCRIPT --FINISH
	exit 0
fi

# Add influx & grafana repos
if dpkg --get-selections | grep -E "^influxdb.*install$" >/dev/null; then 
    echo "influx already installed"; 
else
    echo "Adding influx repos..."
    wget -qO- https://repos.influxdata.com/influxdb.key | sudo apt-key add -
    source /etc/os-release
    echo "deb https://repos.influxdata.com/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/influxdb.list
fi

if dpkg --get-selections | grep -E "^grafana.*install$" >/dev/null; then 
    echo "grafana already installed"; 
else
    echo "Adding grafana repos..."
    wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
    echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
fi

# update repos
if [[ "${flags[@]}" =~ ":noupdate:" ]]; then
    echo "Skipping update..."
else 
    echo "Updating repo lists..."
    apt update
fi

# make sure python3 is installed
apt install -y python3 python3-pip 

# get python requirements
echo "Installing python requirements..."
pip3 install -r python-requirements.txt

# get fresh instance of mpp-solar
rm -r mpp-solar
git clone https://github.com/mholgatem/mpp-solar.git

# install mpp-solar
cd mpp-solar
python3 ./setup.py install
cd ..

# MQTT
install_mqtt () {
  echo
  echo
  echo -e "${CYAN}${UNDERLINE}### INSTALLING MQTT ###${NONE}"
  echo
  apt install -y mosquitto mosquitto-clients; 
}

# GRAFANA
install_grafana () {
    echo
	echo
    echo -e "Which ${FUSCHIA}GRAFANA PACKAGE${NONE} do you want to install?"
	echo -e "${CYAN}Hint:${NONE} grafana-rpi is built for ARMv6 using armhf (RPi zero/RPi first gen), use standard grafana for all other instances"
    select grafana_choice_2 in "grafana" "grafana-rpi"; do
        case $grafana_choice_2 in
            grafana ) echo
					  echo
					  echo -e "${CYAN}${UNDERLINE}### INSTALLING GRAFANA ###${NONE}"
					  echo
					  apt install -y grafana; 
					  break;;
            grafana-rpi ) echo
						  echo
						  echo -e "${CYAN}${UNDERLINE}### INSTALLING GRAFANA-RPI ###${NONE}"
						  echo
						  apt install -y grafana-rpi; 
						  break;;
        esac
    done
}

# INFLUX & TELEGRAF
install_influx (){
    echo
	echo
	echo -e "${CYAN}${UNDERLINE}### INSTALLING INFLUX ###${NONE}"
	echo
    apt install -y influxdb telegraf; 
    influx_config="/etc/influxdb/influxdb.conf"
    #find [http] then replace first occurance of # bind-address = ":8086" with "127.0.0.1:8086"
    sed -i '/[http]/,/#[ ]*bind-address = ":8086"/s/#[ ]*bind-address = ":8086"/bind-address = "127.0.0.1:8086"/' $influx_config
	
	telegraf_config="/etc/telegraf/telegraf.conf"
	sed -i 's/\[\[outputs.influxdb\]\]/#\[\[outputs.influxdb\]\]/' $telegraf_config
	
	telegraf_config="/etc/telegraf/telegraf.d/mqtt-input.conf"
	mv "$telegraf_config" "$telegraf_config.bak" 2>/dev/null
	echo "[[inputs.mqtt_consumer]]" >> $telegraf_config
    echo "  servers = [\"tcp://127.0.0.1:1883\"]" >> $telegraf_config
	echo "  topics = [\"#\",]" >> $telegraf_config
	echo "  data_format = \"influx\"" >> $telegraf_config
	
	echo
	echo
	echo -e "${UNDERLINE}Set a password for your database${NONE} (username will be grafana)"
	echo -e "${CYAN}Hint:${NONE} you can skip this step by leaving the password blank, but you will need to manually configure this later."
	pass1=1
    pass2=2
	while [[ $pass1 != $pass2 ]]; do
	    echo
	    echo "password:"
	    read -p "" pass1
	    echo "please re-enter password:"
	    read -p "" pass2
	    if [[ $pass1 != $pass2 ]]; then echo -e "${CYAN}Passwords do not match.${NONE}"; fi
	done
	echo -e "{$CYAN}ok${NONE}"
    
	if [[ "$pass1" != "" ]]; then
		telegraf_config="/etc/telegraf/telegraf.d/influx-output.conf"
		mv "$telegraf_config" "$telegraf_config.bak" 2>/dev/null
		echo "[[outputs.influxdb]]" >> $telegraf_config
		echo "  urls = [\"http://127.0.0.1:8086\"]" >> $telegraf_config
		echo "  database = \"mppsolar\"" >> $telegraf_config
		echo "  skip_database_creation = true" >> $telegraf_config
		echo "  username = \"grafana\"" >> $telegraf_config
		echo "  password = \"${pass1}\"" >> $telegraf_config
    else
	    echo -e "Skipping... You will need to manually create ${FUSCHIA}$telegraf_config${NONE}"
		echo -e "You will also need to execute the following commands:"
		echo -e "• influx -execute 'create database mppsolar'"
		echo -e "• influx -execute 'create user grafana with password \"<passwordhere>\" with all privileges'"
        echo -e "• influx -execute 'grant all privileges on mppsolar to grafana'"
	fi
}


enable_services () {
	echo
    echo
    echo -e "${CYAN}${UNDERLINE}### ENABLING SERVICES ###${NONE}"
    echo
	# INFLUX
    systemctl unmask influxdb.service;
    systemctl start influxdb;
    systemctl enable influxdb.service;
    influx -execute "create database mppsolar"
    influx -execute "create user grafana with password '${pass1}' with all privileges"
    influx -execute "grant all privileges on mppsolar to grafana"
	
	#TELEGRAF
	systemctl unmask telegraf.service;
	systemctl start telegraf;
	systemctl enable telegraf.service;
	
	# MQTT
	systemctl enable mosquitto.service;
    systemctl start mosquitto.service;
	
	# GRAFANA
	systemctl unmask grafana-server
    systemctl start grafana-server
    systemctl enable grafana-server
}

echo
echo
echo -e "Do you want to install the ${FUSCHIA}WEB SERVICES${NONE}?"
select web_services_choice in "Yes" "No"; do
    case $web_services_choice in
	    Yes ) install_mqtt
		      install_grafana
			  install_influx
			  enable_services
			  break;;
		No ) break;;
	esac
done
		    

if dpkg --get-selections | grep -E "^mosquitto.*install$" >/dev/null; then 
    echo
    echo
	echo -e "Do you want to ${FUSCHIA}test mqtt?${NONE}"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) echo -e "${CYAN}${UNDERLINE}Open a second terminal:${NONE} type ${FUSCHIA}mosquitto_sub -h localhost -v -t \"#\" ${NONE}";
	    	      echo -e "${CYAN}${UNDERLINE}In this terminal:${NONE} press ${FUSCHIA}Enter${NONE} to send a message or type ${FUSCHIA}exit${NONE} to continue ";  
		          while [ ! $msg ];do
                    read -p "" msg
                    if [ ! $msg ]; then 
				        mosquitto_pub -h localhost -t "Message Received:" -m "This is a TEST MESSAGE"
                        echo 'message sent'; 
                    fi
                  done 
                 break;;
            No ) break;;
        esac
    done
fi

### USER INVERTER CONFIGURATION ###

## MODEL
# convert file to unix line-endings
sed -i 's/\r$//' ./supported_inverter_models.txt
# read file into array
mapfile -t MODELS < ./supported_inverter_models.txt
echo
echo
echo -e "Select the number that corresponds to your ${FUSCHIA}INVERTER TYPE${NONE}"
select model in "${MODELS[@]}"; do
break;
done

## INVERTER COUNT
inverter_count=""
only_numbers="^[0-9]"
echo
echo
while [[ ! "$inverter_count" =~ $only_numbers ]]; do
    echo -e "${FUSCHIA}HOW MANY INVERTERS${NONE} do you have connected in parallel?"
    read inverter_count
done

## CONNECTION TYPE
echo
echo
echo -e "Select the number that corresponds to your ${FUSCHIA}USB CONNECTION TYPE${NONE}"
select connection in "Serial Adapter" "Direct USB"; do
    case $REPLY in
	  1 ) connection="serial"; break;;
	  2 ) connection="direct"; break;;
	esac
	break;
done

## DEFINE INVERTER

echo
echo
echo -e "${FUSCHIA}BEFORE CONTINUING${NONE} Make sure that your computer is connected to your inverter (serial or direct-usb)"
echo -e "Press ${FUSCHIA}ENTER${NONE} to continue"
read -p ""

# List usb devices
get_devices () {
  readarray -t DEVICES < <(lsusb)
  DEVICES=("REFRESH LIST" "${DEVICES[@]}" "SKIP STEP")
}

get_devices

#generate tmpfile file descriptor
tmpfile=$(mktemp)
exec 3> "$tmpfile"
exec 4< "$tmpfile"
rm "$tmpfile"

write_to_temp() {
>&3 cat <<EOS
${udev_rule}
EOS
}


usb_count=0
udev_file="/etc/udev/rules.d/10-mpp-solar.rules"
while true; do
  echo
  echo
  echo -e "Select the number that corresponds to ${FUSCHIA}INVERTER USB ${usb_count}${NONE}"
  echo -e "${CYAN}Hint:${NONE} devices will be numbered in "
  echo -e "${CYAN}Hint:${NONE} You will have the opportunity to select more devices"
  echo -e "${CYAN}Hint:${NONE} LV5048 = Cypress Semiconductor USB to Serial"
  #Display USB devices
  select usb_choice in "${DEVICES[@]}"; do
    if [ "$usb_choice" == "REFRESH LIST" ]; then
      get_devices; break;
    elif [ "$usb_choice" == "SKIP STEP" ]; then
      break 2 ;
    else
      # regex= 'alpha-num(x 4):alpha-num(x 4)'
      regex="[\S]{4}:[\S]{4}"
      readarray -t device < <(echo "${usb_choice}" | grep -P -o "${regex}" | grep -P -o "([^:]){4}")

      udev_rule="ACTION==\"add\", ATTRS{idVendor}==\"${device[0]}\", ATTRS{idProduct}==\"${device[1]}\", SYMLINK+=\"mppsolar/${connection}/${usb_count}\", MODE=\"0660\", GROUP=\"plugdev\""
      write_to_temp $udev_rule
      usb_count=$((usb_count + 1))
      
      echo
      echo
      echo -e "Do you want to add another device?"
      select continue_usb in "Yes" "No";do
        case $REPLY in
            1) break 2;;

            2)	  #avoid creating conflicting rules by emptying file first
                  if test -f "$udev_file"; then
                    mv "$udev_file" "$udev_file.bak" 2>/dev/null
                  fi
                  echo "$(cat <&4)" >> $udev_file
                  echo -e "Adding symlink rule to ${FUSCHIA}$udev_file${NONE}"
                  
                  break ;
            ;;
        esac
      done
      
      break 2;
    fi
  done
done

## CREATE CONFIG FILE

config_file="./$model.conf"
if test -f "$config_file"; then
    echo "config file already exists. Moving to $config_file.bak"
    mv "$config_file" "$config_file.bak" 2>/dev/null
fi
echo "[SETUP]
# Number of seconds to pause between command execution loop
# 0 is no pause, greater than 60 will cause service restarts
pause=5
mqtt_broker=localhost
" >> $config_file

# Set model parameters
case $model in
    LV5048 ) model_type="LV5048";is_parallel_model=true
	;;
	Voltronic-Axpert-MKS-5KVA ) model_type=="LV5048";is_parallel_model=true
	;;
	* ) model_type="standard";is_parallel_model=false
	;;
esac

# set default port
port_name="/dev/mppsolar/${connection}/0"
if [ "$usb_choice" == "SKIP STEP" ]; then
    case $connection in
	    serial ) port_name="/dev/ttyUSB0";break;;
		direct ) port_name="/dev/hidraw0";break;;
	esac
fi

## commands
echo
echo
echo -e "Enter the ${FUSCHIA}INVERTER COMMANDS${NONE} that you want to use"
echo -e "${CYAN}Hint:${NONE} you can supply mutiple comma separated commands"
echo -e "${CYAN}Hint:${NONE} replace inverter number with [I] (ex - QPGS0,QP2GS0 = QPGS[I],QP2GS[I])"
IFS=', ' read -p "command(s): " -r -a commands

# create entry for each of users inverters
for (( c=1; c<=$inverter_count; c++ )); do

    
    inverter_number=$[c-1]
    count=0;
    for command in ${commands[@]}; do
        (( count++ ))
        inverter_label="[Inverter_$[c]_L$[count]]"
        command=${command^^}
        command=${command//\[I\]/${inverter_number}}
        echo "$inverter_label
model=$model_type
port=$port_name
baud=2400
command=${command}
tag=Inverter$[c]
format=influx2
" >> $config_file
    done
done

echo
echo
echo -e "Generating config file... ${FUSCHIA}Done${NONE}"
msg="Would you like to ${FUSCHIA}EDIT THE CONFIG FILE${NONE} now?"
while [ ! $finished_editing ]; do
    echo -e "$msg"
    select edit_config in "Yes" "No"; do
        case $REPLY in
          1 ) sudo nano $config_file; 
              clear;
              msg="Would you like to make any more changes to the config file before proceeding?";
              break;;
          2 ) finished_editing=true; break;;
        esac
        break;
    done
done

echo
echo
echo -e "copying config file to ${FUSCHIA}/etc/mpp-solar/mpp-solar.conf${NONE}"
cp $config_file "/etc/mpp-solar/mpp-solar.conf"

exit 0
