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
			'owner:s' => \$opt{owner}, # 
			'start:s' => \$opt{start}, # starting address
			'trans:s' => \$opt{trans}, # starting address
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{desc} ||= "AddressDescriptions.dat";
$opt{key} ||= 'TQPWAY66XX2SXFGPTT7677TENHFFQTMGNH'; # from etherscan.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
$opt{start} ||= "0x34a85d6d243fb1dfb7d1d2d44f536e947a4cee9e";
$opt{trans} ||= "EtherTransactions.dat";

# Global variables

my $cablefile = "Cable.dat";
my $cable = {}; # hash keyed on date containing daily USD/GBP exchange rates
my %BananaMapping = (
    "David,BTC" => 10100,
);
my $url = "https://api.etherscan.io/api?";
my $txlist = "${url}module=account&action=txlist&startblock=0&endblock=99999999&sort=asc&apikey=$opt{key}"; # add &address=$address
my $txlistinternal = "${url}module=account&action=txlistinternal&startblock=0&endblock=99999999&sort=asc&apikey=$opt{key}"; # add &address=$address
my $balanceurl = "${url}module=account&action=balance&tag=latest&apikey=$opt{key}";


# Subroutines
sub printHelp {
	print <<HELP

Usage: $0 [options]

Options 
	[ -d datadir ]      - path to directory where all datafiles are stored
	[ --desc file ]	    - file containing address descriptions
	[ --help ]          - print this help and exit
	[ --key apikey ]    - get an API key from https://etherscan.io/myapikey
	[ --owner name ]    - owner of the address from AddressDescription file
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

sub getJsonBalance {
	my $address = shift;
	return 0 unless $address =~ m/^0x/;
	my $action = 'balance'; # txlist or txlistinternal
	my $cachefile = "$opt{datadir}/$action$address.json"; # reads from cache file if one exists. Otherwise calls api and stores to cache file
	my $result = 0;
	if (-e $cachefile) {
		$result = retrieve($cachefile);
		return $$result;
	}
	my $url = "$balanceurl&address=$address";
	my $ua = new LWP::UserAgent;
	$ua->agent("banana/1.0");
	my $request = new HTTP::Request("GET", $url);
	my $response = $ua->request($request);
	my $content = $response->content;
	if ($content) {
		my $data = parse_json($content);
		if ($data->{message} eq "OK" and $data->{status} == 1) {
			$result = $data->{result};
			store(\$result, $cachefile);
		}
	}	
	return $result;
}

# addressDesc returns the description for an address as loaded from the AddressDescriptions.dat file
sub addressDesc {
	my ($address, $field) = @_;
	$field ||= 'Desc'; #  default is to return the description for the given address
	state $desc = undef; # Descriptions keyed on address
	$address = lc $address; # force lowercase for lookups
	if (not defined $desc) {
		my $ad  = csv( in => "$opt{datadir}/$opt{desc}", headers => "auto", filter => {1 => sub {length > 1} } );
		foreach my $rec (@$ad) {
			$rec->{Address} = lc $rec->{Address}; # force lowercase
			$desc->{$rec->{Address}} = $rec;
#			$desc->{$rec->{Address}} = $rec->{Desc};
#			if ($rec->{Follow} eq 'N') {
#				$done->{$rec->{Address}} = 1 ; # pretend we've already done and therefore processed this address
#			}
		}
	}
	return $desc->{$address}{$field};
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
		$t->{TxnFee} = $t->{'TxnFee(ETH)'};
		$t->{txnFee} = $t->{TxnFee} * 1e18; # txnfee in Wei
		$t->{Value} = $t->{'Value_IN(ETH)'} + $t->{'Value_OUT(ETH)'};
		$t->{value} = $t->{Value} * 1e18;
		$t->{isError} = $t->{Status} ? 1 : 0;
	}
}

