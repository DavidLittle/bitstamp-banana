use feature qw(state say);
use English;
use strict;
use DateTime;
# https://github.com/DavidLittle/bitstamp-banana.git
#use Parse::CSV;
use Data::Dumper;
use Storable qw(dclone store retrieve);
use vars qw(%opt);
use Getopt::Long;
use lib '.';
use Account;
use AccountsList;
use Person;
use Transaction;
use TransactionUtils;

# Process a Bitstamp export CSV file so that it is conveniently usable as a spreadsheet or as an import into an accounting system
# Program works in several stages:
# First, process the Bitstamp export parsing the dates and times into DateTime objects and splitting fields that have numbers and currencies
#       also do the account mapping to Banana Credit and Debit accounts. Put the results into an array of hashes called $data1
# Second, loop through the $data1 records accumulating multiple market trades transacted the same day into single records. Put the results into $data2
# Third, loop again through the $data1 records processing fees - Fee records are accumulated to one Fee line per month. Results are appended to $data2
# Fourth, process the accumulated buys and sells to produce 2 records for each market order. One is the Debit Cash record, other is the Credit ETH

# TBD - process USD/GBP exchange rates cable.dat
# TBD - process Internal Txns (contract executions) eg 0x793C64E8D1c70DD1407Bca99C8A97eA8eb662ECc

