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

# Commandline args
GetOptions('d:s' => \$opt{datadir}, # Data Directory address
			'g:s' => \$opt{g}, # 
			'h' => \$opt{h}, # 
			'key:s' => \$opt{key}, # API key to access etherscan.io
			'o:s' => \$opt{owner}, # 
			'start:s' => \$opt{start}, # starting address

			'bitstamp:s' => \$opt{bitstamp}, # starting address
			'classic:s' => \$opt{classic}, # starting address
			'ether:s' => \$opt{ether}, # starting address
			'shapeshift:s' => \$opt{shapeshift}, # starting address
			'trace:s' => \$opt{trace},
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{desc} ||= "ACK.csv"; #"AddressDescriptions.dat";
$opt{key} ||= ''; # from etherscan.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.

$opt{bitstamp} ||= "BitstampTransactions.dat";
$opt{bitcoin} ||= "BlockchainTransactions.dat";
$opt{bitcoincash} ||= "BCHTransactions.dat";
$opt{classic} ||= "ClassicTransactions.dat";
$opt{ether} ||= "EtherTransactions.dat";
$opt{shapeshift} ||= "ShapeshiftTransactions.dat";

# Global variables

#Shapeshift transactions have minimal data. Therefore enrich with data from the same transaction captured elsewhere
sub enrichShapeShiftTransactions { 
	my ($st,$all) = @_;
	my (%hdict, %adict);
	my $enriched;
	my %count;
	
	# create dictionary of transactions keyed on txhash
	foreach my $a (@$all) {
		if (ref($a) ne 'HASH') {
			say "Oops";
			next;
		}
		if ($opt{trace} and $a->{account} eq $opt{trace}) { say "Found from address in transactions $a->{account}"};
		if ($opt{trace} and $a->{toaccount} eq $opt{trace}) { say "Found to address in transactions $a->{toaccount}"};
		if (! defined $a->{toaccount} or !defined $a->{toaccount}) {
			say "Oops no account or toaccount";
		}
		# BTC and BCH transactions can be split into multiple sub transactions - they have hash field set to hash-index
		# We can therefore we need to remove the suffix.
		my $hash = $a->{hash};
		$hash =~ s/-[0-9]*$//;
		if ($opt{trace} and $hash eq $opt{trace}) { say "Found hash in transactions $hash"};
		$hdict{$hash} = $a;
		$adict{"to $a->{toaccount} $a->{amount}"} = $a;
		$adict{"from $a->{account} $a->{amount}"} = $a;
		$count{Transactions}++;
		$count{"Transactions in ccy $a->{ccy}"}++;
		$count{"Transactions in amountccy $a->{amountccy}"}++;
	}
#	print Dumper $adict{'0x85a9962fbc35549afec891c285b3fe057ec334cc'};
	
	# enrich shapeshit transactions from the dict
	foreach my $t (@$st) {
		if ($opt{trace} and $t->{address} eq $opt{trace}) {
			say "Found receive address in SS $t->{address} withdraw hash:$t->{transaction}"
		};
		if ($opt{trace} and $t->{withdraw} eq $opt{trace}) {
			say "Found withdraw address in SS $t->{withdraw} withdraw hash:$t->{transaction}"
		};
		$count{all}++;
		$count{"Status $t->{status}"}++; 
		if ($t->{status} eq 'error') {
			next;
		}
		$count{"$t->{incomingType} to $t->{outgoingType}"}++; 
		if ($t->{outgoingType} eq 'BTC') {
#			next;
		}
		
		my $h = ($t->{transaction});
		$h =~ s/-.*$//; # Strip off -SS
		if ($h and $t->{outgoingType} =~ /ET[CH]/) {
			$h = "0x$h";
			$h =~ s/0x0x/0x/;
		}
		if ($opt{trace} and $h eq $opt{trace}) { say "Found hash in ss data $h"};
		if ($h and $hdict{$h}) {
			$t->{T} = $hdict{$h}{T};
			$t->{dt} = $hdict{$h}{dt};
			$t->{timeStamp} = $hdict{$h}{timeStamp};
			$t->{to} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toaccount} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShapesHit';
			$t->{hash} = "$t->{transaction}-SS-$t->{withdraw}";
			$count{h}++;
			push @$enriched, $t;
			next;
		}
		$h = substr($h,0,9); # hashes from Gastracker.io (ETC) have truncated transaction hashes
		if ($h and $hdict{$h}) {
			$t->{T} = $hdict{$h}{T};
			$t->{dt} = $hdict{$h}{dt};
			$t->{timeStamp} = $hdict{$h}{timeStamp};
			$t->{to} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toaccount} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShapesHIT';
			$t->{hash} = "$t->{transaction}-SS-$t->{withdraw}";
			$count{shorthash}++;
			push @$enriched, $t;
			next;
		}
		my $a = ($t->{address}); #ss deposit address
		if ($a) {
			$a = "0x$a";
			$a =~ s/0x0x/0x/;
		}
		if ($a and $adict{"to $a $t->{incomingCoin}"}) {
			$t->{T} = $adict{$a}{T};
			$t->{dt} = $adict{$a}{dt};
			$t->{timeStamp} = $adict{$a}{timeStamp};
			$t->{to} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toaccount} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShApeshit';
			$t->{hash} = "$t->{transaction}-SS-$t->{withdraw}";
			if ($t->{transaction} eq 'a9100aabc21a2c7df291a9e05eb32ee3c77fe5e06b31f6f867277570459ef90a') {
				$t->{dt} = DateTime->new(year=>2017,month=>06,day=>13,hour=>11,minute=>13,second=>59,time_zone=>'UTC');	
			}
			$count{a}++;
			push @$enriched, $t;
			next;
		}
		my $w = ($t->{withdraw}); #ss withdrawal address
		if ($w) {
			$w = "0x$w";
			$w =~ s/0x0x/0x/;
		}
		if ($w and $adict{"from $w $t->{outgoingCoin}"}) {
			$t->{T} = $adict{$w}{T};
			$t->{dt} = $adict{$w}{dt};
			$t->{timeStamp} = $adict{$w}{timeStamp};
			$t->{to} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toaccount} = 'ShapeShiftInternalAddresses'; # $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShapeshiW';
			$t->{hash} = "$t->{transaction}-SS-$t->{withdraw}";
			$count{w}++;
			push @$enriched, $t;
			next;
		}
		$count{none}++;	
	}
	foreach my $c (sort keys %count) {
		say "$c $count{$c}";
	}
	return $enriched;
}

