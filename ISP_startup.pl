#!/usr/bin/perl -w
###############################################################################
#                                                                             #
#   Konfiguracja HADR na instancji IBM Spectrum Protect                       #
#                                                                             #
#     marcin_stec@pl.ibm.com                                                  #
#                                                                             #
###############################################################################
#                                                                             #
#  Kody powrotu z tego skrptu:                                                #
#   0   - Wszystko git                                                        #
#   1   - Nie podano trybu pracy                                              #
#   2   - Niepoprawna opcja                                                   #
#   3   - Nipoprawny tryb pracy                                               #
#   4   - Nie znaleziono insancji db2 dla $instuser                           #
#   5   - Podano nieprawidłowego użytkownika instancji                        #
#   6   - Skrypt uruchomiono jako nie root                                    #
#   7   - Nie podano nazwy hosta partnera                                     #
#   8   - Podano niepoprawny port do replikacji                               #
#   9   - Baza nieaktywna a powinna być uruchomona                            #
#  10   - Przerwane przez użyszkodnika                                        #
#  11   - ISP Działa, a powinien być zatrzymany                               #
#  12   - Niepoprawna konfiguracja HADR                                       #
#  13   - Nie udało się uruchomić slave                                       #
#  14   - Nie udało się uruchomić database managera                           #
#  15   - Katalog instancji niewłaściwy lub niedostępny                       #
#  16   - Baza działa, ale nie w trybie master                                #
#  17   - Nie udało się uruchomić TSMa                                        #
#                                                                             #
###############################################################################
use Getopt::Std;
use strict "vars";
use lib './;../toys';								# żeby można było rzrobić use Moduł z pliku Moduł.pm w biezacym katalogu
use HADRtools;	
use Toys;
use ISPtools;
# Kosmetyka 
our $debug = 0;
our $verbose = 0;
our $my_name = $0;
our %opts;
our %hadr_cfg =();
our $instuser = "tsminst1";							# Użyszkodnik instancji
our $instdir = "/tsm/tsminst1/";							# Domyślny katalog instancji tsm
our $mode="";

# Wyświetla help do programu.
sub help($)
{
	print "Użycie: $my_name [-v] [-h] [-d] -m master|slave|show [-u użyszkodnik] [-i inst_dir]\n";
	print " -m: tryb startu:\n";
	print "  master: Uruchmiana instancja będzie masterem.\n";
	print "  slave: Uruchamiana instancja będzie slave.\n";
	print "  takeover: Grzecznie przełącza uruchomioną instancję slave na master.\n";
	print "  failover: Brutalnie uruchomioną instancję slave na master. Używać w razie awarii mastera!!!.\n";
	print "  show: Podaje bieżącą konfigurację HADR.\n";
	print "  status: Podaje bieżący status HADR.\n";
	print " -u użytkownik: Zmiana domyślnego użytkownika instancji  ISP/HADR.\n";
	print " -i inst_dir: Katalog instancji serwera.\n";
	print " -v: gadatliwie\n";
	print " -d: debug, czyli jeszcze bardziej gadatliwie\n";
	print " -h: Wyświetla pomoc, czyli ten kominikat :-P\n";
	exit($_[0]);
}

sub setup()
# Parsowanie wiersza poleceń i ogólen sprawdzanie poprawności.
{
	if($< != 0)
	{
		print STDERR "Ten program musi być uruchomiony jako uzytkownik root.\n";
		help(6);
	}
	getopts("vdhm:u:i:",\%opts) or help(2);
	if(defined $opts{"d"}) 
	{ 
		$debug =1;
		$HADRtools::debug=1;			# Bo debug w HADRtools jest w innym package
		$ISPtools::debug=1;			# Bo debug w ISPtools jest w innym package
		$Toys::debug=1;				# Bo debug w Toys jest w innym package
		dbg("MAIN::setup","Włączono tryb debug.\n");
	}
	if(defined $opts{"v"}) 
	{ 
		$verbose =1; 
		$HADRtools::verbose=1;			# Bo debug w HADRtools jest w innym package
		$ISPtools::verbose=1;			# Bo debug w ISPtools jest w innym package
		$Toys::verbose=1;			# Bo debug w Toys jest w innym package
		dbg("Main::setup","Włączono tryb verbose.\n");
	}
	if(defined $opts{"h"}) { help(0); }
	if(defined $opts{"m"})
	{
		$mode = $opts{"m"};
		if("$mode" ne "master" and "$mode" ne "slave" and "$mode" ne "show" and "$mode" ne "status" and "$mode" ne "takeover" and "$mode" ne "failover")
		{
			print STDERR "Błędny tryb pracy: $mode. Poprawny tryb to master, slave, takeover, failover, status lub show.\n";
			exit(3);
		}	
	}
	else
	{
		print STDERR "Nie podano trybu pracy. Nie wiem co robić. Może na początek -h?\n";
		exit(1);
	}
		
	if(defined $opts{"u"})
	{
		$instuser = $opts{"u"};
		dbg("Main::setup", "Zmieniono domyslnego użytkownika instancji na $instuser.\n");
		verbose("Uzytkownik instancji ISP/DB2: $instuser.\n");
		my $uid = getpwnam("$instuser");
		if(defined $uid) 
		{
			dbg("Main::setup","Użyszkodnik $instuser istnieje.\n");
		}
		else
		{
			print STDERR "Użytkownik $instuser nie istnieje.\n";
			exit 5;
		}
	}
	
	if(defined $opts{"i"})
	{
		$instdir = $opts{"i"};
		dbg("Main::setup", "Zmieniono domyslną ścieżkę katalogu instancji na $instdir.\n");
		$instdir =~ s/(.*)\//$1/;
		verbose("Katalog instancji instancji ISP: $instdir.\n");
	}
	
	verbose("Sprawdzanie poprawności użyszkodnika $instuser... ");
	if(check_DB2_inst("$instuser"))
	{
		verbose("OK\n");
	}
	else
	{
		verbose("Qpa!\n");
		print STDERR "Użytkownik $instuser nie jest właścicielem instancji DB2.\n";
		exit(4);
	}
	
	verbose("Sprawdzanie czy plik $instdir/dsmserv.opt jest dostępny... ");
	if( -r "$instdir/dsmserv.opt" )
	{
		verbose("Tak\n");
	}
	else
	{
		verbose("Nie\n");
		if("$mode" eq "master")
		{
			print STDERR "Plik $instdir/dsmserv.opt musi być dostępny przy uruchamianiu w trybie master.\n";
			exit(15);
		}
	}
	
	dbg("Main::setup","Tryb: $mode\n");
}

