#!/bin/bash 
#
# Auteur: William Pelletier
#
#
# Tous l'information sur la copie ou l'envoie de fichier de config vers une machine Cisco
# par le protocole SNMP a été trouvé au lien quit suit:
# https://www.cisco.com/c/en/us/support/docs/ip/simple-network-management-protocol-snmp/15217-copy-configs-snmp.html
#
#
# Explication des arguments univer passé a tout les utilitaire de net-snmp utilisé dans le script:
#   -v3 =>  specifie la version 3 du protocole snmp
#   -O q => specifie que la commande retourne la réponse d'une facon 
#           quelle soit facile à faire le traitement de texte sur celle-ci.
#   -t 1 => timeout de 1 seconde
#   -r 1 => nombre d'essai
#   -u =>   utilisateur snmp créer dans la machine
#   -a =>   l'algorythme de hashage
#   -A =>   le mot de passe d'authentification 
#   -x =>   la méthode d'encryption
#   -X =>   le mot de passe de confidentialité
#   -l =>   niveau de securiter


# import
source $ZANE_BED/src/utils.sh
source $ZANE_BED/src/secret.sh

#######################################
# Global/Constante
#######################################
HASH_ALG="SHA"
ENCRYPTION_METHOD="DES"

conf_type=""
protocol=""

#######################################
# Demander une valeur à un agent snmp 
# d'une machine.
#
# parametre:
#   Object identifier (OID) qu'on 
#   souhaite aller chercher.
#   l'addresse ip de la machine.
#
# retourne 
#   la valeur demander si aucune
#   erreur (0).
#   Rien si une erreur c'est 
#   passer (1).
#
#######################################
function snmp_get() {
   
  local oid=$1
  local ip=$2

  resp=$(snmpwalk \
    -v3 \
    -O q \
    -u "zane" \
    -a $HASH_ALG \
    -A $RW_AUTH \
    -x $ENCRYPTION_METHOD \
    -X $RW_PRIVACY \
    -l authPriv\
    $ip $oid 2>&1 )
  
  # vérifie que l'exécution c'est passé sans problème 
  if [ $? != 0 ]; then
    $LOGGER -t F "$2 ne peut aller chercher la valeur de '$1' cause par $resp"
    return 1
  fi 
  
  # transforme la reponse en un array et prend le deuxieme
  # element qui est la valeur qu'on souhaite aller chercher
  read -ra OUTPUT <<< $resp
  echo "${OUTPUT[1]}"

  return 0

}

#######################################
# Vérifie le status d'une execution
# en cour.
#
# parametre:
#   le nombre representant l'execution
#   qu'on souhaite savoir le status.
#   address ip de l'hote qui execute
#   la requete.
# retourne:
#   0 -> si succes
#   1 -> si echoue 
#
#######################################
function get_exe_status() {

  local rand_num=$1
  local ip=$2

  # nombre maximal de fois qu'on essaie de voir le
  # statut de l'execution. Si nous depassons cette limite,
  # un probleme est survenu avec la connection ssh ou tftp
  try=15
  # pour empecher log redondant
  last=""
  finish=false

  while [ $finish = false ];
  do

    if [ $try -eq 0 ]; then
      $LOGGER -t E "Incapable de finir l'execution. Temps d'executions expirer"
      return 1
    fi 
    
    status=$( snmp_get CISCO-CONFIG-COPY-MIB::ccCopyState.$rand_num $ip )
    
    # possible valeurs retourné
    case $status in
      waiting)
        $LOGGER -t D "mode d'execution: en attente"
        last="waiting"
        sleep 1 
        ;;
      running)
    
        if [ "$last" != "running" ]; then
          $LOGGER -t D "Transaction de fichier en cour" 
          last="running"
        fi
        
        sleep 1
        ;;
      successful)
        finish=true
        $LOGGER -t I "execution sur l'hote $ip a ete un succes"
        ;;
    
      failed)

        reason=$( snmp_get CISCO-CONFIG-COPY-MIB::ccCopyFailCause $ip )
        
        # On n'est pas capable de trouver la cause de l'erreur
        if [ $? -ne 0 ]; then
          reason="inconnu"
        fi
        
        $LOGGER -t E "L'execution a echouer. cause: $reason"
        return 1
        ;;

    esac

    try=$(( try - 1 ))
  done
  
  return 0
    
}

