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
use vars qw(%counts);
use Getopt::Long;
use Data::Dumper;
use lib '.';
use AccountsList;
use Account;
use Person;
use Transaction;
use TransactionUtils;

# Process a shapeshift.io address to confirm exchanges transactions
# Reads all the addresses in the AddressDescriptions.dat file. If the owner is marked as ShapeShift then we call the ShapeShift API
# to get data on the SHapeShift transactions associated with that address.
# The ShapeShift API txStat only returns data for deposit addresses, not for withdrawal addresses - that's a problem!
# The ShapeShift API only returns data for the last transaction that uses the deposit address - that's a problem if a deposit address has been reused.
# Nevertheless, when it works it is evidence that the address really is a SHapeShift deposit address ie an address for which SHapeShift has the private key.

# Commandline args
GetOptions(
	'accounts!' => \$opt{accounts}, # Get SS transactions by looking at every entry in the Accounts (AddressDesc) file
	'balances!' => \$opt{balances},
	'counts!' => \$opt{counts},
	'datadir:s' => \$opt{datadir}, # Data Directory path
	'desc:s' => \$opt{desc},
	'g:s' => \$opt{g}, #
	'help' => \$opt{h}, #
	'key:s' => \$opt{key}, # API key to access etherscan.io
	'owner:s' => \$opt{owner}, #
	'quick!' => \$opt{quick}, #
	'start:s' => \$opt{start}, # starting address
	'trans:s' => \$opt{trans}, # filename to store transactions
	'trace:s' => \$opt{trace}, # trace a given address or ShapeShift status (prints Data::Dumper)
);

# Example data returned from txStat
# Note - no timestamp is included, therefore use transaction hash as the lookup key
#          'incomingType'   => 'ETH',
#          'incomingCoin'   => '13.75',
#          'address'        => '0xfb27d2ddd73daae45d664271c2794e0c6bf09c90',
#          'outgoingType'   => 'BTC',
#          'outgoingCoin'   => '1.8826024',
#          'transaction'    => 'cb250b00194b69515cce5dbf2aad520dd83e83a77fc03f1fdb397fef37681755',
#          'transactionURL' => 'https://blockchain.info/tx/cb250b00194b69515cce5dbf2aad520dd83e83a77fc03f1fdb397fef37681755',
#          'withdraw'       => '1KvL2tDzZ5tqaiqyVmmJHPR2NSeQVefDox'
#          'status'         => 'complete',


$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{key} ||= ''; # from shapeshift.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
$opt{trans} ||= "ShapeshiftTransactions.dat";

$opt{bitcoin} ||= "BlockchainTransactions.dat";
$opt{bitcoincash} ||= "BCHTransactions.dat";
$opt{classic} ||= "ClassicTransactions.dat";
$opt{ether} ||= "EtherTransactions.dat";


# Global variables
my $baseurl = "https://shapeshift.io/";

# getTxStat - reads ShapeShift transaction details from cache file if one exists. Otherwise calls ShapeShift api and stores returned data to the cache file
sub getTxStat {
	my $address = shift;
	my $action = 'txStat';
	my $cachefile = "$opt{datadir}/ShapeShift$action$address.json";
	my $result = [];
	if (-e $cachefile) {
		$result = retrieve($cachefile);

		return $result;
	}
	my $url = "$baseurl$action/$address";
	my $ua = new LWP::UserAgent;
	$ua->agent("banana/1.0");
	my $request = new HTTP::Request("GET", $url);
	say $url;
	my $response = $ua->request($request);
	my $content = $response->content;
	if ($content) {
		my $data = parse_json($content);
		# Following line is a dirty hack where SS API has returned the wrong hash
		$data->{transaction} = '0xbd98b2d4ee9ddd6b235781b2220fa782ca76b8baa3f6963ded05b4fc3c9e9630' if $data->{transaction} eq '0x01973de82f9da359738d364a64de7aa9a5022c9bc314fbaefce42374ea61d1a0';
		store($data, $cachefile);
		return $data;
	}
	return 0; # What should we return here??
}

sub getTransactionDate {
	my $data = shift;
	return DateTime->now->truncate( to => 'day' ); # dirty hack to make extracts created on the same day comparable
}

