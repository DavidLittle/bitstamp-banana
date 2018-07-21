use English;
use strict;
use DateTime;
# https://github.com/DavidLittle/bitstamp-banana.git
#use Parse::CSV;
use Data::Dumper;
use Storable qw(dclone);

# Process a Bitstamp export CSV file so that it is conveniently usable as a spreadsheet or as an import into an accounting system
# Program works in several stages:
# First, process the Bitstamp export parsing the dates and times into DateTime objects and splitting fields that have numbers and currencies
#       also do the account mapping to Banana Credit and Debit accounts. Put the results into an array of hashes called $data1
# Second, loop through the $data1 records accumulating multiple market trades transacted the same day into single records. Put the results into $data2
# Third, loop again through the $data1 records processing fees - Fee records are accumulated to one Fee line per month. Results are appended to $data2
# Fourth, process the accumulated buys and sells to produce 2 records for each market order. One is the Debit Cash record, other is the Credit ETH

# TBD - process USD/GBP exchange rates cable.dat



my %M = ('Jan'=>1,'Feb'=>2,"Mar"=>3,"Apr"=>4,"May"=>5,"Jun"=>6,"Jul"=>7,"Aug"=>8,"Sep"=>9,"Oct"=>10,"Nov"=>11,"Dec"=>12);
my $data1; # parsed input CSV file, with mapped banana account codes
my $data2; # consecutive Buy and Sell records accumulated over 24 hour window
my $data3; # fee records appended

my $owner = "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
my $cablefile = "Cable.dat";
my $cable = {}; # hash keyed on date containing daily USD/GBP exchange rates
my %BananaMapping = (
    "David,Main Account,BTC" => 10100,
    "David,Main Account,ETH" => 10101,
    "David,Main Account,USD" => 10102,
    "David,Main Account,BCH" => 10103,
    "David,BitstampFee,USD"	 => 6070,
    "David,BitstampFee,BTC"  => 6071,
    "David,BitstampFee,ETH"  => 6072,
);

# Read in FX rates
my $cab = undef;
open($cab, $cablefile) || die "Can't open $cablefile for reading: $!";
while(<$cab>) {
    s/\r//; #Remove carriage return
	chomp;
	next if $_ =~ /^#/; #skip comment lines
	my($day, $month, $year, $rate) = split(/\s/);
	my $dt = DateTime->new(year => $year, month => $M{$month}, day => $day, hour => 0, minute => 0, second => 0, time_zone => "UTC");
	$cable->{$dt->dmy("/")} = $rate;
#	print "$day, $month, $year, $rate " . $dt->dmy() . "\n";
}
#qprint "Rate for 19-07-2018 is $cable->{'19-07-2018'}\n";


my $filename = $ARGV[0] || "Transactions.csv";
my $in = undef;
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
        $rec->{type} = $type;
        $rec->{subtype} = $subtype;
        $rec->{dt} = $dt;
        $rec->{date} = $dt->dmy("/");
        $rec->{time} = $dt->hms();
        $rec->{account} = $account;
        $rec->{amount} = $amount;
        $rec->{amountccy} = $amountccy;
        $rec->{value} = $value;
        $rec->{valueccy} = $valueccy;
        $rec->{rate} = $rate;
        $rec->{rateccy} = $rateccy;
        $rec->{fee} = $fee;
        $rec->{feeccy} = $feeccy;
        if ($type eq "Deposit" || $type eq "Card Deposit") {
            $rec->{debitaccount} = $BananaMapping{"$owner,$account,$amountccy"};
        } elsif ($type eq "Withdrawal") {
            $rec->{creditaccount} = $BananaMapping{"$owner,$account,$amountccy"};
        } elsif ($type eq "Market" and $subtype eq "Buy") {
            $rec->{debitaccount} = $BananaMapping{"$owner,$account,$amountccy"};
            $rec->{creditaccount} = $BananaMapping{"$owner,$account,$valueccy"};
        } elsif ($type eq "Market" and $subtype eq "Sell") {
            $rec->{debitaccount} = $BananaMapping{"$owner,$account,$valueccy"};
            $rec->{creditaccount} = $BananaMapping{"$owner,$account,$amountccy"};
        }
        $rec->{USDvalue} = 0;
		$rec->{USDvalue} = $amount if $rec->{amountccy} eq 'USD';
		$rec->{USDvalue} = $value if $rec->{valueccy} eq 'USD';
		$rec->{GBPvalue} = $rec->{USDvalue} / $cable->{$rec->{date}};
        push @$data1, $rec;
        #print "$type,$subtype,$day-$month-$year,$hour:$min:00,$account,$amount,$amountccy,$value,$valueccy,$rate,$rateccy,$fee,$feeccy\n";
    }
}