#######################################
# Envoyer une config vers une machine 
# cisco. 
#
# parametre:
#   Address ip.
#   Nom du fichier a envoyer a la 
#   machine.
#   Type de config (running,startup).
#   Protocole d'envoi (ssh | tftp )
#######################################
function send_config() {
  
  local ip=$1
  local file=$2
  local ctype=$3
  local protocol=$4

  # Chaque fois qu'on copie une config, on doit ajouter un nombre à la fin d'un OID.
  # Ce nombre crée une rangé dans un tableau et ajoute tout les OID et leur valeur 
  # a celle-ci. On ne peut pas utiliser le meme numero de rangé pour plusieurs transfere si
  # celle-ci exitste déja (il vive pour 5 minutes). Alors, nous utilisons un chiffre
  # aléatoire.
  local rand_num=$(( RANDOM % 1000 ))
  
  # utilise le protocole ssh
  if [ $protocol = "ssh" ]; then
    # Explication des OID:
    #   1. CISCO-CONFIG-COPY-MIB::ccCopyProtocol
    #       desc: spécifie le protocole qui devrait être utiliser pour le transfere 
    #       valeur: 4 (scp)
    #   2. CISCO-CONFIG-COPY-MIB::ccCopySourceFileType
    #       desc: spécifie le type de fichier source (fichier à envoyer)
    #       valeur: 1 (Network File) *représente un fichier sur un autre machine du réseau
    #   3. CISCO-CONFIG-COPY-MIB::ccCopyDestFileType
    #       desc: specifie le type de fichier de destination
    #       valeur: 3 (startupConfig) ou 4(runningConfig)
    #   4. CISCO-CONFIG-COPY-MIB::ccCopyServerAddress
    #       desc: l'adresse ip du serveur où le fichier de config se trouve
    #   5. CISCO-CONFIG-COPY-MIB::ccCopyFileName
    #       desc: le nom du fichier de config a envoyer
    #   6. CISCO-CONFIG-COPY-MIB::ccCopyUserName
    #       desc: un nom d'utilisateur sur le serveur où se trouve le fichier de config
    #   7. CISCO-CONFIG-COPY-MIB::ccCopyUserPassword
    #       desc: le mot de passe pour l'utilisateur sur le serveur
    #   8. CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus
    #       desc: activer le transfere 
    #       valeur: 1 (CreateAndGo)
    response=$(snmpset \
      -v3 \
      -O q \
      -l authPriv \
      -u "zane" \
      -a $HASH_ALG \
      -A $RW_AUTH \
      -x $ENCRYPTION_METHOD \
      -X $RW_PRIVACY \
      $ip \
      CISCO-CONFIG-COPY-MIB::ccCopyProtocol.$rand_num i 4 \
      CISCO-CONFIG-COPY-MIB::ccCopySourceFileType.$rand_num i 1 \
      CISCO-CONFIG-COPY-MIB::ccCopyDestFileType.$rand_num i $ctype \
      CISCO-CONFIG-COPY-MIB::ccCopyServerAddress.$rand_num a $ZANE_IP \
      CISCO-CONFIG-COPY-MIB::ccCopyFileName.$rand_num s "scp/send/$file" \
      CISCO-CONFIG-COPY-MIB::ccCopyUserName.$rand_num s $SSH_USER \
      CISCO-CONFIG-COPY-MIB::ccCopyUserPassword.$rand_num s $SSH_PASSWD \
      CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$rand_num i 4 \
      2>&1 )  

  # utillise le protocole tftp
  else 

    # Explication des OID:
    #   1. CISCO-CONFIG-COPY-MIB::ccCopyProtocol
    #       desc: spécifie le protocole qui devrait être utiliser pour le transfere 
    #       valeur: 1 (tftp)
    #   2. CISCO-CONFIG-COPY-MIB::ccCopySourceFileType
    #       desc: spécifie le type de fichier source (fichier à envoyer) 
    #       valeur: 1 (Network File) *représente un fichier sur un autre machine du réseau
    #   3. CISCO-CONFIG-COPY-MIB::ccCopyDestFileType
    #       desc: specifie le type de fichier de destination
    #       valeur: 3 (startupConfig) ou 4(runningConfig)
    #   4. CISCO-CONFIG-COPY-MIB::ccCopyServerAddress
    #       desc: l'adresse ip du serveur où le fichier de config se trouve
    #   5. CISCO-CONFIG-COPY-MIB::ccCopyFileName
    #       desc: le nom du fichier de config a envoyer
    #   6. CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus
    #       desc: activer le transfere 
    #       valeur: 1 (CreateAndGo)
    response=$(snmpset \
      -v3 \
      -O q \
      -l authPriv \
      -u "zane" \
      -a $HASH_ALG \
      -A $RW_AUTH \
      -x $ENCRYPTION_METHOD \
      -X $RW_PRIVACY \
      $ip \
      CISCO-CONFIG-COPY-MIB::ccCopyProtocol.$rand_num i 1 \
      CISCO-CONFIG-COPY-MIB::ccCopySourceFileType.$rand_num i 1 \
      CISCO-CONFIG-COPY-MIB::ccCopyDestFileType.$rand_num i $ctype \
      CISCO-CONFIG-COPY-MIB::ccCopyServerAddress.$rand_num a $ZANE_IP \
      CISCO-CONFIG-COPY-MIB::ccCopyFileName.$rand_num s "send/$file" \
      CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$rand_num i 4 \
      2>&1 )
  fi 

  # vérifie que l'exécution de la commande n'a pas échoué
  if [ $? -ne 0 ]; then
    $LOGGER -t E "Transfere de fichier de config à echoué. $response"
    return 1
  fi
  
  # s'assure que l'exécution s'est passé sans problème
  get_exe_status $rand_num $ip

  return $?

}

