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
use Person;


# Process Blockchain.info API

# Commandline args
GetOptions('datadir:s' => \$opt{datadir}, # Data Directory address
			'g:s' => \$opt{g}, #
			'h' => \$opt{h}, #
			'key:s' => \$opt{key}, # API key to access etherscan.io
			'owner:s' => \$opt{owner}, #
			'quick!' => \$opt{quick},
			'start:s' => \$opt{start}, # starting address
			'trace:s' => \$opt{trace}, # trace hash or address
			'trans:s' => \$opt{trans}, # Blockchain transactions datafile
			'ss' => \$opt{ss}, # Process all ShapeShift transactions to harvest relevant BCH addresses
			'sstrans:s' => \$opt{sstrans}, # Shapeshift transactions datafile
			'testArmory!' => \$opt{testArmory},
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{key} ||= ''; # from etherscan.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
$opt{start} ||= "";
$opt{trans} ||= "BCHTransactions.dat";
$opt{sstrans} ||= "ShapeshiftTransactions.dat";

my $url = "https://bch-chain.api.btc.com";
my $txurl = "${url}/v3/tx/";
my $txurlsuffix = "?verbose=2";
my $addrurl = "${url}/v3/address/";
my $addrurlsuffix = "/tx";

my $BCHForkTime = DateTime->new(year=>2017,month=>8,day=>1,hour=>13,minute=>16,second=>14,time_zone=>'UTC');

sub getTx {
	my $tran = shift;
	state $processed;
#	$tran = lc $tran; # Can't lowercase BitcoinCash addresses or transactions
	return undef if ($processed->{$tran});
	$processed->{$tran} = 1;
	my $cachefile = "$opt{datadir}/BCHtx$tran.json"; # reads from cache file if one exists. Otherwise calls api and stores to cache file
	my $data = {};
	if (-e $cachefile) {
		$data = retrieve($cachefile);
		if (ref($data) eq 'HASH' and $data->{hash} eq "$tran") {
			return $data;
		}
		elsif ($data->{err_no}) {
			say "Transaction: $tran Error:$data->{err_msg}";
			return undef; #Fail
		} else {
			say "Transaction: $tran Unknown Error";
			return undef; #Fail
		}
	}
	my $url = "${txurl}${tran}${txurlsuffix}";
	say "$url";
	my $ua = new LWP::UserAgent;
	$ua->agent("banana/1.0");
	my $request = new HTTP::Request("GET", $url);
	my $response = $ua->request($request);
	my $content = $response->content;
	if ($content eq "Transaction not found") {
		say "$content $tran";
		$content = "";
	}

	if ($content) {
		$data = parse_json($content);
		if (ref($data->{data}) eq 'HASH' and $data->{data}{hash} eq "$tran") {
			store($data->{data}, $cachefile);
			return $data->{data};
		}
	}
	if ($data->{err_no}) {
		say "Transaction: $tran Error:$data->{err_msg}";
		store($data, $cachefile);
	}

	return undef; # Fail if we get here
}

sub getAddr {
	my ($address, $docache) = @_;
	$docache ||= 1; # Normally we want to cache results. Except when testing addresses eg for Armory wallet
	state $processedad;
#	$address = lc $address; # Can't lowercase BitcoinCash addresses or transactions
	$address =~ s/-bch//; # We can and should trim off any -bch unique suffix
	return undef if ($processedad->{$address} or AccountsList->address($address,'Follow') eq 'N');
	$processedad->{$address} = 1;
	my $cachefile = "$opt{datadir}/BCHaddr$address.json"; # reads from cache file if one exists. Otherwise calls api and stores to cache file
	my $result = 0;
	if (-e $cachefile) {
		$result = retrieve($cachefile);
		return $result;
	}
	my $url = "${addrurl}$address";
	say $url;
	my $ua = new LWP::UserAgent;
	$ua->agent("banana/1.0");
	my $request = new HTTP::Request("GET", $url);
	my $response = $ua->request($request);
	my $content = $response->content;
	if ($content eq "AccountRef not found" or $content =~ /^Illegal character/ or $content =~ /^Can't connect/) {
		say "$content address:$address";
		$content = "";
	}

	#say $content;
	my $data = {};
	if ($content) {
		my $data = parse_json($content);
		if (ref($data->{data}) eq 'HASH' and $data->{data}{address} eq "$address") {
			store($data->{data}, $cachefile) if $docache;
			return $data->{data};
		}
	}
	store($data, $cachefile) if $docache;
	return $data;
}

sub getAddrTransactions {
	my ($address, $docache) = @_;
	$docache ||= 1; # Normally we want to cache results. Except when testing addresses eg for Armory wallet
	state $processedad;
#	$address = lc $address; # Can't lowercase BitcoinCash addresses or transactions
	$address =~ s/-bch//; # We can and should trim off any -bch unique suffix
	return undef if ($processedad->{$address} or AccountsList->address($address,'Follow') eq 'N');
	$processedad->{$address} = 1;
	my $cachefile = "$opt{datadir}/BCHaddrTx$address.json"; # reads from cache file if one exists. Otherwise calls api and stores to cache file
	my $data = 0;
	if (-e $cachefile) {
		$data = retrieve($cachefile);
		if (ref($data) eq 'ARRAY') {
			return $data;
		}
		elsif (ref($data) eq 'HASH' and $data->{err_no} == 0) {
			return $data->{data}{list};
		}
		elsif (ref($data) eq 'HASH') {
			say "AccountRef $address Error no:$data->{err_no} msg:$data->{err_msg}";
			store($data,$cachefile);
			return 0;
		}
	}
	my $url = "${addrurl}$address${addrurlsuffix}";
	say $url;
	my $ua = new LWP::UserAgent;
	$ua->agent("banana/1.0");
	my $request = new HTTP::Request("GET", $url);
	my $response = $ua->request($request);
	my $content = $response->content;
	if ($content eq "Resource not found" or $content =~ /^Illegal character/ or $content =~ /^Can't connect/) {
		say "$content address:$address";
		$content = "";
	}

	#say $content;
	my $data = 0;
	if ($content) {
		my $data = parse_json($content);
		if (ref($data) eq 'HASH' and $data->{err_no} == 0) {
			store($data->{data}{list}, $cachefile) if $docache;
			return $data->{data}{list};
		}
		else {
			say "AccountRef $address Error no:$data->{err_no} msg:$data->{err_msg}";
			store({},$cachefile);
			return 0;
		}
	}
	return $data;
}

sub printTx {
	my $tran = shift;
	my $in = $tran->{inputs};
	my $out = $tran->{outputs};
	my $ts = $tran->{'block_time'};
	my $hash = $tran->{'hash'};
	my ($sumin, $sumout) = (0,0);
	my $dt = DateTime->from_epoch(epoch => $ts);
	say $dt->dmy('/'), " ", $dt->hms(), " $hash";
	say "Inputs";
	foreach my $i (@$in) {
		my $val = $i->{prev_value} / 1e8;
		$sumin += $val;
		my $addr = $i->{prev_addresses}[0];
		say "\t$val $addr";
	}
	say "Outputs";
	foreach my $o (@$out) {
		my $val = $o->{value} / 1e8;
		$sumout += $val;
		my $addr = $o->{addresses}[0];
		say "\t$val $addr";
	}
	my $fee = $sumin - $sumout;
	say "Sum of inputs: $sumin Sum of outputs: $sumout Fee: $fee";
}

sub printTxFromSS {
	my ($tran, $ssqty, $ssaddress) = @_;
	my $in = $tran->{inputs};
	my $out = $tran->{outputs};
	my $ts = $tran->{'block_time'};
	my $hash = $tran->{'hash'};
	my ($sumin, $sumout) = (0,0);
	my $dt = DateTime->from_epoch(epoch => $ts);
	foreach my $i (@$in) {
		my $val = $i->{prev_value};
		$val /= 1e8;
		$sumin += $val;
		my $addr = $i->{prev_addresses}[0];
		if ($addr eq $ssaddress and $val == $ssqty) {
			say $dt->dmy('/'), " ", $dt->hms(), " $val BCH $addr Shapeshift Input";
		}
	}
	foreach my $o (@$out) {
		my $val = $o->{value};
		$val /= 1e8;
		$sumout += $val;
		my $addr = $o->{addresses}[0];
		if ($addr eq $ssaddress and $val == $ssqty) {
			say $dt->dmy('/'), " ", $dt->hms(), " $val BCH $addr Shapeshift Output";
			my $d = getAddr($addr);
			my $txs = getAddrTransactions($addr);
			foreach my $tran (@$txs) {
				my $h = $tran->{'hash'};
				say "hash $h";
#				getTx($h);
			}
		}
	}
	my $fee = $sumin - $sumout;
#	say "Sum of inputs: $sumin Sum of outputs: $sumout Fee: $fee";
}

#Shapeshift transaction records give the txhash, CCY and Amount of the withdrawal.
# For all BCH withdrawals from Shapeshift we can collect the Blockchain info
sub processShapeShiftTransactions {
	my $sst = retrieve("$opt{datadir}/$opt{sstrans}");
	foreach my $t (@$sst) {
		if ($t->{outgoingType} eq 'BCH') {
			my ($txhash, $qty, $address) = ($t->{transaction}, $t->{outgoingCoin}, $t->{withdraw});
			my $tran = getTx($txhash);
			if (defined $tran and ref($tran) eq 'HASH') {
				printTxFromSS($tran, $qty, $address);
			}
		}
	}
}

sub getTransactionsFromAccountsList {
	my $transactions = [];
	my $processed;
	my $accounts = AccountsList->addresses('BCH');
	foreach my $address (sort keys %$accounts) {
		my $owner = $accounts->{$address}{Owner};
		my $follow = $accounts->{$address}{Follow} eq 'Y';
		my $currency = $accounts->{$address}{Currency};
		my $sstype = $accounts->{$address}{ShapeShift}; # set to Input or Output if this is a ShapeShift transaction

		if ($currency eq 'BCH' and $follow ) {
			my $txs = getAddrTransactions($address);
			next unless ref($txs) eq 'ARRAY';
			foreach my $tran (@$txs) {
				my $h = $tran->{'hash'};
				#say "address $address owner $owner hash $h";
				push @$transactions, $h;
			}
		}
	}
	return $transactions;
}

sub doSOmethingUseful {
	my $hashes = shift;
	my $transactions = [];
	foreach my $hash (@$hashes) {
		if ($opt{trace} and $opt{trace} eq $hash) {
			say "Tracing hash $hash";
		}
		my $data = getTx($hash);
		next unless defined $data and ref($data) eq 'HASH';

		my $ins = $data->{inputs};
		my $outs = $data->{outputs};
		foreach my $in (@$ins) {
			my $addr = $in->{prev_addresses}[0];
			if ($opt{trace} and $opt{trace} eq $addr) {
				say "Tracing input address $addr";
			}
			$data->{invalue} += $in->{prev_value};
			my $owner = AccountsList->address($addr,'Owner');
			$in->{inowner} = $owner;
			$data->{inownercount}{$owner}++;
			my $follow = AccountsList->address($addr,'Follow');
			$in->{infollow} = $follow;
			$data->{infollowcount}{$follow}++;
			my $ss = AccountsList->address($addr,'ShapeShift');
			$in->{ShapeShift} = $ss;
			$data->{inshapeshiftcount}{$ss}++;
			$in->{AccountRefUnique} = AccountsList->address($addr,'AccountRefUnique') || $addr;
			$data->{incount}++;
		}
		foreach my $out (@$outs) {
			my $addr = $out->{addresses}[0];
			if ($opt{trace} and $opt{trace} eq $addr) {
				say "Tracing output address $addr";
			}
			$data->{outvalue} += $out->{value};
			my $owner = AccountsList->address($addr,'Owner');
			$data->{outknowncount}++ if $owner;
			$out->{owner} = $owner;
			$data->{outownercount}{$owner}++;
			my $follow = AccountsList->address($addr,'Follow');
			$out->{outfollow} = $follow;
			$data->{outfollowcount}{$follow}++;
			my $ss = AccountsList->address($addr,'ShapeShift');
			$out->{ShapeShift} = $ss;
			$data->{outshapeshiftcount}{$ss}++;
			$out->{AccountRefUnique} = AccountsList->address($addr,'AccountRefUnique') || $addr;
			$data->{outcount}++;
		}
		if ($data->{outfollowcount}{'Y'} == 1 and $data->{inownercount}{''} == $data->{incount}) {
			# Many to one (or 2) many inputs can be collapsed into one dummy address
			# This is a ShapeShift Output transaction. There could be many inputs and they are all ShapeShift internal addresses (unknown to AccountsList->)
			# There will be one or two outputs. One is the AccountRef that ShapeShift has sent the funds to - it should be owned by one of us with Follow=Y
			# The second output address is optional change address and would not be known to us
			# There may be trades other than ShapeShift that fit the same criteria, so we don't check that every input is ShapeShift=Output address.
			# Create a transaction with a dummy input and full amount of transaction to the output address.
			# Find the output address with Follow=Y
			my $out; # There is only one output address - let's find it
			foreach my $o (@$outs) {
				if ($o->{outfollow} eq 'Y') {
					$out = $o;
					last;
				}
			}
			my $account = "Unknown addresses";
			$account = "ShapeShiftInternalAddresses" if $out->{ShapeShift} eq 'Output'; # output ShapeShift withdrawal address, therefore input is SS internal
			$account = "BitstampInternalAddresses" if $data->{inownercount}{'Bitstamp'} > 0; # We only need to identify 1 input in the Accounts file
			$account = "itBitInternalAddresses" if $data->{inownercount}{'itBit'} > 0; # We only need to identify 1 input in the Accounts file
			$account = "MtGoxWithdraw" if $data->{inownercount}{'MtGox'} > 0; # We only need to identify 1 input in the Accounts file
			$account = "LocalBitcoins" if $data->{inownercount}{'LocalBitcoins'} > 0; # We only need to identify 1 input in the Accounts file

			$data->{type} = "Transfer";
			$data->{subtype} = "BitcoinCash";
			$data->{account} = $account;
			$data->{toaccount} = $out->{AccountRefUnique}; # This is the Shapeshift withdraw address - outgoing from ShapeShift
			$data->{amount} = $out->{value} / 1e8; # This is the amout of BCH credited from the ShapeShift transaction
			$data->{amountccy} = 'BCH';
			$data->{valueX} = 'NULL'; # This is the Shapeshift withdraw amount
			$data->{valueccy} = 'NULL'; # This is the Shapeshift withdraw coin type
			$data->{rate} = 'NULL';
			$data->{rateccy} = 'NULL';
			$data->{fee} = 'NULL'; # We are not interested in the BitcoinCash mining fee, our fee is the spread from ShapeShift
			$data->{feeccy} = 'NULL';
			$data->{owner} = $out->{owner};
			$data->{hash} = $data->{hash}; # This is the transaction hash for the overall transaction. Populated by btc.com
			$data->{dt} = DateTime->from_epoch(epoch => $data->{block_time});
			push @$transactions, $data;
		}
		elsif ($data->{infollowcount}{'Y'} == $data->{incount} and $data->{outknowncount} == 1 and $data->{outcount} == 1 ) {
			# Many to one
			# All the inputs are Follow addresses. e.g. this may be a withdrawal from multiple Jaxx addresses to a cold storage or Bitstamp address
			# We need to create one transaction for each of the inputs
			# There should be at least one output account that is relevant for us (known address). It may or may not be a Follow account
			# Owner should be the input owner since that is the sender - they own the transaction as they initiated it
			# If there are unknown outputs, they need to be investigated. For now test that outcount == outknowncount

			my $out; # There is only one output address - let's find it
			foreach my $o (@$outs) {
				if (defined $o->{owner}) {
					$out = $o;
					last;
				}
			}
			my $index = 0;
			foreach my $in (@$ins) {
				my $account = $in->{AccountRefUnique};

				$data->{type} = "Transfer";
				$data->{subtype} = "BitcoinCash";
				$data->{account} = $account;
				$data->{toaccount} = $out->{AccountRefUnique}; # This is the Shapeshift withdraw address - outgoing from ShapeShift
				$data->{amount} = $in->{prev_value} / 1e8; # This is the amout of BCH credited from the ShapeShift transaction
				$data->{amountccy} = 'BCH';
				$data->{valueX} = 'NULL'; # This is the Shapeshift withdraw amount
				$data->{valueccy} = 'NULL'; # This is the Shapeshift withdraw coin type
				$data->{rate} = 'NULL';
				$data->{rateccy} = 'NULL';
				$data->{fee} = 'NULL'; # We are not interested in the BitcoinCash mining fee, our fee is the spread from ShapeShift
				$data->{feeccy} = 'NULL';
				$data->{owner} = $in->{owner};
				$data->{hash} = "$hash-$index"; # This is the transaction hash for the overall transaction.258
				$data->{dt} = DateTime->from_epoch(epoch => $data->{block_time});

				my $sub = dclone($data);
				push @$transactions, $sub;
				$index++;

			}

		}
		elsif ($data->{infollowcount}{'Y'} == 1 and $data->{incount} == 1 and $data->{outknowncount} == $data->{outcount}) {
			# One to many
			# The single input is a Follow address. e.g. this may be a withdrawal from Jaxx address to a ShapeShift or Bitstamp address
			# Two outputs - one is change back to the wallet (known, Follow) other is to destination (known)
			# We need to create one transaction for each of the outputs
			# Owner should be the input owner since that is the sender - they own the transaction as they initiated it
			# If there are unknown outputs, they need to be investigated. For now test that outcount == outknowncount

			my $in; # There is only one input address - let's find it
			foreach my $i (@$ins) {
				if (defined $i->{inowner}) {
					$in = $i;
					last;
				}
			}
			my $index = 0;
			foreach my $out (@$outs) {
				my $account = $out->{AccountRefUnique};

				$data->{type} = "Transfer";
				$data->{subtype} = "BitcoinCash";
				$data->{account} = $in->{AccountRefUnique};
				$data->{toaccount} = $account;
				$data->{amount} = $out->{value} / 1e8; # This is the amout of BCH going to this output
				$data->{amountccy} = 'BCH';
				$data->{valueX} = 'NULL'; # This is the Shapeshift withdraw amount
				$data->{valueccy} = 'NULL'; # This is the Shapeshift withdraw coin type
				$data->{rate} = 'NULL';
				$data->{rateccy} = 'NULL';
				$data->{fee} = 'NULL'; # We are not interested in the BitcoinCash mining fee
				$data->{feeccy} = 'NULL';
				$data->{owner} = $in->{inowner};
				$data->{hash} = "$hash-$index"; # This is the transaction hash hyphen index
				$data->{dt} = DateTime->from_epoch(epoch => $data->{block_time});

				my $sub = dclone($data);
				push @$transactions, $sub;
				$index++;

			}
		}
		elsif ($data->{infollowcount}{'Y'} >= 1 ) { # and $data->{outknowncount} == $data->{outcount}
			# Many to many - Follows on input, known on output
			# The inputs are all Follow addresses. e.g. this may be a withdrawal from Jaxx address to a ShapeShift or Bitstamp address
			# Two outputs - one is change back to the wallet (known, Follow) other is to destination (known)
			# We need to create one transaction for each of the inputs and one for each outputs
			# Owner should be the input owner since that is the sender - they own the transaction as they initiated it
			# If there are unknown outputs, they need to be investigated. For now test that outcount == outknowncount

			my $in; # There is only one input address - let's find it
			my $index = 0;
			my $journal = "JournalAccount";
			foreach my $in (@$ins) {
				my $account = $in->{AccountRefUnique};

				$data->{type} = "Transfer";
				$data->{subtype} = "BitcoinCash";
				$data->{account} = $account;
				$data->{toaccount} = $journal; #$out->{addr};
				$data->{amount} = $in->{prev_value} / 1e8; # This is the amout of BCH credited from the ShapeShift transaction
				$data->{amountccy} = 'BCH';
				$data->{valueX} = 'NULL'; # This is the Shapeshift withdraw amount
				$data->{valueccy} = 'NULL'; # This is the Shapeshift withdraw coin type
				$data->{rate} = 'NULL';
				$data->{rateccy} = 'NULL';
				$data->{fee} = 'NULL'; # We are not interested in the BitcoinCash mining fee, our fee is the spread from ShapeShift
				$data->{feeccy} = 'NULL';
				$data->{owner} = $in->{owner};
				$data->{hash} = "$hash-$index"; # This is the transaction hash for the overall transaction.258
				$data->{dt} = DateTime->from_epoch(epoch => $data->{block_time});

				my $sub = dclone($data);
				push @$transactions, $sub;
				$index++;

			}
			foreach my $out (@$outs) {
				my $account = $out->{addresses}[0];

				$data->{type} = "Transfer";
				$data->{subtype} = "BitcoinCash";
				$data->{account} = $journal; #$in->{AccountRefUnique};
				$data->{toaccount} = $account;
				$data->{amount} = $out->{value} / 1e8; # This is the amount of BCH going to this output
				$data->{amountccy} = 'BCH';
				$data->{valueX} = 'NULL'; # This is the Shapeshift withdraw amount
				$data->{valueccy} = 'NULL'; # This is the Shapeshift withdraw coin type
				$data->{rate} = 'NULL';
				$data->{rateccy} = 'NULL';
				$data->{fee} = 'NULL'; # We are not interested in the BitcoinCash mining fee
				$data->{feeccy} = 'NULL';
				$data->{owner} = $in->{inowner};
				$data->{hash} = "$hash-$index"; # This is the transaction hash hyphen index
				$data->{dt} = DateTime->from_epoch(epoch => $data->{block_time});

				my $sub = dclone($data);
				push @$transactions, $sub;
				$index++;

			}
		}
		else {
			say "Not sure what to do with transaction $hash $data->{incount} F=$data->{infollowcount}{Y} SS=$data->{inownercount}{ShapeShift} => $data->{outcount} F=$data->{outfollowcount}{N} K=$data->{outknowncount} SS=$data->{outshapeshiftcount}{Output} ";

			next;
		}

	}
	return $transactions;
}

# Example transaction ce5a3077dded32db95db46724ecd79eec4d9226ef4505cd9e0298307bc89022f
#		Bitstamp output transaction crediting many addresses in a single transaction - only one is ours
#		Many unknown inputs (Internal Bitstamp addresses)
#		Many outputs with just 1 known

# Example transaction 65949e2c927776359f79e7d738337e24eedfaf25c59939deac1078fc9998a1d0
#		6 inputs from Jaxx wallet - all are ShapeShift=Output, Follow=Y
#		2 outputs: 1 to Bitstamp Deposit (Follow=N), 1 change back to a Jaxx wallet address

# Example transaction https://blockchair.com/bitcoin/transaction/f21ce056bb04c8ee5b08a947f9891ab39243d0e52a547d07f2403795ef2fef25
#		1 input from eg Jaxx Wallet - known, follow=Y
#		2 outputs eg one to SS or Bitstamp deposit (Follow=N) and one returning as change to our wallet: known, follow=Y

# Example transaction 65949e2c927776359f79e7d738337e24eedfaf25c59939deac1078fc9998a1d0
#		Many to many eg Jaxx to Bitstamp with change back to Jaxx
#		several inputs eg from Jax Wallet all with Follow=Y all known
#		normally 2 outputs - one change and one destination. all known

# Example transaction f6aa903d87b4001bcdba52569e507876743f7558e40388f2e12712dec3680e3e
#		Many to many - withdraw BCH from Bitstamp with change back to Bitstamp
#		One or more inputs from  eg from Jax Wallet all with Follow=Y all known
#		normally 2 outputs - one change and one destination.



sub printMySQLTransactions {
	my $trans = shift;
    print "TradeType,Subtype,DateTime,Account,ToAccount,Amount,AmountCcy,ValueX,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Owner,Hash\n";
    for my $rec (sort {$a->{dt} <=> $b->{dt}} @$trans) {
    	my $dt = $rec->{dt};
    	next if $dt < $BCHForkTime; # Don't print BCH transactions before the fork
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

sub printTransactions {
	my ($transactions,$address) = @_;
	my $processed;
	foreach my $t (sort {$a->{dt} <=> $b->{dt}} @$transactions) {
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
    	my $datetime = $t->{dt}->datetime(" ");
		next if $address and $t->{from} ne $address and $t->{to} ne $address;
		my $fromAccount = AccountsList->address($t->{account});
		my $toAccount = AccountsList->address($t->{toaccount});
		my $fromS = substr($t->{account},0,8);
		my $toS = substr($t->{toaccount},0,8);
		my $shorthash = substr($t->{hash},0,6) . ".." . substr($t->{hash},-6,6);
		print "$datetime $fromS $fromAccount->{Owner} $fromAccount->{AccountName} $t->{'amount'} $t->{amountccy} $toAccount->{AccountName} $toAccount->{Owner} $toS $shorthash\n";
	}
}

sub testArmoryAddresses {
	my $armoryAddressFile = "armoryFull.txt";
	open(my $fh, "<", $armoryAddressFile) || die "Failed to open $armoryAddressFile";
	my $ids;
	my ($file,$name,$id,$a,$c);
	while(<$fh>) {
		s/\r//;
		chomp;
		if ($_ =~ /^arm/) {
			say $_;
			($file, $name) = split(" ",$_,2);
			($a,$id,$c) = split("_", $file);
#			say "file:$file name:$name id:$b";
		}
		next unless $_ =~ /^1/;
		$ids->{$_} = {id => $id, 'name' => $name};
		#my $res = getAddr($_,1);
		#say "$_ $res->{n_tx}";
	}
#	say Dumper $ids;
#	return;
	my $armoryAddressFile = "armoryUsed.txt";
	open(my $fh, "<", $armoryAddressFile) || die "Failed to open $armoryAddressFile";
	while(<$fh>) {
		s/\r//;
		chomp;
		next unless $_ =~ /^1/;
		my $res = getAddr($_,1);
		if ($res->{n_tx} > 0) {
			my $owner = $ids->{$_}{name};
			$owner =~ s/s .*//;
			say "$_,$owner,Armory $ids->{$_}{name},$owner Armory $ids->{$_}{id},Y,BCH,Wallet,";
		}
	}
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}


AccountsList->new();
AccountsList->backCompatible();

if ($opt{start}) {
	my $d = getTx($opt{start});
	if (defined $d and ref($d) eq 'HASH') {
		printTx($d) if $d;
	}
}
elsif ($opt{ss}) {
	processShapeShiftTransactions();

}
elsif ($opt{testArmory}) {
	testArmoryAddresses();
}
elsif ($opt{quick}) {
	my $t = getTransactionsFromAccountsList();
	my $t1 = doSOmethingUseful($t);
	printTransactions($t1);
	saveTransactions($t1);
}
else {
	my $t = getTransactionsFromAccountsList();
	my $t1 = doSOmethingUseful($t);
	printMySQLTransactions($t1);
	saveTransactions($t1);
}

# NULL addresses
# Tokens - VEE, Stellar, ...