# Commandline args
GetOptions(
	'balances!' => \$opt{balances}, # Data Directory address
	'datadir:s' => \$opt{datadir}, # Data Directory address
	'g:s' => \$opt{g}, #
	'help' => \$opt{h}, #
	'quick!' => \$opt{quick}, #
	'start:s' => \$opt{start}, # starting address
	'trans:s' => \$opt{trans}, # name of transactions CSV file
	'cablefile:s' => \$opt{cablefile}, # filename of CSV file with USD GBP rates
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{hist} = "";
$opt{start} ||= "";
$opt{trans} ||= "BitstampTransactions.dat";

$opt{cablefile} ||= "Cable.dat";
my $inputs = [
	{
		transactions => "DavidsBitstampTransactions.csv",
		history  => "bitstamp_account_81162_history.txt",
		owner => "David",
	},
	{
		transactions => "RichardsBitstampTransactions.csv",
		history  => "bitstamp_account_512288_history.txt",
		owner => "Richard",
	},
	{
		transactions => "KevinsBitstampTransactions.csv",
		history  => "bitstamp_account_vulx4255_history.txt",
		owner => "Kevin",
	},
];



my %M = ('Jan'=>1,'Feb'=>2,"Mar"=>3,"Apr"=>4,"May"=>5,"Jun"=>6,"Jul"=>7,"Aug"=>8,"Sep"=>9,"Oct"=>10,"Nov"=>11,"Dec"=>12);
my $data2; # consecutive Buy and Sell records accumulated over 24 hour window
my $data3; # fee records appended

my $owner = $opt{owner}; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
my $cable = {}; # hash keyed on date containing daily USD/GBP exchange rates
my $withdrawal = {}; # hash keyed on datetime containing withdrawal addresses

sub getWithdrawalsFromHistory {
	my ($histfile, $owner) = @_;
	my $hist = undef;
	$withdrawal = {}; #Reset it for each new owner being processed
	open($hist, "$opt{datadir}/$histfile") || die "Can't open $opt{hist} for reading: $!";
	while(<$hist>) {
		s/\r//; #Remove carriage return
		chomp;
		next if $_ !~ /withdrawal request for /; #skip non-withdrawal
		next if $_ =~ /international wire transfer withdrawal request for /; # Skip the Fiat withdrawals
		next if $_ =~ /SEPA transfer withdrawal request for /; # Skip the Fiat withdrawals
#		say $_;
		my($year, $month, $day, $hour, $min, $sec, $amount, $type, $address) = m/(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d).*withdrawal request for ([\d\.]+) (\w+) to (.*)/;
		my $dt = DateTime->new(year => $year, month => $month, day => $day, hour => $hour, minute => $min, second => $sec, time_zone => "UTC");
		my $ts = $dt->epoch();
#		say "$ts $amount $type $address";
		$withdrawal->{$ts} = {amount => $amount, type => $type, address => $address, owner =>$owner};
#		say "--"
	}
}


# Read in FX rates
sub readFXrates {
	my $cab = undef;
	open($cab, $opt{cablefile}) || die "Can't open $opt{cablefile} for reading: $!";
	while(<$cab>) {
		s/\r//; #Remove carriage return
		chomp;
		next if $_ =~ /^#/; #skip comment lines
		my($day, $month, $year, $rate) = split(/\s/);
		my $dt = DateTime->new(year => $year, month => $M{$month}, day => $day, hour => 0, minute => 0, second => 0, time_zone => "UTC");
		$cable->{$dt->dmy("/")} = $rate;
	#	print "$day, $month, $year, $rate " . $dt->dmy() . "\n";
	}
}
#print "Rate for 19-07-2018 is $cable->{'19-07-2018'}\n";

sub readBitstampTransactions {
	my ($transactionfile, $owner) = @_;
	my $filename = "$opt{datadir}/$transactionfile";
	my $in = undef;
	my $data = [];
	open($in, $filename) || die "Can't open $filename for reading: $!";
	while(<$in>) {
		s/\r//; #Remove carriage return
		chomp; #Remove any linefeed
		if ($. == 1) { #First line - headers
		    #print "Type,Subtype,Date,Time,Account,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy\n";
		} else {
		    # Timestamp has spaces, commas and dots embedded, and is surrounded with double quotes so we'll process it in stages
		    my ($type, $timestamp, $rest) = m/([a-zA-Z]+),"(.*)",(.*)/;
		    # Break up the timestamp into its component parts
		    my ($month, $day, $year, $time, $ampm) = split(/ /, $timestamp);
		    my ($hour, $min) = split(/:/, $time);
		    $year =~ s/,//;
		    $month =~ s/\.//;
		    $day =~ s/,//;
		    $hour += 12 if ($ampm eq "PM" && $hour < 12);
		    my $dt = DateTime->new(year => $year, month => $M{$month}, day => $day, hour => $hour, minute => $min, second => 0, time_zone => "UTC");
		    # Now split the rest of the line on comma delimiter
		    my ($account, $amountx, $valuex, $ratex, $feex, $subtype) = split(/,/, $rest);
		    my ($amount, $amountccy) = split(/ /, $amountx);
		    my ($value, $valueccy) = split(/ /, $valuex);
		    my ($rate, $rateccy) = split(/ /, $ratex);
		    my ($fee, $feeccy) = split(/ /, $feex);
		    my $rec = {};
		    $rec->{tran_type} = 'Bitstamp';
		    $rec->{tran_subtype} = $subtype;
		    $rec->{dt} = $dt;
		    $rec->{from_account} = $account;
		    $rec->{amount} = $amount;
		    $rec->{currency} = $amountccy;
	    	$rec->{value} = $value if $value;
	    	$rec->{value_currency} = $valueccy;
		    $rec->{rate} = $rate || 1;
			$rec->{fee_currency} = $feeccy if $feeccy;
			$rec->{hash} = "$opt{trans}-Line$.";
			my ($toprefix, $fromprefix) = (undef,undef);
			$fromprefix = '0x' if ($amountccy =~ /^(ETH|ETC)$/);
			$fromprefix = '3' if ($amountccy =~ /^(BTC|BCH)$/);
			$toprefix = '0x' if ($valueccy =~ /^(ETH|ETC)$/);
			$toprefix = '3' if ($valueccy =~ /^(BTC|BCH)$/);
		    if ($type eq "Deposit" || $type eq "Card Deposit") {
				$rec->{tran_subtype} = $type;
				${toprefix} = ${fromprefix}; # On a withdrawal to and from are same CCY
		        $rec->{toaccount} = "${toprefix}Bitstamp${amountccy}Trading${owner}";
				$rec->{fromaccount} = "${fromprefix}Bitstamp${amountccy}Wallet$owner";
				$rec->{value_currency} = $rec->{currency}; # we don't get a value currency from Bitstamp for deposits
				$rec->{amount} = $amount;
				$rec->{value} = $amount;
				$rec->{from_fee} = $fee || 0;
		    } elsif ($type eq "Withdrawal") {
				$rec->{tran_subtype} = $type;
				${toprefix} = ${fromprefix}; # On a withdrawal to and from are same CCY
		        my $ts = $rec->{dt}->epoch();
		        my $offset = 0;
		        while (!defined $withdrawal->{$ts-$offset} and !defined $withdrawal->{$ts+$offset} and $offset < 60*60*5) {
		        	$offset++;
		        }
		        my $wd = $withdrawal->{$ts-$offset} || $withdrawal->{$ts-$offset};
		        if (!defined $wd) {
			        say "Failed to find withdrawal address: $_" if $amountccy =~ /^(BTC|ETH)$/;
			    }
				# Withdrawal of crypto will be to $wd->{address}; withdrawal of Fiat will be to Wallet
				$rec->{toaccount} = "${toprefix}Bitstamp${amountccy}Wallet$owner";
				$rec->{fromaccount} = "${fromprefix}Bitstamp${amountccy}Trading$owner";
				$rec->{value_currency} = $rec->{currency}; # we don't get a value currency from Bitstamp for withdrawals
				$rec->{amount} = $amount;
				$rec->{value} = $amount;
				my $toaddress = $wd->{address};
				$rec->{hash} .=	"-$toaddress";
				$rec->{to_fee} = $fee || 0;
			} elsif ($type eq "Market" and $subtype eq "Buy") {
				$rec->{toaccount} = "${fromprefix}Bitstamp${amountccy}Trading${owner}";
				$rec->{fromaccount} = "${toprefix}Bitstamp${valueccy}Trading${owner}";
				$rec->{amount} = $value;
				$rec->{value} = $amount;
				$rec->{currency} = $valueccy;
				$rec->{value_currency} = $amountccy;
				$rec->{from_fee} = $fee || 0;

		    } elsif ($type eq "Market" and $subtype eq "Sell") {
				$rec->{toaccount} = "${toprefix}Bitstamp${valueccy}Trading${owner}";
				$rec->{fromaccount} = "${fromprefix}Bitstamp${amountccy}Trading$owner";
				$rec->{toamount} = $value;
				$rec->{fromamount} = $amount;
				$rec->{to_fee} = $fee || 0;
		    }

			$rec->{from_account} = AccountsList->account($rec->{fromaccount});
			$rec->{to_account} = AccountsList->account($rec->{toaccount});

			if (! defined $rec->{from_account}) {
				say "From account undefined $rec->{fromaccount} ($type $subtype $amountccy)";
				next;
			}
			if (ref($rec->{from_account}) ne 'Account') {
				say "From account is not a proper account $rec->{fromaccount} ($type $subtype $amountccy)";
				next;
			}
			if (! defined $rec->{to_account}) {
				say "To account undefined $rec->{toaccount} ($type $subtype $amountccy)";
				next;
			}
			if (ref($rec->{to_account}) ne 'Account') {
				say "To account is not a proper account $rec->{toaccount} ($type $subtype $amountccy)";
				next;
			}


			my $T = Transaction->new($rec);

		    #$rec->{USDvalue} = 0;
			#$rec->{USDvalue} = $amount if $rec->{amountccy} eq 'USD';
			#$rec->{USDvalue} = $value if $rec->{valueccy} eq 'USD';
			#if ($cable->{$rec->{date}}) {
		#		$rec->{GBPvalue} = $rec->{USDvalue} / $cable->{$rec->{date}};
		#	}
		#	else {
		#		die "No cable rate for $rec->{date}";
		#	}
		    push @$data, $T;
		    #print "$type,$subtype,$day-$month-$year,$hour:$min:00,$account,$amount,$amountccy,$value,$valueccy,$rate,$rateccy,$fee,$feeccy\n";
		}
	}
	return $data;
}

# Accumulate market orders within 24 hours
# Accumulate fees to end of month
# Deposits and withdrawals do not get accumulated
sub accumulateMktOrders {
	my $data = shift;
	my $acc_data = [];
	my $acc = {'count' => 0}; #initialise the accumulator for trades
	foreach my $rec (@$data) {
	    if ($acc->{count} == 0) {
	        $acc = dclone($rec); # If accumulator is empty then first record goes into the accumulator (deep copy, so that @data1 is preserved)
	        $acc->{count}++;
		    push @$acc_data, $acc;
	    }
	    elsif ($rec->{type} eq 'Market' and
	            $rec->{type} eq $acc->{type} and
	            $rec->{subtype} eq $acc->{subtype} and
	            $rec->{account} eq $acc->{account} and
	            $rec->{amountccy} eq $acc->{amountccy} and
	            $rec->{valueccy} eq $acc->{valueccy} and
	            $rec->{date} eq $acc->{date} )
	    {
	        # Add this record to the accumulator
	        $acc->{date} = $rec->{date};
	        $acc->{time} = $rec->{time};
	        $acc->{amount} += $rec->{amount};
	        $acc->{value} += $rec->{value};
	        $acc->{rate} = $acc->{value} / $acc->{amount};
	        $acc->{fee} += $rec->{fee};
	        $acc->{USDvalue} += $rec->{USDvalue};
	        $acc->{GBPvalue} += $rec->{GBPvalue};
	        $acc->{count}++;
	    }
	    else {
	        if ( $acc->{count}) { #We have something in the accumulator so print it, then reset the acc
	            $acc = {count => 0}; #reinitialise
	            redo; # start from the top of the loop again - needed if multiple BUY records follow multiple SELL records in order to re-initialise the accumulator
	        }
	    }
	}
	return $acc_data;
}

# Split Market Buys and Sells into two records one for the DebitAccount and one for the CreditAccount (dual entry bookkeeping)
sub splitMarketOrders {
	my $data = shift;
	my $split_data = [];
#    print "Type,Subtype,Date,Time,Account,DebitAccount,CreditAccount,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Count\n";
    foreach my $rec (@$data) {
    	if ($rec->{type} eq 'Market') {
    		if ($rec->{subtype} eq 'Buy') { # eg Buy ETH therefore ETH balance increases (debit) and USD balance decreases (credit)
    			my $debit = dclone($rec);
    			$debit->{account} = $rec->{debitaccount};
    			$debit->{amount} = -$rec->{amount};
    			$debit->{amountccy} = $rec->{amountccy};

    			my $credit = dclone($rec);
    			$credit->{account} = $rec->{creditaccount};
    			$credit->{amount} = $rec->{value};
    			$credit->{amountccy} = $rec->{valueccy};

				push @$split_data, $debit;
				push @$split_data, $credit;
    		}
    		elsif ($rec->{subtype} eq 'Sell') { # eg Sell ETH therefore ETH balance reduces (credit) and USD balance increases (debit)
    			my $debit = dclone($rec);
    			$debit->{account} = $rec->{debitaccount};
    			$debit->{amount} = -$rec->{value};
    			$debit->{amountccy} = $rec->{valueccy};

    			my $credit = dclone($rec);
    			$credit->{account} = $rec->{creditaccount};
    			$credit->{amount} = $rec->{amount};
    			$credit->{amountccy} = $rec->{amountccy};

				push @$split_data, $debit;
				push @$split_data, $credit;
    		}
    		else {
    			die "Unexpected subtype";
    		}
		}
		else { #Not a Buy or sell - just push it onto the output array
			push @$split_data, $rec;
		}
	}
	return $split_data;
}

# Accumulate fees to end of month
sub accumulateFees {
	my $data = shift;
	my $fees = [];
    my $feeacc = {'count' => 0}; # initialise the fee accumulator
#    print "Type,Subtype,Date,Time,Account,DebitAccount,CreditAccount,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Count\n";
    foreach my $rec (@$data) {
    	next if $rec->{fee} == 0; # ignore records that don't have a fee
        my $date = $rec->{dt}->dmy("/");
        my $time = $rec->{dt}->hms();
        my $month = $rec->{dt}->month() ."-" . $rec->{dt}->year();
        if ($feeacc->{count} == 0) {
	        $feeacc = dclone($rec);
	        $feeacc->{subtype} = "Fee";
	       	$feeacc->{amountccy} = $rec->{feeccy};
	       	$feeacc->{amount} = $rec->{fee};
	       	$feeacc->{creditaccount} = "";
	       	$feeacc->{month} = $month;
	       	$feeacc->{date} = $date;
	       	$feeacc->{time} = $time;
	       	$feeacc->{count}++;
	        $feeacc->{USDvalue} = 0;
			$feeacc->{USDvalue} = $feeacc->{amount} if $feeacc->{amountccy} eq 'USD';
			$feeacc->{GBPvalue} = $feeacc->{USDvalue} / $cable->{$date};
	        push @$fees, $feeacc;
	    }
        elsif ($feeacc->{count} > 0 and
        		$feeacc->{type} eq $rec->{type} and
	       		$feeacc->{amountccy} eq $rec->{feeccy} and
        		$month eq $feeacc->{month}
        		)
        	{
		        	# accumulate this fee record
			       	$feeacc->{amount} += $rec->{fee};
			       	$feeacc->{USDvalue} += $rec->{fee};
			       	$feeacc->{GBPvalue} += ($rec->{fee} / $cable->{$date});
			       	$feeacc->{count}++;
		}
		else {
			$feeacc = {"count" => 0}; # reinitialise feeacc
			redo;
		}

	}
	return $fees;
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}


# Main program
AccountsList->new();
readFXrates();
my $data = [];
foreach my $files (@$inputs) {
	getWithdrawalsFromHistory($files->{history}, $files->{owner});
	my $trans = readBitstampTransactions($files->{transactions}, $files->{owner});
	push @$data, @$trans;
}

if($opt{balances}) {
	TransactionUtils->printBalances($data);
}
elsif($opt{quick}) {
	TransactionUtils->printTransactions($data);
}
else {
	TransactionUtils->printMySQLTransactions($data);
}
saveTransactions($data);
