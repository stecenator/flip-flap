package HADRtools;
use strict;
use warnings;
use lib qw(./ ../toys/lib);
use Gentools qw(verb dbg print_hash error);
use Exporter qw(import);
# exportowane funkcje
our @EXPORT = qw(get_HADR_mode $debug get_HADR_cfg check_DB2_inst set_HADR_cfg 
	is_DB2_active start_HADR_slave start_HADR_master start_DB2 get_HADR_status is_DB_active is_peer_connected
	takeover_HADR_forced stop_DB2 takeover_HADR);
our ($debug, $verbose);

sub is_DB_active($$)
# is_DB_active($user, $baza) - sprawdza czy $baza jest aktywna w instancji $user
# Zwrotka
#	1 - jest 
#	0 - nie jest
{
	my @out = qx/su - $_[0] -c "db2 list active databases"/;
	my $rc = $? >> 8;
	return 0 if $rc == 2;						# Database manager powiedział, że nie ma aktywnych baz
	if ($rc != 0)							# Coś poszło nie tak
	{
		dbg("HADRtools::get_HADR_status", "Wykonanie db2pd na użytkowniku $_[0] nie powiodło się. Kod wyjścia z \"su -c ...\": $rc\n");
		return 0;
	}
	else
	{
		foreach my $line (@out)
		{
			return 1 if uc($line) =~ /$_[1]/;		# bazy są zwracane dużymi litermi
		}
	}
	return 0;							# jak tu jestem, to żadna ze zwróconych baz nie była tą któ©ej szukam.
}

sub get_HADR_status($)
# get_HADR_status("instance_user") - argumentem jest nazwa użytkownika instancji TSM
# Zwrotki:
#	hash z bieżącym statusem HADR. Jak coś jet nie tak, hash jest pusty. To jest STATUS pobierany z db2pd. 
{
	my %ret = ();
	my @out = qx/su - $_[0] -c "db2pd -hadr -db tsmdb1"/;
	my $rc = $? >> 8;
	if ($rc != 0)			# Coś poszło nie tak
	{
		dbg("HADRtools::get_HADR_status", "Wykonanie db2pd na użytkowniku $_[0] nie powiodło się. Kod wyjścia z \"su -c ...\": $rc\n");
	}
	else
	{
		dbg("HADRtools::get_HADR_status", "Wykonanie db2pd na użytkowniku $_[0] powiodło się.\n");
		foreach my $line (@out)
		{
			next if !($line =~ / = /);			# pomijanie śmieci
			chomp $line;
			(my $key, my $val) = split / = /, $line;
			$key =~ s/^\s+|\s+$//g;
			$val =~ s/^\s+|\s+$//g;
			$ret{"$key"} = $val;
		}
	}
	return %ret;
}	

sub start_DB2($)
# start_DB2($user) - wykonuje db2start na userze $user.
# Zwrotka:
#	1 - Start udany
#	0 - Start nie udany
{
	my @out = qx/su - $_[0] -c "db2start"/;
	print "Na wszelki wypadek:\n", @out;
	my $rc = $? >> 8;
	if ($rc != 0)			# Coś poszło nie tak
	{
		dbg("HADRtools::start_DB2", "Komenda \"db2start\" nie powiodła się. Kod wyjścia \"su -c ...\": $rc\n");
		return 0;
	}
	dbg("HADRtools::start_DB2", "su - $_[0] -c \"db2start\" RC = $rc.\n");
	return 1;
}

sub stop_DB2($)
# start_DB2($user) - wykonuje db2start na userze $user.
# Zwrotka:
#	1 - Stop udany
#	0 - Stop nie udany
{
	my @out = qx/su - $_[0] -c "db2stop"/;
	print @out;
	my $rc = $? >> 8;
	if ($rc != 0)			# Coś poszło nie tak
	{
		dbg("HADRtools::stop_DB2", "Komenda \"db2stop\" nie powiodła się. Kod wyjścia \"su -c ...\": $rc\n");
		return 0;
	}
	return 1;
}