sub readEtherscan { # take an address return a pointer to array of hashes containing the transactions found on that address
	my ($address, $transactions) = @_;
	state $processed;
	$address = lc $address;
	my $aoh = [];
	return $aoh if ($processed->{$address} or addressDesc($address,'Follow') eq 'N');
	$processed->{$address} = 1;

	my $f = "$opt{datadir}/export-$address.csv";
	if (-e $f) {
		$aoh = csv( in => $f, headers => "auto");
		convertFileToJson($aoh);
#		push @$transactions, @$aoh;
	}
	elsif (addressDesc($address,'Follow') eq 'N') {
		say "Not following $address";
	}
	else {
		say "Missing file $f " . addressDesc($address);
	}
	
	foreach my $tran (@$aoh) {
		$tran->{'hash'} = $tran->{Txhash};
		next if $processed->{$tran->{hash}} == 1;
		$processed->{$tran->{hash}} = 1;
		my ($to, $from) = ($tran->{to}, $tran->{from});
		my $dt = DateTime->from_epoch( epoch => $tran->{timeStamp} );
		$tran->{source} = 'EtherscanExport.pl'; # to identify the source in Banana
		$tran->{T} = $dt->dmy("/") . " " . $dt->hms();
		$tran->{toDesc} = addressDesc($to) || "Unknown";
		$tran->{fromDesc} = addressDesc($from) || "Unknown";
		$tran->{toS} = substr($tran->{to},0,6);
		$tran->{fromS} = substr($tran->{from},0,6);
		push @$transactions, $tran;

#		readEtherscan($from, $transactions) unless $processed->{$from};
		readEtherscan($to, $transactions) unless $processed->{$to};
	}
			
	return;
}

sub readJson { # take an address return a pointer to array of hashes containing the transactions found on that address
	my ($address, $transactions) = @_;
	$address = lc $address;
	state $processed;
	my $aoh = [];
	return $aoh if ($processed->{$address} or addressDesc($address,'Follow') eq 'N');;
	$processed->{$address} = 1;

	$aoh = getJson($address);
#	push @$transactions, @$aoh;
	
	foreach my $tran (@$aoh) {
		next if $processed->{$tran->{hash}} == 1;
		$processed->{$tran->{hash}} = 1;
		my ($to, $from) = ($tran->{to}, $tran->{from});
		my $dt = DateTime->from_epoch( epoch => $tran->{timeStamp} );
		$tran->{source} = 'Etherscan'; # to identify the source in Banana
		$tran->{T} = $dt->dmy("/") . " " . $dt->hms();
		$tran->{toDesc} = addressDesc($to) || "Unknown";
		$tran->{fromDesc} = addressDesc($from) || "Unknown";
		$tran->{toS} = substr($tran->{to},0,6);
		$tran->{fromS} = substr($tran->{from},0,6);
		$tran->{Value} = $tran->{value} / 1e18; # Value in ETH
		$tran->{txnFee} = $tran->{gasPrice} * $tran->{gasUsed}; # txn fee in Wei
		$tran->{TxnFee} = $tran->{txnFee} / 1e18; # txnfee in ETH
		$tran->{ccy} = 'ETH';
		push @$transactions, $tran;

#		readJson($from, $transactions) unless $processed->{$from};
		readJson($to, $transactions) if addressDesc($to,'Owner') eq $opt{owner} and not $processed->{$to};
	}
			
	return;
}

sub calcBalances {
	my $transactions = shift;
	my $processed;
	my $balances;
	foreach my $t (sort {$a->{timeStamp} <=> $b->{timeStamp}} @$transactions) {
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
		$balances->{'txnFee'} += $t->{'txnFee'};
		$balances->{$t->{from}} -= $t->{'txnFee'}; # process tx fee even if this is an error transaction
		next if $t->{isError}; # Typically out of gas (make sure fees are processed but principal is not.
		$balances->{$t->{from}} -= $t->{'value'};
		$balances->{$t->{to}} += $t->{'value'};
	}
	return $balances;
}

sub printBalances {
	my $balances = shift;
	foreach my $address (sort keys %$balances) {
		next if addressDesc($address,'Follow') eq 'N';
		my $bal1 = $balances->{$address} / 1e18;
		my $bal2 = getJsonBalance($address) / 1e18;
		say "$address $bal1 $bal2 " . addressDesc($address);
	}
}

sub printTransactions {
	my ($transactions,$address) = @_;
	my $processed;
	foreach my $t (sort {$a->{UnixTimestamp} <=> $b->{UnixTimestamp}} @$transactions) {
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
		next if $address and $t->{from} ne $address and $t->{to} ne $address;
		print "$t->{T} $t->{fromS} $t->{fromDesc} $t->{'Value'} ETH $t->{toS} $t->{toDesc}\n";
	}
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}


# Main Program
printHelp if $opt{h};
print "Start address $opt{start}\n";
addressDesc($opt{start}); # initialise the addresses
getJsonBalance('txnFee');

#say 'File transactions:';
#my $tf = [];
#readEtherscan($opt{start}, $tf);
#printTransactions($tf);
#my $bf = calcBalances($tf);
#print Dumper $bf;
#printBalances($bf);

say 'Json transactions:';
my $tj = [];
readJson($opt{start}, $tj);
printTransactions($tj);
saveTransactions($tj);
#my $bj = calcBalances($tj);
#print Dumper $bj;
#printBalances($bj);



