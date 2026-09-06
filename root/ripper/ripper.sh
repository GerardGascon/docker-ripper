#!/bin/bash

RIPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/config/Ripper.log"

# Startup Info
printf "Starting Ripper. Optical Discs will be detected and ripped within 60 seconds.\n"

# Set default values for configuration options if not already set
: "${EJECTENABLED:=true}"
: "${STORAGE_CD:=/out/Ripper/CD}"
: "${STORAGE_DVD:=/out/Ripper/DVD}"
: "${STORAGE_BD:=/out/Ripper/BluRay}"
: "${DRIVE:=/dev/sr0}"
: "${BAD_THRESHOLD:=5}"
: "${DEBUG:=false}"
: "${SEPARATERAWFINISH:=false}"
: "${TIMESTAMPPREFIX:=false}"
: "${MINIMUMLENGTH:=600}"
: "${FILEUSER:=nobody}"
: "${FILEGROUP:=users}"
: "${FILEMODE:=g+rw}"
# Print the values of configuration options if DEBUG is enabled
if [[ "$DEBUG" == true ]]; then
   printf "SEPARATERAWFINISH: %s\n" "$SEPARATERAWFINISH"
   printf "EJECTENABLED: %s\n" "$EJECTENABLED"
   printf "TIMESTAMPPREFIX: %s\n" "$TIMESTAMPPREFIX"
   printf "STORAGE_CD: %s\n" "$STORAGE_CD"
   printf "STORAGE_DVD: %s\n" "$STORAGE_DVD"
   printf "STORAGE_BD: %s\n" "$STORAGE_BD"
   printf "DRIVE: %s\n" "$DRIVE"
   printf "BAD_THRESHOLD: %s\n" "$BAD_THRESHOLD"
   printf "DEBUG: %s\n" "$DEBUG"
   printf "MINIMUMLENGTH: %s\n" "$MINIMUMLENGTH"
   printf "FILEUSER: %s\n" "$FILEUSER"
   printf "FILEGROUP: %s\n" "$FILEGROUP"
   printf "FILEMODE: %s\n" "$FILEMODE"
fi

BAD_RESPONSE=0
DISC_TYPE=""
# Define the drive types and patterns to match against the output of makemkvcon
declare -A DRIVE_TYPE_PATTERNS=(
   [empty]='DRV:[0-9]+,0,999,0,"'
   [open]='DRV:[0-9]+,1,999,0,"'
   [loading]='DRV:[0-9]+,3,999,0,"'
   [bd1]='DRV:[0-9]+,2,999,12,"'
   [bd2]='DRV:[0-9]+,2,999,28,"'
   [dvd]='DRV:[0-9]+,2,999,1,"'
   [cd1]='DRV:[0-9]+,2,999,0,"'
   [cd2]='","","'$DRIVE'"'
)

get_disc_directory() {
   local storage_root="$1"
   local disc_label="$2"
   local timestamp_prefix="$3"
   local disc_directory=""

   if [[ "$timestamp_prefix" == "true" ]]; then
      disc_directory="${storage_root}/$(date "+%Y%m%d_%H%M%S")_${disc_label}"
   else
      disc_directory="${storage_root}/${disc_label}"
   fi

   echo "$disc_directory"
}

