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
#   4   - Nie znaleziono instancji db2 dla $instuser                          #
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
#  18   - Próba failover przy działającym partnerze                           #
#  19   - Próba failover przy na węźle primary                                #
#  20   - Failover  nie udany                                                 #
#  21   - Takeover nieudany                                                   #
#  22   - DB2 się nie złożyło                                                 #
#  23   - Nie udało się podnieść bazy w trybie HADR master                    #
#  24   - Próba uruchomienia mastera na wężle, który był slave                #
#  25   - Nie udało się przełączyć mastera HADR w stand-alone                 #
#                                                                             #
###############################################################################
use Getopt::Std;
use strict "vars";
use lib qw(./ ../toys/lib);							# żeby można było rzrobić use Moduł z pliku Moduł.pm w biezacym katalogu
use HADRtools;	
use Gentools qw(dbg verb yes_no print_hash check_proc error);
use ISPtools qw(start_ISP is_ISP_active stop_ISP);
# Kosmetyka 
our $debug = 0;
our $verbose = 0;
our $my_name = $0;
our %opts;
our %hadr_cfg =();
our $instuser = "tsminst1";							# Użyszkodnik instancji
our $instdir = "/tsm/tsminst1/";						# Domyślny katalog instancji tsm
our $mode="";
our $isp_pid = -1;
our $ispadm = "admin";								# Administrator ISP.
our $isppass = "ibm123";							# hasło tegoż

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
	print " -a administrator ISP. Domyślnie admin.\n";
	print " -p hasło ISP. Domyślnie ibm12345.\n";
	print " -i inst_dir: Katalog instancji serwera.\n";
	print " -v: gadatliwie\n";
	print " -d: debug, czyli jeszcze bardziej gadatliwie\n";
	print " -h: Wyświetla pomoc, czyli ten kominikat :-P\n";
	exit($_[0]);
}

