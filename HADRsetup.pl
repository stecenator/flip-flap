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
#                                                                             #
###############################################################################
use Getopt::Std;
use strict "vars";
use lib './';									# żeby można było rzrobić use Moduł z pliku Moduł.pm w biezacym katalogu
# Moje moduły
#~ use HADRtools qw(get_HADR_mode get_HADR_cfg check_DB2_inst set_HADR_cfg);	# Bo nie chce wciągać wszystkich exportowanych funkcji
use HADRtools;	
use Gentools qw(verb dbg print_hash);
use ISPtools;
# Kosmetyka 
our $debug = 0;
our $verbose = 0;
our $my_name = $0;
our %opts;
our $instuser = "tsminst1";							# Użyszkodnik instancji
our $l_host = `hostname -s`;							# Nazwa lokalnego hosta
chomp $l_host;
our $r_host = "";								# Nazwa partnera
our $hadr_port = 60011;								# Port replikacji. Dla uproszczenia daję taki sam na obu. mimo, że DB2 pozwala na inne.
our $mode="show";								# Tryb pracy.


# Wyświetla help do programu.
sub help($)
{
	print "Użycie: $my_name [-v] [-h] [-d] -m master|slave|show [-u użytkownik] [-l host_lokalny] [-r host_zdalny] [-p port_replikacji]\n";
	print "\t-m:\ttryb konfiguracji:\n";
	print "\t\tmaster:\tKonfigurowana instancja będzie masterem.\n";
	print "\t\tslave:\tKonfigurowana instancja będzie slave.\n";
	print "\t\tshow:\tPodaje bieżącą konfigurację HADR.\n";
	print "\t-u użytkownik:\tZmiana domyślnego użytkownika instancji  ISP/HADR.\n";
	print "\t-l host_loklany:\tLokalna nazwa hosta. Domyślnie `hostname -s`.\n";
	print "\t-r host_zdalny:\tHostname partnera.\n";
	print "\t-p host_zdalny:\tHostname partnera.\n";
	print "\t-v:\tgadatliwie\n";
	print "\t-d:\tdebug, czyli jeszcze bardziej gadatliwie\n";
	print "\t-h:\tWyświetla pomoc, czyli ten kominikat :-P\n";
	exit($_[0]);
}

sub setup()
{
	if($< != 0)
	{
		print STDERR "Ten program musi być uruchomiony jako uzytkownik root.\n";
		help(6);
	}
	getopts("vdhm:u:p:l:r:",\%opts) or help(2);
	if(defined $opts{"d"}) 
	{ 
		$debug =1;
		$HADRtools::debug=1;			# Bo debug w HADRtools jest w innym package
		$ISPtools::debug=1;			# Bo debug w ISPtools jest w innym package
		$Gentools::debug=1;				# Bo debug w Toys jest w innym package
		dbg("setup","Włączono tryb debug.\n");
	}
	if(defined $opts{"v"}) 
	{ 
		$verbose =1; 
		$HADRtools::verbose=1;			# Bo debug w HADRtools jest w innym package
		$ISPtools::verbose=1;			# Bo debug w ISPtools jest w innym package
		$Gentools::verbose=1;			# Bo debug w Toys jest w innym package
		dbg("setup","Włączono tryb verbose.\n");
	}
	if(defined $opts{"h"}) { help(0); }
	if(defined $opts{"m"})
	{
		$mode = $opts{"m"};
		if("$mode" ne "master" and "$mode" ne "slave" and "$mode" ne "show")
		{
			print STDERR "Błędny tryb pracy: $mode. Poprawny tryb to master, slave lub show.\n";
			exit(3);
		}
		if("$mode" eq "master" or "$mode" eq "slave")
		{
			if(defined $opts{"r"}) 
			{
				$r_host = $opts{"r"};
				# tu można wstawić kod sprawdzający cy ta maszyna istnieje i żyje
				verb("Ustawiono parntera na $r_host.\n");
			}
			else
			{
				print STDERR "Nazwa zdalnego hosta (partnera) jest obowiązkowa.\n";
				exit(7);
			}
		}	
	}
	else
	{
		print STDERR "Nie podano trybu pracy. Nie wiem co robić. Może na początek -h?\n";
		exit(1);
	}
	
	if(defined $opts{"p"})
	{
		$hadr_port = $opts{"p"};
		if($hadr_port < 1024)			# port jest z dupy
		{
			print STDERR "Podana wartość portu jest nieprawidłowa. Poprawna wartość to liczba z zakresu 1024 do 65536.\n";
			exit(8);
		}
	}
	
	if(defined $opts{"l"})
	{
		$l_host = $opts{"l"};
		verb("Ustawiono lokalny host na $l_host.\n");
	}
	
	if(defined $opts{"u"})
	{
		$instuser = $opts{"u"};
		dbg("Main::setup", "Zmieniono domyslnego użytkownika instancji na $instuser.\n");
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
	
	verb("Sprawdzanie poprawności użyszkodnika $instuser... ");
	if(check_DB2_inst("$instuser"))
	{
		verb("OK\n");
	}
	else
	{
		verb("Qpa!\n");
		print STDERR "Użytkownik $instuser nie jest właścicielem instancji DB2.\n";
		exit(4);
	}
	
	dbg("setup","Host lokalny: $l_host\n");
	dbg("setup","Host zdalny: $r_host\n");
	dbg("setup","Tryb: $mode\n");
	dbg("setup","Port:\t$hadr_port\n");
}

# Main
setup();

if("$mode" eq "show")
{
	my %hadr_cfg = get_HADR_cfg("$instuser");
	verb("Kondiguracja HADR dla tsmdb1, użytkownik $instuser:\n");
	print_hash(%hadr_cfg);
	exit 0;
}

if("$mode" eq "master" or "$mode" eq "slave")
{
	# TSM nie powinien działać
	if(is_ISP_active("$instuser"))
	{
		print STDERR "IBM Spectrum Protect działa. Musi być zatrzymany.\n";
		exit(11);
	}
	
	# Baza powinna działać
	if(!is_DB2_active("$instuser"))
	{
		print STDERR "Baza DB2 nie działa.\nPrzed rekonfiguracją należy upwenić się, że IBM Spectrum Protect jest zatrzymany a database manager jest uruchomiony.\n";
		exit(9);
	}
	
	
	# przerywamy, jeśli nie ma backupu bazy
	exit(10) if !yes_no("Czy jest backup bazy z poziomu TSM i offline backup bazy z poziomu DB2?","t");
	
	my %hadr_cfg = (
		"HADR_LOCAL_HOST" => "$l_host",
		"HADR_REMOTE_HOST" => "$r_host",
		"HADR_LOCAL_SVC" => "$hadr_port",
		"HADR_REMOTE_SVC" => "$hadr_port",
		"HADR_REMOTE_INST" => "$instuser",
		"HADR_SYNCMODE" => "SYNC",
		"LOGINDEXBUILD" => "ON"
		);
	my %hadr_upd_status = set_HADR_cfg($instuser, %hadr_cfg);
	print_hash("Status aktualizacji parametrów HADR:", %hadr_upd_status);
	exit 0;
}
