#!/bin/bash
# Cloudflare Auto Under Attack Mode = CF Auto UAM
# version 0.9beta

# Security Level Enums
SL_OFF=0
SL_ESSENTIALLY_OFF=1
SL_LOW=2
SL_MEDIUM=3
SL_HIGH=4
SL_UNDER_ATTACK=5

SL_OFF_S="off"
SL_ESSENTIALLY_OFF_S="essentially_off"
SL_LOW_S="low"
SL_MEDIUM_S="medium"
SL_HIGH_S="high"
SL_UNDER_ATTACK_S="under_attack"

#config
debug_mode=1 # 1 = true, 0 = false
install_parent_path="/home"
cf_email=""
cf_apikey=""
cf_zoneid=""
upper_cpu_limit=10 # 10 = 10% load, 20 = 20% load.  Total load, taking into account # of cores
lower_cpu_limit=5
regular_status=$SL_HIGH
regular_status_s=$SL_HIGH_S
time_limit_before_revert=$((60 * 10)) # 10 minutes by default
#end config

# Functions

install() {
  mkdir $install_parent_path"/cfautouam"

  cat >$install_parent_path"/cfautouam/cfautouam.service" <<EOF
[Unit]
Description=Enable Cloudflare Under Attack Mode under high load
[Service]
ExecStart=$install_parent_path/cfautouam/cfautouam.sh
EOF

  cat >$install_parent_path"/cfautouam/cfautouam.timer" <<EOF
[Unit]
Description=Enable Cloudflare Under Attack Mode under high load
[Timer]
OnBootSec=60
OnUnitActiveSec=7
AccuracySec=1
[Install]
WantedBy=timers.target
EOF

  chmod +x $install_parent_path"/cfautouam/cfautouam.service"
  systemctl enable $install_parent_path"/cfautouam/cfautouam.timer"
  systemctl enable $install_parent_path"/cfautouam/cfautouam.service"
  systemctl start cfautouam.timer
  exit
}

uninstall() {
  systemctl stop cfautouam.timer
  systemctl stop cfautouam.service
  systemctl disable cfautouam.timer
  systemctl disable cfautouam.service
  rm -R $install_parent_path"/cfautouam"
  exit
}

disable_uam() {
  curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$cf_zoneid/settings/security_level" \
    -H "X-Auth-Email: $cf_email" \
    -H "X-Auth-Key: $cf_apikey" \
    -H "Content-Type: application/json" \
    --data "{\"value\":\"$regular_status_s\"}" &>/dev/null

  # log time
  date +%s >$install_parent_path"/cfautouam/uamdisabledtime"

  echo "$(date) - cfautouam - CPU Load: $curr_load - Disabled UAM" >>$install_parent_path"/cfautouam/cfautouam.log"
}

enable_uam() {
  curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$cf_zoneid/settings/security_level" \
    -H "X-Auth-Email: $cf_email" \
    -H "X-Auth-Key: $cf_apikey" \
    -H "Content-Type: application/json" \
    --data '{"value":"under_attack"}' &>/dev/null

  # log time
  date +%s >$install_parent_path"/cfautouam/uamenabledtime"

  echo "$(date) - cfautouam - CPU Load: $curr_load - Enabled UAM" >>$install_parent_path"/cfautouam/cfautouam.log"
}

get_current_load() {
  numcores=$(grep -c 'model name' /proc/cpuinfo)
  currload=$(uptime | awk -F'average:' '{ print $2 }' | awk '{print $1}' | sed 's/,/ /')
  currload=$(bc <<<"scale=2; $currload / $numcores * 100")
  currload=${currload%.*}
  return $currload
}

get_security_level() {
  curl -X GET "https://api.cloudflare.com/client/v4/zones/$cf_zoneid/settings/security_level" \
    -H "X-Auth-Email: $cf_email" \
    -H "X-Auth-Key: $cf_apikey" \
    -H "Content-Type: application/json" 2>/dev/null |
    awk -F":" '{ print $4 }' | awk -F',' '{ print $1 }' | tr -d '"' >$install_parent_path"/cfautouam/cfstatus"

  security_level=$(cat $install_parent_path"/cfautouam/cfstatus")

  case $security_level in
  "off")
    return $SL_OFF
    ;;
  "essentially_off")
    return $SL_ESSENTIALLY_OFF
    ;;
  "low")
    return $SL_LOW
    ;;
  "medium")
    return $SL_MEDIUM
    ;;
  "high")
    return $SL_HIGH
    ;;
  "under_attack")
    return $SL_UNDER_ATTACK
    ;;
  *)
    return 100 # error
    ;;
  esac
}

