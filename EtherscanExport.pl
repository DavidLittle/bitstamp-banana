use feature qw(state say);
#use warnings;
use English;
use strict;
use DateTime;
# https://github.com/DavidLittle/bitstamp-banana.git
use Text::CSV_XS qw(csv);
use Data::Dumper;
use Storable qw(dclone store retrieve);
use JSON::Parse qw(parse_json json_file_to_perl);
use LWP::Simple;
use vars qw(%opt);
use Getopt::Long;


# Process an Etherscan.io export CSV file so that it is conveniently usable as a spreadsheet or as an import into an accounting system
# Program works in several stages:
# First, process the Etherscan export parsing the dates and times into DateTime objects and splitting fields that have numbers and currencies
#       also do the account mapping to Banana Credit and Debit accounts. Put the results into an array of hashes called $data1
# Third, loop again through the $data1 records processing fees - Fee records are accumulated to one Fee line per month. Results are appended to $data2

# TBD - process USD/GBP exchange rates cable.dat

# Commandline args
GetOptions('d:s' => \$opt{datadir}, # Data Directory address
			'g:s' => \$opt{g}, # 
			'h' => \$opt{h}, # 
			'key:s' => \$opt{key}, # API key to access etherscan.io
			'o:s' => \$opt{owner}, # 
			'start:s' => \$opt{start}, # starting address
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{desc} ||= "AddressDescriptions.dat";
$opt{key} ||= 'TQPWAY66XX2SXFGPTT7677TENHFFQTMGNH'; # from etherscan.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
$opt{start} ||= "0x34a85d6d243fb1dfb7d1d2d44f536e947a4cee9e";

# Global variables
my $data1; # parsed input CSV file, with mapped banana account codes
my $data2; # consecutive Buy and Sell records accumulated over 24 hour window
my $data3; # fee records appended

my $cablefile = "Cable.dat";
my $cable = {}; # hash keyed on date containing daily USD/GBP exchange rates
my %BananaMapping = (
    "David,BTC" => 10100,
);
my $url = "https://api.etherscan.io/api?";
my $txlist = "${url}module=account&action=txlist&startblock=0&endblock=99999999&sort=asc&apikey=$opt{key}"; # add &address=$address
my $txlistinternal = "${url}module=account&action=txlistinternal&startblock=0&endblock=99999999&sort=asc&apikey=$opt{key}"; # add &address=$address
my $balance = "${url}module=account&action=balance&tag=latest&apikey=$opt{key}";

my $transactions = undef; # Transactions
my $balances;
my $done = {"GENESIS" => 1}; # Used to avoid reprocessing addresses and transactions that have already been done (and processed)

# Subroutines
sub printHelp {
	print <<HELP

Usage: $0 [options]

Options 
	[ -d datadir ]      - path to directory where all datafiles are stored
	[ --desc file ]	    - file containing address descriptions
	[ --help ]          - print this help and exit
	[ --key apikey ]    - get an API key from https://etherscan.io/myapikey
	[ --owner apikey ]  - get an API key from https://etherscan.io/myapikey
	[ --start address ] - starting address to retrieve and follow transaction train
	
	
HELP
;
exit 0;
}

sub renameExportFiles {
	# Ethereum addresses are hexadecimal and not case sensitive. But case is used to help avoid mistyping addresses. 
	# For our purposes we want all addresses to be lowercase all the time. This renames export files forcing lowercase
	my @files = glob "$opt{datadir}/export-*.csv";
	foreach my $f (@files) {
		$f =~s|.*/||; #basename only - allow mixed case for directory elements
		my $lcf = lc $f;
		rename "$opt{datadir}/$f", "$opt{datadir}/$lcf" if $f ne $lcf;
	}
}

sub getJson {
	my $address = shift;
	my $action = 'txlist'; # txlist or txlistinternal
#	my $action = txlistinternal;
	my $cachefile = "$opt{datadir}/$action$address.json"; # reads from cache file if one exists. Otherwise calls api and stores to cache file
	my $result = [];
	if (-e $cachefile) {
		$result = retrieve($cachefile);
		return $result;
	}
	my $url = "https://api.etherscan.io/api?module=account&action=$action&startblock=0&endblock=99999999&sort=asc&apikey=$opt{key}&address=$address";
	my $ua = new LWP::UserAgent;
	$ua->agent("banana/1.0");
	my $request = new HTTP::Request("GET", $url);
	my $response = $ua->request($request);
	my $content = $response->content;
	if ($content) {
		my $data = parse_json($content);
		if ($data->{message} eq "OK" and $data->{status} == 1) {
			$result = $data->{result};
			store($result, $cachefile);
		}
	}	
	return $result;
}

# addressDesc returns the description for an address as loaded from the AddressDescriptions.dat file
sub addressDesc {
	state $desc = undef; # Descriptions keyed on address
	my $address = shift;
	$address = lc $address; # force lowercase for lookups
	if (not defined $desc) {
		my $ad  = csv( in => "$opt{datadir}/$opt{desc}", headers => "auto", filter => {1 => sub {length > 1} } );
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

sub convertFileToJson {
	my $aoh = shift;
	foreach my $t (@$aoh) {
		$t->{to} = $t->{To};
		$t->{from} = $t->{From};
		$t->{timeStamp} = $t->{UnixTimestamp};
		$t->{hash} = $t->{TxHash};
		$t->{blockNumber} = $t->{Blockno};
		$t->{contractAddress} = $t->{ContractAddress};
		$t->{value} = ($t->{'Value_IN(ETH)'} + $t->{'Value_OUT(ETH)'} ) * 1e18; # value in Wei
		#"TxnFee(ETH)",
		#"Status",
		#"ErrCode"		
	}
}

sub readEtherscan { # take an address return a pointer to array of hashes containing the transactions found on that address
	my $address = shift;
	$address = lc $address;
	my $aoh = [];
#	return $aoh if $done->{$address};
	$done->{$address} = 1;

	my $f = "$opt{datadir}/export-$address.csv";
	if (-e $f) {
		$aoh = csv( in => $f, headers => "auto");
		convertFileToJson($aoh);
		push @$transactions, @$aoh;
	}
	else {
		say "Missing file $f " . addressDesc($address);
	}
	
	foreach my $tran (@$aoh) {
		my ($to, $from) = ($tran->{to}, $tran->{from});
		my $dt = DateTime->from_epoch( epoch => $tran->{timeStamp} );
		$tran->{source} = 'EtherscanExport.pl'; # to identify the source in Banana
		$tran->{T} = $dt->dmy("/") . " " . $dt->hms();
		$tran->{toDesc} = addressDesc($to) || "Unknown";
		$tran->{fromDesc} = addressDesc($from) || "Unknown";
		$tran->{toS} = substr($tran->{to},0,6);
		$tran->{fromS} = substr($tran->{from},0,6);
		$tran->{TxnFee} = $tran->{'TxnFee(ETH)'};
		$tran->{txnFee} = $tran->{txnFee} * 1e18; # txnfee in Wei

#		readEtherscan($from) unless $done->{$from};
#		readEtherscan($to) unless $done->{$to};
	}
			
	return;
}

sub readJson { # take an address return a pointer to array of hashes containing the transactions found on that address
	my $address = shift;
	$address = lc $address;
	my $aoh = [];
	return $aoh if $done->{$address};
	$done->{$address} = 1;

	$aoh = getJson($address);
	push @$transactions, @$aoh;
	
	foreach my $tran (@$aoh) {
		my ($to, $from) = ($tran->{to}, $tran->{from});
		my $dt = DateTime->from_epoch( epoch => $tran->{timeStamp} );
		$tran->{source} = 'EtherscanExport.pl'; # to identify the source in Banana
		$tran->{T} = $dt->dmy("/") . " " . $dt->hms();
		$tran->{toDesc} = addressDesc($to) || "Unknown";
		$tran->{fromDesc} = addressDesc($from) || "Unknown";
		$tran->{toS} = substr($tran->{to},0,6);
		$tran->{fromS} = substr($tran->{from},0,6);
		$tran->{Value} = $tran->{value} / 1e18; # Value in ETH
		$tran->{txnFee} = $tran->{gasPrice} * $tran->{gasUsed}; # txn fee in Wei
		$tran->{TxnFee} = $tran->{txnFee} / 1e18; # txnfee in ETH
		$tran->{Status} = $tran->{txreceipt_status}; # 0 if successful, 1 if out of gas, NULL if pre Byzantium

		readJson($from) unless $done->{$from};
		readJson($to) unless $done->{$to};
	}
			
	return;
}

sub calcBalances {
	my $processed;
	foreach my $t (sort {$a->{timeStamp} <=> $b->{timeStamp}} @$transactions) {
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
		$balances->{'TxnFee'} += $t->{'TxnFee'};
		$balances->{$t->{from}} -= $t->{'TxnFee'}; # process tx fee even if this is an error transaction
		next if $t->{Status}; # Typically out of gas (make sure fees are processed but principal is not.
		$balances->{$t->{from}} -= $t->{'Value'};
		$balances->{$t->{to}} += $t->{'Value'};
		#my $address = lc "0x0aFa235C9D6a59c227Be92995b7E55a4dbC9cC19";
		#if ($t->{From} eq $address || $t->{To} eq $address) {
		#	say "balance $t->{T} $balances->{$address} ", substr($t->{Txhash},0,6), " $t->{'Value_IN(ETH)'} $t->{'Value_OUT(ETH)'} $t->{'TxnFee(ETH)'}"; 
		#}
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

# Main Program
printHelp if $opt{h};
print "Start address $opt{start}\n";
readJson($opt{start});
addressDesc($opt{start}); # initialise the addresses
#my $p = json_file_to_perl (',j');
#readEtherscan($opt{start});
calcBalances();
printBalances();

#printTransactions();
#print Dumper $done;

#print Dumper $desc;
#foreach my $a ( keys %$done) {
#	next if addressDesc($a);
#	next if length($a) > 40;
#	print "$a,ShapeShift,N\n";
#}

