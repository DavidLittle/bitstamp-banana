use feature qw(state say);
#use warnings;
use English;
use strict;
use DateTime;
# https://github.com/DavidLittle/bitstamp-banana.git
use Text::CSV_XS qw(csv);
use Data::Dumper;
use Storable qw(dclone);

# Process an Etherscan.io export CSV file so that it is conveniently usable as a spreadsheet or as an import into an accounting system
# Program works in several stages:
# First, process the Etherscan export parsing the dates and times into DateTime objects and splitting fields that have numbers and currencies
#       also do the account mapping to Banana Credit and Debit accounts. Put the results into an array of hashes called $data1
# Third, loop again through the $data1 records processing fees - Fee records are accumulated to one Fee line per month. Results are appended to $data2

# TBD - process USD/GBP exchange rates cable.dat

my $data1; # parsed input CSV file, with mapped banana account codes
my $data2; # consecutive Buy and Sell records accumulated over 24 hour window
my $data3; # fee records appended

my $owner = "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
my $cablefile = "Cable.dat";
my $cable = {}; # hash keyed on date containing daily USD/GBP exchange rates
my %BananaMapping = (
    "David,BTC" => 10100,
);

my $start = "0x34a85d6d243fb1dfb7d1d2d44f536e947a4cee9e";
my $DataDir = "/home/david/Dropbox/Investments/Ethereum/Etherscan";
my $adf = "$DataDir/AddressDescriptions.dat";
my $transactions = undef; # Transactions
my $balances;
my $done = {"GENESIS" => 1}; # Used to avoid reprocessing addresses and transactions that have already been done (and processed)

# Ethereum addresses are hexadecimal and not case sensitive. But case is used to help avoid mistyping addresses. 
# For our purposes we want all addresses to be lowercase all the time. This renames export files forcing lowercase
my @files = glob "$DataDir/export-*.csv";
foreach my $f (@files) {
	$f =~s|.*/||; #basename only - allow mixed case for directory elements
	my $lcf = lc $f;
	rename "$DataDir/$f", "$DataDir/$lcf" if $f ne $lcf;
}
	

# addressDesc returns the description for an address as loaded from the AddressDescriptions.dat file
sub addressDesc {
	state $desc = undef; # Descriptions keyed on address
	my $address = shift;
	$address = lc $address; # force lowercase for lookups
	if (not defined $desc) {
		my $ad  = csv( in => $adf, headers => "auto", filter => {1 => sub {length > 1} } );
		foreach my $rec (@$ad) {
			$rec->{Address} = lc $rec->{Address}; # force lowercase
			$desc->{$rec->{Address}} = $rec->{Desc};
			if ($rec->{Follow} eq 'N') {
				$done->{$rec->{Address}} = 1 ; # pretend we've already done and therefore processed this address
			}
		}
	}
	return $desc->{$address};
}

sub readEtherscan { # take an address return a pointer to array of hashes containing the transactions found on that address
	my $address = shift;
	$address = lc $address;
	my $aoh = [];
	return $aoh if $done->{$address};
	$done->{$address} = 1;

	my $f = "$DataDir/export-$address.csv";
	if (-e $f) {
		$aoh = csv( in => $f, headers => "auto");
		push @$transactions, @$aoh;
	}
	else {
		say "Missing file $f " . addressDesc($address);
	}
	
	foreach my $tran (@$aoh) {
		my ($to, $from) = ($tran->{To}, $tran->{From});
		my $dt = DateTime->from_epoch( epoch => $tran->{UnixTimestamp} );
		$tran->{T} = $dt->dmy("/") . " " . $dt->hms();
		$tran->{ToDesc} = addressDesc($to) || "Unknown";
		$tran->{FromDesc} = addressDesc($from) || "Unknown";
		$tran->{ToS} = substr($tran->{To},0,6);
		$tran->{FromS} = substr($tran->{From},0,6);

		readEtherscan($from) unless $done->{$from};
		readEtherscan($to) unless $done->{$to};
	}
			
	return;
}

sub calcBalances {
	my $processed;
	foreach my $t (sort {$a->{UnixTimestamp} <=> $b->{UnixTimestamp}} @$transactions) {
		next if $processed->{$t->{Txhash}};
		$processed->{$t->{Txhash}} = 1;

		#tbd - PROCESS FEES
		next if $t->{Status} eq 'Error(0)'; # Typically out of gas (make sure fees are processed but principal is not.
		$balances->{$t->{From}} -= $t->{'Value_IN(ETH)'};
		$balances->{$t->{From}} -= $t->{'Value_OUT(ETH)'};
		$balances->{$t->{To}} += $t->{'Value_IN(ETH)'};
		$balances->{$t->{To}} += $t->{'Value_OUT(ETH)'};
		my $address = lc "0x0aFa235C9D6a59c227Be92995b7E55a4dbC9cC19";
		say "balance $t->{T} $balances->{$address} $t->{Txhash}" if ($t->{From} eq $address || $t->{To} eq $address);
		
	}
}

sub printBalances {
	foreach my $b (sort keys %$balances) {
		my $desc = addressDesc($b);
		next if $desc eq 'ShapeShift';
		say "$b $balances->{$b} $desc";
	}
}

sub printTransactions {
	foreach my $t (sort {$a->{UnixTimestamp} <=> $b->{UnixTimestamp}} @$transactions) {
		next if $done->{$t->{Txhash}};
		print "$t->{T} $t->{FromS} $t->{FromDesc} $t->{'Value_IN(ETH)'} $t->{'Value_OUT(ETH)'} $t->{ToS} $t->{ToDesc}\n";
		$done->{$t->{Txhash}} = 1;
	}
}

print "Start address $start\n";
addressDesc($start); # initialise the addresses
readEtherscan($start);
calcBalances();
printBalances();
#printTransactions();
#print Dumper $done;

#print Dumper $transactions;
#print Dumper $desc;
#foreach my $a ( keys %$done) {
#	next if addressDesc($a);
#	next if length($a) > 40;
#	print "$a,ShapeShift,N\n";
#}

