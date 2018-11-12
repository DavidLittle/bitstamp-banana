use feature qw(state say);
use English;
use strict;
use DateTime;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Text::CSV_XS qw(csv);
use Storable qw(dclone store retrieve);
use vars qw(%opt);
use Getopt::Long;
use lib '.';
use Account;
use AccountsList;
use Person;
use Transaction;
use TransactionUtils;

# Process a MtGox export CSV file so that it is conveniently usableas an import into an accounting system

# Commandline args
GetOptions(
	'balances!' => \$opt{balances}, # Data Directory address
	'datadir:s' => \$opt{datadir}, # Data Directory address
	'g:s' => \$opt{g}, #
	'help' => \$opt{h}, #
	'quick!' => \$opt{quick}, #
	'start:s' => \$opt{start}, # starting address
	'trans:s' => \$opt{trans}, # name of transactions CSV file
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{start} ||= "";
$opt{trans} ||= "MtGoxTransactions.dat";

my $inputs = [
	{
		transactions => "MtGoxHistory.csv",
		owner => "David",
	},
];

sub readMtGoxTransactions {
	my ($transactionfile, $owner) = @_;
	my $filename = "$opt{datadir}/$transactionfile";
	my $in = undef;
	my $data = [];
	my $aoh;
	if (-e $filename) {
		$aoh = csv( in => $filename, headers => "auto", encoding => "UTF-8");
	}
	else {
		say "Missing file $filename";
	}
	my $line_number = 1;
	foreach my $rec (@$aoh) {
		$rec->{tran_type} = 'MtGox';
		$line_number++;
		$rec->{Date} =~ s/ /T/; #Change 2017-02-08 14:53:27 to 2017-02-08T14:53:27
		$rec->{dt} = DateTime::Format::ISO8601->parse_datetime( $rec->{Date} );
		my $type = $rec->{Type};
	    $rec->{amount} = $rec->{Value};
	    $rec->{currency};
		$rec->{note} .= "$rec->{Ref} $rec->{Info}";
		my $currency = $rec->{currency};
    	$rec->{value} = $rec->{amount};
    	$rec->{value_currency} = $rec->{currency};
	    $rec->{rate} = 1;
		$rec->{fee_currency} = $rec->{currency};
		$rec->{from_fee} = $rec->{to_fee} = 0; # We get no fee information from
		$rec->{hash} = "${transactionfile}-Line$line_number";
		$rec->{owner} = 'David' if $rec->{Ref} =~ /DL/;
		$rec->{owner} = 'Richard' if $rec->{Ref} =~ /RL/;
		my $info = $rec->{Info};
		my $tid;
		if ($type eq 'in' and $info =~ /^BTC bought: \[tid:([0-9]+)\]\s+(\S+)\s+BTC\s+at\s+(\S+)\s+(\S+)/) {
			$rec->{tran_subtype} = 'Buy';
			my $quantity = $rec->{amount};
			$tid = $1;
			$rec->{value} = $2;
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = $3;
			my $price = $4;
			$rec->{amount} = $4 * $2;
			$rec->{fromaccount} = "MtGox$rec->{value_currency}Wallet$rec->{owner}";
			$rec->{toaccount} = "3MtGox$rec->{currency}Trading$rec->{owner}";
			$rec->{from_fee} = 0;
			$rec->{fee_currency} = 'BTC';
		}
		elsif ($type eq 'fee' and $info =~ /^BTC bought: \[tid:([0-9]+)\] (\S+)\s+BTC at\s+(\S+)\s+(\S+)/) {
			$rec->{tran_subtype} = 'Fee';
			$tid = $1;
			$rec->{from_fee} = $rec->{value};
			$rec->{amount} = 0;
			$rec->{value} = 0;
			$rec->{fee_currency} = 'BTC';
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = $3;
			my $price = $4;
			$rec->{fee_currency} = 'BTC';
			$rec->{fromaccount} = "MtGox$rec->{value_currency}Wallet$rec->{owner}";
			$rec->{toaccount} = "3MtGox$rec->{currency}Trading$rec->{owner}";
			$rec->{fee_currency} = 'BTC';
		}
		elsif ($type eq 'out' and $info =~ /^BTC sold: \[tid:([0-9]+)\] (\S+)\s+BTC at\s+(\S+)\s+(\S+)/) {
			$rec->{tran_subtype} = 'Sell';
			$tid = $1;
			$rec->{amount} = $2;
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = $3;
			my $price = $4;
			$rec->{value} = $price * $rec->{amount};
			$rec->{toaccount} = "MtGox$rec->{value_currency}Wallet$rec->{owner}";
			$rec->{fromaccount} = "3MtGox$rec->{currency}Trading$rec->{owner}";
			$rec->{from_fee} = 0;
			$rec->{fee_currency} = 'BTC';
		}
		elsif ($type eq 'in' and $info =~ /^Cancelled transfer because of timeout \(fee\):/) {
			$rec->{tran_subtype} = 'Cancel Fee';
			#$tid = $1;
			$rec->{amount} = 0;
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = 'BTC';
			$rec->{fee_currency} = 'BTC';
			$rec->{from_fee} = $rec->{value} * -1; # This is a fee refund so -ve fee
			$rec->{value} = 0;
			$rec->{fee_currency} = 'BTC';
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = 'BTC';
			my $price = $4;
			$rec->{fromaccount} = "3MtGox$rec->{value_currency}Wallet$rec->{owner}";
			$rec->{toaccount} = "3MtGox$rec->{currency}Trading$rec->{owner}";
		}
		elsif ($type eq 'in' and $info =~ /^Cancelled transfer because of timeout:/) {
			$rec->{tran_subtype} = 'Cancel Withdraw';
			#$tid = $1;
			$rec->{value} *= -1; # Refund of full withdraw amount
			$rec->{amount} = $rec->{value};
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = 'BTC';
			$rec->{fee_currency} = 'BTC';
			$rec->{from_fee} = 0; # This is a fee refund
			$rec->{toaccount} = "3MtGox$rec->{value_currency}Wallet$rec->{owner}";
			$rec->{fromaccount} = "3MtGox$rec->{currency}Trading$rec->{owner}";
		}
		elsif ($type eq 'withdraw' and $info =~ /^Bitcoin withdraw to (\S+)$/) {
			$rec->{tran_subtype} = 'Withdraw';
			my $address = $1;
			$rec->{amount} = $rec->{value};
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = 'BTC';
			$rec->{fee_currency} = 'BTC';
			$rec->{from_fee} = 0; # Fee is on a separate record
			$rec->{toaccount} = "3MtGox$rec->{value_currency}Wallet$rec->{owner}";
			$rec->{fromaccount} = "3MtGox$rec->{currency}Trading$rec->{owner}";
		}
		elsif ($type eq 'fee' and $info =~ /^Fees for Bitcoin withdraw to (\S+)$/) {
			$rec->{tran_subtype} = 'Withdraw Fee';
			my $address = $1;
			$rec->{from_fee} = $rec->{value};
			$rec->{amount} = $rec->{value} = 0;
			$rec->{currency} = 'BTC';
			$rec->{value_currency} = 'BTC';
			$rec->{fee_currency} = 'BTC';
			$rec->{toaccount} = "3MtGox$rec->{value_currency}Wallet$rec->{owner}";
			$rec->{fromaccount} = "3MtGox$rec->{currency}Trading$rec->{owner}";
		}
		else {
			say "Not sure what to do with $type $info $rec->{Ref}";
			next;
		}

		$rec->{from_account} = AccountsList->account($rec->{fromaccount});
		$rec->{to_account} = AccountsList->account($rec->{toaccount});

		if (! defined $rec->{from_account}) {
			say "From account undefined $rec->{fromaccount} ($type $rec->{currency} $rec->{note})";
			next;
		}
		if (ref($rec->{from_account}) ne 'Account') {
			say "From account is not a proper account $rec->{fromaccount} ($type $rec->{currency} $rec->{note})";
			next;
		}
		if (! defined $rec->{to_account}) {
			say "To account undefined $rec->{toaccount} ($type $rec->{currency} $rec->{note})";
			next;
		}
		if (ref($rec->{to_account}) ne 'Account') {
			say "To account is not a proper account $rec->{toaccount} ($type $rec->{currency} $rec->{note})";
			next;
		}

		my $T = Transaction->new($rec);

	    push @$data, $T;
	}
	return $data;
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}

# Main program
AccountsList->new();
my $data = [];
foreach my $files (@$inputs) {
	my $trans = readMtGoxTransactions($files->{transactions}, $files->{owner});
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
