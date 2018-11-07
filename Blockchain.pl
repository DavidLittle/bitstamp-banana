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


# Process Blockchain.info API

# Commandline args
GetOptions(
	'counts!' => \$opt{counts}, # Calc and print balances
	'datadir:s' => \$opt{datadir}, # Data Directory address
	'balances!' => \$opt{balances}, # Calc and print balances
	'quick!' => \$opt{quick},
	'start:s' => \$opt{start}, # starting address
	'trace:s' => \$opt{trace}, # trace hash or address
	'trans:s' => \$opt{trans}, # Blockchain transactions datafile
	'ss' => \$opt{ss}, # Process all ShapeShift transactions to harvest relevant BTC addresses
	'sstrans:s' => \$opt{sstrans}, # Shapeshift transactions datafile
	'testArmory!' => \$opt{testArmory},
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{key} ||= ''; # from etherscan.io
$opt{start} ||= "";
$opt{trans} ||= "BlockchainTransactions.dat";
$opt{sstrans} ||= "ShapeshiftTransactions.dat";


my $url = "https://blockchain.info/";
my $txurl = "${url}rawtx/";
my $addrurl = "${url}rawaddr/";
my $addrurlsuffix = "?&n=50&offset=";
my %counts;

my $BCHForkTime = DateTime->new(year=>2017,month=>8,day=>1,hour=>13,minute=>16,second=>14,time_zone=>'UTC');

sub getTx {
	my $tran = shift;
	state $processed;
#	$tran = lc $tran; # Can't lowercase bitcoin addresses or transactions
	return undef if ($processed->{$tran});
	$processed->{$tran} = 1;
	my $cachefile = "$opt{datadir}/BTCtx$tran.json"; # reads from cache file if one exists. Otherwise calls api and stores to cache file
	my $result = 0;
	if (-e $cachefile) {
		$result = retrieve($cachefile);
		return $result;
	}
	my $url = "${txurl}$tran";
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
		my $data = parse_json($content);
		if ($data->{hash} eq "$tran") {
			store($data, $cachefile);
			return $data;
		}
	}
	store(undef, $cachefile);
	return undef;
}

sub getAddr {
	my ($address) = @_;
	state $processedad;
#	$address = lc $address; # Can't lowercase bitcoin addresses or transactions
	return undef if ($processedad->{$address} or AccountsList->address($address,'Follow') eq 'N');
	$processedad->{$address} = 1;
	my $cachefile = "$opt{datadir}/BTCaddr$address.json"; # reads from cache file if one exists. Otherwise calls api and stores to cache file
	my $result = 0;
	if (-e $cachefile) {
		$result = retrieve($cachefile);
		return $result;
	}
	my $offset = 0;
	my $n_tx = 0; # Total number of transactions on this address (returned by API)
	my $count_retrieved = -1;
	my $txndata = [];
	my $url;
	my $data;

	while ($count_retrieved < $n_tx) {
		$url = "${addrurl}$address${addrurlsuffix}$offset";
		say "$url";
		my $ua = new LWP::UserAgent;
		$ua->agent("banana/1.0");
		my $request = new HTTP::Request("GET", $url);
		my $response = $ua->request($request);
		my $content = $response->content;
		if ($content eq "Address not found" or $content =~ /^Illegal character/ or $content =~ /^Can't connect/ or $content =~ /Checksum does not validate/) {
			say "$content address:$address";
			$content = "";
		}

		#say $content;
		if ($content) {
			$data = parse_json($content);

			$n_tx = $data->{n_tx}; # Total number of transactions for this address
			push @$txndata, @{$data->{txs}}; # Array of transactions retrieved (max 50)
			$count_retrieved = scalar(@{$txndata});
			say "n_tx:$n_tx count_retrieved:$count_retrieved";
			$offset += 50; # Ready for the next batch (if needed)
		}
		else {
			die "Problem retrieving transactions from $url"; # die to avoid infinite loop
		}
	}

	$data->{txs} = $txndata;
	if ($data->{address} eq "$address") {
		store($data, $cachefile);
	}
	return $data;
}