main() {
  # Get current protection level & load
  get_security_level
  curr_security_level=$?
  get_current_load
  curr_load=$?

  if [ $debug_mode == 1 ]; then
    #curr_load=5
    time_limit_before_revert=30
  fi

  # If UAM was recently enabled

  if [[ $curr_security_level == "$SL_UNDER_ATTACK" ]]; then
    uam_enabled_time=$(<uamenabledtime)
    currenttime=$(date +%s)
    timediff=$((currenttime - uam_enabled_time))

    # If time limit has passed
    if [[ $timediff -gt $time_limit_before_revert ]]; then

      # If time limit has passed & cpu limit has normalized
      if [[ $curr_load -lt $upper_cpu_limit ]]; then
        if [ $debug_mode == 1 ]; then
          echo "$(date) - cfautouam - CPU Load: $curr_load - CPU Below threshhold, time limit has passed" >>$install_parent_path"/cfautouam/cfautouam.log"
        fi
        disable_uam
      else
        if [ $debug_mode == 1 ]; then
          echo "$(date) - cfautouam - CPU Load: $curr_load - CPU Above threshhold, time limit has passed - do nothing" >>$install_parent_path"/cfautouam/cfautouam.log"
        fi
      fi

    else
      if [ $debug_mode == 1 ]; then
        echo "$(date) - cfautouam - CPU Load: $curr_load - UAM already set, waiting out time limit" >>$install_parent_path"/cfautouam/cfautouam.log"
      fi
    fi
    exit
  fi

  # Enable and Disable UAM based on load

  #if load is higher than limit
  if [[ $curr_load -gt $upper_cpu_limit && $curr_security_level == "$regular_status" ]]; then
    enable_uam
  #else if load is lower than limit
  elif [[ $curr_load -lt $lower_cpu_limit && $curr_security_level == "$SL_UNDER_ATTACK" ]]; then
    disable_uam
  else
    if [ $debug_mode == 1 ]; then
      echo "$(date) - cfautouam - CPU Load: $curr_load - no change necessary" >>$install_parent_path"/cfautouam/cfautouam.log"
    fi
  fi
}

# End Functions

# Main

if [ "$1" = '-install' ]; then
  install
  exit
elif [ "$1" = '-uninstall' ]; then
  uninstall
  exit
elif [ "$1" = '-disable_script' ]; then
  systemctl disable cfautouam.timer
  systemctl disable cfautouam.service
  echo "$(date) - cfautouam - Script Manually Disabled" >>$install_parent_path"/cfautouam/cfautouam.log"
  disable_uam
  rm  $install_parent_path"/cfautouam/uamdisabledtime"
  rm  $install_parent_path"/cfautouam/uamenabledtime"
  exit
elif [ "$1" = '-enable_script' ]; then
  systemctl enable $install_parent_path"/cfautouam/cfautouam.timer"
  systemctl enable $install_parent_path"/cfautouam/cfautouam.service"
  systemctl start cfautouam.timer
  echo "$(date) - cfautouam - Script Manually Enabled" >>$install_parent_path"/cfautouam/cfautouam.log"
  exit
elif [ "$1" = '-enable_uam' ]; then
  echo "$(date) - cfautouam - UAM Manually Enabled" >>$install_parent_path"/cfautouam/cfautouam.log"
  enable_uam
  exit
elif [ "$1" = '-disable_uam' ]; then
  echo "$(date) - cfautouam - UAM Manually Disabled" >>$install_parent_path"/cfautouam/cfautouam.log"
  disable_uam
exit
elif [ -z "$1" ]; then
  main
  exit
else
  echo "cfautouam - Invalid argument"
  exit
fi
