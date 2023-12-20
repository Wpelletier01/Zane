#!/bin/bash 
# auteur: William Pelletier


# import 
source /opt/h34_projet/src/utils.sh

#######################################
# affiche le message d'aide.
#
#######################################
function helper() {

  echo "
    logger.sh [OPTION] message
      
    OPTION:
    -t        tye de log, D(debug) | I(info)| W(warn) | E(error) | F(fatal)
  "
  exit 0;
  
}


# COLOR
GREEN="\e[32m"
BLUE="\e[36m"
RED="\e[31m"
YELLOW="\e[33m"
DEFAULT="\e[39m"

log_type=""
print_to_screen=false


# verification de depart 
if [ -z "${ZANE_LOG}" ]; then
  echo -e  "${RED}Variable d'environement non initialiser, vous devez l'initialiser 
avant de pouvoir executer le sript${DEFAULT}"
  
  exit 1;
fi


# valide si aucun parametre/caractere sont passer
if [[ ${#} -eq 0 ]]; then
  helper
fi

while getopts "t:p:i" OPTION; do 
  
  case "${OPTION}" in
    t) # definition du type de log 
      case "${OPTARG}" in
        D)
          log_type="${BLUE}DEBUG${DEFAULT}"
          ;;
        I)
          log_type="${GREEN}INFO${DEFAULT}"
          ;;
        W)
          log_type="${YELLOW}WARN${DEFAULT}"
          ;;
        E)
          log_type="${RED}ERROR${DEFAULT}"
          ;;
        F)
          log_type="${RED}FATAL${DEFAULT}"
          ;;
        *)
          echo -e "${RED}Invalide type de log${DEFAULT}"
          helper 
          ;;
      esac
      ;;
    

    *)
      helper 
      ;;

  esac 
done

# nous permet de capturer tout se que getopts n'a pas toucher 
shift "$((OPTIND-1))"
message="$@"

# s'assure qu'un message a ete entrer
if [ -z "${message}" ]; then
  echo -e "${RED}Vous devez entrer un message${DEFAULT}"
  exit 1;
fi

# s'assure qu'un type de log a ete specifier 
if [ -z $log_type ]; then
  echo -e "${RED}Le type de log doit etre specifier"
  exit 1;
fi

# se qui sera dans son fichier log respectif et peut-etre, affiche au terminal
log="[$(date +"%H:%M:%S")] [${log_type}] $message"

# affiche au terminal si active
if [ $ZANE_DEBUG -eq 0 ]; then
  echo -e $log
fi

if [ $ZANE_TEST -eq 0 ]; then
  echo echo -e $log >> "$ZANE_LOG/test_$(date +'%d-%m-%g').log" 
else
  # envoie le log au fichier qui corespond a sa journe
  echo -e $log >> "$ZANE_LOG/exec_$(date +'%d-%m-%g').log"
fi 