sub printTx {
	my $tran = shift;
	my $in = $tran->{inputs};
	my $out = $tran->{out};
	my $ts = $tran->{'time'};
	my $hash = $tran->{'hash'};
	my ($sumin, $sumout) = (0,0);
	my $dt = DateTime->from_epoch(epoch => $ts);
	say $dt->dmy('/'), " ", $dt->hms(), " $hash";
	say "Inputs";
	foreach my $i (@$in) {
		my $val = $i->{prev_out}{value};
		$sumin += $val;
		my $addr = $i->{prev_out}{addr};
		say "\t$val $addr";
	}
	say "Outputs";
	foreach my $o (@$out) {
		my $val = $o->{value};
		$sumout += $val;
		my $addr = $o->{addr};
		say "\t$val $addr";
	}
	my $fee = $sumin - $sumout;
	say "Sum of inputs: $sumin Sum of outputs: $sumout Fee: $fee";
}

sub printTxFromSS {
	my ($tran, $ssqty, $ssaddress) = @_;
	my $in = $tran->{inputs};
	my $out = $tran->{out};
	my $ts = $tran->{'time'};
	my $hash = $tran->{'hash'};
	my ($sumin, $sumout) = (0,0);
	my $dt = DateTime->from_epoch(epoch => $ts);
	foreach my $i (@$in) {
		my $val = $i->{prev_out}{value};
		$val /= 1e8;
		$sumin += $val;
		my $addr = $i->{prev_out}{addr};
		if ($addr eq $ssaddress and $val == $ssqty) {
			say $dt->dmy('/'), " ", $dt->hms(), " $val BTC $addr Shapeshift Input";
		}
	}
	foreach my $o (@$out) {
		my $val = $o->{value};
		$val /= 1e8;
		$sumout += $val;
		my $addr = $o->{addr};
		if ($addr eq $ssaddress and $val == $ssqty) {
			say $dt->dmy('/'), " ", $dt->hms(), " $val BTC $addr Shapeshift Output";
			my $d = getAddr($addr);
			my $a = $d->{txs};
			foreach my $tran (@$a) {
				my $h = $tran->{'hash'};
				say "hash $h";
				getTx($h);
			}
		}
	}
	my $fee = $sumin - $sumout;
#	say "Sum of inputs: $sumin Sum of outputs: $sumout Fee: $fee";
}

