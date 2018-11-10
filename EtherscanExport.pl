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
use lib '.';
use AccountsList;
use Account;
use Person;
use Transaction;
use TransactionUtils;

# Process an Etherscan.io export CSV file so that it is conveniently usable as a spreadsheet or as an import into an accounting system
# Program works in several stages:
# First, process the Etherscan export parsing the dates and times into DateTime objects and splitting fields that have numbers and currencies
#       also do the account mapping to Banana Credit and Debit accounts. Put the results into an array of hashes called $data1
# Third, loop again through the $data1 records processing fees - Fee records are accumulated to one Fee line per month. Results are appended to $data2

# TBD - process USD/GBP exchange rates cable.dat

# Commandline args
GetOptions(
	'balances!' => \$opt{balances}, # Data Directory address
	'datadir:s' => \$opt{datadir}, # Data Directory address
	'desc:s' => \$opt{desc}, #
	'g:s' => \$opt{g}, #
	'h' => \$opt{h}, #
	'key:s' => \$opt{key}, # API key to access etherscan.io
	'quick!' =>\$opt{quick},
	'start:s' => \$opt{start}, # starting address
	'trace:s' => \$opt{trace}, # starting address
	'trans:s' => \$opt{trans}, # starting address
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{key} ||= 'TQPWAY66XX2SXFGPTT7677TENHFFQTMGNH'; # from etherscan.io
$opt{trans} ||= "EtherTransactions.dat";

# Global variables

my $cablefile = "Cable.dat";
my $cable = {}; # hash keyed on date containing daily USD/GBP exchange rates

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
	[ --help ]          - print this help and exit
	[ --key apikey ]    - get an API key from https://etherscan.io/myapikey
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
	my ($address, $action) = @_; # $action can be 'txlist' or 'txlistinternal' for transactions that invoke smart contracts
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
	say "$url";
	my $response = $ua->request($request);
	my $content = $response->content;
	if ($content) {
		my $data = parse_json($content);
		if ($data->{message} eq "OK" and $data->{status} == 1) {
			$result = $data->{result};
		}
	}
	store($result, $cachefile);
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
		}
	}
	store(\$result, $cachefile);
	return $result;
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
	return $aoh if ($processed->{$address} or AccountsList->address($address,'Follow') eq 'N');
	$processed->{$address} = 1;

	my $f = "$opt{datadir}/export-$address.csv";
	if (-e $f) {
		$aoh = csv( in => $f, headers => "auto");
		convertFileToJson($aoh);
#		push @$transactions, @$aoh;
	}
	elsif (AccountsList->address($address,'Follow') eq 'N') {
		say "Not following $address";
	}
	else {
		say "Missing file $f " . AccountsList->address($address);
	}

	foreach my $tran (@$aoh) {
		$tran->{'hash'} = $tran->{Txhash};
		next if $processed->{$tran->{hash}} == 1;
		$processed->{$tran->{hash}} = 1;
		my ($to, $from) = ($tran->{to}, $tran->{from});
		my $dt = DateTime->from_epoch( epoch => $tran->{timeStamp} );
		$tran->{source} = 'EtherscanExport.pl'; # to identify the source in Banana
		$tran->{T} = $dt->dmy("/") . " " . $dt->hms();
		$tran->{toDesc} = AccountsList->address($to, 'Description') || "Unknown";
		$tran->{fromDesc} = AccountsList->address($from, 'Description') || "Unknown";
		$tran->{toS} = substr($tran->{to},0,8);
		$tran->{fromS} = substr($tran->{from},0,8);
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
	return $aoh if ($processed->{$address} or AccountsList->address($address,'Follow') eq 'N');;
	$processed->{$address} = 1;

	$aoh = getJson($address,'txlist');
	my $aoh2 = getJson($address,'txlistinternal');
	push @$aoh, @$aoh2;
#	push @$transactions, @$aoh;

	foreach my $tran (@$aoh) {
		next if $processed->{$tran->{hash}} == 1;
		$processed->{$tran->{hash}} = 1;
		if ($opt{trace} and $tran->{hash} =~ /$opt{trace}/) {
			say "Found! $tran->{hash}" ;
		}
		if ($tran->{hash} eq '0x48cc8e48645959e1501655a807cd188adfd607abf554d5d6c7447ddf839ce76d') {
			# Sadly etherscan.io API does not return correct info for invocation of ReplaySafeSplit contract - force the addresses
			$tran->{to} = '0x93a44c99642a02fc4e62a97e13c703932682db36';
			$tran->{from} = '0xd5fbb237f5200b097031025cdb914c4595bceffa';
			$tran->{note} .= "EtherscanExport.pl munged from and to addresses for ReplaySafeSplit";
		}
		if($tran->{from} eq '0x1522900b6dafac587d499a862861c0869be6e428') {
			# Bitstamp withdrawal contract - we need to override to fix the owner
			# in order for Bitstamp wallet reconciliation to work
			my $ow = AccountsList->account($tran->{to})->Owner->name();
			my $ad = "0xBitstampETHWallet$ow";
			if(AccountsList->account($ad)) {
				$tran->{note} .= "OrigFromAddress:$tran->{from}";
				$tran->{from} = $ad;
			}
		}
		my ($to, $from) = ($tran->{to}, $tran->{from});

		my $dt = DateTime->from_epoch( epoch => $tran->{timeStamp} );
		if ($tran->{isError}) {
			$tran->{value} = 0; # e.g. if transaction is Out Of Gas. Keep the transaction because the fee is still charged.
		}
		$to ||= $tran->{contractAddress}; # eg hash 0xf904b24eb23de15624f8eaa1e005b94bfd3cd3bb6b589a0c28a8cbc36ddd2c8f contract invocation
		if ($opt{trace} and ($tran->{from} =~ /$opt{trace}/i or $tran->{to} =~ /$opt{trace}/i)) {
			say "Found tracing $opt{trace} ! From: $tran->{from} To: $tran->{to}" ;
		}
		my $fromaccount = AccountsList->account($from);
		my $toaccount = AccountsList->account($to);
		say "From account missing from AccountsList: From: $from To: $to" if !defined $fromaccount;
		say "To account missing from AccountsList: From: $from To: $to" if !defined $toaccount;
		$tran->{to_account} = $toaccount;
		$tran->{from_account} = $fromaccount;
		if(!defined $tran->{to_account} or !defined $tran->{from_account}) {
			say "Oops from_account $tran->{from}";
			say "Oops to_account $tran->{to}";
		}
		$tran->{value} /= 1e18; # Value in ETH
		$tran->{currency} = 'ETH';
		# Following fields are for printMySQLTransactions
		$tran->{tran_type} = 'Transfer';
		$tran->{tran_subtype} = 'Etherscan';
		$tran->{dt} = $dt;
		$tran->{amount} = $tran->{value};
		$tran->{amountccy} = $tran->{ccy};
#		$tran->{value} = $tran->{Value};
#		$tran->{value_currency} = $tran->{ccy};
#		$tran->{rate} = 0;
#		$tran->{rateccy} = '';
		$tran->{from_fee} = $tran->{gasPrice} * $tran->{gasUsed} / 1e18; # txn fee in ETH
		$tran->{to_fee} = 0; # txn fee in ETH
		$tran->{fee_currency} = $tran->{currency};

		next unless _check_consistency($tran,"");
		my $T = Transaction->new($tran);

		push @$transactions, $T;
	}
	return;
}