#######################################
# Copie une config d'une machine sur 
# le serveur.
# 
# parametre:
#   address ip de la machine.
#   emplacement du fichier de 
#   destination.
#   type de fichier a recolter.
#
#######################################
function get_config() {

  local ip=$1
  local file=$2
  local ctype=$3 
  local protocol=$4

  # Chaque fois qu'on copie une config, on doit ajouter un nombre à la fin d'un OID.
  # Ce nombre crée une rangé dans un tableau et ajoute tout les OID et leur valeur 
  # a celle-ci. On ne peut pas utiliser le meme numero de rangé pour plusieurs transfere si
  # celle-ci exitste déja (il vive pour 5 minutes). Alors, nous utilisons un chiffre
  # aléatoire.
  local rand_num=$(( RANDOM % 1000 ))
  
  if [ $protocol = "ssh" ]; then
    # Explication des OID:
    #   1. CISCO-CONFIG-COPY-MIB::ccCopyProtocol
    #       desc: spécifie le protocole qui devrait être utiliser pour le transfere 
    #       valeur: 4 (scp)
    #   2. CISCO-CONFIG-COPY-MIB::ccCopySourceFileType
    #       desc: spécifie le type de fichier source (fichier à envoyer) 
    #       valeur: 3 (startupConfig) ou 4(runningConfig)
    #   3. CISCO-CONFIG-COPY-MIB::ccCopyDestFileType
    #       desc: specifie le type de fichier de destination
    #       valeur: 1 (Network File) *représente un fichier sur un autre machine du réseau
    #   4. CISCO-CONFIG-COPY-MIB::ccCopyServerAddress
    #       desc: l'adresse ip du serveur où le fichier de config se trouve
    #   5. CISCO-CONFIG-COPY-MIB::ccCopyFileName
    #       desc: le nom du fichier de config a envoyer
    #   6. CISCO-CONFIG-COPY-MIB::ccCopyUserName
    #       desc: un nom d'utilisateur sur le serveur où se trouve le fichier de config
    #   7. CISCO-CONFIG-COPY-MIB::ccCopyUserPassword
    #       desc: le mot de passe pour l'utilisateur sur le serveur
    #   8. CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus
    #       desc: activer le transfere 
    #       valeur: 1 (CreateAndGo)
    response=$(snmpset \
      -v3 \
      -l authPriv \
      -u "zane" \
      -a $HASH_ALG \
      -A $RW_AUTH \
      -x $ENCRYPTION_METHOD \
      -X $RW_PRIVACY \
      $ip \
      CISCO-CONFIG-COPY-MIB::ccCopyProtocol.$rand_num i 4 \
      CISCO-CONFIG-COPY-MIB::ccCopyDestFileType.$rand_num i 1 \
      CISCO-CONFIG-COPY-MIB::ccCopySourceFileType.$rand_num i $ctype \
      CISCO-CONFIG-COPY-MIB::ccCopyServerAddress.$rand_num a $ZANE_IP \
      CISCO-CONFIG-COPY-MIB::ccCopyFileName.$rand_num s "scp/get/$file" \
      CISCO-CONFIG-COPY-MIB::ccCopyUserName.$rand_num s $SSH_USER \
      CISCO-CONFIG-COPY-MIB::ccCopyUserPassword.$rand_num s $SSH_PASSWD \
      CISCO-CONFIG-COPY-MIB::ccCopyServerAddressType.$rand_num i 1 \
      CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$rand_num i 4 \
      2>&1 )
      
  # utilise le protocole tfpt
  else

    # Quand nous utilisons tftp pour copier une config, le fichier doit exister dans le serveur
    # avant de pouvoir le copier avec full access à tous pour celui ci (777)
    touch /srv/tftp/get/$file 
    chmod 777 /srv/tftp/get/$file
    
    # Explication des OID:
    #   1. CISCO-CONFIG-COPY-MIB::ccCopyProtocol
    #       desc: spécifie le protocole qui devrait être utiliser pour le transfere 
    #       valeur: 1 (tftp)
    #   2. CISCO-CONFIG-COPY-MIB::ccCopySourceFileType
    #       desc: spécifie le type de fichier source (fichier à envoyer) 
    #       valeur: valeur: 3 (startupConfig) ou 4(runningConfig)
    #   3. CISCO-CONFIG-COPY-MIB::ccCopyDestFileType
    #       desc: specifie le type de fichier de destination
    #       valeur: 1 (Network File) *représente un fichier sur un autre machine du réseau
    #   4. CISCO-CONFIG-COPY-MIB::ccCopyServerAddress
    #       desc: l'adresse ip du serveur où le fichier de config se trouve
    #   5. CISCO-CONFIG-COPY-MIB::ccCopyFileName
    #       desc: le nom du fichier de config a envoyer
    #   6. CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus
    #       desc: activer le transfere 
    #       valeur: 1 (CreateAndGo)
    response=$(snmpset \
      -v3 \
      -l authPriv \
      -u "zane" \
      -a $HASH_ALG \
      -A $RW_AUTH \
      -x $ENCRYPTION_METHOD \
      -X $RW_PRIVACY \
      $ip \
      CISCO-CONFIG-COPY-MIB::ccCopyProtocol.$rand_num i 1 \
      CISCO-CONFIG-COPY-MIB::ccCopySourceFileType.$rand_num i $ctype \
      CISCO-CONFIG-COPY-MIB::ccCopyDestFileType.$rand_num i 1 \
      CISCO-CONFIG-COPY-MIB::ccCopyServerAddress.$rand_num a $ZANE_IP \
      CISCO-CONFIG-COPY-MIB::ccCopyFileName.$rand_num s "get/$file" \
      CISCO-CONFIG-COPY-MIB::ccCopyEntryRowStatus.$rand_num i 4 \
      2>&1)
  fi 

  # vérifie que l'exécution de la commande n'a pas échoué
  if [ $? -ne 0 ]; then
    $LOGGER -t E "Copie de fichier de config à echoué. $response"
    return 1
  fi
  
  # s'assure que l'exécution s'est passé sans problème
  get_exe_status $rand_num $ip

  return $?

}


