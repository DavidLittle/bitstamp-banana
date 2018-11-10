package TransactionUtils;

use lib '.';
use Person;
use Account;
use AccountsList;
use Transaction;

sub printBalances {
	my ($self,$transactions) = @_;
	my $processed;
	my $balances;
	foreach my $t (sort {$a->{dt} <=> $b->{dt}} @$transactions) {
		#next if $processed->{$t->{hash}};
		#$processed->{$t->{hash}} = 1;
		#$balances->{'txnFee'} += $t->{'txnFee'};
		#$balances->{$t->{from}} -= $t->{'txnFee'}; # process tx fee even if this is an error transaction
		#next if $t->{isError}; # Typically out of gas (make sure fees are processed but principal is not.
		$balances->{$t->{from_account}{Currency}}{$t->{from_account}{Owner}{name}} -= $t->{amount};
		$balances->{$t->{to_account}{Currency}}{$t->{to_account}{Owner}{name}} += $t->{value};
		$balances->{$t->{from_account}{Currency}}{$t->{from_account}{AccountName}} -= $t->{amount};
		$balances->{$t->{to_account}{Currency}}{$t->{to_account}{AccountName}} += $t->{value};
		print join (',',
			$t->{dt}->datetime(" "),
			$t->{from_account}{Owner}{name},
			$balances->{$t->{from_account}{Currency}}{$t->{from_account}{Owner}{name}},
			$t->{from_account}{AccountName},
			$balances->{$t->{from_account}{Currency}}{$t->{from_account}{AccountName}},
			' => ',
			$t->{amount},
			' => ',
			$t->{to_account}{AccountName},
			$balances->{$t->{to_account}{Currency}}{$t->{to_account}{AccountName}},
			$t->{to_account}{Owner}{name},
			$balances->{$t->{to_account}{Currency}}{$t->{to_account}{Owner}{name}},
			) . "\n";
	}
	return $balances;
}

sub printTransactions {
	my ($self,$transactions) = @_;
    Transaction->printHeader;
    for my $t (sort {$a->{dt} <=> $b->{dt}} @$transactions) {
		$t->print;
	}
}

sub printMySQLTransactions {
	my ($self,$transactions) = @_;
    Transaction->printMySQLHeader;
    for my $t (sort {$a->{dt} <=> $b->{dt}} @$transactions) {
		$t->printMySQL;
	}
}


1;
