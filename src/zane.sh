#!/bin/bash

# import
source $ZANE_BED/src/secret.sh


# s'assure que le repo est à jour
git pull >/dev/null 2>&1


# se diriger dans le submodule des config
cd ../config

# 1. aller chercher les adresses ip des machine et leur hostname (section de Bill)
fichier=/etc/zane/list.cfg

hotes_ip=()
hotes_name=()

#si le fichier existe alors
if [ -f $fichier ]; then

  #lire le fichier 
  while read host; do

    #recuper le ip du routeur
    hotes_ip+=($(echo $host | cut -d' ' -f 1))

    #recupere le hostname du routteur
    hotes_name+=($(echo $host | cut -d' ' -f 2))
    # echo "le hostname est $hostname et le ip est $ip"

  done < "$fichier"

#si le fichier n'existe pas
else
    $LOGGER -t F "le fichier que vous demander n'existe pas, le bon fichier est $fichier"
    exit 200
fi


# 2. aller verifier s'il y a des config à envoyer 

send_config=()

$LOGGER -t D "Cherche pour fichier a envoyer"

# solution pour quand dossier vide: 
# https://unix.stackexchange.com/questions/239772/bash-iterate-file-list-except-when-empty
shopt -s nullglob

for path in "$ZANE_BED/config/sends"/*.cfg
do
  
  # on veux seulement le nom du fichier sans son extension
  file=$(basename $path)
  filename="${file%%.*}"
  
  send_config+=($filename)
  
  $LOGGER -t D "$filename. trouve!"
done

$LOGGER -t I "${#send_config[@]} nouvelle(s) config(s) doivent être envoyé"

# b. verifier si hote existe
for name in ${send_config[@]}
do

  found=false
  for((i=0; i < "${#hotes_name[@]}"; i++)); do
    
    if [ "${hotes_name[$i]}" == "$name" ]; then

      # c. envoie config vers sa machine destiner 
      #
      cp $ZANE_BED/config/sends/$name.cfg /srv/scp/send/$name.cfg
      
      ip="${hotes_ip[$i]}"
      

      # s'assure que la machine est active
      if ping -c 1 -W 1 $ip > /dev/null 2>&1 ; then

        $LOGGER -t D "Envoie de la config vers 'running-config' pour $name"
        
        # envoi vers running config
        $ZANE_CONF_GRABBER -t running-config -p ssh send $name.cfg $ip
        
        if [ $? -eq 200 ]; then
          $LOGGER -t F "Erreur irrécupérable est survenu"
          exit 200
        fi

        if [ $? -eq 1 ]; then 
          $LOGGER -t E "Incapable d'envoyer config vers 'running-config' de la machine $name"  
        fi 

        $LOGGER -t D "Envoie de la config vers 'startup-config' pour $name"  
        
        # envoi vers startup-config
        $ZANE_CONF_GRABBER -t startup-config -p ssh send $name.cfg $ip
        
        if [ $? -eq 200 ]; then
          $LOGGER -t F "Erreur irrécupérable est survenu"          
          exit 200
        fi   

        if [ $? -eq 1 ]; then   
          $LOGGER -t E "Incapable d'envoyer config vers 'startup-config' de la machine $name"
        fi
      
      else
        $LOGGER -t E "incapable d'envoyer la config de $name car il est inactif"  
      fi
      
      found=true
      break
      
    fi

  done
  
  if [ $found = false ]; then
    $LOGGER -t E "L'hote $name est inconnu, la config ne sera pas envoyer"
  fi
  
  git rm sends/$name.cfg >/dev/null 2>&1

done 

# commit seulement si au moin un fichier à été envoyé
if [ ${#send_config[@]} -ne 0 ]; then
  
  cmd=$(git commit -m "suprimer les config a envoyer apres execution")

  if [ $? -ne 0 ]; then
    $LOGGER -t E "Incapable de commit la supression des config envoyer. sortie: $cmd"
  else
    $LOGGER -t I "Commit les fichier suprimer apres envoie"
  fi 

fi


# enregistre le nombre de config qui ont changé pour que s'il y en a plus 
# d'une, on commit
counter=0

for((i=0; i < "${#hotes_name[@]}"; i++))
do 
  name="${hotes_name[$i]}"
  ip="${hotes_ip[$i]}"
  $LOGGER -t D "Nom: $name Ip: $ip"
  # a) verifier si machine et active
  if ping -c 2 -W 2 $ip 2>&1 > /dev/null ; then

    # copier la running config 
    $ZANE_CONF_GRABBER -t running-config -p ssh get $name.cfg $ip

    # comparer la config copié à celle dans le repo,
    file1="$ZANE_BED/config/saves/$name.cfg"
    file2="/srv/scp/get/$name.cfg"

    #si le fichier existe
    if [ -f "$file2" ]; then

      #comparer le comptenu du fichier
      if cmp -s "$file1" "$file2"; then
        $LOGGER -t I "Les fichiers de configuration sont identiques, rien à changer."

      #mettre a jour le fichier si il est different de l'ancient fichier
      else
      
        cp -f "$file2" "$file1"
        
        git add $file1 >/dev/null 2>&1
        
        $LOGGER -t I "Le fichier de configuration a été mis à jour."
            
        counter=$(( counter + 1 ))
      fi
    fi


  else
    $LOGGER -t E "Incapable de copier la config de $name car il est inactif"
  fi
done


if [ $counter -gt 0 ]; then
  
  cmd=$(git commit -m "Mise a jour des fichier de config")

  if [ $? -ne 0 ]; then
    $LOGGER -t E "Incapable de commit la supression des config envoyer. sortie: $cmd"
  else
    $LOGGER -t I "Commit les nouveau fichier de config"
  fi


fi


# appliquer tout les changements au repo des config
git push https://$GIT_BOT_CONFIG:$GIT_TOKEN_CONFIG@$GIT_URL_CONFIG 2>/dev/null

if [ $? -ne 0 ]; then   
  $LOGGER -t E "Incapable de mettre à jour le repositoire des "                                                                           
else
  $LOGGER -t I "L'envoie des nouvelles commits à été un succes"            
fi   

# retourne au git racine
cd ../src

# mise a jour du git racine
git add ../config &>/dev/null

git commit -m "Mise à jour du stockage des config" &>/dev/null

# si une erreur arrive, ça peut être tout simplement rien qui a été changer
if [ $? -eq 0 ]; then
  cmd=$(git push -q https://$GIT_BOT_MAIN:$GIT_TOKEN_MAIN@$GIT_URL_MAIN)
  
  if [ $? -ne 0 ]; then
    $LOGGER -t E "La mise à jour du répositoire à échoué. raison: $cmd"
  else
    $LOGGER -t I "La mise à jour du répositoire à réussi"
  fi

fi 

$LOGGER -t I "L'exécution terminé"