#######################################
# Affiche le message d'aide du script
# et met fin au script.
#######################################
function helper() {
  
  echo "
  config-graber.sh [OPTION] [ACTION] [FILE] MACHINE_IP
  
  ACTION:
    get:  faire une demande d'envoi d'une config
    send: Envoyer une config a une machine 
  
  FILE:   nom du fichier de destination quand on fait une
          requete d'envoi de config (get) ou emplacenent
          d'une fichier a envoyer
  OPTION:
    -h    Affiche ce message. 
    -t    Type de config [ running-config | startup-config ]
    -p    le protocole a utiliser pour la copy [ ssh | tftp ]

  MACHINE IP:   address ip de la machine"

  exit 0
}


# s'assure qu'on passe au moins 1 arguments même si ce n'est pas valide
if [ $# -eq 0 ]; then
  $LOGGER -t F "Aucun arguent a ete passer"
  exit 200 
fi

while getopts "ht:p:" ARG; do
  
  case ${ARG} in
    h)
      helper
      ;;
    t)

      if [ ${OPTARG} == "running-config" ];then
        conf_type=4
      elif [ ${OPTARG} == "startup-config" ]; then
        conf_type=3
      else
        $LOGGER -t F "invalide argument -t  '${OPTARG}'"
        exit 200
      fi

      ;;

    p)
      if [ ${OPTARG} == "ssh" ]; then
        protocol="${OPTARG}" 
      elif [ ${OPTARG} == "tftp" ]; then 
        protocol="${OPTARG}"
      else
        $LOGGER -t F "invalide protocole specifier '-t'"
        exit 200
      fi

      ;;

    *)
      # pour des arguments invalide
      helper
      ;;

  esac 

