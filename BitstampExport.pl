use English;
use strict;
use DateTime;
#use Parse::CSV;

# Process a Bitstamp export CSV file so that it is conveniently usable as a spreadsheet or as an import into an accounting system
my %M = ('Jan'=>1,'Feb'=>2,"Mar"=>3,"Apr"=>4,"May"=>5,"Jun"=>6,"Jul"=>7,"Aug"=>8,"Sep"=>9,"Oct"=>10,"Nov"=>11,"Dec"=>12);
my $data = [];
my $owner = "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
my %BananaMapping = (
    "David,Main Account,BTC" => 10100,
    "David,Main Account,ETH" => 10101,
    "David,Main Account,USD" => 10102,
    "David,Main Account,BCH" => 10103,
    "David,BitstampFee,USD"	 => 6070,
    "David,BitstampFee,BTC"  => 6071,
    "David,BitstampFee,ETH"  => 6072,
);

my $filename = $ARGV[0] || "Transactions.csv";
my $in = undef;
open($in, $filename) || die "Can't open $filename for reading: $!";
while(<$in>) {
    s/\r//; #Remove carriage return
    chomp; #Remove any linefeed
    if ($. == 1) { #First line - headers
        #print "Type,Epoch,Date,Time,Account,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy,SubType\n";
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
        $rec->{epoch} = $dt->epoch();
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
        push @$data, $rec;
        #print "$type,$subtype,$epoch,$day-$month-$year,$hour:$min:00,$account,$amount,$amountccy,$value,$valueccy,$rate,$rateccy,$fee,$feeccy\n";
    }
}


if (1) { # Accumulate market orders within 24 hours
		 # Accumulate fees to end of month
		 # Deposits and withdrawals do not get accumulated
    my $acc = {'count' => 0}; #initialise the accumulator for trades
#    my $feeacc = {'count' => 0}; # initialise the fee accumulator
    print "Type,Subtype,Date,Time,FirstEpoch,LastEpoch,Account,DebitAccount,CreditAccount,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Count\n";
    foreach my $rec (@$data) {
        my $date = $rec->{dt}->dmy();
        my $time = $rec->{dt}->hms();
        my $epoch = $rec->{dt}->epoch();
#        if ($rec->{fee} > 0) {
#        	$feeacc->{$rec->{feeccy}} += $rec->{fee};
#        	$feeacc->{count}++;
#        	$feeacc->{firstepoch} ||= $rec->{epoch};
#        	$feeacc->{date} ||= $date;
#        	$feeacc->{time} ||= $time;
#        }
        if ($rec->{type} eq 'Market' and $acc->{count} == 0) {
            $acc = $rec; # If accumulator is empty then first Market record goes into the accumulator
            $acc->{firstepoch} = $rec->{epoch};
            $acc->{count} = 1;
        }
        elsif ($rec->{type} eq 'Market' and 
                $rec->{subtype} eq $acc->{subtype} and 
                $rec->{account} eq $acc->{account} and 
                $rec->{amountccy} eq $acc->{amountccy} and 
                $rec->{valueccy} eq $acc->{valueccy} and 
                $rec->{epoch} - $acc->{epoch} < 60*60*24) 
        {
            # Add this record to the accumulator
            $acc->{dt} = $rec->{dt};
            $acc->{epoch} = $rec->{epoch};
            $acc->{amount} += $rec->{amount};
            $acc->{value} += $rec->{value};
            $acc->{rate} = $acc->{value} / $acc->{amount};
            $acc->{fee} += $rec->{fee};
            $acc->{count}++;
        }
        else {
            if ( $acc->{count}) { #We have something in the accumulator so print it, then reset the acc
                my $date = $acc->{dt}->dmy();
                my $time = $acc->{dt}->hms();
                print "$acc->{type},$acc->{subtype},$date,$time,$acc->{firstepoch},$acc->{epoch},$acc->{account},$acc->{debitaccount},$acc->{creditaccount},$acc->{amount},$acc->{amountccy},$acc->{value},$acc->{valueccy},$acc->{rate},$acc->{rateccy},$acc->{fee},$acc->{feeccy},$acc->{count}\n";
                $acc = {count => 0};
                redo; # start from the top of the loop again - needed if multiple BUY records follow multiple SELL records in order to re-initialise the accumulator
            }
            # If we don't have anything in the accumulator, just print the current rec            
            print "$rec->{type},$rec->{subtype},$date,$time,$epoch,$epoch,$rec->{account},$rec->{debitaccount},$rec->{creditaccount},$rec->{amount},$rec->{amountccy},$rec->{value},$rec->{valueccy},$rec->{rate},$rec->{rateccy},$rec->{fee},$rec->{feeccy},1\n";
        }
#        if ($feeacc->{count} > 0 and $rec->{epoch} - $feeacc->{firstepoch} > 30*24*60*60) { #fees have accumulated for 30 days
#        	# print a fee record
#        	foreach my $ccy (keys %$feeacc) {
#        		next unless length($ccy) == 3;
#        		my $debitaccount = $BananaMapping{"$owner,BitstampFee,$ccy"};
#        		my $amount = $feeacc->{$ccy};
#            	print "Fee,Fee,$feeacc->{date},$feeacc->{time},$feeacc->{firstepoch},$rec->{epoch},$debitaccount,$debitaccount,,$amount,$ccy,$amount,$ccy,,,,,$feeacc->{count}\n";
#				$feeacc = {"count" => 0}; # reinitialise feeacc
#            }
#        }
	}
}


