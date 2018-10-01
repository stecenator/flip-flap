#!/usr/bin/perl -w
###############################################################################
#                                                                             #
#   Główny skrypt przełączania IBM Spectrum Protect pomiędzy lokalizacjami    #
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
#   4   - Nie znaleciono insancji HADR dla $instuser                          #
#   5   - Podano nieprawidłowego użytkownika instancji                        #
#   6   - Skrypt uruchomiono jako nie root                                    #
#                                                                             #
#                                                                             #
#                                                                             #
#                                                                             #
#                                                                             #
###############################################################################
use Getopt::Std;
use strict "vars";
use lib './';									# żeby można było rzrobić use Moduł z pliku Moduł.pm w biezacym katalogu
# Moje moduły
use Toys;
use HADRtools qw(get_HADR_mode);						# Bo nie chce wciągać wszystkich exportowanych funkcji
# Kosmetyka 
our $debug = 0;
our $verbose = 0;
our $my_name = $0;
our $mode;
our ($opt_h, $opt_d, $opt_v, $opt_m, %opts);
our $instuser = "tsminst1";							# Użyszkodnik instancji
#~ our $instuser = "marcinek";							# Użyszkodnik instancji

sub dbg($$)
# Komunikat do wyświetlenia, jesli jest włączony tryb debug.
{
	print "$_[0]:\t$_[1]" if $debug;
}

sub verbose($)
# Komunikat do wyświetlenia, jesli jest włączony tryb debug.
{
	print "$_[0]" if $verbose or $debug;
}
sub yes_no($$)
# Zadaje pytanie typu tak/nie podane jako pierwszy argument z defaultem podanym w drugim
# Zwraca:
#    1 - na tak
#    0 - na nie.
{
	my $answer;
	my $ret;
	print "$_[0]\n";
	while(1)
	{
		print "Tak/Nie [$_[1]]: ";
		$answer = <>;
		$answer = "$_[1]" if $answer eq "\n";
		chomp($answer);
		#~ dbg("yes_no", "Odpowiedź: $answer.\n");
		if($answer =~ /(^[TtYy])/)					# Jestem na tak
		{
			$ret = 1;
			last;
		}
		elsif($answer =~ /(^[Nn])/)					# Jestem na nie
		{
			$ret = 0;
			last;
		}
	}
	return $ret;
}

sub help($)
{
	print "Użycie: $my_name [-v] [-h] [-d] -m failover|secondary ]\n";
	print "\t-m:\ttryb pracy. Argument to jeden oprazcja do wykonania:\n";
	print "\t\tfailover:\tWykonanie pełnego przełączenia. Masterem będzie serwer,\n\t\t\t\tna którym uruchomiono ten skrypt.\n";
	print "\t\tsecondary:\tPrzełączenie bieżacy serwera w tryb repliki.\n";
	print "\t-u użytkownik:\tZmiana domyślnego użytkownika instancji  ISP/HADR.\n";
	print "\t-v:\tgadatliwie\n";
	print "\t-d:\tdebug, czyli jeszcze bardziej gadatliwie\n";
	print "\t-h:\tWyświetla pomoc, czyli ten kominikat :-P\n";
	exit($_[0]);
}

sub setup()
# Rzeczy do wykonania na początek. Jakieś ustawianie zmiennych, poprawność wywołania itd.
{
	if($< != 0)
	{
		print STDERR "Ten program musi być uruchomiony jako uzytkownik root.\n";
		exit 6;
	}
	getopts("vdhm:u:",\%opts) or help(2);
	if(defined $opts{"d"}) 
	{ 
		$debug =1;
		$HADRtools::debug=1;			# Bo debug w HADRtools jest w innym package
		dbg("setup","Włączono tryb debug.\n");
	}
	if(defined $opts{"v"}) 
	{ 
		$verbose =1; 
		dbg("setup","Włączono tryb verbose.\n");
	}
	if(defined $opts{"h"}) { help(0); }
	if(defined $opts{"m"})
	{
		$mode = $opts{"m"};
		if("$mode" ne "takeover" and "$mode" ne "secondary")
		{
			print STDERR "Błędny tryb pracy: $mode. Poprawny tryb to takeover lub secondary.\n";
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
		dbg("setup", "Zmieniono domyslnego użytkownika instancji na $instuser.\n");
		my $uid = getpwnam("$instuser");
		if(defined $uid) 
		{
			dbg("setup","Użyszkodnik $instuser istnieje.\n");
		}
		else
		{
			print STDERR "Użytkownik $instuser nie istnieje.\n";
			exit 5;
		}
	}
	else
	{
		dbg("setup", "Nie podano użytkownika instancji. Zostanie użyty domyślny: $instuser.\n");
	}
}
################################################################################
# No i główny program

setup();
if("$mode" eq "takeover")
{
	my $hadr_mode;
	print("Uruchamianie procesu takeover:\n");
	print("Przelączanie HADR na serwerze IBM Spectrum Protect...\n");
	if($hadr_mode=get_HADR_mode("$instuser"))
	{
		verbose("Na użytkowniku $instuser wykryto instancję HADR.\n");
		if($hadr_mode == 1)						# Trafiłem w mastera. Pytanie czy przez pomyłkę?
		{
			if(yes_no("DB2/ISP na tym systemie jest już w trybie master.\nPrzerwać sktypt?", "N"))
			{
				print "Może to i słusznie...\n";
			}
			# Czy MASTER jest zatrzymany?
			# Robimy Promocję HADRa - pewnie jakaś procedura tutaj
		}
	}
	else
	{
		print STDERR "Na użytkowniku $instuser nie wykryto instancji HADR.\n";
		exit 4;
	}
		
	print("Przełączanie na replikę VTL...\n");
	print("Aktualizowanie DNSów...\n");
	print("Jeszcze jakieś chrum-chrum...\n");
}
elsif("$mode" eq "secondary")
{
	print("Przełączanie w tryb secondary\n");
}