sub printTransactions {
	my ($transactions,$sstransactions) = @_;
	foreach my $t (sort {$a->{timeStamp} <=> $b->{timeStamp}} @$transactions) {
		print "$t->{source} $t->{T} $t->{fromS} $t->{amount} $t->{fromDesc} $t->{'Value'} $t->{ccy} $t->{toS} $t->{toDesc}\n";
	}
}

sub printMySQLTransactions {
	my $trans = shift;
    print "TradeType,Subtype,DateTime,Account,ToAccount,Amount,AmountCcy,ValueX,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Owner,Hash\n";
    for my $rec (sort {$a->{dt} <=> $b->{dt}} @$trans) {
    	my $dt = $rec->{dt};
    	if (ref($dt) ne 'DateTime' ) {
   		 	say "Oops" if !defined $dt;
   		 	next;
    	}
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


#Main Program

my ($btc, $bch, $etc, $eth, $ss) = ([],[],[],[],[]);
#$bi = retrieve("$opt{datadir}/$opt{bitstamp}");
$btc = retrieve("$opt{datadir}/$opt{bitcoin}");
$bch = retrieve("$opt{datadir}/$opt{bitcoincash}");
$eth = retrieve("$opt{datadir}/$opt{ether}");
$etc = retrieve("$opt{datadir}/$opt{classic}");
$ss = retrieve("$opt{datadir}/$opt{shapeshift}");

my $all = [];
push(@$all, @$btc, @$bch, @$eth, @$etc);
my $richer = enrichShapeShiftTransactions($ss, $all);
#push(@$all, @$richer);
printMySQLTransactions($richer);

