use feature qw(state say);
#use warnings;
use English;
use strict;
use Carp;
use DateTime;
# https://github.com/DavidLittle/bitstamp-banana.gitperl Ac
use Text::CSV_XS qw(csv);
use Data::Dumper;
use Storable qw(dclone store retrieve);
use JSON::Parse qw(parse_json json_file_to_perl);
use LWP::Simple;
use vars qw(%opt);
use Getopt::Long;
use Term::ANSIColor;
use lib '.';
use Account;
use Person;
use AccountsList;

# Process Blockchain.info API

# Commandline args
GetOptions('datadir:s' => \$opt{datadir}, # Data Directory address
			'accountsList:s' => \$opt{accountsList}, # AccountsList file
			'desc:s' => \$opt{desc}, # AddressDescriptions file
			'g:s' => \$opt{g}, #
			'h' => \$opt{h}, #
			'key:s' => \$opt{key}, # API key to access etherscan.io
			'newal:s' => \$opt{newal}, # Name of new AddressList file to write
			'owner:s' => \$opt{owner}, #
			'start:s' => \$opt{start}, # starting address
			'trace:s' => \$opt{trace}, # trace hash or address
			'trans:s' => \$opt{trans}, # Blockchain transactions datafile
			'ss' => \$opt{ss}, # Process all ShapeShift transactions to harvest relevant BTC addresses
			'sstrans:s' => \$opt{sstrans}, # Shapeshift transactions datafile
			'trace:s' => \$opt{trace},
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{newal} ||= "AccountsListNew.csv"; # AccountsList file in MySQL format - created by this program
$opt{key} ||= ''; # from etherscan.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
$opt{start} ||= "";
$opt{trans} ||= "BlockchainTransactions.dat";
$opt{sstrans} ||= "ShapeshiftTransactions.dat";


my $url = "https://blockchain.info/";
my $txurl = "${url}rawtx/";
my $addrurl = "${url}rawaddr/";


#accountList - load an AccountsList file extracted from mysql database
sub accountsList {
	my ($address, $field) = @_;
	$field ||= 'Desc'; #  default is to return the description for the given address
	state $desc2 = undef; # Descriptions keyed on address
	$address = lc $address if $address =~ /^0x/; # force lowercase for lookups on Ethereum type addresses
	if (not defined $desc2) {
		my $ad  = csv( in => $opt{accountsList}, headers => "auto", filter => {1 => sub {length > 0} } );
		foreach my $rec (@$ad) {
			if ($opt{trace} and $rec->{AccountRef} =~ /$opt{trace}/i) {
				say "Tracing $rec->{AccountRef}";
			}
			$rec->{AccountRef} = lc $rec->{AccountRef} if $rec->{AccountRef} =~ /^0x/; # force lowercase for lookups on Ethereum type addresses
			if (exists $desc2->{$rec->{AccountRef}}) {
				say "Duplicate address: $rec->{AccountRef}";
				say Dumper $rec;
				say Dumper $desc2->{$rec->{AccountRef}};
			}
			$desc2->{$rec->{AccountRef}} = $rec;
			$rec->{OwnerID} = $rec->{AccountOwner};
			$rec->{AccountOwner} = Person->name($rec->{AccountOwner});
		}
	}
	return $desc2->{$address}{$field} if $address;
	return $desc2;
}

sub printAL {
	my $als = shift;
	my @rows;

	my $csv = Text::CSV_XS->new ({ binary => 0, auto_diag => 1, strict => 1, });

	push @rows, [split(",", "idAccounts,AccountRef,AccountName,Description,AccountOwner,Currency,AccountType,BananaCode,Source,SourceRef,Follow,ShapeShift")];
	foreach my $addr (sort { $als->{$a}{idAccounts} <=> $als->{$b}{idAccounts}} keys %$als) {
		my $al = $als->{$addr};
		my $row = [
			$al->{idAccounts},
			$al->{AccountRef},
			$al->{AccountName},
			$al->{Description},
			$al->{AccountOwner},
			$al->{Currency},
			$al->{AccountType},
			$al->{BananaCode},
			$al->{Source},
			$al->{SourceRef},
			$al->{Follow},
			$al->{ShapeShift}
		];
		push @rows, $row;
	}
	# and write as CSV
	open my $fh, ">:encoding(utf8)", $opt{newal} or die "$opt{newal}: $!";
	$csv->say ($fh, $_) for @rows;
	close $fh or die "$opt{newal}: $!";
}

sub compareOldNew {
	my ($ads, $als) = @_;
	say "Checking that all AD addresses exist as AccountList";
	foreach my $addr (keys %$ads) {
		if (!exists $als->{$addr}) {
#			say "Address $addr missing from new addressList";
			printADRowInALFormat($ads->{$addr});
#			my $al = convertADtoAL($ads->{$addr});
#			say join ',', @$al;
		}
	}
	say "Checking that all AccountList addresses exist in AD file";
	foreach my $addr (keys %$als) {
		if (!exists $ads->{$addr}) {
			say "Address $addr missing from old AddressDescrption file";
		}
	}
	say "Checking that Follow fields are consistent";
	foreach my $addr (keys %$als) {
		next unless defined $ads->{$addr};
		my $old = $ads->{$addr}{Follow};
		$old = 'N' if $old eq "" or $old eq "NULL";
		my $new = $als->{$addr}{Follow};
		$new = 'N' if $new eq "" or $new eq "NULL";
		if ($old ne $new) {
			say "Address $addr Follow old addressDesc:$old new Accounts:$new";
		}
	}
	say "Checking that Owner fields are consistent";
	foreach my $addr (keys %$als) {
		next unless defined $ads->{$addr};
		my $old = $ads->{$addr}{Owner};
		my $new = $als->{$addr}{AccountOwner};
		if ($old ne $new) {
			say "Address $addr Owner old:$old new:$new";
		}
	}
	say "Checking that Desc fields are consistent";
	foreach my $addr (keys %$als) {
		next unless defined $ads->{$addr};
		my $old = $ads->{$addr}{Desc};
		my $new = $als->{$addr}{Description};
		if ($old ne $new) {
			say "Address $addr Description old:$old new:$new";
		}
	}
	say "Checking that AccountName fields are consistent";
	foreach my $addr (keys %$als) {
		next unless defined $ads->{$addr};
		my $old = $ads->{$addr}{AccountName};
		my $new = $als->{$addr}{AccountName};
		if ($old ne $new) {
			say "Address $addr AccountName old:$old new:$new";
		}
	}
}

sub interactiveUpdate {
	my ($ads, $als) = @_;
	say "Interactive update of AccountsList from AddressDesc";
	foreach my $addr (keys %$ads) {
		if (!exists $als->{$addr}) {
#			say "Address $addr missing from new addressList";
			printADRowInALFormat($ads->{$addr});
#			my $al = convertADtoAL($ads->{$addr});
#			say join ',', @$al;
		}
	}
	say "Checking that all AccountList addresses exist in AD file";
	foreach my $addr (keys %$als) {
		if (!exists $ads->{$addr}) {
			say "Address $addr missing from old AddressDescrption file";
		}
	}
	say "Checking that fields are consistent";
	$Term::ANSIColor::AUTORESET = 1; # resets color to default after each newline is printed
	print color 'reset';
	foreach my $addr (sort {$als->{$a}{idAccounts} <=> $als->{$b}{idAccounts}} keys %$als) {
		next unless defined $ads->{$addr};
		next if defined $opt{start} and $als->{$addr}{idAccounts} < $opt{start};
		my $oldf = $ads->{$addr}{Follow};
		$oldf = 'N' if $oldf eq "" or $oldf eq "NULL";
		my $newf = $als->{$addr}{Follow};
		$newf = 'N' if $newf eq "" or $newf eq "NULL";
		my $oldo = $ads->{$addr}{Owner};
		my $newo = $als->{$addr}{AccountOwner};
		my $oldd = $ads->{$addr}{Desc};
		my $newd = $als->{$addr}{Description};
		my $olda = $ads->{$addr}{AccountName};
		my $newa = $als->{$addr}{AccountName};
		my $oldc = $ads->{$addr}{Currency};
		my $newc = $als->{$addr}{Currency};
		my $olds = $ads->{$addr}{ShapeShift};
		my $news = $als->{$addr}{ShapeShift};
		my ($f, $o, $d, $a, $c, $s) = ($oldf, $oldo, $oldd, $olda, $oldc, $olds);
		my $cls = `clear`;
		next if $oldf eq $newf and $oldo eq $newo and $oldd eq $newd and $olda eq $newa and $oldc eq $newc and $olds eq $news;
		my $resp;
		while (1) {
#			say "$cls";
			say "Address $addr   Account number $als->{$addr}{idAccounts}";
			printADRowInALFormat($ads->{$addr});
			printALRowInALFormat($als->{$addr});
			say "";
			if ($oldf ne $newf) {print color 'bold blue';} else {print color 'reset'}
			print sprintf("%15s : %-45s | %-45s | %-45s\n", "Follow", $oldf, $newf, $f);
			if ($oldo ne $newo) {print color 'bold blue';} else {print color 'reset'}
			print sprintf("%15s : %-45s | %-45s | %-45s\n", "Owner", $oldo, $newo, $o);
			print sprintf("%15s : %-45s | %-45s | %-45s\n", "Owner", Person->id($oldo), Person->id($newo), Person->id($o));
			if ($oldd ne $newd) {print color 'bold blue';} else {print color 'reset'}
			print sprintf("%15s : %-45s | %-45s | %-45s\n", "Description", $oldd, $newd, $d);
			if ($olda ne $newa) {print color 'bold blue';} else {print color 'reset'}
			print sprintf("%15s : %-45s | %-45s | %-45s\n", "AccountName", $olda, $newa, $a);
			if ($oldc ne $newc) {print color 'bold blue';} else {print color 'reset'}
			print sprintf("%15s : %-45s | %-45s | %-45s\n", "Currency", $oldc, $newc, $c);
			if ($olds ne $news) {print color 'bold blue';} else {print color 'reset'}
			print sprintf("%15s : %-45s | %-45s | %-45s\n", "ShapeShift", $olds, $news, $s);
			print color 'reset';
			print "\nEnter FODACS, fodacs, b to break, r to return, w to write >";
			$resp = <STDIN>;
			chomp $resp;
			if ($resp =~ /f:(.*)/i) {$resp = ""; $f = $1};
			if ($resp =~ /o:(.*)/i) {$resp = ""; $o = $1};
			if ($resp =~ /d:(.*)/i) {$resp = ""; $d = $1};
			if ($resp =~ /a:(.*)/i) {$resp = ""; $a = $1};
			if ($resp =~ /c:(.*)/i) {$resp = ""; $c= $1};
			if ($resp =~ /s:(.*)/i) {$resp = ""; $s = $1};
			$f = $newf if $resp =~ /f/;
			$o = $newo if $resp =~ /o/;
			$d = $newd if $resp =~ /d/;
			$a = $newa if $resp =~ /a/;
			$c = $newc if $resp =~ /c/;
			$s = $news if $resp =~ /s/;
			$f = $oldf if $resp =~ /F/;
			$o = $oldo if $resp =~ /O/;
			$d = $oldd if $resp =~ /D/;
			$a = $olda if $resp =~ /A/;
			$c = $oldc if $resp =~ /C/;
			$s = $olds if $resp =~ /S/;
			$f = "Y" if $resp =~ /Y/i;
			$f = "N" if $resp =~ /N/i;
			last if $resp =~ /b/i;
		}
		printALRowInALFormat($als->{$addr});
		$als->{$addr}{Follow} = $f;
		$als->{$addr}{AccountOwner} = $o;
		$als->{$addr}{Description} = $d;
		$als->{$addr}{AccountName} = $a;
		$als->{$addr}{ShapeShift} = $s;
		printALRowInALFormat($als->{$addr});
		say "\n";
		return 0 if $resp =~ /r/i; # return without writing results
		return 1 if $resp =~ /w/i; # write results
	}
	return 1; # Write results if we get all the way through
}


sub updateFromFile {
	my ($accountsList, $filename, $fields) = @_;
	my $upd  = csv( in => $filename, headers => "auto", filter => {1 => sub {length > 0} } );
	foreach my $rec (@$upd) {
		my $ac = $rec->{AccountRef};
		next unless $ac and $accountsList->{$ac};
		foreach my $field (@$fields) {
			my $f = $rec->{$field};
			$accountsList->{$ac}{$field} = $f;
		}
	}
}

sub test_account_consistency {
	my $als = shift;
	foreach my $acc (keys %$als) {
		my $a = $als->{$acc};
		my $id = $a->{idAccounts};
		#say "# Check Follow set to Y or N";
		my $f = $a->{Follow};
		warn "$acc Follow = $f" unless $f eq 'Y' or $f eq 'N';

		#say "# Test All ShapeShift inputs are owned by ShapeShift";
		my $o = $a->{Owner}->name;
		my $ss = $a->{ShapeShift};
		warn "$id,$acc Owner $o ShapeShift $ss" if $ss eq 'Input' and $o ne 'ShapeShift';

		#say "# Test All ShapeShift outputs are NOT owned by ShapeShift";
		my $o = $a->{Owner}->name;
		my $ss = $a->{ShapeShift};
		warn "$id,$acc Owner $o ShapeShift $ss" if $ss eq 'Output' and $o eq 'ShapeShift';

		#say "# Check -bch and -etc properly unique";
		if ($a->AccountRef ne $a->AccountRefUnique) {
			my $pair = $als->{$a->{AccountRef}};
			if ($a->AccountRef eq $pair->AccountRef and $a->{Currency} eq $pair->{Currency}) {
				warn "Duplicate entries: $a->{idAccounts} $a->{AccountRef} and $pair->{idAccounts} $pair->{AccountRef}";
			}
		}

	}
}



# Main program
my $al = AccountsList->new()->accounts;
test_account_consistency($al);
#compareOldNew($ad, $al);
#updateALFromAD($ad, $al);
#my $result = interactiveUpdate($ad, $al);
#updateFromFile($al,"/home/david/Downloads/JaxxAddresses.csv",["AccountOwner","Currency","AccountName","Description"]);
#printAL($al);