sub start_HADR_master($)
# start_HADR_master($user) - startuje bazę w trybie master
# Zwrotka:
#	1 - OK
#	0 - Nie OK.
{
	my @out = qx/su - $_[0] -c "db2 start hadr on db tsmdb1 as primary"/;
	my $rc = $? >> 8;
	if ($rc != 0)			# Coś poszło nie tak
	{
		dbg("HADRtools::start_HADR_master", "Komenda \"db2 start hadr on db tsmdb1 as primary\" nie powiodła się. Kod wyjścia \"su -c ...\": $rc\n");
		return 0;
	}
	dbg("HADRtools::start_HADR_master", "Wykonano: su - $_[0] -c \"db2 start hadr on db tsmdb1 as primary\"\n");
	return 1;
}

sub start_HADR_slave($)
# start_HADR_slave($user) - startuje bazę w trybie slave
# Zwrotka:
#	1 - OK
#	0 - Nie OK.
{
	my @out = qx/su - $_[0] -c "db2 start hadr on db tsmdb1 as standby"/;
	my $rc = $? >> 8;
	if ($rc != 0)			# Coś poszło nie tak
	{
		dbg("HADRtools::start_HADR_slave", "Komenda \"db2 start hadr on db tsmdb1 as standby\" nie powiodła się. Kod wyjścia \"su -c ...\": $rc\n");
		return 0;
	}
	#~ dbg("HADRtools::start_HADR_slave", "su - $_[0] -c \"db2 start hadr on db tsmdb1 as standby\"\n");
	return 1;
}

sub is_DB2_active($)
# is_DB2_Active($istuser) - sprawdza, czy na userze $instuser działają procesy db2sysc.
# Zwrotka:
#	1 - są
#	0 - nie ma.
{
	return 1 if( grep /db2sysc/, qx/ps -u $_[0]/ );
	return 0;
}
	

sub set_HADR_cfg($\%)
# set_HADR_cfg(\%hadr_cfg) - update db cfg. Argumentem jest hash zmienna -> wartość. 
# Zwrotka:
#	hash ze statusem każdej zmiany, np LOCAL_INSTANCE -> OK
{
	my %ret = ();
	my %hadr_cfg = %{$_[1]};
	foreach my $var (keys %hadr_cfg)
	{
		my @out = qx/su - $_[0] -c "db2 update db cfg for tsmdb1 using $var $hadr_cfg{$var}"/;
		my $rc = $? >> 8;
		if ($rc != 0)			# Coś poszło nie tak
		{
			dbg("HADRtools::set_HADR_cfg", "Komenda \"db2 update db cfg for tsmdb1 using $var $hadr_cfg{$var}\" nie powiodła się. Kod wyjścia \"su -c ...\": $rc\n");
			$ret{"$var"} = "Qpa!";
		}
		else
		{
			$ret{"$var"} = "OK";
		}
		#~ dbg("HADRtools::set_HADR_cfg", "Wykonuję: \"db2 update db cfg for tsmdb1 using $var $hadr_cfg{$var}\"\n");
		#~ $ret{"$var"} = "OK";
	}
	
	return %ret;
}

sub check_DB2_inst($)
# check_DB2_inst($instuser) - sprawdza, czy na $insuser jest instancja DB2. Żeby później nie trzeba bylo sprawdzać, czy można odpalać komendy db2
# Zwrotka:
#	1 - $insuser jest właścicielem instancji
#	0 - nie jest.
{
	my $uid = getpwnam($_[0]);
	dbg("HADRtools::check_DB2_inst", "Użyszkodnik $_[0] ma UID: $uid.\n");
	if($uid > 0 )
	{
		my @out = qx/su - $_[0] -c "db2ilist"/;
		my $rc = $? >> 8;
		if ($rc != 0)			# Coś poszło nie tak
		{
			dbg("HADRtools::check_DB2_inst", "Użyszkodnik $_[0] nie jest właścicielem instancji DB2. Kod wyjścia z \"su -c ...\": $rc\n");
			return 0;
		}
		else
		{
			chomp @out;
			dbg("HADRtools::check_DB2_inst", "Znaleziono insancję $out[0] na koncie użyszkodnika $_[0].\n");
			return 1;
		}
	}
	dbg("HADRtools::check_DB2_inst", "Użytkownik $_[0], jest niewłaściwy. Może go nie ma?\n");
	return 0;
}

