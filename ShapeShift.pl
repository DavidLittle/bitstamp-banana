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
use Data::Dumper;


# Process a shapeshift.io address to confirm exchanges transactions
# Reads all the addresses in the AddressDescriptions.dat file. If the owner is marked as ShapeShift then we call the ShapeShift API
# to get data on the SHapeShift transactions associated with that address.
# The ShapeShift API txStat only returns data for deposit addresses, not for withdrawal addresses - that's a problem!
# The ShapeShift API only returns data for the last transaction that uses the deposit address - that's a problem if a deposit address has been reused.
# Nevertheless, when it works it is evidence that the address really is a SHapeShift deposit address ie an address for which SHapeShift has the private key.

# Commandline args
GetOptions( 'datadir:s' => \$opt{datadir}, # Data Directory address
			'desc:s' => \$opt{desc},
			'enrichedAddress!' => \$opt{enrichedAddress},
			'g:s' => \$opt{g}, # 
			'help' => \$opt{h}, # 
			'key:s' => \$opt{key}, # API key to access etherscan.io
			'owner:s' => \$opt{owner}, # 
			'start:s' => \$opt{start}, # starting address
			'trans:s' => \$opt{trans}, # filename to store transactions
			'track:s' => \$opt{track}, # track a given address or ShapeShift status (prints Data::Dumper)
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
$opt{desc} ||= "AddressDescriptions.dat";
$opt{key} ||= ''; # from shapeshift.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
$opt{trans} ||= "ShapeshiftTransactions.dat";

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
		store($data, $cachefile);
		return $data;
	}
	return 0; # What should we return here??	
}

# addressDesc returns the description for an address as loaded from the AddressDescriptions.dat file
sub addressDesc {
	my ($address, $field) = @_;
	$field ||= 'Desc'; #  default is to return the description for the given address
	state $desc = undef; # Descriptions keyed on address
	$address = lc $address  if $address =~ /^0x/; # force lowercase for lookups
	if (not defined $desc) {
		my $ad  = csv( in => "$opt{datadir}/$opt{desc}", headers => "auto", filter => {1 => sub {length > 1} } );
		foreach my $rec (@$ad) {
			$rec->{Address} = lc $rec->{Address} if $rec->{Address} =~ /^0x/; # force lowercase for ethereum addresses
			$desc->{$rec->{Address}} = $rec;
			if ($opt{track} and $opt{track} eq $rec->{Address}) {
				say "Tracking address $opt{track}";
				print Dumper $rec;
			}
		}
	}
	return $desc->{$address}{$field} if $address;
	return $desc;
}

sub getTransactionDate {
	my $data = shift;
	if ($data->{incomingType} eq "ETH") {
	
	}
	return DateTime->now;
}