sub getAddressesFromFiles {
	my $desc = shift;
	my $addresses;
	my $action = 'txStat';
	my @files = glob "$opt{datadir}/ShapeShift$action*.json";
	for my $f (@files) {
		$counts{"getAddressesFromFiles: total"}++;
		my $t = retrieve($f);
		next unless $t;
		if ($t->{error} eq 'Invalid Address') {
			next;
		}
		$counts{"getAddressesFromFiles: Status $t->{status}"}++;
		if ($t->{status} eq 'error') {
			next;
		}
		$counts{"$t->{incomingType} to $t->{outgoingType}"}++;
		my $address = $t->{address};
		if ($address eq $opt{trace}) {
			say "Found in getAddressesFromFiles $address";
			say Dumper $t;
		}
		$addresses->{$address} = $t;
	}
	return $addresses;
}

sub getTransactionsFromAccountsList {
	my $accounts = shift || AccountsList->accounts();
	my $Transactions = [];
	my $processed;
	foreach my $address (sort keys %$accounts) {
		if (length($address) > 30 or $accounts->{$address}{Owner} =~ /ShapeShift/) {
			my $data = getTxStat($address);
			next unless $data->{status} eq 'complete';
			if ($data->{outgoingType} eq 'ETH' and $data->{withdraw} !~ /^0x/) {
				$data->{withdraw} = "0x$data->{withdraw}";
			}
			$data->{tran_type} = "Exchange";
			$data->{tran_subtype} = "ShapeShift";
			$data->{from_account} = AccountsList->account($data->{address});
			$data->{to_account} = AccountsList->account($data->{withdraw});
			$data->{amount} = $data->{incomingCoin}; # This is the Shapeshift deposit amount
			$data->{currency} = $data->{incomingType}; # This is the Shapeshift deposit coin type
			$data->{value} = $data->{outgoingCoin}; # This is the Shapeshift withdraw amount
			$data->{value_currency} = $data->{outgoingType}; # This is the Shapeshift withdraw coin type
			$data->{rate} = $data->{value} / $data->{amount};
			$data->{fee} = 0;
			$data->{fee_currency} = $data->{currency};
			#$data->{owner} = AccountsList->address($data->{toaccount}, 'Owner');
			$data->{hash} = "$data->{transaction}-SS"; # This is the transaction hash for the outgoing transaction SS to identify it as ShapeShift and keep hashes unique

			if ($opt{trace} and $opt{trace} eq $data->{address}) {
				say "traceing address $opt{trace}";
				print Dumper $data;
			}
			if ($opt{trace} and $opt{trace} eq $data->{withdraw}) {
				say "traceing withdraw address $opt{trace}";
				print Dumper $data;
			}
			if ($opt{trace} and $opt{trace} eq $data->{status}) {
				say "traceing status $opt{trace}";
				print Dumper $data;
			}
			$data->{dt} = getTransactionDate($data);
#			if ($data->{transaction}) {
#				$transactions->{$data->{transaction}} = $data;
#				$processed->{$data->{transaction}} = 1;
#			}
#			if ($data->{address}) {
#				$transactions->{$data->{address}} = $data;
#				$processed->{$data->{address}} = 1;
#			}
#			if ($data->{withdraw}) {
#				$transactions->{$data->{withdraw}} = $data;
#				$processed->{$data->{withdraw}} = 1;
#			}
			if ($data->{status} eq 'error') {
#				say "$address,ShapeShift,ShapeShift error,N";
			}
			elsif ($data->{status} eq 'complete') {
				if (!defined $data->{from_account} or !defined $data->{to_account}) {
					say "$address,ShapeShift,ShapeShift $data->{incomingCoin} $data->{incomingType} to $data->{outgoingCoin} $data->{outgoingType} $data->{withdraw} $data->{transaction}";
					say "Missing From account: $data->{address}" if !defined $data->{from_account};
					say "Missing To account: $data->{withdraw}" if !defined $data->{to_account};
					say "Skipping this transaction";
					next;
				}
				if ($data->{from_account}->ShapeShift ne 'Input') {
					say "$data->{from_account}{AccountRefUnique} should be set to Input";
				}
				if ($data->{from_account}->Owner->name ne 'ShapeShift') {
					say "$data->{from_account}{AccountRefUnique} deposit address should be owned by ShapeShift " . $data->{from_account}->Owner->name;
				}
				if ($data->{from_account}->Currency ne $data->{incomingType}) {
					say "$data->{from_account}{AccountRefUnique} Currency mismatch incomingType is $data->{incomingType}";
				}
				if ($data->{to_account}->ShapeShift ne 'Output') {
					say "$data->{to_account}{AccountRefUnique} outgoingType is $data->{outgoingType} should be set to Output and Follow ";
				}
				if ($data->{to_account}->Owner->name eq 'ShapeShift') {
					say "$data->{to_account}{AccountRefUnique} withdraw address should NOT be owned by ShapeShift " . $data->{to_account}->Owner->name;
				}
				if ($data->{to_account}->Currency ne $data->{outgoingType}) {
					say "$data->{to_account}{AccountRefUnique} Currency mismatch outgoingType is $data->{outgoingType}";
				}
				my $T = Transaction->new($data);
				push(@$Transactions, $T);
			}
			elsif ($data->{status} eq 'failed') {
#				say "$address,ShapeShift,ShapeShift ETH deposit failed,N";
			}
			elsif ($data->{status} eq 'resolved') {
#				say "$address,ShapeShift,ShapeShift ETH deposit failed,N";
#				push(@$transactions, $data); # Need to fix withdraw addresses before bringing in these 4 transactions
			}
			else {
				say "Unexpected: $address,ShapeShift,ShapeShift $data->{incomingCoin} $data->{incomingType} to $data->{outgoingCoin} $data->{outgoingType} $data->{status},N";
			}
		}
	}
	return $Transactions;
}