sub get_HADR_cfg($)
# get_HADR_cfg("instance_user") - argumentem jest nazwa użytkownika instancji TSM
# Zwraca:
#	hash z db2 get db cfg for tsmdb1 z konfiguracją hadra + logindexbould. Konfiguracja HADR bazy, ale nie jej bieżący status HADR!
{
	my %ret =();
	my $uid = getpwnam($_[0]);
	dbg("HADRtools::get_HADR_cfg", "Użyszkodnik $_[0] ma UID: $uid.\n");
	if($uid > 0 )
	{
		my @out = qx/su - $_[0] -c "db2 get db cfg for tsmdb1"/;
		my $rc = $? >> 8;
		if ($rc != 0)			# Coś poszło nie tak
		{
			error("HADRtools::get_HADR_cfg", "Wykonanie db2 get db cfg for tsmdb1 na użytkowniku $_[0] nie powiodło się. Kod wyjścia z \"su -c ...\": $rc\n", 0);
			if( $rc == 4 ) 
			{
				error("HADRtools::get_HADR_cfg", "Manager bazy danych nie został wystartowany.\n", 9);		# 9 - kod z HADRsetup oznaczający brak managera bazy danych
			}
		}
		else
		{
			dbg("HADRtools::get_HADR_cfg", "Wykonanie db2 get db cfg for tsmdb1 na użytkowniku $_[0] powiodło się.\n");
			foreach my $line (@out)
			{
				chomp $line;
				#~ dbg("get_HADR_mode", "$line");
				if($line =~ /HADR database role *= (.*$)/)	# Wyciągam atrybut konifguracji HADRdatabase role bo ten atrybut jest nietypowy
				{
					$ret{"ROLE"} = "$1";			# Buduję hasha HADR_COŚTAM -> Wartość Sprawdzić czy nie trzeba chomp($2)
					dbg("HADRtools::get_HADR_cfg", "ROLE -> $1\n");
					next;
				}
				
				if($line =~ /(HADR_SPOOL_LIMIT)\) = (.*)\(/)	# Wyciągam atrybuty konifguracji HADR_SPOOL_LIMIT bo ten atrybut jest nietypowy
				{
					$ret{"$1"} = "$2";			# Buduję hasha HADR_COŚTAM -> Wartość Sprawdzić czy nie trzeba chomp($2)
					dbg("HADRtools::get_HADR_cfg", "$1 -> $2\n");
					next;
				}
				
				if($line =~ /(HADR_\w+)\) = (.*$)/)		# Wyciągam atrybuty konifguracji HADR
				{
					if("$2" eq "")				# Buduję hasha HADR_COŚTAM -> Wartość  - Wartość nie może być pusta bo się pierdoli w hashu
					{
						$ret{"$1"} = "NONE";
					}
					else
					{
						$ret{"$1"} = "$2";
					}
					
					dbg("HADRtools::get_HADR_cfg", "$1 -> ".$ret{"$1"}."\n");
					next;
				}
				if($line =~ /(LOGINDEXBUILD)\) = (.*$)/)
				{
					$ret{"$1"} = "$2";			# Dokładam LOGINDEXBUILD bo to ważna dla HADRa Sprawdzić czy nie trzeba chomp($2)
					dbg("HADRtools::get_HADR_cfg", "$1 -> $2\n");
				}
				#~ dbg("HADRtools::get_HADR_cfg", "Niepasująca linia: $line\n");
			}
		}
	}
	return %ret;
}

