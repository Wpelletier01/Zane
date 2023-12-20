#!/bin/bash



#######################################
# valide si l'utilisateur qui execute
# est root ou non.
# 
# parametre:
#   aucun 
# general:
#   1 -> s'il n'est pas root 
#   0 -> s'il est root 
#######################################
function isRoot() {
  if [[ "$EUID" -eq 0 ]];
  then
    return 0
  else
    return 1
  fi  
}


#######################################
# Verifie si l'address ip passer est 
# un address ipv4 valide.
#
# parametre:
#   l'address a verifier
# retourne:
#   1 -> si l'address est invalide
#   0 -> si l'address est valide 
#
#######################################
function valid_ipv4_addr() {
  
  local ip=$1
  local result=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    
    result=0
    IFS="." read -ra SADDR <<< $ip 
    

    for((byte=0;byte < ${#SADDR[@]}; byte++)); do

      if [ ${SADDR[$byte]} -gt 255 ]; then
          return 1;
      fi 

    done 
  
  fi 
  
  return $result
}

