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
use lib '.';
use Account;
use Transaction;
use Person;

# Commandline args
GetOptions(
	'counts!' => \$opt{counts},
	'datadir:s' => \$opt{datadir}, # Data Directory address
	'quick!' => \$opt{quick}, #
	'start:s' => \$opt{start}, # starting address
	'trace:s' => \$opt{trace},
)
#	'bitstamp:s' => \$opt{bitstamp}, # starting address
#	'classic:s' => \$opt{classic}, # starting address
#	'ether:s' => \$opt{ether}, # starting address
#	'shapeshift:s' => \$opt{shapeshift}, # starting address
;

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{bitstamp} ||= "BitstampTransactions.dat";
$opt{bitcoin} ||= "BlockchainTransactions.dat";
$opt{bitcoincash} ||= "BCHTransactions.dat";
$opt{classic} ||= "ClassicTransactions.dat";
$opt{ether} ||= "EtherTransactions.dat";
$opt{shapeshift} ||= "ShapeshiftTransactions.dat";

# Global variables

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
			$counts{"withdraw address resolved"}++;
		}

		$ss_t->{dt} = $ss_t->{withdraw_t}{dt} || $ss_t->{deposit_t}{dt} || DateTime->now;
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


#Main Program

#my ($btc, $bch, $etc, $eth, $ss) = ([],[],[],[],[]);
#$bi = retrieve("$opt{datadir}/$opt{bitstamp}");
my $btc = retrieve("$opt{datadir}/$opt{bitcoin}");
my $bch = retrieve("$opt{datadir}/$opt{bitcoincash}");
my $eth = retrieve("$opt{datadir}/$opt{ether}");
my $etc = retrieve("$opt{datadir}/$opt{classic}");
my $ss = retrieve("$opt{datadir}/$opt{shapeshift}");

my $all = [];
push(@$all, @$btc, @$bch, @$eth, @$etc);
enrichShapeShiftTransactions($ss, $all);
#push(@$all, @$richer);
if ($opt{quick}) {
	printTransactions($ss);
} else {
	printMySQLTransactions($ss);
}
reportCounts if $opt{counts};