sub get_HADR_mode($)
# check_HADR_mode("instance_user") - argumentem jest nazwa użytkownika instancji TSM
# Zwrotki:
#	1 - Instancja jest HADR master
#	2 - Instancja jest HADR slave
#	0 - Instancja jest standalone
#	-1 - Niewłaściwy user, albo go nie ma
#	-2 - Nie ma instnacji DB2 na podanym userze.
{
	my $ret;
	my $uid = getpwnam($_[0]);
	dbg("HADRtools::get_HADR_mode", "Użyszkodnik $_[0] ma UID: $uid.\n");
	if($uid > 0 )
	{
		my @out = qx/su - $_[0] -c "db2pd -hadr -db tsmdb1"/;
		my $rc = $? >> 8;
		if ($rc != 0)			# Coś poszło nie tak
		{
			dbg("HADRtools::get_HADR_mode", "Wykonanie db2pd na użytkowniku $_[0] nie powiodło się. Kod wyjścia z \"su -c ...\": $rc\n");
			$ret=-2;
		}
		else
		{
			dbg("HADRtools::get_HADR_mode", "Wykonanie db2pd na użytkowniku $_[0] powiodło się.\n");
			$ret=15;			# nachwilę
			foreach my $line (@out)
			{
				#~ dbg("get_HADR_mode", "$line");
				if($line =~ /HADR_ROLE/)		# Dokopałem się do statusu HADR
				{
					my $tmp;
					my $hadr_role;
					chomp $line;				# bo się chcrzani w porównanianiach 
					($tmp, $hadr_role) = split / = /, $line;
					dbg("HADRtools::get_HADR_mode", "Wykryty tryb HADR: $hadr_role.\n");
					if( "$hadr_role" eq "STANDBY" )
					{
						dbg("HADRtools::get_HADR_mode", "Kod wyjścia 2, STANDBY\n");
						return 2;
						#~ last;
					}
					elsif ( "$hadr_role" eq "PRIMARY" )
					{
						dbg("HADRtools::get_HADR_mode", "Kod wyjścia 1, PRIMARY\n");
						return 1;
						#~ last;
					}
				}
				if($line =~ /HADR is not active/)	# HADR jest nieskonfigurowany
				{
					dbg("HADRtools::get_HADR_mode", "Kod wyjścia 0, STANDALONE\n");
					$ret = 0;
					last;
				}
			}
		}
	}
	else
	{
		dbg("HADRtools::get_HADR_mode","Nie znaleziono użytkownika $_[0].\n");
		$ret = -1;
	}
	return $ret;
}	

sub is_peer_connected($)
# Sprawdza, czy peer ma status connected
{
	my $instuser = shift;
	my %status = get_HADR_status("$instuser");
	dbg("HADRtools::is_peer_connected", "Status partnera: ".$status{"HADR_CONNECT_STATUS"}."\n");
	if( $status{"HADR_CONNECT_STATUS"} eq "CONNECTED")
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

sub takeover_HADR_forced($$)
# wykonuje na uzerze $_[1] komendę db2 takeover hadr on db $_[2] by force.
# Zwrotki:
#	1 - Udało się
#	0 - Nie udało się
{
	my @out = qx/su - $_[0] -c "db2 takeover hadr on db $_[1] by force"/;
	my $rc = $? >> 8;
	if ($rc != 0)			# Coś poszło nie tak
	{
		dbg("HADRtools::takeover_HADR_forced", "Wykonanie \"db2 takeover hadr on db $_[1] by force\" na użytkowniku $_[0] nie powiodło się. Kod wyjścia: $rc\n");
		return 0;
	}
	return 1;			# Udało się!
}

sub takeover_HADR($$)
# wykonuje na uzerze $_[1] komendę db2 takeover hadr on db $_[2]
# Zwrotki:
#	1 - Udało się
#	0 - Nie udało się
{
	my @out = qx/su - $_[0] -c "db2 takeover hadr on db $_[1]"/;
	my $rc = $? >> 8;
	if ($rc != 0)			# Coś poszło nie tak
	{
		dbg("HADRtools::takeover_HADR_forced", "Wykonanie \"db2 takeover hadr on db $_[1]\" na użytkowniku $_[0] nie powiodło się. Kod wyjścia: $rc\n");
		return 0;
	}
	return 1;			# Udało się!
}

1;					# Bo tak kurwa ma być