if (1) { # Accumulate fees to end of month
    my $feeacc = {'count' => 0}; # initialise the fee accumulator
    print "Type,Subtype,Date,Time,FirstEpoch,LastEpoch,Account,DebitAccount,CreditAccount,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Count\n";
    foreach my $rec (@$data) {
        my $date = $rec->{dt}->dmy();
        my $time = $rec->{dt}->hms();
        my $epoch = $rec->{dt}->epoch();
        if ($rec->{fee} > 0) {
        	$feeacc->{$rec->{feeccy}} += $rec->{fee};
        	$feeacc->{count}++;
        	$feeacc->{firstepoch} ||= $rec->{epoch};
        	$feeacc->{date} ||= $date;
        	$feeacc->{time} ||= $time;
        }
        if ($feeacc->{count} > 0 and $rec->{epoch} - $feeacc->{firstepoch} > 30*24*60*60) { #fees have accumulated for 30 days
        	# print a fee record
        	foreach my $ccy (keys %$feeacc) {
        		next unless length($ccy) == 3;
        		my $debitaccount = $BananaMapping{"$owner,BitstampFee,$ccy"};
        		my $amount = $feeacc->{$ccy};
            	print "Fee,Fee,$feeacc->{date},$feeacc->{time},$feeacc->{firstepoch},$rec->{epoch},MainAccount,$debitaccount,,$amount,$ccy,$amount,$ccy,,,,,$feeacc->{count}\n";
				$feeacc = {"count" => 0}; # reinitialise feeacc
            }
        }
	}
}
  
  
if (0) { # Print every record
    print "Type,Subtype,Date,Time,Epoch,Account,Amount,AmountCcy,Value,ValueCcy,Rate,RateCcy,Fee,FeeCcy\n";
    for my $rec (@$data) {
        my $date = $rec->{dt}->dmy();
        my $time = $rec->{dt}->hms();
        my $epoch = $rec->{dt}->epoch();
        print "$rec->{type},$rec->{subtype},$date,$time,$epoch,$rec->{account},$rec->{amount},$rec->{amountccy},$rec->{value},$rec->{valueccy},$rec->{rate},$rec->{rateccy},$rec->{fee},$rec->{feeccy}\n";
    }

}