if (1) { # Accumulate market orders within 24 hours
		 # Accumulate fees to end of month
		 # Deposits and withdrawals do not get accumulated
    my $acc = {'count' => 0}; #initialise the accumulator for trades
    foreach my $rec (@$data1) {
        if ($acc->{count} == 0) {
            $acc = dclone($rec); # If accumulator is empty then first record goes into the accumulator (deep copy, so that @data1 is preserved)
            $acc->{count}++;
	        push @$data2, $acc;
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
            $acc->{count}++;
        }
        else {
            if ( $acc->{count}) { #We have something in the accumulator so print it, then reset the acc
                $acc = {count => 0}; #reinitialise
                redo; # start from the top of the loop again - needed if multiple BUY records follow multiple SELL records in order to re-initialise the accumulator
            }
        }
	}
}

if (1) { # Split Market Buys and Sells into two records one for the DebitAccount and one for the CreditAccount (dual entry bookkeeping)
#    print "Type,Subtype,Date,Time,Account,DebitAccount,CreditAccount,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Count\n";
    foreach my $rec (@$data2) {
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

				push @$data3, $debit;
				push @$data3, $credit;
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

				push @$data3, $debit;
				push @$data3, $credit;
    		}
    		else {
    			die "Unexpected subtype";
    		}
		}
		else { #Not a Buy or sell - just push it onto the output array
			push @$data3, $rec;
		}
	}
}


if (1) { # Accumulate fees to end of month
    my $feeacc = {'count' => 0}; # initialise the fee accumulator
#    print "Type,Subtype,Date,Time,Account,DebitAccount,CreditAccount,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Count\n";
    foreach my $rec (@$data1) {
    	next if $rec->{fee} == 0; # ignore records that don't have a fee
        my $date = $rec->{dt}->dmy("/");
        my $time = $rec->{dt}->hms();
        my $month = $rec->{dt}->month() ."-" . $rec->{dt}->year();
        if ($feeacc->{count} == 0) {
	        $feeacc = dclone($rec);
	        $feeacc->{subtype} = "Fee";
	       	$feeacc->{amountccy} = $rec->{feeccy};
	       	$feeacc->{amount} = $rec->{fee};
	       	$feeacc->{account} = $BananaMapping{"$owner,BitstampFee,$rec->{feeccy}"};
	       	$feeacc->{debitaccount} = $BananaMapping{"$owner,BitstampFee,$rec->{feeccy}"};
	       	$feeacc->{creditaccount} = "";
	       	$feeacc->{month} = $month;
	       	$feeacc->{date} = $date;
	       	$feeacc->{time} = $time;
	       	$feeacc->{count}++;
	        $feeacc->{USDvalue} = 0;
			$feeacc->{USDvalue} = $feeacc->{amount} if $feeacc->{amountccy} eq 'USD';
			$feeacc->{GBPvalue} = $feeacc->{USDvalue} / $cable->{$date};
	        push @$data3, $feeacc;
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
}


if (1) {
    print "Type,Subtype,Date,Time,Account,Amount,AmountCcy,USDValue,GBPValue,Count\n";
    for my $rec (@$data3) {
       	print "$rec->{type},$rec->{subtype},$rec->{date},$rec->{time},$rec->{account},$rec->{amount},$rec->{amountccy},$rec->{USDvalue},$rec->{GBPvalue},$rec->{count}\n";
	}
}


  
#print Dumper $data1;
  