#Shapeshift transaction records give the txhash, CCY and Amount of the withdrawal.
# For all BTC withdrawals from Shapeshift we can collect the Blockchain info
sub processShapeShiftTransactions {
	my $sst = retrieve("$opt{datadir}/$opt{sstrans}");
	foreach my $t (@$sst) {
		if ($t->{outgoingType} eq 'BTC') {
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
	my $accounts = AccountsList->addresses('BTC');
	foreach my $address (sort keys %$accounts) {
		my $follow = $accounts->{$address}{Follow} eq 'Y';
		my $currency = $accounts->{$address}{Currency};
		if ($opt{trace} and $opt{trace} eq $address) {
			say "Tracing input address $address";
		}


		if ($currency eq 'BTC' and $follow ) {
			my $data = getAddr($address);
			my $a = $data->{txs};
			foreach my $tran (@$a) {
				my $h = $tran->{'hash'};
#				say "address $address owner $owner hash $h";
				push @$transactions, $h;
			}
		}
	}
	return $transactions;
}

sub doSOmethingUseful {
	my $hashes = shift;
	my $Transactions = [];
	my $journal_account = AccountsList->account("JournalAccount");
	my $unknown_account = AccountsList->account("Unknown addresses");

	foreach my $hash (@$hashes) {
		if ($opt{trace} and $hash =~ /$opt{trace}/) {
			say "Tracing hash $hash";
		}
		my $data = getTx($hash);
		next unless $data;

		$data->{tran_type} = "Transfer";
		$data->{tran_subtype} = "Bitcoin";
		$data->{currency} = 'BTC';
		$data->{value_currency} = 'BTC';
		$data->{fee_currency} = 'BTC';
		$data->{rate} = 1;
		$data->{to_fee} = 0;
		$data->{from_fee} = 0;

		my $ins = $data->{inputs};
		my $outs = $data->{out};
		my ($SSoutput,$SSinput);
		foreach my $in (@$ins) {
			my $addr = $in->{prev_out}{addr};
			if ($opt{trace} and $opt{trace} eq $addr) {
				say "Tracing input address $addr";
			}
			$in->{address} = $addr;
			$in->{from_account} = AccountsList->account($addr);
			if (!defined $in->{from_account}) {
				#say "Failed to find from_account $addr substituting unknown account";
				$in->{from_account} = $unknown_account;
			}
			$data->{invalue} += $in->{prev_out}{value};
			my $owner = $in->{from_account}->Owner->name;
			$in->{inowner} = $owner;
			$data->{inownercount}{$owner}++;
			my $follow = $in->{from_account}->Follow;
			$in->{infollow} = $follow;
			$data->{infollowcount}{$follow}++;
			my $ss = $in->{from_account}->ShapeShift;
			$in->{ShapeShift} = $ss;
			$data->{inshapeshiftcount}{$ss}++;
			$data->{incount}++;
		}
		foreach my $out (@$outs) {
			my $addr = $out->{addr};
			if ($opt{trace} and $opt{trace} eq $addr) {
				say "Tracing output address $addr";
			}
			$out->{to_account} = AccountsList->account($addr);
			if (!defined $out->{to_account}) {
				#say "Failed to find to_account $addr substituting unknown account";
				$out->{to_account} = $unknown_account;
			}
			my $ss = $out->{to_account}->ShapeShift;
			$SSoutput = $ss eq 'Output';
			$data->{outvalue} += $out->{value};
			my $owner = $out->{to_account}->Owner->name;
			$data->{outknowncount}++ if $owner ne 'Unknown';
			$out->{owner} = $owner;
			$data->{outownercount}{$owner}++;
			my $follow = $out->{to_account}->Follow;
			$out->{outfollow} = $follow;
			$data->{outfollowcount}{$follow}++;
			$out->{ShapeShift} = $ss;
			$data->{outshapeshiftcount}{$ss}++;
			$data->{outcount}++;
		}
		$data->{txnFee} = ($data->{invalue} - $data->{outvalue}) / 1e8;
		if ($data->{outfollowcount}{'Y'} == 1 and ($data->{inownercount}{'Unknown'} == $data->{incount} or $data->{infollowcount}{'Y'} == 0) ) {
			# Many to one (or 2) many inputs can be collapsed into one dummy address
			# This is a ShapeShift Output transaction. There could be many inputs and they are all ShapeShift internal addresses (unknown to addressDesc)
			# Or this is a Bitstamp withdrawal to multiple outputs only one of which is ours. We can ignore all the inputs which if present should all be Follow=N
			# There will be one or two outputs. One is the Address that ShapeShift has sent the funds to - it should be owned by one of us with Follow=Y
			# The second output address is optional change address and would not be known to us
			# There may be trades other than ShapeShift that fit the same criteria, so we don't check that every input is ShapeShift=Output address.
			# Create a transaction with a dummy input and full amount of transaction to the output address.
			# Find the output address with Follow=Y
			$counts{"Type 1 - unknown inputs collapsed"}++;
			my $out; # There is only one output address - let's find it
			foreach my $o (@$outs) {
				if ($o->{outfollow} eq 'Y') {
					$out = $o;
					last;
				}
			}
			my $address = "Unknown addresses";
			$address = "ShapeShiftInternalAddresses" if $out->{ShapeShift} eq 'Output'; # output ShapeShift withdrawal address, therefore input is SS internal
			#
			$address = "BitstampInternalAddresses" if $data->{inownercount}{'Bitstamp'} > 0; # We only need to identify 1 input in the Accounts file
			$address = "itBitInternalAddresses" if $data->{inownercount}{'itBit'} > 0; # We only need to identify 1 input in the Accounts file
			$address = "MtGoxWithdraw" if $data->{inownercount}{'MtGox'} > 0; # We only need to identify 1 input in the Accounts file
			$address = "LocalBitcoins" if $data->{inownercount}{'LocalBitcoins'} > 0; # We only need to identify 1 input in the Accounts file

			$data->{address} = $address;
			$data->{toaddress} = $out->{addr}; # This is the Shapeshift withdraw address - outgoing from ShapeShift
			$data->{from_account} = AccountsList->account($address) || $unknown_account;
			$data->{to_account} = $out->{to_account}; # This is the Shapeshift withdraw address - outgoing from ShapeShift
			$data->{amount} = $out->{value} / 1e8; # This is the amout of BTC credited from the ShapeShift transaction
			$data->{from_fee} = 0; # We are not interested in the fee if inputs are Unknown
			$data->{to_fee} = 0; # We are not interested in the fee if inputs are Unknown
			$data->{owner} = $out->{owner};
			$data->{hash} = $data->{hash}; # This is the transaction hash for the overall transaction. Populated by blockchain.info
			$data->{dt} = DateTime->from_epoch(epoch => $data->{time});
			$data->{note} = "Type1.";
			next if !_check_consistency($data, "Type 1");
			my $T = Transaction->new($data);
			push @$Transactions, $T;
		}
		elsif ($data->{infollowcount}{'Y'} == $data->{incount} and $data->{outknowncount} == 1 and $data->{outcount} == 1 ) {
			# Many to one
			# All the inputs are Follow addresses. e.g. this may be a withdrawal from multiple Jaxx addresses to a cold storage or Bitstamp address
			# We need to create one transaction for each of the inputs
			# There should be at least one output account that is relevant for us (known address). It may or may not be a Follow account
			# Owner should be the input owner since that is the sender - they own the transaction as they initiated it
			# If there are unknown outputs, they need to be investigated. For now test that outcount == outknowncount
			$counts{"Type 2 - many to one"}++;

			my $out; # There is only one output address - let's find it
			foreach my $o (@$outs) {
				if (defined $o->{owner}) {
					$out = $o;
					last;
				}
			}
			my $index = 0;
			foreach my $in (@$ins) {
				$data->{address} = $in->{prev_out}{addr};
				$data->{toaddress} = $out->{addr};

				$data->{from_account} = $in->{from_account};
				$data->{to_account} = $out->{to_account};
				$data->{note} = "Type2.";
				if(scalar(@{$ins}) == 1) {
					# We can better represent the amounts and fees by putting the
					# fee on the input. Can't do it when there's more than one
					# input because we wouldn't know how to split it.
					$data->{amount} = $out->{value} / 1e8; # This is the amout of BTC credited from the ShapeShift transaction
					$data->{from_fee} = 0; #Needed because doesnt reset on next pass through the loop
					$data->{to_fee} = 0; #Needed because doesnt reset on next pass through the loop
					$data->{from_fee} = $data->{txnFee} if $index == 0; # Stick fee on first one
				} else {
					my $note = sprintf("Outvalue %.8f", $out->{value} / 1e8);
					$data->{note} .= $note if $index == 0;
					$data->{amount} = $in->{prev_out}{value} / 1e8; # This is the amout of BTC credited from the ShapeShift transaction
					$data->{from_fee} = 0; #Needed because doesnt reset on next pass through the loop
					$data->{to_fee} = 0; #Needed because doesnt reset on next pass through the loop
					$data->{to_fee} = $data->{txnFee} if $index == 0; # Stick fee on first one
				}
				$data->{hash} = "$hash-$index"; # This is the transaction hash for the overall transaction.258
				$data->{dt} = DateTime->from_epoch(epoch => $data->{time});

				next if !_check_consistency($data, "Type 2");
				my $T = Transaction->new($data);
				push @$Transactions, $T;
				$index++;
			}
			$counts{"Type 2 - many to one, index $index"}++;

		}
		elsif ($data->{infollowcount}{'Y'} == 1 and $data->{incount} == 1 and $data->{outknowncount} == $data->{outcount}) {
			# One to many
			# The single input is a Follow address. e.g. this may be a withdrawal from Jaxx address to a ShapeShift or Bitstamp address
			# Two outputs - one is change back to the wallet (known, Follow) other is to destination (known)
			# We need to create one transaction for each of the outputs
			# Owner should be the input owner since that is the sender - they own the transaction as they initiated it
			# If there are unknown outputs, they need to be investigated. For now test that outcount == outknowncount
			$counts{"Type 3 - one to many"}++;

			my $in; # There is only one input address - let's find it
			foreach my $i (@$ins) {
				if (defined $i->{inowner}) {
					$in = $i;
					last;
				}
			}
			my $index = 0;
			foreach my $out (@$outs) {
				$data->{toaddress} = $out->{addr};

				$data->{address} = $in->{prev_out}{addr};
				$data->{from_account} = $in->{from_account};
				$data->{to_account} = $out->{to_account};
				$data->{amount} = $out->{value} / 1e8; # This is the amout of BTC going to this output
				$data->{to_fee} = 0; # We're using out values so fee has already been "deducted"
				$data->{from_fee} = 0; # We're using out values so fee has already been "deducted"
				$data->{from_fee} = $data->{txnFee} if $index == 0; # Stick fee on first one
				#$data->{owner} = $in->{inowner};
				$data->{hash} = "$hash-$index"; # This is the transaction hash hyphen index
				$data->{dt} = DateTime->from_epoch(epoch => $data->{time});
				$data->{note} = "Type3.";

				next if !_check_consistency($data, "Type 3");
				my $T = Transaction->new($data);
				push @$Transactions, $T;
				$index++;

			}
			# create fee transaction to fully drain the prev_out UTXO
		}
		elsif ($data->{infollowcount}{'Y'} >= 1 ) { # and $data->{outknowncount} == $data->{outcount}
			# Many to many - Follows on input, known on output
			# The inputs are all Follow addresses. e.g. this may be a withdrawal from Jaxx address to a ShapeShift or Bitstamp address
			# Two outputs - one is change back to the wallet (known, Follow) other is to destination (known)
			# We need to create one transaction for each of the inputs and one for each outputs
			# Owner should be the input owner since that is the sender - they own the transaction as they initiated it
			# If there are unknown outputs, they need to be investigated. For now test that outcount == outknowncount
			$counts{"Type 4 - many to many via journal"}++;

			my $in;
			my $index = 0;

			foreach my $in (@$ins) {
				$data->{address} = $in->{prev_out}{addr};
				$data->{from_account} = $in->{from_account};
				$data->{to_account} = $journal_account;
				$data->{toaddress} = $journal_account->AccountRef;
				$data->{amount} = $in->{prev_out}{value} / 1e8; # This is the amout of BTC credited from the ShapeShift transaction
				$data->{from_fee} = 0; #Needed because doesnt reset on next pass through the loop
				$data->{to_fee} = 0; #Needed because doesnt reset on next pass through the loop
				$data->{hash} = "$hash-$index"; # This is the transaction hash for the overall transaction.258
				$data->{dt} = DateTime->from_epoch(epoch => $data->{time});
				$data->{note} = "Type4a.";

				next if !_check_consistency($data, "Type 4a");
				my $T = Transaction->new($data);
				push @$Transactions, $T;
				$index++;
			}
			foreach my $out (@$outs) {
				$data->{toaddress} = $out->{addr};

				$data->{address} = $journal_account->AccountRef;
				$data->{from_account} = $journal_account;
				$data->{to_account} = $out->{to_account};
				$data->{amount} = $out->{value} / 1e8; # This is the amount of BTC going to this output
				$data->{from_fee} = 0; # We are not interested in the Bitcoin mining fee
				$data->{to_fee} = 0; # We are not interested in the Bitcoin mining fee
				$data->{hash} = "$hash-$index"; # This is the transaction hash hyphen index
				$data->{dt} = DateTime->from_epoch(epoch => $data->{time});
				$data->{note} = "Type4b.";

				next if !_check_consistency($data, "Type 4b");
				my $T = Transaction->new($data);
				push @$Transactions, $T;
				$index++;

			}
			# create fee trade to account for difference between ins and outs
		}
		else {
			say "Not sure what to do with transaction $hash $data->{incount} F=$data->{infollowcount}{Y} SS=$data->{inownercount}{ShapeShift} => $data->{outcount} F=$data->{outfollowcount}{N} K=$data->{outknowncount} SS=$data->{outshapeshiftcount}{Output} ";
			# 2 of these are Bitstamp withdrawals of BTC - we don't yet have the BTC addresses mapped out
			# 1LooJCWTqEVNAVN2C5QmZQeBvVkJTJ7NZ7
			# 13PEwUirXaa6CGTHrUDue1GUxSdhsHvmikq
			next;
		}
	}
	return $Transactions;
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
#		Many to many - withdraw BTC from Bitstamp with change back to Bitstamp
#		One or more inputs from  eg from Jax Wallet all with Follow=Y all known
#		normally 2 outputs - one change and one destination.

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

sub printMySQLTransactions {
	my $trans = shift;
    Transaction->printMySQLHeader;
    for my $t (sort {$a->{dt} <=> $b->{dt}} @$trans) {
		$t->printMySQL;
	}
}

sub printTransactions {
	my $trans = shift;
    Transaction->printHeader;
    for my $t (sort {$a->{dt} <=> $b->{dt}} @$trans) {
		$t->print;
	}
}

sub testArmoryAddresses {
	my $armoryAddressFile = "archive/armoryFull.txt";
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
		#my $res = getAddr($_);
		#say "$_ $res->{n_tx}";
	}
#	say Dumper $ids;
#	return;
	my $armoryUsedAddressFile = "armoryUsed.txt";
	open(my $fh, "<", $armoryUsedAddressFile) || die "Failed to open $armoryUsedAddressFile";
	while(<$fh>) {
		s/\r//;
		chomp;
		next unless $_ =~ /^1/;
		my $res = getAddr($_);
		if ($res->{n_tx} > 0) {
			my $owner = $ids->{$_}{name};
			$owner =~ s/s .*//;
			say "$_,$owner,Armory $ids->{$_}{name},$owner Armory $ids->{$_}{id},Y,BTC,Wallet,";
		}
	}
}

sub calcBalances {
	my ($transactions,$date) = @_;
	my $processed;
	my $balances;
	foreach my $t (sort {$a->{dt} <=> $b->{dt}} @$transactions) {
		last if $date and $t->{dt} > $date;
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
		$balances->{'txnFee'} += $t->{'txnFee'};
		$balances->{$t->{from}} -= $t->{'txnFee'}; # process tx fee even if this is an error transaction
		next if $t->{isError}; # Typically out of gas (make sure fees are processed but principal is not.
		$balances->{$t->{account}} -= $t->{'amount'};
		$balances->{$t->{toaccount}} += $t->{'amount'};
	}
	return $balances;
}

sub printBalances {
	my $balances = shift;
	foreach my $addr (sort keys %$balances) {
		next unless $addr;
		my $d = AccountsList->address($addr);
		next if $d->{Follow} eq 'N';
		my $bal1 = $balances->{$addr};
		$bal1 = 0 if $bal1 < 0.0000001;
		next if $bal1 == 0;
#		my $bal2 = getJsonBalance($addr) / 1e18;
#		say "$addr $bal1 $bal2 " . AccountsList->address($address);
		say "$addr $bal1 $d->{AccountName} $d->{Owner} $d->{Follow}";
	}
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}

sub reportCounts {
	foreach my $c (sort keys %counts) {
		say "\t count of $c $counts{$c}";
	}
}


AccountsList->new();
AccountsList->backCompatible();

if ($opt{start}) {
	my $d = getTx($opt{start});
	printTx($d) if $d;
}
elsif ($opt{ss}) {
	processShapeShiftTransactions();

}
elsif ($opt{testArmory}) {
	testArmoryAddresses();

}
elsif ($opt{balances}) {
	my $t = getTransactionsFromAccountsList();
	my $t1 = doSOmethingUseful($t);
	printBalances(calcBalances($t1, $BCHForkTime));
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
reportCounts() if $opt{counts};
# NULL addresses
# Tokens - VEE, Stellar, ...
