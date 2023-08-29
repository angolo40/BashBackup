#!/bin/bash

#===============================================================
# Initial checks
#===============================================================

# rsync must be installed
if [ -z "$(which rsync)" ]; then
    echo "Error: rsync is not installed"
    read -p "Press Enter to exit..."
    exit 1
fi

# Leggi le variabili dal file .config
config=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/$1

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
ENDCOLOR="\e[0m"

BACKUP_FREQ=("daily" "weekly" "monthly" "yearly")
TODAY=$(date +'%Y-%m-%d')
WEEKDAY=$(date +%u)
MONTH=$(date +%m)
MONTHDAY=$(date +%d)
YEAR=$(date +%Y)

function start_backup() {

  freq_backup_dir="$BACKUP_DIR/$freq/$TODAY"
  freq_log_file="/tmp/backup_${freq}_${TODAY}.log"

  case $B_TYPE in
    1)
      ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" mkdir -p "$freq_backup_dir"
      last_backup=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -d $BACKUP_DIR/$freq/* | tail -n1 | head -n 1")
      prev_backup=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -d $BACKUP_DIR/$freq/* | tail -n2 | head -n 1")
      oldest_backup=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -td $BACKUP_DIR/$freq/* | tail -n2 | head -n 1")
      count=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -l $BACKUP_DIR/$freq | grep '^d' | wc -l")
      ;;
    2|3)
      mkdir -p "$freq_backup_dir"
      last_backup=$("ls -d $BACKUP_DIR/$freq/* | tail -n1 | head -n 1")
      prev_backup=$("ls -d $BACKUP_DIR/$freq/* | tail -n2 | head -n 1")
      oldest_backup=$("ls -td $BACKUP_DIR/$freq/* | tail -n2 | head -n 1")
      count=$("ls -l $BACKUP_DIR/$freq | grep '^d' | wc -l")
      mkdir -p "$freq_backup_dir"
      ;;
    esac

  echo " "
  echo -e "${BLUE}Latest Backup Date: $last_backup ${ENDCOLOR}"
  echo -e "${BLUE}Prev Backup Date: $prev_backup ${ENDCOLOR}"
  echo -e "${BLUE}Oldest Backup Date: $oldest_backup ${ENDCOLOR}"
  echo " "

  while [ 1 ]
    do
      case $B_TYPE in
        1)
          # rsync local to remote via SSH
          rsync -avz --timeout=60 --partial --progress --link-dest="$prev_backup/$(basename "$dir")" --exclude=$EXCLUDE_DIR --log-file=$freq_log_file -e "ssh -i $SSH_PRIVATE_KEY" "$dir/" "$SSH_USER@$SSH_HOST:$freq_backup_dir/$(basename "$dir")"
          ;;
        2)
          # rsync remote to local via SSH
          if [ $USE_REMOTE_SUDO == "Y"  ]; then
            rsync -avz --timeout=60 --partial --progress --link-dest="$prev_backup/$(basename "$dir")" --exclude=$EXCLUDE_DIR --rsync-path="sudo rsync" --log-file=$freq_log_file -e "ssh -i $SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST:$dir/" "$freq_backup_dir/$(basename "$dir")"
          else
            rsync -avz --timeout=60 --partial --progress --link-dest="$prev_backup/$(basename "$dir")" --exclude=$EXCLUDE_DIR --log-file=$freq_log_file -e "ssh -i $SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST:$dir/" "$freq_backup_dir/$(basename "$dir")"
          fi
          ;;
        3)
          # Effettua il backup delle cartelle specificate utilizzando rsync prendendo i file di un server remoto e copiando in locale attraverso SSH
          rsync -avz --timeout=60 --partial --progress --link-dest="$prev_backup/$(basename "$dir")" --exclude=$EXCLUDE_DIR --log-file=$freq_log_file "$dir/" "$freq_backup_dir/$(basename "$dir")"
          ;;
        esac

      if [ "$?" = "0" ] ; then
        echo "Rsync completed"
        # Invia una mail con il risultato del backup
        BACKUP_STATUS="SUCCESS"
        mail -s $EMAIL_SUB -a "From: $FROM_EMAIL" $DEST_EMAIL < $freq_log_file
        rm -rf $freq_log_file
        break
      else
        echo "Rsync failure. Backing off and retrying..."
        sleep 90
      fi
  done

}

function clean_backup() {

  echo "Verifico vecchi backup......."
  freq_upper=${freq^^}
  Retention="R_$freq_upper"

  if [[ $count -gt $Retention ]]; then
    echo "Ci sono piu di $Retention backup. Avvio pulizia....."
    case $B_TYPE in
      1)
        case $R_TYPE in
          1)
            # Comprimi la cartella di backup
            ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" tar -cvf "$oldest_backup.tar" "$oldest_backup"
            # Rimuovi la cartella non compressa
            ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" rm -rf "$oldest_backup"
            ;;
          2)
            # Rimuovi la cartella non compressa
            ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" rm -rf "$oldest_backup"
            ;;
          esac
        ;;
      2|3)
        case $R_TYPE in
          1)
            # Comprimi la cartella di backup
            tar -cvf "$oldest_backup.tar" "$oldest_backup"
            # Rimuovi la cartella non compressa
            rm -rf "$oldest_backup"
            ;;
          2)
            # Rimuovi la cartella non compressa
            rm -rf "$oldest_backup"
            ;;
          esac
        ;;
      esac
  else
     echo "Ci sono $count cartelle, pulizia non necessaria"
  fi

}


# Start Backup Process
echo " "
echo -e "${RED}Start Backup Process: $TODAY - Weekday: $WEEKDAY ${ENDCOLOR}"
echo " "
    for freq in "${BACKUP_FREQ[@]}"; do
        for dir in "${SOURCE_DIRS[@]}"; do
            case $freq in

                "daily" )
                    echo -e "${RED} $freq backup of folder: $dir ${ENDCOLOR}"
                    ;;

                "weekly" )
                    if echo "${B_WEEKDAY[@]}" | grep -qw "$WEEKDAY"; then
                        echo -e "${RED} $freq backup of folder: $dir ${ENDCOLOR}"
                    else
                        echo "No $freq backup needed for $dir"
                        continue
                    fi
                    ;;

                "monthly" )
                    if echo "${B_MONTH[@]}" | grep -qw "$MONTH"; then
                        if echo "${B_MONTHDAY[@]}" | grep -qw "$MONTHDAY"; then
                            echo -e "${RED} $freq backup of folder: $dir ${ENDCOLOR}"
                        else
                            echo "No $freq backup needed for $dir"
                            continue
                        fi
                    else
                        echo "No $freq backup needed for $dir"
                        continue
                    fi
                    ;;

                "yearly" )
                    if echo "${B_YEAR[@]}" | grep -qw "$YEAR"; then
                      if echo "${B_MONTH[@]}" | grep -qw "$MONTH"; then
                        if echo "${B_MONTHDAY[@]}" | grep -qw "$MONTHDAY"; then
                            echo -e "${RED} $freq backup of folder: $dir ${ENDCOLOR}"
                        else
                          echo "No $freq backup needed for $dir"
                          continue
                        fi
                      else
                          echo "No $freq backup needed for $dir"
                          continue
                      fi
                    else
                        echo "No $freq backup needed for $dir"
                        continue
                    fi
                    ;;

                esac

                start_backup
                clean_backup

                echo " "
                echo -e "${RED}End Backup Process: $TODAY - Weekday: $WEEKDAY ${ENDCOLOR}"
                echo " "

        done
    done