sub setup()
# Parsowanie wiersza poleceń i ogólne sprawdzanie poprawności.
{
	if($< != 0)
	{
		print STDERR "Ten program musi być uruchomiony jako uzytkownik root.\n";
		help(6);
	}
	getopts("vdhm:u:i:a:p:",\%opts) or help(2);
	if(defined $opts{"d"}) 
	{ 
		$debug =1;
		$HADRtools::debug=1;			# Bo debug w HADRtools jest w innym package
		$ISPtools::debug=1;			# Bo debug w ISPtools jest w innym package
		$Gentools::debug=1;				# Bo debug w Toys jest w innym package
		dbg("MAIN::setup","Włączono tryb debug.\n");
	}
	if(defined $opts{"v"}) 
	{ 
		$verbose =1; 
		$HADRtools::verbose=1;			# Bo verbose w HADRtools jest w innym package
		$ISPtools::verbose=1;			# Bo verbose w ISPtools jest w innym package
		$Gentools::verbose=1;			# Bo verbose w Toys jest w innym package
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
		verb("Uzytkownik instancji ISP/DB2: $instuser.\n");
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
		verb("Katalog instancji instancji ISP: $instdir.\n");
	}
	
	if(defined $opts{"a"})
	{
		$ispadm = $opts{"a"};
		dbg("Main::setup", "Zmieniono domyslnego admina ISP na $ispadm.\n");
		verb("Administrator ISP: $ispadm.\n");
	}
	
	if(defined $opts{"p"})
	{
		$isppass = $opts{"p"};
		dbg("Main::setup", "Zmieniono domyślne hasło admina ISP.\n");
		verb("Zmieniono domyślne hasło admina ISP.\n");
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
	
	verb("Sprawdzanie czy plik $instdir/dsmserv.opt jest dostępny... ");
	if( -r "$instdir/dsmserv.opt" )
	{
		verb("Tak\n");
	}
	else
	{
		verb("Nie\n");
		if("$mode" eq "master")
		{
			print STDERR "Plik $instdir/dsmserv.opt musi być dostępny przy uruchamianiu w trybie master.\n";
			exit(15);
		}
	}
	
	ISPtools::init_module($debug, $verbose, "$ispadm", "$isppass" );
	
	dbg("Main::setup","Tryb: $mode\n");
}

#main
# Galanteria
setup();

# DB2 musi być wystartowane zawsze.
if(!is_DB2_active("$instuser"))						
{
	verb("Starowanie database managera... ");
	if(start_DB2("$instuser"))
	{
		verb("OK\n");
	}
	else
	{
		verb("Qpa!\n");
		print STDERR "Nie udało się wystartować database managera na użyszkodniku $instuser (komenda db2start).\n";
		exit(14);
	}
}
else
{
	verb("Manager bazy danych jest już uruchomiony.\n");
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
	# Nie checę próbować wystartować bazy, która nie  była, lub nie może być masterem.
	
	if( ( $hadr_cfg{"ROLE"} ne "PRIMARY") || ( $hadr_cfg{"ROLE"} ne "STANDARD"))
	{
		error("MAIN::master", "Bieżący host nie był wcześniej masterem. Jeśli wiesz co robisz, użyj operaccji \"failover\".\n", 24);
	}
	
	dbg("MAIN::master", "Rola =".$hadr_cfg{"ROLE"}."\n.");
	
	# W trybie master chcemy mieć najpierw pasywną maszynę	
	exit(10) if !yes_no("Czy instancja $instuser na ".$hadr_cfg{"HADR_REMOTE_HOST"}." jest uruchomiona w trybie slave?", "N");
	
	print "Sprawdzanie, czy $instuser/TSMDB1 jest już aktywna... ";
	if(is_DB_active("$instuser","TSMDB1"))
	{
		print "Tak\n";
		print "Sprawdzenie biezącego trybu HADR bazy $instuser/TSMDB1... ";
		my $hadr_mode = get_HADR_mode("$instuser");
		if( $hadr_mode == 0)
		{	
			print "Standalone\n";
			if( yes_no("Czy przestawić bieżący węzeł w tryb \"master\"?", "N") )
			{
				print "Przełączanie bazy TSMDB1: Standalone -> Master ... ";
				if( !start_HADR_master("$instuser") )
				{
					print " Qpa.\n";
					error("MAIN::master", "Nie udało się przestawić bazy w tryb master.\n", 16);
				}
				print " OK.\n";
			}
			else
			{
				error("MAIN::master", "Użyszkodnik spietrał. Może to i lepiej?\n", 24);
			}
		}
		elsif ( $hadr_mode == 2 )
		{	
			print "Slave\n";
			error("MAIN::master:", "Baza $instuser/TSMDB1 działa, ale jako HADR slave.\n", 0);
			error("MAIN::master:", "Żeby przełączyć klaster na tę instancję użyj polecenia $my_name -m takeover.\n", 16);
		}
		elsif ( $hadr_mode == 1 )
		{
			print "Master\n";
		}
		else
		{
			print "Nieznany\n";
			error("MAIN::master:", "Nie udało się określić trybu pracy bazy $instuser/TSMDB1. Być może warto użyć trybu debug (-d).\n", 16);
		}
	}
	else
	{
		print "Nie\n";
		print "Uruchamianie bazy $instuser/TSMDB1 w trybie master... ";
		if(start_HADR_master($instuser))
		{
			print "OK.\n";
		}
		else
		{
			print "Qpa!\n";
			error("MAIN::master:", "Uruchomienie bazy $instuser/TSMDB1 w trybie master nie powodło się.\n", 13);
		}
	}
	
	# Na tym etapie baza TSMDB1 jest aktywowana jako HADR master.
	print "Startowanie instancji IBM spectrum Protect: $instuser... ";
	if(start_ISP("$instuser", "$instdir"))
	{
		print "OK\n";
		exit(0)
	}
	else
	{
		print "Qpa!\n";
		error("MAIN::master:", "Nie udało się uruchomić instancji $instuser IBM Spectrum Protect.\n", 17);
	}
}
elsif($mode eq "slave")
{
	print "Uruchamianie instancji $instuser w trybie slave... ";
	if(start_HADR_slave($instuser))
	{
		print "OK.\n";
	}
	else
	{
		print "Qpa!\n";
		error("MAIN::slave:", "Uruchomienie instancji $instuser w trybie slave nie powodło się.\n", 13);
	}
	
	print "Jeżeli włączono slave po awarii, upewnij się, że HADR na głównym serwerze jest włączony! \n";
	
}
elsif($mode eq "takeover")
{
	print("Sprawdzanie czy baza $instuser/TSMDB1 jest aktywna... ");
	if(!is_DB_active("$instuser", "TSMDB1"))
	{
		print("Nie\n");
		error("MAIN::takeover:", "Baza TSMDB1 nie jest aktywna. Status HADR niedostępny.\n", 9);
	}
	print("Tak\n");
	
	my %hadr_status = get_HADR_status("$instuser");
	if ( $hadr_status{"HADR_ROLE"} eq "PRIMARY" )		# Jestem na masterze. CZy mam się przygotować do zmiany roli?
	{
		print "Wywołano takeover na serwerze \"master\".\n";
		print "Możesz przygotować go do roli slave.\n";
		print "W ramach przygotowania zostaną wykonane następujące czynności:\n";
		print "*\tZatrzymanie serwera ISP i silnika bazy DB2\n";
		print "*\tStart silnika bazy DB2 (ciągle w trybie \"master\") \n\t- zamiana ról jest inicjowana przez drugą stronę.\n";
		if( !yes_no(" Czy przygotować ten serwer do roli \"slave\"?\n", "N") )
		{
			error("MAIN::failover", "Użyszkodnik spietrał.\n", 10);
		}
		
		# No to Zatrzymujemy TSMa. Razem z nim staje db2, więc trzeba ję będzie póżniej podnieść z powrotem
		print "Zatrzymywanie serwera ISP (DB2 razem z nim)... ";
		if( !stop_ISP() )
		{
			print "Ciągle żyje!\n";
			error("MAIN:takeover_prepare", "Serwer ISP się nie złożył.\n", 11);
		}
		print "Trup.\n";
		
		#Start managera
		print "Startowanie managera DB2...";
		if ( !start_DB2("$instuser") )
		{
			print "Nie udane.\n";
			error("MAIN:takeover_prepare", "Rozruch DB2 nieudany.\n", 14);
		}
		print "OK.\n";
		
		#start HADRa na TSMDB1
		print "Startowanie TSMDB1 jako HADR master... ";
		if( !start_HADR_master("$instuser") )
		{
			print "Nie udane.\n";
			error("MAIN::takeover_prepare", "Rozruch bazy TSMDB1 w trybie HADR master nieudany.\n", 23);
		}
		print "OK.\n";
		
		print "Przygotowanie do \"takeover\" zakończone. Wykonaj teraz tę operację na serwerze \"slave\".\n";
	}
	#Czy jestem na slave?
	elsif ($hadr_status{"HADR_ROLE"} eq "STANDBY" )		# Jestem na slave. Pora się wypromować
	{
	# Czas na ogarnięcie synchronizacji VTL/Storage pool. Zewnętrznymi skryptami!
		if ( !yes_no("Czy failover VTL został już zrobiony?", "N") )
		{
			error("MAIN::failover", "Wcześniej należy dokonać przełączenia VTL na stronę, gdzie przenoszony jest ISP.\n", 10);
		}
	
	#Czy na masterze wykonano takeover_prepare?
		if( !yes_no("Czy na serwerze \"master\" wykonano przygotowanie do \"takeover\"?", "N") )
		{
			error("MAIN::takeover", "Wykonaj najpierw operację \"takeover\" na masterze.\n", 10);
		}
		
	# Czy jestem w stanie PEER, CONNECTED
		if( ($hadr_status{"HADR_STATE"} ne "PEER") || ($hadr_status{"HADR_CONNECT_STATUS"} ne "CONNECTED") )
		{
			error("MAIN::takeover", "Stan połączenia HADR jest niewłaściwy: HADR_STATE = ".$hadr_status{"HADR_STATE"}." HADR_CONNECT_STATUS = ".$hadr_status{"HADR_CONNECT_STATUS"}.".\n", 12);
		}
	
	#Chwila refleksji
		if ( !yes_no("Na pewno przełączać?", "N") )
		{
			error("MAIN::failover", "Przewano na życzenie użyskodnika.\n", 10);
		}
		
	# Takeover HADRa
		print "Promowanie instancji $instuser...";
		if( !takeover_HADR("$instuser", "TSMDB1") )
		{
			print "Nie udane.\n";
			error("MAIN::takeover", "Nie udało się wypromować bazy TSMDB1 w instancji $instuser.\n", 21);
		}
		print "OK.\n";
		
	# Start TSMa w nowej lokalizacji
		print "Startowanie instancji IBM spectrum Protect: $instuser... ";
		if( my $pid = start_ISP("$instuser", "$instdir"))
		{
			verb("OK, pid = $pid\n");
			exit(0)
		}
		else
		{
			verb("Qpa!\n");
			error("MAIN::takeover", "Nie udało się uruchomić instancji $instuser IBM Spectrum Protect.\n", 17);
		}
	}
}
elsif($mode eq "failover")
{
	print("Sprawdzanie czy baza $instuser/TSMDB1 jest aktywna... ");
	if(!is_DB_active("$instuser", "TSMDB1"))
	{
		print("Nie\n");
		print STDERR "Baza TSMDB1 nie jest aktywna. Status HADR niedostępny.\n";
		exit(9);
	}
	print("Tak\n");
	
	my %hadr_status = get_HADR_status("$instuser");
	if ( $hadr_status{"HADR_ROLE"} ne "STANDBY" )
	{
		error("MAIN::failover", "Operację \"failover\" można wykonać wyłącznie na maszynie w trybie STANDBY. Bieżący tryb to ".$hadr_status{"HADR_ROLE"}.".\n", 19);
	}
	
	dbg("MAIN::failover", "Rozpoczynanie operacji failover.\n");
	verb("Rozpoczynanie operacji failover.\n");
	
	# Czy HADR ciągle działa? Nie chcę tego.
	if ( $hadr_status{"HADR_CONNECT_STATUS"} eq "CONNECTED" )
	{
		error("MAIN::failover", "Partner nadal jest podłączony. Użyj funkcji \"takeover\" lub wyłącz mastera.\n", 18);
	}
	
	# Czas na ogarnięcie synchronizacji VTL/Storage pool. Zewnętrznymi skryptami!
	if ( !yes_no("Czy failover VTL został już zrobiony?", "N") )
	{
		error("MAIN::failover", "Wcześniej należy dokonać przełączenia VTL na stronę, gdzie przenoszony jest ISP.\n", 10);
	}
	
	#Chwila refleksji
	if ( !yes_no("Na pewno przełączać?", "N") )
	{
		error("MAIN::failover", "Przewano na życzenie użyskodnika.\n", 10);
	}
	
	#Przełączenie 
	if ( takeover_HADR_forced("$instuser", "TSMDB1") )
	{
		print "Baza TSMDB1 instancji $instuser została przełączona na ten serwer.\n";
	}
	else
	{
		error("MAIN::failover", "Nie udało się wypromować bazy.\n", 20);
	}
	
	if( stop_HADR_master("$instuser") )
	{
		dbg("MAIN::failover", "Zatrzymano HADR na bazie TSMDB1, bo ISP nie umie jej poprawnie wystartować bez dostępu do STANDBY.\n");
	}
	else
	{
		error("MAIN::failover", "Nie udało się wyłączyć HADR na bazie TSMDB1.\n", 25);
	}
	
	#Jeśli tu jestem, to mogę startować TSM
	verb("Startowanie instancji IBM spectrum Protect: $instuser... ");
	if( my $pid = start_ISP("$instuser", "$instdir"))
	{
		verb("OK, pid = $pid\n");
		exit(0)
	}
	else
	{
		verb("Qpa!\n");
		print STDERR "Nie udało się uruchomić instancji $instuser IBM Spectrum Protect.\n";
		exit(17);
	}
	
	print "Failover zakończony.\n";
	print "Po przywróceniu fukcjnonowania uszkodzonego węzła należy:";
	print "\t- Uruchomić uszkodzony węzeł w trybie \"slave\"";
	print "\t- Przywrócić HADR komendą \"$my_name -m master\" na aktywnym  węźle.\n";
}
elsif($mode eq "show")
{
	verb("Konifugacja HADR bazy TSMDB1 instancji $instuser:\n");
	print_hash(%hadr_cfg);
	exit 0;
}
elsif($mode eq "status")
{
	print("Sprawdzanie czy baza $instuser/TSMDB1 jest aktywna... ");
	if(!is_DB_active("$instuser", "TSMDB1"))
	{
		print("Nie\n");
		print STDERR "Baza TSMDB1 nie jest aktywna. Status HADR niedostępny.\n";
		exit(9);
	}
	print("Tak\n");
	my %hadr_status = get_HADR_status("$instuser");
	print("Status HADR bazy TSMDB1:\n");
	print_hash(%hadr_status);
	
	print("Status serwera ISP...");
	$isp_pid = is_ISP_active("$instuser");
	if( $isp_pid > 0 )
	{
		print "Aktywny. PID = $isp_pid\n";
	}
	else
	{
		print "Nie aktywny.\n";
	}
	
	exit 0;
}
