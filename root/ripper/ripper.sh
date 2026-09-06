#!/bin/bash

RIPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/config/Ripper.log"

# Startup Info
printf "Starting Ripper. Optical Discs will be detected and ripped.\n"

# Set default values for configuration options if not already set
: "${EJECTENABLED:=true}"
: "${STORAGE_CD:=/out/Ripper/CD}"
: "${DRIVE:=/dev/sr0}"
: "${BAD_THRESHOLD:=5}"
: "${DEBUG:=false}"
: "${SEPARATERAWFINISH:=false}"
: "${TIMESTAMPPREFIX:=false}"
: "${FILEUSER:=nobody}"
: "${FILEGROUP:=users}"
: "${FILEMODE:=g+rw}"
# Print the values of configuration options if DEBUG is enabled
if [[ "$DEBUG" == true ]]; then
   printf "SEPARATERAWFINISH: %s\n" "$SEPARATERAWFINISH"
   printf "EJECTENABLED: %s\n" "$EJECTENABLED"
   printf "TIMESTAMPPREFIX: %s\n" "$TIMESTAMPPREFIX"
   printf "STORAGE_CD: %s\n" "$STORAGE_CD"
   printf "DRIVE: %s\n" "$DRIVE"
   printf "BAD_THRESHOLD: %s\n" "$BAD_THRESHOLD"
   printf "DEBUG: %s\n" "$DEBUG"
   printf "FILEUSER: %s\n" "$FILEUSER"
   printf "FILEGROUP: %s\n" "$FILEGROUP"
   printf "FILEMODE: %s\n" "$FILEMODE"
fi

BAD_RESPONSE=0
DISC_TYPE=""

cleanup_tmp_files() {
    rm -f /tmp/*.tmp 2>/dev/null
}

check_disc() {
   local cd_output
   cd_output=$(timeout 30s cdparanoia -d "$DRIVE" -Q 2>&1)
   local rc=$?

   if [[ "$rc" -eq 0 ]] && printf '%s\n' "$cd_output" | grep -q "audio tracks"; then
      DISC_TYPE="cd"
      BAD_RESPONSE=0
      return
   fi

   # No audio CD detected. Check whether the tray is open.
   if eject -q "$DRIVE" 2>/dev/null; then
      DISC_TYPE="empty"
      BAD_RESPONSE=0
      return
   fi

   # If cdparanoia failed, don't immediately count it as a bad response.
   # Optical drives can take a few seconds to settle after insertion.
   if [[ "$rc" -eq 2 ]] || printf '%s\n' "$cd_output" | grep -qiE "no cd|no disc|not an audio"; then
      DISC_TYPE="empty"
      BAD_RESPONSE=0
      return
   fi

   printf "Unable to determine drive state.\n"
   printf "cdparanoia output: %s\n" "$cd_output"
   ((BAD_RESPONSE++)
}

handle_cd_disc() {
   printf "Audio CD detected: Ripping to FLAC.\n"

   mkdir -p "$STORAGE_CD"

   /usr/bin/abcde \
      -d "$DRIVE" \
      -c /ripper/abcde.conf \
      -N \
      -x \
      -l \
      >>"$LOGFILE" 2>&1

   local rc=$?

   if [[ "$rc" -eq 0 ]]; then
      printf "Completed CD rip successfully.\n"

      chown -R "$FILEUSER":"$FILEGROUP" "$STORAGE_CD"
      chmod -R "$FILEMODE" "$STORAGE_CD"
   else
      printf "CD rip failed with exit code %d.\n" "$rc"
   fi

   return "$rc"
}

ejectdisc() {
   if [[ "$EJECTENABLED" == "true" ]]; then
      if eject -v "$DRIVE" &>/dev/null; then
         printf "Ejecting disc succeeded.\n"
      else
         printf "Ejecting disc failed. Attempting alternative method.\n"
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

         if [[ "$DISC_TYPE" == "empty" ]]; then
             break
         fi

         printf "Disc still present; rechecking in 5 seconds.\n"
         sleep 5
      done
   fi
}

launcher_function() {
   while true; do
      cleanup_tmp_files
      check_disc

      case "$DISC_TYPE" in
         "empty")
            ;;

         "cd")
            handle_cd_disc
            ejectdisc
            ;;

         "")
            printf "Unable to determine drive state. Bad response %d/%d.\n" \
                "$BAD_RESPONSE" "$BAD_THRESHOLD"

            if [[ "$BAD_RESPONSE" -ge "$BAD_THRESHOLD" ]]; then
               printf "Too many bad responses, checking stopped.\n"
               exit 1
            fi
            ;;

         *)
            printf "Disc type '%s' not recognized.\n" "$DISC_TYPE"
            ;;
      esac

      sleep 5
   done
}

launcher_function
