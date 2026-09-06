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
: "${FILEUSER:=nobody}"
: "${FILEGROUP:=users}"
: "${FILEMODE:=g+rw}"

BAD_RESPONSE=0
DISC_TYPE=""

cleanup_tmp_files() {
    rm -f /tmp/*.tmp 2>/dev/null
}

check_disc() {
   local cd_output
   local rc

   cd_output=$(timeout 30s cdparanoia -d "$DRIVE" -Q 2>&1)
   rc=$?

   # Audio CD detected.
   if [[ "$rc" -eq 0 ]] && \
      printf '%s\n' "$cd_output" | grep -qi "audio tracks"; then
      DISC_TYPE="cd"
      BAD_RESPONSE=0
      return 0
   fi

   # No disc / no readable audio CD.
   # This is a normal idle state, not an error.
   if printf '%s\n' "$cd_output" | grep -qiE \
      'Unable to open disc|Unable to read table of contents|no audio CD|no disc'; then
      DISC_TYPE="empty"
      BAD_RESPONSE=0
      return 0
   fi

   # Anything else is an actual unexpected error.
   printf "Unable to determine drive state.\n"
   printf "cdparanoia output:\n%s\n" "$cd_output"

   ((BAD_RESPONSE++))
   return 1
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