cleanup_tmp_files() {
    rm -f /tmp/*.tmp 2>/dev/null
}

check_disc() {
   INFO=$(timeout 30s makemkvcon -r --cache=1 info disc:9999 | grep DRV:.*$DRIVE)
   printf "INFO: $INFO"
   DISC_TYPE="" # Clear previous disc type value

   for TYPE in "${!DRIVE_TYPE_PATTERNS[@]}"; do
      PATTERN=${DRIVE_TYPE_PATTERNS[$TYPE]}
      if echo "$INFO" | grep -E -q "$PATTERN"; then
         DISC_TYPE=$TYPE
         printf "Detected disc type: $DISC_TYPE"
         break
      fi
   done

   # If MakeMKV reports empty, double-check with cdparanoia for audio CDs
   if [[ "$DISC_TYPE" == "empty" ]]; then
      if cdparanoia -d "$DRIVE" -Q 2>&1 | grep -q "audio tracks"; then
         DISC_TYPE="cd1"
         printf "Audio CD detected via cdparanoia fallback.\n"
      fi
   fi

   if [[ -z "$DISC_TYPE" ]]; then
      printf "Unexpected makemkvcon output: %s\n" "$INFO"
      ((BAD_RESPONSE++))
   else
      BAD_RESPONSE=0
   fi
}

handle_bd_disc() {
   local disc_info="$1"
   printf "Handling BluRay disc."
   local disc_label="$(echo "$disc_info" | grep -o -P '(?<=",").*(?=",")')"
   local bd_path
   bd_path=$(get_disc_directory "$STORAGE_BD" "$disc_label" "$TIMESTAMPPREFIX")
   local disc_number="$(echo "$disc_info" | grep "$DRIVE" | cut -c5)"
   printf "Disc label: $disc_label, Disc number: $disc_number, BD path: $bd_path"
   mkdir -p "$bd_path"

   local alt_rip="${RIPPER_DIR}/BLURAYrip.sh"
   if [[ -f $alt_rip && -x $alt_rip ]]; then
      printf "BluRay detected: Executing %s\n" "$alt_rip"
      "$alt_rip" "$disc_number" "$bd_path" "$LOGFILE"
   else
      printf "BluRay detected: Saving MKV\n"
      makemkvcon --profile=/config/default.mmcp.xml -r --decrypt --minlength="$MINIMUMLENGTH" mkv disc:"$disc_number" all "$bd_path" >>"$LOGFILE" 2>&1
   fi

   move_to_finished "$bd_path" "$STORAGE_BD"
}

handle_dvd_disc() {
   local disc_info="$1"
   printf "Handling DVD disc.\n"
   local disc_label="$(echo "$disc_info" | grep -o -P '(?<=",").*(?=",")')"
   local dvd_path
   dvd_path=$(get_disc_directory "$STORAGE_DVD" "$disc_label" "$TIMESTAMPPREFIX")
   local disc_number="$(echo "$disc_info" | grep "$DRIVE" | cut -c5)"
   printf "Disc label: $disc_label, Disc number: $disc_number, DVD path: $dvd_path"
   mkdir -p "$dvd_path"

   local alt_rip="${RIPPER_DIR}/DVDrip.sh"
   if [[ -f $alt_rip && -x $alt_rip ]]; then
      printf "DVD detected: Executing %s\n" "$alt_rip"
      "$alt_rip" "$disc_number" "$dvd_path" "$LOGFILE"
   else
      printf "DVD detected: Saving MKV\n"
      makemkvcon --profile=/config/default.mmcp.xml -r --decrypt --minlength="$MINIMUMLENGTH" mkv disc:"$disc_number" all "$dvd_path" >>"$LOGFILE" 2>&1
   fi

   move_to_finished "$dvd_path" "$STORAGE_DVD"
}

handle_cd_disc() {
   local disc_info="$1"
   local alt_rip="${RIPPER_DIR}/CDrip.sh"
   if [[ -f $alt_rip && -x $alt_rip ]]; then
      printf "CD detected: Executing %s\n" "$alt_rip"
      "$alt_rip" "$DRIVE" "$STORAGE_CD" "$LOGFILE"
   else
      printf "CD detected: Saving FLAC\n"
      /usr/bin/abcde -d "$DRIVE" -c /ripper/abcde.conf -N -x -l >>"$LOGFILE" 2>&1
   fi
   printf "Completed CD rip.\n"
   chown -R "$FILEUSER":"$FILEGROUP" "$STORAGE_CD" && chmod -R "$FILEMODE" "$STORAGE_CD"
}

move_to_finished() {
   local src_path="$1"
   local dst_root="$2"
   if [ "$SEPARATERAWFINISH" = 'true' ]; then
      local finish_path="${dst_root}/finished/"
      mkdir -p "$finish_path"
      local base_name=$(basename "$src_path")
      finish_path+="$base_name"
      printf "Moving ${src_path} to finished directory: ${finish_path}\n"
      mv -v "$src_path" "$finish_path"
      chown -R "$FILEUSER":"$FILEGROUP" "$dst_root" && chmod -R "$FILEMODE" "$dst_root"
      printf "Moved $src_path to $finish_path\n"
   else
      printf "SEPARATERAWFINISH is disabled, not moving $src_path\n"
      chown -R "$FILEUSER":"$FILEGROUP" "$src_path" && chmod -R "$FILEMODE" "$src_path"
      printf "Changed owner and permissions for: $src_path\n"
   fi
}

ejectdisc() {
   if [[ "$EJECTENABLED" == "true" ]]; then
      if eject -v "$DRIVE" &>/dev/null; then
         printf "Ejecting disc Succeeded\n"
      else
         printf "Ejecting disc Failed. Attempting Alternative Method.\n"
         sleep 2
         sdparm --command=unlock "$DRIVE"
         sleep 1
         sdparm --command=eject "$DRIVE"
      fi
   else
      printf "It is now safe to eject.\n"
      printf "Ejecting is disabled, waiting for manual eject.\n"
      while true; do
         check_disc
         if [[ "$DISC_TYPE" == "open" || "$DISC_TYPE" == "empty" ]]; then
            break
         fi
         printf "Disc still present or drive not open; rechecking in 5 seconds.\n"
         sleep 5
      done
   fi
}

process_disc_type() {
   case "$DISC_TYPE" in
   "empty")
      printf "No disc inserted.\n"
      ;;
   "open")
      printf "Disc tray open.\n"
      ;;
   "loading")
      printf "Disc loading.\n"
      ;;
   "bd1" | "bd2")
      handle_bd_disc "$INFO"
      ;;
   "dvd")
      handle_dvd_disc "$INFO"
      ;;
   "cd1" | "cd2")
      handle_cd_disc "$INFO"
      ;;
   *)
      printf "Disc type '%s' not recognized.\n" "$DISC_TYPE"
      ;;
   esac
}

launcher_function() {
   while true; do
      cleanup_tmp_files
      check_disc
      case "$DISC_TYPE" in
      "empty")
         printf "No disc inserted, checking again in 1 minute.\n"
         ;;
      "open")
         printf "Disc tray open, checking again in 1 minute.\n"
         ;;
      "loading")
         printf "Disc loading, checking again in 1 minute.\n"
         ;;
      *)
         if [ "$BAD_RESPONSE" -lt "$BAD_THRESHOLD" ]; then
            process_disc_type
            ejectdisc
         else
            printf "Too many bad responses, checking stopped.\n"
            debug_log "Too many bad responses, checking stopped."
            ejectdisc
            exit 1
         fi
         ;;
      esac
      sleep 1m # Wait 1 minute before checking for a new disc
   done
}

launcher_function