#main
# Galanteria
setup();

# DB2 musi być wystartowane zawsze.
if(!is_DB2_active("$instuser"))						
{
	verbose("Starowanie database managera... ");
	if(start_DB2("$instuser"))
	{
		verbose("OK\n");
	}
	else
	{
		verbose("Qpa!\n");
		print STDERR "Nie udało się wystartować database managera na użyszkodniku $instuser (komenda db2start).\n";
		exit(14);
	}
}
else
{
	verbose("Manager bazy danych jest już uruchomiony.\n");
}

# Baza wystartowana, sciągam konfig HADRa
%hadr_cfg = get_HADR_cfg("$instuser");
if(!%hadr_cfg)
{
	print STDERR "Nie można pobrać konfiguracji HADR!\n";
	exit(12);
}

# Startuję w trybie mastera
if($mode eq "master")
{
	# W trybie master chcemy mieć najpierw pasywną maszynę	
	exit(10) if !yes_no("Czy instancja $instuser na ".$hadr_cfg{"HADR_REMOTE_HOST"}." jest uruchomiona w trybie slave?", "N");
	
	verbose("Sprawdzanie, czy $instuser/TSMDB1 jest już aktywna... ");
	if(is_DB_active("$instuser","TSMDB1"))
	{
		verbose("Tak\n");
		verbose("Sprawdzenie biezącego trybu HADR bazy $instuser/TSMDB1... ");
		my $hadr_mode = get_HADR_mode("$instuser");
		if( $hadr_mode == 0)
		{	
			verbose("Standalone\n");
			print STDERR "Baza $instuser/TSMDB1 działa, ale w trybie samodzielnym.\n";
			exit(16);
		}
		elsif ( $hadr_mode == 2 )
		{	
			verbose("Slave\n");
			print STDERR "Baza $instuser/TSMDB1 działa, ale jako HADR slave.\n";
			print STDERR "Żeby przełączyć klaster na tę instancję użyj polecenia $my_name -m takeover.\n";
			exit(16);
		}
		elsif ( $hadr_mode == 1 )
		{
			verbose("Master\n");
		}
		else
		{
			verbose("Nieznany\n");
			print STDERR "Nie udało się określić trybu pracy bazy $instuser/TSMDB1. Być może warto użyć trybu debug (-d).\n";
			exit(16);
		}
	}
	else
	{
		verbose("Nie\n");
		verbose("Uruchamianie bazy $instuser/TSMDB1 w trybie master... ");
		if(start_HADR_master($instuser))
		{
			verbose("OK.\n");
		}
		else
		{
			verbose("Qpa!\n");
			print STDERR "Uruchomienie bazy $instuser/TSMDB1 w trybie master nie powodło się.\n";
			exit(13);
		}
	}
	# Na tym etapie baza TSMDB1 jest aktywowana jako HADR master.
	verbose("Startowanie instancji IBM spectrum Protect: $instuser... ");
	if(start_ISP("$instuser"))
	{
		verbose("OK\n");
		exit(0)
	}
	else
	{
		verbose("Qpa!\n");
		print STDERR "Nie udało się uruchomić instancji $instuser IBM Spectrum Protect.\n";
		exit(17);
	}
}
elsif($mode eq "slave")
{
	verbose("Uruchamianie instancji $instuser w trybie slave... ");
	if(start_HADR_slave($instuser))
	{
		verbose("OK.\n");
	}
	else
	{
		verbose("Qpa!\n");
		print STDERR "Uruchomienie instancji $instuser w trybie slave nie powodło się.\n";
		exit(13);
	}
}
elsif($mode eq "takeover")
{
	verbose("Takeover - durnostojka.\n");
}
elsif($mode eq "failover")
{
	verbose("Failover - Durnostojka.\n");
}
elsif($mode eq "show")
{
	print_hash("Konifugacja HADR bazy TSMDB1 instancji $instuser:", %hadr_cfg);
	exit 0;
}
elsif($mode eq "status")
{
	verbose("Sprawdzanie czy baza $instuser/TSMDB1 jest aktywna... ");
	if(!is_DB_active("$instuser", "TSMDB1"))
	{
		verbose("Nie\n");
		print STDERR "Baza TSMDB1 nie jest aktywna. Status HADR niedostępny.\n";
		exit(9);
	}
	verbose("Tak\n");
	my %hadr_status = get_HADR_status("$instuser");
	print_hash("Status HADR bazy TSMDB1:", %hadr_status);
	exit 0;
}