#Shapeshift transactions have minimal data. Therefore enrich with data from the same transaction captured elsewhere
sub enrichShapeShiftTransactions {
	my ($ss_transactions,$blockchain_transactions) = @_;
	my (%hdict, %adict);
	my $enriched;

	# create dictionary of transactions keyed on txhash
	foreach my $t (@$blockchain_transactions) {
		if (ref($t) ne 'Transaction' ) {
			say 'Oops unexpected type for $t: ' . ref($t);
			next;
		}
		if ($opt{trace} and $t->{from_account}{AccountRef} eq $opt{trace}) {
			say "Found from address in transactions $t->{from_account}{AccountRef}";
		};
		if ($opt{trace} and $t->{to_account}{AccountRef} eq $opt{trace}) {
			say "Found to address in transactions $t->{to_account}{AccountRef}";
		};
		if (! defined $t->{from_account} or !defined $t->{to_account}) {
			say "Oops no from_account or to_account";
		}
		# BTC and BCH transactions can be split into multiple sub transactions
		# they have hash field set to hash-index. We want to find Transactions
		# by looking up the transaction hash returned from SS API. therefore
		# we strip the suffix. It doesn't matter that we only get one of the
		# sub-transactions
		my $hash = $t->{hash};
		$hash =~ s/-.*//;
		if ($opt{trace} and $hash =~ /$opt{trace}/) {
			say "Found hash in transactions $hash $t->{currency}";
		};
		$hdict{$hash} = $t; # Used to lookup the withdraw side of the SS transaction
		# For Type2 BTC and BCH transactions we need the output amount stored in the note field
		my $amount = $t->{amount};
		if ($t->{note} =~ /Type2.Outvalue ([0-9.]+)/) {
			$amount = $1;
		}
		$adict{"$t->{to_account}{AccountRef} $amount"} = $t;
		#$adict{"from $t->{from_account}{AccountRef} $t->{amount}"} = $t;
		$counts{Transactions}++;
		$counts{"Transactions in currency $t->{currency}"}++;
		$counts{"adict keys"} = scalar(keys %adict);
		$counts{"hdict keys"} = scalar(keys %hdict);
	}
#	print Dumper $adict{'0x85a9962fbc35549afec891c285b3fe057ec334cc'};

	# enrich shapeshit transactions from the dict
	foreach my $ss_t (@$ss_transactions) {
		if ($opt{trace} and $ss_t->{from_account}{AccountRef} =~ /$opt{trace}/) {
			say "Found receive address in SS $ss_t->{from_account}{AccountRef} withdraw hash:$ss_t->{hash}"
		};
		if ($opt{trace} and $ss_t->{to_account}{AccountRef} =~ /$opt{trace}/) {
			say "Found withdraw address in SS $ss_t->{to_account}{AccountRef} withdraw hash:$ss_t->{hash}"
		};
		$counts{all}++;
		$counts{"$ss_t->{currency} to $ss_t->{value_currency}"}++;

		# Now find the incoming deposit transaction and outgoing withdraw transactions

		my $a = $ss_t->{from_account}{AccountRef}; #ss deposit address
		$ss_t->{deposit_t} = $adict{"$a $ss_t->{amount}"};
		if (defined $ss_t->{deposit_t}) {
			$ss_t->{dt} = $ss_t->{deposit_t}{dt};
			$ss_t->{dt}->add(seconds=>1);
			$counts{"deposit address resolved"}++;
		}

		my $h = ($ss_t->{hash});
		$h =~ s/-.*$//; # Strip off -SS-.*
		#if ($h and $ss_t->{outgoingType} =~ /ET[CH]/) {
		#	$h = "0x$h";
		#	$h =~ s/0x0x/0x/;
		#}
		if ($opt{trace} and $h =~ /$opt{trace}/) { say "Found hash in ss data $h"};
		$ss_t->{withdraw_t} = $hdict{$h};
		if (defined $ss_t->{withdraw_t}) {
			$ss_t->{dt} = $ss_t->{withdraw_t}{dt};
			$ss_t->{dt}->subtract(seconds=>1);
			$counts{"withdraw address resolved"}++;
		}


		$ss_t->{hash} = "$ss_t->{deposit_t}{hash}-SS-$ss_t->{withdraw_t}{hash}";
		$ss_t->{note} = join "-",
			$ss_t->{deposit_t}{from_account}{AccountRefUnique},
			$ss_t->{deposit_t}{to_account}{AccountRefUnique},
			$ss_t->{withdraw_t}{from_account}{AccountRefUnique},
			$ss_t->{withdraw_t}{to_account}{AccountRefUnique},
		;
		if ($ss_t->{transaction} eq 'a9100aabc21a2c7df291a9e05eb32ee3c77fe5e06b31f6f867277570459ef90a') {
			$ss_t->{dt} = DateTime->new(year=>2017,month=>06,day=>13,hour=>11,minute=>13,second=>59,time_zone=>'UTC');
		}

	}
}