sub _check_consistency {
	my ($data, $str) = @_;
	#say $data->{toaccount} if !defined $data->{to_account};
	#say $data->{fromaccount} if !defined $data->{from_account};
	if (! defined $data->{from_account}) {
		say "$str From account undefined $data->{address}";
		return 0;
	}
	if (ref($data->{from_account}) ne 'Account') {
		say "$str From account is not a proper account $data->{address}";
		return 0;
	}
	if (! defined $data->{to_account}) {
		say "$str To account undefined $data->{toaddress}";
		return 0;
	}
	if (ref($data->{to_account}) ne 'Account') {
		say "$str To account is not a proper account $data->{toaddress}";
		return 0;
	}
	return 1;
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
		next if AccountsList->address($address,'Follow') eq 'N';
		my $bal1 = $balances->{$address} / 1e18;
		my $bal2 = getJsonBalance($address) / 1e18;
		say "$address $bal1 $bal2 " . AccountsList->account($address, 'Description');
	}
}

sub xprintTransactions {
	my ($transactions,$address) = @_;
	my $processed;
	foreach my $t (sort {$a->{dt} <=> $b->{dt}} @$transactions) {
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
		next if $address and $t->{from} ne $address and $t->{to} ne $address;
		print "$t->{T} $t->{fromAccount}{AccountRefShort} $t->{fromAccount}{Owner} $t->{fromAccount}{AccountName} $t->{'Value'} $t->{amountccy} $t->{toAccount}{AccountRefShort} $t->{toAccount}{AccountName} $t->{toAccount}{Owner}\n";
	}
}
sub printTransactions {
	my $trans = shift;
    Transaction->printHeader;
    for my $t (sort {$a->{dt} <=> $b->{dt}} @$trans) {
		$t->print;
	}
}

sub printMySQLTransactions {
	my $trans = shift;
    Transaction->printMySQLHeader;
    for my $t (sort {$a->{dt} <=> $b->{dt}} @$trans) {
		$t->printMySQL;
	}
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}

sub getAllTransactions {
	my ( $tj) = @_;
	my $addresses = AccountsList->addresses("ETH");
	foreach my $ad (sort keys %$addresses) {
		my $h = $addresses->{$ad};
		if($h->{Follow} eq 'Y') {
			if($h->{Address} =~ /^0x/) {
				readJson($h->{Address}, $tj);
			}
		}
	}
}

# Main Program
printHelp if $opt{h};
AccountsList->new();
AccountsList->backCompatible();

#getJsonBalance('txnFee');

#say 'File transactions:';
#my $tf = [];
#readEtherscan($opt{start}, $tf);
#printTransactions($tf);
#my $bf = calcBalances($tf);
#print Dumper $bf;
#printBalances($bf);

#say 'Json transactions:';
my $tj = [];
if($opt{start}) {
	print "Start address $opt{start}\n";
	readJson($opt{start}, $tj);
}
elsif($opt{balances}) {
	getAllTransactions($tj);
	TransactionUtils->printBalances($tj);
}
elsif($opt{quick}) {
	getAllTransactions($tj);
	TransactionUtils->printTransactions($tj);
}
else {
	getAllTransactions($tj);
	TransactionUtils->printMySQLTransactions($tj);
}
saveTransactions($tj);
#my $bj = calcBalances($tj);
#print Dumper $bj;
#printBalances($bj);
