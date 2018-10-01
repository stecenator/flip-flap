#!/usr/bin/perl -w
# resurect.pl 
# wersja 0.1
# 
# 
#     -----   To jest bardzo testowy skrypt -----
#
#       Ograniczenia:
#               - Wznawianie działania tylko WAW2-SRV02 na WAW5-SRV02
#               - HADR failover musi być zrobion wcześniej i TSM podniesiony 

# Kosmetyka 
our $debug = 1;
our $verbose = 1;

# Połączenia
our $admin="ibm";
our $pass="ibm123";
our $dsmadmc="dsmadmc -id=$admin -pa=$pass -dataonly=yes -comma ";

# Dane globalne
our @lib_paths=();
our @libs=();
our @drives=();
our %DR_drives= ();

sub gen_drv_hash($$$$)                          # generuje hash do podstawienia napędów
# napędy = (
#        prefix1nrX -> prefix2nrX
#        ...
#)
{
        my %drives = ();
        my $prefix = shift;
        my $prefixDR = shift;
        my $start = shift;
        my $end = shift;
        for(my $i=$start; $i<=$end; $i++)
        {
                $drives{"$prefix$i"} = "$prefixDR$i";
        }
        return %drives;
}

sub get_libs()                                  # zwraca tablicę bibliotek. Atrybuty biblioteki po atrybutach ściezki
{
        my @all_libs = ();
        my $cmd=$dsmadmc."\"select LIBRARY_NAME,LIBRARY_TYPE,SHARED,AUTOLABEL,LIBRARY_SERIAL,RESETDRIVES,RELABELSCRATCH from libraries\"";
        open(LIBS, "$cmd|") or die "Nie mogę uruchomić dsmadmc z poleceniem $cmd\n";
        while(<LIBS>)
        {
                next if /^$/;                   # Bo czasem daje puste linie 
                chomp;
                my @lib = split /,/;
                push(@all_libs, [@lib]);
        }
        close(LIBS);
        return @all_libs;
}


sub get_lib_paths()                             # zwraca tablice tablic. Wiersz to src, dst, srct, destt, device
{
        my @paths = ();
        my $cmd=$dsmadmc."\"select SOURCE_NAME, DESTINATION_NAME, SOURCE_TYPE, DESTINATION_TYPE, DEVICE from paths where DESTINATION_TYPE='LIBRARY'\"";
        open(PATHS, "$cmd|") or die "Nie mogę uruchomić dsmadmc z poleceniem $cmd\n";
        while(<PATHS>)
        {
                next if /^$/;                   # Bo czasem daje puste linie 
                chomp;
                my @path = split /,/;
                push(@paths, [@path]);
        }
        close(PATHS);
        return @paths;
}

sub get_drv_paths($)                            # zwraca tablicę tablic. Scieżki do napędów dla zadanej biblioteki
{
        my $lib = shift;
        my $cmd=$dsmadmc."\"select SOURCE_NAME, DESTINATION_NAME, SOURCE_TYPE, DESTINATION_TYPE, LIBRARY_NAME, DEVICE from paths where DESTINATION_TYPE='DRIVE' and LIBRARY_NAME='$lib'\"";
        open(PATHS, "$cmd|") or die "Nie mogę uruchomić dsmadmc z poleceniem $cmd\n";
        while(<PATHS>)
        {
                next if /^$/;                   # Bo czasem daje puste linie 
                chomp;
                my @path = split /,/;
                push(@paths, [@path]);
        }
        close(PATHS);
        return @paths;
}

sub get_all_drives()                            # Zwraca tablicę napędów, seriali i elementów
{
        my @drvs = ();
        my $cmd=$dsmadmc."\"select DRIVE_NAME, LIBRARY_NAME, ELEMENT, DRIVE_SERIAL, WWN from drives\"";
        open(DRIVES, "$cmd|") or die "Nie mogę uruchomić dsmadmc z poleceniem $cmd\n";
        while(<DRIVES>)
        {
                next if /^$/;                   # Bo czasem daje puste linie 
                chomp;
                my @drv = split /,/;
                push(@drvs, [@drv]);
        }
        close(DRIVES);
        return @drvs;
}

sub get_lib_drives($)                           # Zwraca tablicę napędów dla biblioteki 
{
        my @drvs = ();
        my $lib = shift;
	if(!@drives)
        {
                @drives = get_all_drives();
        }
	print "get_lib_drives:\t Biblioteka: $lib\n" if $debug;
	foreach my $d (@drives)
	{
		if("${$d}[1]" eq "$lib") 
		{
			push(@drvs, [@{$d}]);
			print "get_lib_drives:\t ".join(";",@{$d})."\n" if $debug;					
		}
	}
	return @drvs;
}

sub print_del_lib_path(@)                       # wypisuje komendę kasowania śćiezki do biblioteki
{
        my @lib_path = @_;
        print "delete path $lib_path[0] $lib_path[1] srct=$lib_path[2] destt=$lib_path[3]\n";
}

sub print_del_drv_path(@)                        # wypisuje komendę kasowania śćieżki do napędu
{
        my @drv_path = @_;
        print "delete path $drv_path[0] $drv_path[1] srct=$drv_path[2] destt=$drv_path[3] libr=$drv_path[4]\n";
}

sub print_del_prod_paths()                      # wypisuje komendy usunięcia produkcyjnej konfiguracji
{
        foreach my $lib (@libs)
        {
                my @drv_paths = get_drv_paths(${$lib}[1]);
                foreach my $drv (@drv_paths)
                {
                        print_del_drv_path(@{$drv});
                }
                print_del_lib_path(@{$lib});
        }
}

sub save_recovery_info($)                       # do zadanego pliku zrzuca informacje o napędach, bibliotekach i 
                                                # ściezkach do usunięcia. Robi to w formie makra zakładającego te rzeczy z powrotem
{
        my $save_file = shift;
        if(!@lib_paths)
        {
             @lib_paths = get_lib_paths();   
        }
        if(!@libs)
        {
                @libs = get_libs();
        }
        if(!@drives)
        {
                @drives = get_all_drives();
        }
        open(SAV, ">$save_file") or die "Nie mogę utworzyć pliku $save_file.\n";
	foreach my $lib (@libs) 
	{
		print SAV "define libr ${$lib}[0] libt=${$lib}[1] shared=${$lib}[2] autolabel=${$lib}[3] resetdrives=${$lib}[5] relabelscr=${$lib}[6]\n";
	}
        foreach my $lib (@lib_paths)
        {
                print SAV "define path ${$lib}[0] ${$lib}[1] srct=${$lib}[2] dest=${$lib}[3] device=${$lib}[4]\n";
                my @drv_paths = get_drv_paths(${$lib}[1]);
		my @lib_drvs = get_lib_drives(${$lib}[1]);
		foreach my $drv (@lib_drvs)
		{
			print SAV "define drive ${$lib}[1] ${$drv}[0] elem=${$drv}[2]\n";
		}
                foreach my $drv (@drv_paths)
                {
                        print SAV "define path ${$drv}[0] ${$drv}[1] srct=server destt=drive libr=${$drv}[4] device=${$drv}[5]\n";
                }
                
        }
        close(SAV);
}

# main
@lib_paths = get_lib_paths();
@libs = get_libs();
@drives = get_all_drives();
%DR_drives = gen_drv_hash("waw5dr-ptdrv", "waw2dr-ptdrv", 2, 65);
save_recovery_info("waw2dr.tsm");               # zrzutka komend służących do odtworzenia konfiguracji 