sub reportCounts {
	foreach my $c (sort keys %counts) {
		say "\t count of $c $counts{$c}";
	}
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}


sub printOutputData {
	my ($trans,$ccy) = (@_);
	foreach my $t (@$trans) {
		if ($t->{outgoingType} eq $ccy) {
			say $t->{transaction}, " ", $t->{outgoingCoin}, " ", $t->{outgoingType}, " ", $t->{withdraw};
		}
	}
}

sub printMySQLTransactions {
	my $trans = shift;
    Transaction->printMySQLHeader;
    for my $t (sort {$a->{dt} <=> $b->{dt}} @$trans) {
		$t->printMySQL;
	}
}

# Main Program
my $btc = retrieve("$opt{datadir}/$opt{bitcoin}");
my $bch = retrieve("$opt{datadir}/$opt{bitcoincash}");
my $eth = retrieve("$opt{datadir}/$opt{ether}");
my $etc = retrieve("$opt{datadir}/$opt{classic}");

my $all = [];
push(@$all, @$btc, @$bch, @$eth, @$etc);

AccountsList->new();
my $transactions;
if ($opt{start}) { # for interactive use to check a single address
	my $x = getTxStat($opt{start});
	say Dumper $x;
	exit 0;
}
elsif ($opt{accounts}) { # Get the ShapeShift transactions from the accounts file
	$transactions = getTransactionsFromAccountsList();
}
else {
	my $d2 = getAddressesFromFiles();
	$transactions = getTransactionsFromAccountsList($d2);
}

enrichShapeShiftTransactions($transactions, $all);

if ($opt{balances}) {
	TransactionUtils->printBalances($transactions);
}
elsif ($opt{quick}) {
	TransactionUtils->printTransactions($transactions);
}
else  {
	TransactionUtils->printMySQLTransactions($transactions);
}
reportCounts if $opt{counts};

saveTransactions($transactions);
