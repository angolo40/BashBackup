#!/bin/bash

# Leggi le variabili dal file .config
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/backup.config

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
      last_backup=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -td $BACKUP_DIR/$freq/* | head -n 1")
      prev_backup=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -trd $BACKUP_DIR/$freq/* | tail -2 | head -n 1")
      oldest_backup=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -trd $BACKUP_DIR/$freq/* | head -n 1")
      count=$(ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" "ls -l $BACKUP_DIR/$freq | grep '^d' | wc -l")
      ssh -i "$SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST" mkdir -p "$freq_backup_dir"
      ;;
    2|3)
      last_backup=$("ls -td $BACKUP_DIR/$freq/* | head -n 1")
      prev_backup=$("ls -trd $BACKUP_DIR/$freq/* | tail -2 | head -n 1")
      oldest_backup=$("ls -trd $BACKUP_DIR/$freq/* | head -n 1")
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
          # Effettua il backup delle cartelle specificate utilizzando rsync verso un server remoto attraverso SSH
          rsync -avz --timeout=60 --partial --progress --link-dest="$prev_backup/$(basename "$dir")" --exclude=$EXCLUDE_DIR --log-file=$freq_log_file -e "ssh -i $SSH_PRIVATE_KEY" "$dir/" "$SSH_USER@$SSH_HOST:$freq_backup_dir/$(basename "$dir")"
          ;;
        2)
          # Effettua il backup delle cartelle specificate utilizzando rsync prendendo i file di un server remoto e copiando in locale attraverso SSH
          rsync -avz --timeout=60 --partial --progress --link-dest="$prev_backup/$(basename "$dir")" --exclude=$EXCLUDE_DIR --log-file=$freq_log_file -e "ssh -i $SSH_PRIVATE_KEY" "$SSH_USER@$SSH_HOST:$dir/" "$freq_backup_dir/$(basename "$dir")"
          ;;
        3)
          # Effettua il backup delle cartelle specificate utilizzando rsync prendendo i file di un server remoto e copiando in locale attraverso SSH
          rsync -avz --timeout=60 --partial --progress --link-dest="$prev_backup/$(basename "$dir")" --exclude=$EXCLUDE_DIR --log-file=$freq_log_file "$dir/" "$freq_backup_dir/$(basename "$dir")"
          ;;
        esac

      if [ "$?" = "0" ] ; then
        echo "Rsync completed normally"
        # Invia una mail con il risultato del backup
        #echo "Message Body Here" | mutt -s "$freq_mail_subject" -a $freq_log_file $DEST_EMAIL
        mail -s "Backup [SUCCESS] [$SERVERNAME] [$freq] [$dir]" -a "From: $FROM_EMAIL" $DEST_EMAIL < $freq_log_file
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
                        echo "No weekly backup needed for $dir"
                        continue
                    fi
                    ;;

                "monthly" )
                    if echo "${B_MONTH[@]}" | grep -qw "$MONTH"; then
                        if echo "${B_MONTHDAY[@]}" | grep -qw "$MONTHDAY"; then
                            echo -e "${RED} $freq backup of folder: $dir ${ENDCOLOR}"
                        else
                            echo "No monthly backup needed for $dir"
                            continue
                        fi
                    else
                        echo "No monthly backup needed for $dir"
                        continue
                    fi
                    ;;

                "yearly" )
                    if [[ $YEAR != "01" ]]; then
                      echo "No yearly backup needed for $dir"
                      continue
                    fi
                    echo -e "${RED} $freq backup of folder: $dir ${ENDCOLOR}"
                    ;;

                esac

                start_backup
                clean_backup

                echo " "
                echo -e "${RED}End Backup Process: $TODAY - Weekday: $WEEKDAY ${ENDCOLOR}"
                echo " "


        done
    done