done 

# on ne veux que les arguments que getopt n'a pas traité
shift "$((OPTIND-1))"

# soit send ou get
action=$1
file=$2
ip=$3 

# s'assure qu'un type de config est passé 
if [ -z $conf_type ]; then
  $LOGGER -t F "aucun type de config  à été spécifié '-t'"
  exit 200
fi

# s'assure qu'un protocole est passé
if [ -z $protocol ]; then
  $LOGGER -t F "aucun protocole à été spécifié '-p'"
  exit 200
fi

# s'assure qu'une addresse a été passé 
if [ -z $ip ]; then 
  $LOGGER -t F "aucun adresse ip à été spécifié"
  exit 200
fi

# s'assure que l'addresse ip est une adresse IPV4 valide (voir fichier utils.sh)
valid_ipv4_addr $ip
if [ $? -eq 1 ]; then 
  $LOGGER -t F "invalide ipv4 addresse a ete passer: $ip"
  exit 200
fi

# s'assure qu'un nom de fichier est passé
if [ -z $file ]; then
  $LOGGER -t F "aucun nom de fichier a ete specifier"
  exit 200
fi

# on veut copier un fichier de config d'une machine
if [ $action = "get" ]; then
  $LOGGER -t I "Début de la copie de la config"
  get_config $ip $file $conf_type $protocol
  exit $?  
# on veut envoyer un fichier de config d'une machine  
elif [ $action = "send" ]; then
  $LOGGER -t I "Début de transfert de la config"
  send_config $ip $file $conf_type $protocol
  exit $?
else 
  $LOGGER -t F "invalid action $action"
  exit 200
fi
