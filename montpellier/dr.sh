#!/bin/ksh
# to prepare for DR
# vero updated 15/04/2013

clear
tsm="dsmadmc -id=ibm -pass=$PTP -dataonly=yes"
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
echo "*     --> Prepare the RESTORE DB                                       *"
echo "*                                                                      *"
echo "*     --> First we cleanup the TSM dirs                                *"
echo "*                                                                      *"
echo "************************************************************************"
CheckOK
rm -r /tsm/inst1_activelog/* > /dev/null 2>&1
rm -r "/tsm/inst1_archivelog/*" > /dev/null 2>&1
rm -r /tsm/inst1_archivelog/* > /dev/null 2>&1
rm -r /tsm/inst1_database/* > /dev/null 2>&1
rm -r "/tsm/inst1_database/*" > /dev/null 2>&1
rm -r /tsm/inst1_archivefailoverlog/recov/* > /dev/null 2>&1
echo "************************************************************************"
echo "*                                                                      *"
echo "*     Searching for the latest synchronized DBB with up to 4 dbbvols   *"
echo "*                                                                      *"
echo "************************************************************************"
cp -p /tsmDR_tsmaix2/volhist.opt /tsm/inst1_configuration/volhist.opt.tsminst1
cp -p /tsmDR_tsmaix2/volhist.opt /tsm/inst1_configuration/volhist.opt
cp -p /tsmDR_tsmaix2/dsmserv.opt.DR.Reference /tsm/inst1_configuration/dsmserv.opt    
cp -p /tsmDR_tsmaix2/devconfig.DR.Reference  /tsm/inst1_configuration/devconfig.opt 
chown tsminst1:tsmsrvrs /tsm/inst1_configuration/devconfig.opt
cp -p /tsmDR_tsmaix2/info_db.out /tsm/inst1_configuration/info_db.out.tsmaix1             
cp -p /tsmDR_tsmaix2/dsmserv.opt.tsmaix1 /tsm/inst1_configuration/
cp -p /tsmDR_tsmaix2/qdbb.out             /tsm/inst1_configuration/qdbb.out.tsminst1
cp -p /tsmDR_tsmaix2/dbbvols.out             /tsm/inst1_configuration/dbbvols.out.tsminst1

# analyse of the DB Backup volumes
typeset -i Index=0
typeset    Line=""
typeset    Input="/tsmDR_tsmaix2/dbbvols.out"

# At first we fill the array:
(( Index = 1 ))                               # we want to start our indices with 1
grep "\-\-" "$Input" | while read Line ; do
     typeset Array[$Index]="${Line}"  
     (( Index += 1 ))                         # increment index
done

echo "************************************************************************"
echo "*                                                                      *"
echo "*             We've found ${#Array[*]} TSM DB full backups                        *"
echo "*   -->  Do you want to choose the backup serie you want to restore?   *"
echo "*                                                                      *"
echo "************************************************************************"
CheckOK

# now let us try to display the array contents:
(( Index = 1 ))                               # reset our array index
                                              # ${#Array[*]} evaluates to the number of elements in the array
clear
echo "************************************************************************"
echo "*                                                                      *"
echo "*     List of the ${#Array[*]} TSM DB full backups  available                     *"
echo "*                                                                      *"
echo "************************************************************************"
echo "\n \n"
while [ $Index -le ${#Array[*]} ] ; do
     choice=$(printf "%4s" ${bold} $Index ${offbold})
     print - "Choice # $choice :\t ${Array[$Index]}"
     (( Index += 1 ))
done
echo "************************************************************************"
echo "*                                                                      *"
echo "* Please enter the $rev number ${unrev} of the DB backup serie you want to restore *"
echo "*                                                                      *"
echo "************************************************************************"
read choice
expr $choice + 0 >/dev/null 2>&1
if [ $? -ne 0 ] ; then
  echo "*************************************"
  echo "*                                   *"
  echo "*     $rev   INVALID CHOICE   $unrev          *"                                  
  echo "*  >>> defaulting to # 1 (last DBB) *"
  echo "*                                   *"
  echo "*************************************"
  choice=1
elif [[ $choice -gt ${#Array[*]} || $choice -le 0 ]] ; then
  echo "*************************************"
  echo "*                                   *"
  echo "*     $rev   INVALID CHOICE   $unrev          *"                                  
  echo "*  >>> defaulting to # 1 (last DBB) *"
  echo "*                                   *"
  echo "*************************************"
  choice=1
fi
dbbdate=$(echo "${Array[$choice]}" | cut -d" " -f1)
dbbtime=$(echo "${Array[$choice]}" | cut -d" " -f2)
dbbserie=$(echo "${Array[$choice]}" | cut -d" " -f3)
dbbvols=$(echo "${Array[$choice]}" | cut -c 27-67)
dbbtest=$dbbvols
i=1
while [ $i -le 4  ] 
do
#  echo $i $dbbtest
  typeset dbbvol_[$i]=$(echo $dbbtest | cut -d"," -f1)
  dbbtest=$(echo $dbbtest | cut -c 10-80)     
# echo "dbbtest est ensuite = à:***${dbbtest}***"
  if [ -z "${dbbtest}" ]; then break; fi
  (( i += 1 ))
done
jdbbvols=$(printf "-30s" $dbbvols)
echo "************************************************************************"
echo "*                                                                      *"
echo "*  You've chosen the DB backup serie n° $dbbserie                             *"
echo "*    --> This DB Full Backup was created the $bold $dbbdate ${offbold}at${bold} $dbbtime $offbold  *"
echo "*                                                                      *"
echo "* $rev $i $unrev volumes will be required for the restore db:                     *"
echo "*   --> $jdbbvols                         *"                       
j=1
while [ $j -le ${#dbbvol_[*]} ]  
do
  tgtslot=$(expr 2021 + $j)
  echo "*   *** dbbvol${j} == ${dbbvol_[$j]}  must pe placed in slot $tgtslot               *"
  sed -e "s/dbbtape${j}/${dbbvol_[$j]}/" /tsm/inst1_configuration/devconfig.opt > devconf.tmp
  mv devconf.tmp /tsm/inst1_configuration/devconfig.opt
  (( j += 1 ))
done
echo "*                                                                      *"
echo "************************************************************************"
CheckOK     
echo "************************************************************************"
echo "*                                                                      *"
echo "*     Please insert the DBB vols into the target slots of DR_MAINLIB   *"
echo "*                                                                      *"
echo "*  When DONE then continue and check the device config file was filled *"
echo "*  with the accurate volname(s)                                        *"
echo "************************************************************************"
CheckOK
vi /tsm/inst1_configuration/devconfig.opt
echo "************************************************************************"
echo "*                                                                      *"
echo "*     Now we use the TSM DB2 instance to perform the restore DB        *"
echo "*                                                                      *"
echo "*     3 aliases were set to make it easier for the demo:               *"
echo "*          ${bold}cddb${offbold} = su - tsminst1                                        *"
echo "*          ${bold}cdcfg${offbold} = cd in the local tsm config dir                      *"
echo "*                                                                      *"
echo "*          ${bold} to be run as tsminst1 & from the configuration dir ${offbold}        *"
echo "*                                                                      *"
echo "************************************************************************"
dateyy=`echo $dbbdate|cut -c 1-4`;datemm=`echo $dbbdate|cut -c 6-7`;datedd=`echo $dbbdate|cut -c 9-10`
date=${datemm}'/'${datedd}'/'${dateyy}
echo " --> /opt/tivoli/tsm/server/bin/dsmserv -u tsminst1 -i /tsm/inst1_configuration -o /tsm/inst1_configuration/dsmserv.opt ${rev}restore db todate=$date totime=$dbbtime${unrev} on=/tsm/inst1_configuration/dbrep.txt "



