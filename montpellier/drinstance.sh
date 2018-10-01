#!/bin/ksh
# to perform the DR from the TSMINST1 
# vero updated 24/04/2013

clear
tsml="dsmadmc -id=ibm -pass=$PTP -dataonly=yes -se=local"
rev=`tput smso`
unrev=`tput rmso`
# with putty the bold is changed in blue....
bold=`tput bold`
offbold=`tput sgr0`
# vero: fonction pour valider que l'on souhaite continuer
CheckOK(){
   echo "           ****************************************"
   echo "           *     ==> Enter ${rev}y/yes${unrev} to proceed       *"
   echo "           ****************************************"
   read rep
   if [[ $rep = 'y' || $rep = 'Y' || $rep = 'yes'  ]]
      then
      return
   else
      echo "EXIT of script $0"
      exit
   fi
}
clear
# sans le "-" c'est justifié à droite"
scriptname=$(printf "%30s" $0)
scriptname2=$(printf "%-30s" $0)
echo "************************************************************************"
echo "*                                                                      *"
echo "*                  Script $scriptname2               * "
echo "*     --> Perfom  the TSM RESTORE DB + restart                         *"
echo "*                                                                      *"
echo "*     --> First we launch the restore DB                               *"
echo "*                                                                      *"
echo "************************************************************************"
CheckOK
if [[ $USER != 'tsminst1' ]] ; then
 echo "************************************************************************"
 echo "*                                                                      *"
 echo "*     You MUST ${bold}login as tsminst1${offbold} for the restore DB                    *"   
 echo "*                                                                      *"
 echo "************************************************************************"
 exit 99  
fi
echo "************************************************************************"
echo "*                                                                      *"
echo "*   Please do a ${rev}copy/paste$unrev of the ${bold}restore db command$offbold from "DR" script    *"
echo "*     This should be launched in another TSMINST1 window               *"
echo "*                                                                      *"
echo "*          ==> then press ${rev}[ENTER]${unrev} when TSM DB is restored            *"

echo "************************************************************************"
read tsmrest

echo "\n \n"

echo "************************************************************************"
echo "*                                                                      *"
echo "*    we have to start now the TSM server in background:                *"   
echo "*                                                                      *"
echo "* We switch to the 2nd session of TSMINST1 and use the alias tsmstart  *"
echo "* ${bold} /opt/tivoli/tsm/server/bin/rc.dsmserv -u tsminst1${offbold} ,                 *" 
echo "*                                   ${bold}-i /tsm/inst1_configuration${offbold} &      *" 
echo "*                                                                      *"
echo "************************************************************************"
CheckOK
#/opt/tivoli/tsm/server/bin/rc.dsmserv -u tsminst1 -i /tsm/inst1_configuration & 
echo "************************************************************************"
echo "*   Please ${rev}open a TSM admin console${unrev} when server is ready               *"
echo "*          ==> then press ${rev}[ENTER]${unrev} to continue                          *"
echo "************************************************************************"
read x

echo "************************************************************************"
echo "*   we have to refresh the library and drives definitions according    *"
echo "*       the devices available on the DR site                           *"
echo "*     So we delete the obsolete devices with commands:                 *"
echo "* perform libaction mainlib action=delete   + del library mainlib      *"
echo "************************************************************************"
$tsml perform libaction mainlib action=delete
$tsml del libr mainlib
$tsml perform libaction 7610lib action=delete
$tsml del libr 7610lib 
echo "************************************************************************"
echo "* Then we have to define the new devices available on DR site          *"
echo "* define libr dr_mainlib libtype=vtl autolabel=yes                     *"
echo "* perform libaction dr_mainlib action=define device=/dev/smc2  ,       *" 
echo "*                                     prefix=drmain_d                  
*" 
echo "************************************************************************"
$tsml define libr dr_mainlib libtype=vtl autolabel=yes
$tsml perform libaction dr_mainlib action=define devide=/dev/smc2 prefix=drmain_d
echo "************************************************************************"
echo "*   we update the existing device class to point to the new VTL        *"
echo "*   update devc mainlib_dvc libr=dr_mainlib                            *"
echo "************************************************************************"
$tsml update devc mainlib_dvc libr=dr_mainlib
echo "************************************************************************"
echo "*   Using PT Manager, we move all the MLxxxxL3 to the new DR VTL       *"
echo "*          ==> then press ${rev}[ENTER]${unrev} when you're ready      *"
echo "************************************************************************"
read aa 
echo "************************************************************************"
echo "*   We checkin all the tapes, from original site (they will we R/O)    *"
echo "*   and from local site, in case we have already prepared some scratch *"
echo "************************************************************************"
$tsml checkin libvol dr_mainlib search=bulk checkl=b status=private  waitt=0
$tsml checkin libvol dr_mainlib search=yes checkl=b status=scratch
$tsml checkin libvol dr_mainlib search=yes checkl=b status=private 
echo "************************************************************************"
echo "*   We inform the TSM server that the MLxxxx tapes are R/O             *"
echo "*   update vol ML* access=readonly                                     *"
echo "************************************************************************"

$tsml update vol ml* access=readonly
