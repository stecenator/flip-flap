#!/bin/ksh
# to  refresh the device definitions of the virtual library lto
# after a completed demo with DR scenario.                          
# vero: 26/03/2011

tsm="dsmadmc -id=ibm -pass=$PTP -dataonly=yes" 
rev=`tput smso`
unrev=`tput rmso`
# with putty the bold is changed in blue.... 
bold=`tput bold`
offbold=`tput sgr0`   

clear
echo "************************************************************************"
echo "*                                                                      *"
echo "* Script $0 : reset of the LTO devices for BASIC config *"
echo "*                                                                      *"
echo "*       Do you want to define the new library and drives now ?         *"
echo "*            ==> Enter ${rev}y/yes${unrev} to proceed                                *"
echo "*                                                                      *"
echo "************************************************************************"
read rep
if [[ $rep = 'y' || $rep = 'Y' || $rep = 'yes'  ]]
   then 
echo "************************************************************************"
echo "*                                                                      *"
echo "*              --> continuing with TSM definitions                     *"
echo "*                                                                      *"
echo "************************************************************************"

$tsm define libr mainlib libtype=scsi autolabel=yes relabelscratch=yes shared=yes
$tsm commit
$tsm  define path tsm_prod mainlib srctype=server destt=library device=/dev/smc0
if [ $? -gt 0  ]
   then sleep 4
   $tsm  define path tsm_prod mainlib srctype=server destt=library device=/dev/smc0
   if [ $? -gt 0  ]
     then print "LIBRAY PATH could not be defined !!!!"
   fi
fi
$tsm macro /tsm/inst1_configuration/base_dev.mac    
echo "************************************************************************"
echo "*                                                                      *"
echo "*         The library MAINLIB with 32 drives have been defined         *"
echo "*                                                                      *"
echo "*           ===>    Press${bold} enter${offbold} to continue                            *"
echo "*                                                                      *"
echo "************************************************************************"
   read aa
fi
# processing the checkin for already existing empty tapes (scratch)
# and in R/O (write protected by protectier) the original replicated
clear
echo \n \n
echo "************************************************************************"
echo "*                                                                      *"
echo "*         Disaster Recovery: remaining tasks                           *"
echo "*                                                                      *"
echo "*           -   CHECKIN of existing cartridges                         *"
echo "*           -   Registering the LICENSE                                *"
echo "*           -   Updating original cartridges in READ/ONLY (for TSM)    *"
echo "*           -   Resetting the orginal DISKPOOL                         *"
echo "*           -   + adapt other configuration settings                   *"
echo "*                                                                      *"
echo "*            ==> Enter ${rev}${bold}y/yes${offbold}${unrev} to proceed                                *"
echo "*                                                                      *"
echo "************************************************************************"
read aa
$tsm checkin libv drmainlib search=yes  checklabel=barc status=scratch 
$tsm checkin libv drmainlib search=yes  checklabel=barc status=private 
$tsm checkin libv drmainlib search=bulk  checklabel=barc status=private waitt=0

sleep 3 
echo "************************************************************************"
echo "*                                                                      *"
echo "*               Checkin Libvol commands completed                      *"
echo "*    ---> Please check that msg 'XX volumes found' has been issued     *"
echo "*                                                                      *"
echo "*           ===>    Press enter to continue                            *"
echo "*                                                                      *"
echo "************************************************************************"
read aa
if [[ $rep = 'y' || $rep = 'Y' || $rep = 'yes'  ]]
   then 
$tsm update vol ML00* access=reado  > /dev/null 2>&1 
$tsm register lic file=tsmee.lic  > /dev/null 2>&1
$tsm upd devc MAINLIB_DVC libr=DRMAINLIB  > /dev/null 2>&1
$tsm del vol /tsmpool1/smfi_1.dsm discarddata=yes wait=yes  > /dev/null 2>&1
$tsm def vol  smfi_d_prp /tsmpool1/smfi_1.dsm  > /dev/null 2>&1
echo \n \n 
echo "************************************************************************"
echo "*                                                                      *"
echo "*                ${rev} TSM server refresh completed ${unrev}                        *"
echo "*                                                                      *"
echo "************************************************************************"
fi 
