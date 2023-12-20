# Projet Linux (ZANE)

Par William Pelletier


Dépôts :

- [Source code](https://git.dti.crosemont.quebec/1834089/h34_projet)
- [Fichier de configuration](https://git.dti.crosemont.quebec/1834089/h34_projet-config)



## Table des matières
- [Présentation](#présentation)
- [Configuration des machines](#configuration-des-machines)
- [Service](#Service)
- [Structure du Projet](#Structure-du-projet)
- [Fonctionnement](#fonctionnement)


## Présentation

Utilitaire permettant de copier et envoyer des configs à des machines Cisco ainsi que de s'occuper du versionnage et de l'entreposage de configuration dans un dépôt git.

## Configuration des machines

Pour le bon fonctionnement du script, les machines doivent avoir certaine configuration au préalable. Ils doivent avoir un compte SNMP version 3 avec les vues nécessaire pour interagir avec la machine.

Nous avons pris la version 3 de SNMP car les versions précédentes envoyait leurs paquets en plein texte tan disque SNMP version 3 permet l'authentification des TRAPs et encrypte les donnés des paquets (leur payload).

1. Créer une liste d'accès avec l'adresse ip du serveur qui exécute le script.

    ```
    ip access-list standard snmp-service
    remark snmp serveur 
    permit 192.168.56.30
    ```

2. Créer une vue SNMP, c'est-à-dire un groupe de MIB qui peuvent être accédé par un compte ou groupe. Pour le bon fonctionnement du script, nous n'avons que besoin de ccCopy.

    ```
    snmp-server view conf-graber ccCopy included
    ```


3. Créer un groupe avec les droits d'écriture, la vue créer auparavant et accessible de l'adresse dans la liste d'accès précédente.
    ```
    snmp-server group grp1 v3 priv write conf-graber access snmp-service 
    ```

4. Créer un utilisateur dans le groupe créer précédemment avec ses méthodes d'authentification et d'encryptage.
    ```
    snmp-server user zane grp1 v3 auth sha cisco123 priv des crosemont access snmp-service 
    ```


## Service 

Pour respecter les demande de notre projet qui indiquait que le script devait s'exécuter automatiquement à minuit à chaque jour, nous avons créé un service à l'aide de `systemd` et de son module `timer`.

### Configuration de zane.service
```
[Unit]
Description="lance le processus de copie/envoie par le script zane"

[Service]
User=zane # spécifie l'utilisateur qui executera le script
WorkingDirectory=/opt/h34_projet/src # spécifie le dossier dans lequel le service va partir
ExecStart=/opt/h34_projet/src/zane.sh # le script à éxécuter
EnvironmentFile=/opt/h34_projet/environment.cfg # les variables d'environement pour lequel le script aura besoin (voir fichier environement.cfg)

```

### Configuration de zane.timer

C'est ceci qui nous permettra de l'exécuter automatiquement à minuit chaque jour.

```
[Unit]
Description="Execute le service zane.service 5 minutes apres boot a minuit chaque jour"

[Timer]
OnBootSec=5min
OnUnitActiveSec=24h
OnCalendar=*-*-* 00:00:00
Unit=zane.service

[Install]
WantedBy=multi-user.target
```


## Structure du projet 

Dans la racine principale du dépôt, se trouve tout le code source de notre projet, de la documentation et un sous-module, qui est le dépôt de stockage de nos fichiers de configuration.



## Fonctionnement

Voici les différents scripts qui sont utilisé dans notre projet :

#### utils.sh 
---
Simple fonction qui aurait pu être utilisé à plus d'une place. Il n'est pas exécutable et il est passé au différent script à l'aide de la commande : `source utils.sh`

#### zane.sh
--- 

C'est le script principal. C'est lui qui est exécuté en premier. Voici les grandes lignes sur son fonctionnement :


1. Va chercher les noms des machines et leur adresse ip dans le fichier /etc/zane/list.cfg.

2. Va vérifier s'il a des fichiers de configuration à envoyer dans le dossier sends. 

3. S'il y en a, pour chaque d'entre eux, il envoie une copie vers running-config et une autre vers startup-config.

4. Enlève les fichiers envoyés du dépôt.

5. Commit les changements s'il y a lieu.

6. Pour chaque machine collecter au départ,

    a. copie leur running-config localement dans le dossier /srv/scp/get.

    b. on compare le fichier capturer avec celui du même nom dans le dépôt.

    c. s'ils diffèrent, on copie celui que nous sommes allé chercher vers l'emplacement de l'autre dans le dossier saves du dépôt.

7. Commit les changements s'il y a lieu

8. Met à jour le dépôt des configs

9. Commit et met à jour la racine pour qu'elle pointe vers la bonne version du sous-module git des configs.


#### config-grabber.sh
---
C'est lui qui permet l'interaction avec les machines pour l'échange de fichier de config. Il est possible de faire des demandes de copie de fichier à distance par l'entremise du protocole SNMP. Cette méthode est du moins, limiter aux machines Cisco et n'est pas possible pour une machine d'une autre compagnie. La version de l'I0S de vote votre machine doit être d'au minimum v12.0.

Il nous permet en autre de demander une copie d'un fichier de configuration, par exemple, running-config, à être copié sur une machine distante par l'entremise du protocole SCP.

L'équivalent serait d'exécuter sur la machine cette commande 
```
copy running-config scp://<utilisateur>:<mdp>@192.168.56.30
```
L'avantage est que nous n'avons pas à établir une connexion SSH, ensuite exécuter des commandes et de nous déconnecter

Ce script nous permet d'envoyer un fichier et de copier un fichier. On peut aussi spécifier le protocole à utiliser et le fichier souhaité à copier où à être envoyé.

Prendre en note que pour utiliser TFTP pour copier une config, vous devez créer un fichier vide à l'endroit ou vous souhaiter le copier avant de le demander.

Pour s'assurer du bon fonctionnent, vous devez accepter les cyphers et les clés d'algorithme que Cisco [supporte](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/sec_usr_ssh/configuration/xe-16/sec-usr-ssh-xe-16-book/sec-secure-shell-algorithm-ccc.html).

C'est la machine Cisco qui établie une connexion SSH avec votre serveur.


Voici comment utiliser le script :
```
config-graber.sh [OPTION] [ACTION] [FILE] MACHINE_IP
  
  ACTION:
    get:  Faire une demande d'envoi d'une config
    send: Envoyer une config à une machine 
  
  FILE:   Nom du fichier de destination quand on fait une
          requete d'envoi de config (get) ou emplacenent
          d'un fichier à envoyer
  OPTION:
    -h    Affiche ce message. 
    -t    Type de config [ running-config | startup-config ]
    -p    Le protocole à utiliser pour la copy [ ssh | tftp ]

  MACHINE IP:   address ip de la machine
```


#### logger.sh
---
Utilitaire de log qui permet à la fois d'afficher au terminal un message formater, mais de l'enregistrer dans un fichier du dossier /var/log/zane du serveur. Il permet de formater le message avec différent type de log.


#### secret.sh
---
Simple fichier qui est utilisé pour entreposer les noms d'utilisateurs et mot de passe que zane.sh à besoin pour bien marcher. Il n'est pas exécutable et est passé à zane.sh comme ceci : `source secret.sh`.