sub getTransactionsFromAddressDesc {
	my $d = shift;
	my $transactions = [];
	my $processed;
	foreach my $address (sort keys %$d) {
		if (length($address) > 20 or $d->{$address}{Owner} =~ /ShapeShift/) {
			my $data = getTxStat($address);
			$data->{type} = "Exchange";
			$data->{subtype} = "ShapeShift";
			$data->{account} = $data->{address}; # This is the Shapeshift deposit address - incoming to ShapeShift
			$data->{toaccount} = $data->{withdraw}; # This is the Shapeshift withdraw address - outgoing from ShapeShift
			$data->{amount} = $data->{incomingCoin}; # This is the Shapeshift deposit amount
			$data->{amountccy} = $data->{incomingType}; # This is the Shapeshift deposit coin type
			$data->{valueX} = $data->{outgoingCoin}; # This is the Shapeshift withdraw amount
			$data->{valueccy} = $data->{outgoingType}; # This is the Shapeshift withdraw coin type
			$data->{rate} = 'NULL';
			$data->{rateccy} = 'NULL';
			$data->{fee} = 'NULL';
			$data->{feeccy} = 'NULL';
			$data->{owner} = addressDesc($data->{toaccount}, 'Owner');
			$data->{hash} = "$data->{transaction}-SS"; # This is the transaction hash for the outgoing transaction SS to identify it as ShapeShift and keep hashes unique
			if ($opt{track} and $opt{track} eq $data->{toaccount}) {
				say "Tracking address $opt{track}";
				print Dumper $data;
			}
			if ($opt{track} and $opt{track} eq $data->{status}) {
				say "Tracking status $opt{track}";
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
#				say "$address,ShapeShift,ShapeShift $data->{incomingCoin} $data->{incomingType} to $data->{outgoingCoin} $data->{outgoingType} $data->{transaction}";
				push(@$transactions, $data);
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
	return $transactions;
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
    print "TradeType,Subtype,DateTime,Account,ToAccount,Amount,AmountCcy,ValueX,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Owner,Hash\n";
    for my $rec (@$trans) {
    	my $dt = $rec->{dt};
    	my $datetime = $dt->datetime(" ");
    	$rec->{subtype} ||= 'NULL';
    	$rec->{toaccount} ||= 'NULL';
    	$rec->{valueX} ||= 'NULL';
    	$rec->{valueccy} ||= 'NULL';
    	$rec->{rate} ||= 'NULL';
    	$rec->{rateccy} ||= 'NULL';
    	$rec->{fee} ||= 'NULL';
    	$rec->{feeccy} ||= 'NULL';
    	$rec->{owner} ||= 'NULL';
       	print "$rec->{type},$rec->{subtype},$datetime,$rec->{account},$rec->{toaccount},$rec->{amount},$rec->{amountccy},$rec->{valueX},$rec->{valueccy},$rec->{rate},$rec->{rateccy},$rec->{fee},$rec->{feeccy},$rec->{owner},$rec->{hash}\n";
	}
}

sub printEnrichedAddressDesc {
	my ($trans, $desc) = @_;
    print "Address,Owner,Desc,AccountName,Follow,Currency,AccountType,ShapeShift\n";
    for my $rec (@$trans) {
    	my $from = $rec->{account};
    	my $to = $rec->{toaccount};
    	my $ssfrom = $desc->{$from}{ShapeShift};
    	my $ssto = $desc->{$to}{ShapeShift};
    	if (! exists $desc->{$from}) {
    		say "Unexpected desc->from doesn't exist: $from";
    		next;
    	}
    	if (! exists $desc->{$to}) {
    		say "Unexpected desc->to doesn't exist: $to";
    		next;
    	}
    	$desc->{$from}{ShapeShift} = "Input";
    	$desc->{$from}{incomingType} = $rec->{incomingType};
    	$desc->{$to}{ShapeShift} = "Output";
    	$desc->{$to}{outgoingType} = $rec->{outgoingType};
    	if($ssfrom and $ssfrom ne $desc->{$from}{ShapeShift}) {
    		say "Unexpected ssfrom: $ssfrom desc->{from}{ShapeShift} $desc->{$from}{ShapeShift} $from";
    	}
    	if($ssto and $ssto ne $desc->{$to}{ShapeShift}) {
    		say "Unexpected ssto: $ssto desc->{to}{ShapeShift} $desc->{$to}{ShapeShift} $to";
    	}
    }
    for my $addr (sort keys %$desc) {
    	my $h = $desc->{$addr};
    	if($h->{ShapeShift} eq 'Output') {
    		$h->{Owner} ||= 'ShapeShift';
    		$h->{Desc} ||= 'ShapeShift transfer';
    		$h->{AccountName} ||= substr($addr,0,8);
    		$h->{Follow} ||= 'Y';
    		$h->{Follow} = 'Y' if $h->{Follow} eq 'NULL';
    		$h->{Currency} ||= $h->{outgoingType};
    		$h->{AccountType} ||= 'Wallet';
    	}
    	if($h->{ShapeShift} eq 'Input') {
    		$h->{Owner} ||= 'ShapeShift';
    		$h->{Desc} ||= 'ShapeShift deposit';
    		$h->{Desc} = 'ShapeShift deposit' if lc $h->{Desc} eq 'shapeshift transfer';
    		$h->{Desc} = 'ShapeShift deposit' if lc $h->{Desc} eq 'shapeshift deposit';
    		$h->{AccountName} ||= substr($addr,0,8);
    		$h->{Follow} = 'N';
    		$h->{Currency} ||= $h->{incomingType};
    		$h->{AccountType} ||= 'Wallet';
    	}
    	if (exists $h->{outgoingType} and $h->{Currency} ne $h->{outgoingType}) {
    		say "Unexpected desc currency on $addr $h->{Currency} vs. SS outgoingType $h->{outgoingType}";
    	}
       	print "$addr,$h->{Owner},$h->{Desc},$h->{AccountName},$h->{Follow},$h->{Currency},$h->{AccountType},$h->{ShapeShift}\n";
	}
}

# Main Program

my $d = addressDesc();
if ($opt{start}) { # for interactive use to check a single address
	my $x = getTxStat($opt{start});
	say Dumper $x;
	exit 0;
}
if ($opt{enrichedAddress}) { # Tidy up addressDesc file with data from ShapeShift
	my $t = getTransactionsFromAddressDesc($d);
	printEnrichedAddressDesc($t,$d); # Adds ShapeShift Data to the AddressDescription file
	exit 0;
}


my $t = getTransactionsFromAddressDesc($d);
printMySQLTransactions($t);
#printOutputData($t,'BTC');
#printOutputData($t,'ETH');
#printOutputData($t,'DASH');
#	if ($i->{address} eq '0x056a157691922ec30ee833c51446515e0960e167') {
#		say "Found it 0x056a157691922ec30ee833c51446515e0960e167";
#	}
#}
saveTransactions($t);

exit(0);

