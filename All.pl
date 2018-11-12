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
use TransactionUtils;
# Commandline args
GetOptions(
	'balances!' => \$opt{balances},
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
$opt{ItBit} ||= "ItBitTransactions.dat";
$opt{shapeshift} ||= "ShapeshiftTransactions.dat";

# Global variables


sub reportCounts {
	foreach my $c (sort keys %counts) {
		say "\t count of $c $counts{$c}";
	}
}

#Main Program

#my ($btc, $bch, $etc, $eth, $ss) = ([],[],[],[],[]);
my $bit = retrieve("$opt{datadir}/$opt{bitstamp}");
my $itbit = retrieve("$opt{datadir}/$opt{ItBit}");
my $btc = retrieve("$opt{datadir}/$opt{bitcoin}");
my $bch = retrieve("$opt{datadir}/$opt{bitcoincash}");
my $eth = retrieve("$opt{datadir}/$opt{ether}");
my $etc = retrieve("$opt{datadir}/$opt{classic}");
my $ss = retrieve("$opt{datadir}/$opt{shapeshift}");

my $all = [];
push(@$all, @$bit, @$itbit, @$btc, @$bch, @$eth, @$etc, @$ss);

if ($opt{balances}) {
	TransactionUtils->printBalances($all);
} elsif ($opt{quick}) {
	TransactionUtils->printTransactions($all);
} else {
	TransactionUtils->printMySQLTransactions($all);
}

reportCounts() if $opt{counts};
