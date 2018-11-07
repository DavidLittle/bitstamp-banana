package Transaction;

use lib '.';
use Person;
use Account;

use Moose;
use Moose::Util::TypeConstraints;

class_type 'DateTime'; # Moose doesn't know about non-Moose based classes

enum 'Currency' => [qw( BCH BTC ETC ETH USD GBP EUR DASH)];

# TODO from_ref and to_ref instead of or as well as hash?
# TODO usd price where API gives price at time of transfer or exchange
# TODO from_amount and to_amount (get rid of value)
# TODO currecy from from_account (get rid of currency and value_currency)
# TODO rate is conversion_rate - rename

has 'tran_type' 	=> (is => 'rw', isa => 'Str', required => 1,);
has 'tran_subtype' 	=> (is => 'rw', isa => 'Str', required => 1,);
has 'dt' 			=> (is => 'rw', isa => 'DateTime',);
has 'from_account' 	=> (is => 'ro', isa => 'Account', required => 1,);
has 'to_account' 	=> (is => 'ro',	isa => 'Account', required => 1,);
has 'currency' 		=> (is => 'ro',	isa => 'Currency', required => 1,);
has 'amount' 		=> (is => 'rw',	isa => 'Num', required => 1,);
has 'hash' 			=> (is => 'rw', isa => 'Str', required => 1,);
has 'value' 		=> (is => 'rw',	isa => 'Num', default => 0,);
has 'value_currency'=> (is => 'rw', isa => 'Currency', lazy => 1, default => \&_def_currency);
has 'rate' 			=> (is => 'rw', isa => 'Num', default => 1,);
has 'from_fee'		=> (is => 'rw', isa => 'Num', default => 0,);
has 'to_fee' 		=> (is => 'rw', isa => 'Num', default => 0,);
has 'fee_currency' 	=> (is => 'rw', isa => 'Currency', lazy => 1, default => \&_def_currency);
has 'note' 			=> (is => 'rw', isa => 'Str', lazy => 1, default => "");
has 'balance_change'=> (is => 'rw', isa => 'Str', lazy => 1, default => \&_def_balance_change); # used by Kev to update balances


sub printMySQLHeader {
	my $self = shift;
    print "TradeType,Subtype,DateTime,Account,ToAccount,Amount,AmountCcy,ValueX,ValueCcy,Rate,FromFee,ToFee,FeeCcy,BalanceChange,Hash,Note\n";
}
sub printMySQL {
	my $self = shift;
	print join(",",
		$self->tran_type,
		$self->tran_subtype,
		$self->dt->datetime(" "),
		$self->from_account->AccountRefUnique,
		$self->to_account->AccountRefUnique,
		$self->amount,
		$self->currency, # from_account->currency
		$self->value,
		$self->value_currency,
		$self->rate,
		$self->from_fee,
		$self->to_fee,
		$self->fee_currency,
		$self->balance_change,
		$self->hash,
		$self->note
		);
	print "\n";
}

sub printHeader {
	my $self = shift;
    print "DateTime,FmRef,FmAccount,FmOwner,Amount,Ccy,Value,ValueCcy,ToOwner,ToAccount,ToRef,Hash\n";
}
sub print {
	my $self = shift;
	print join(",",
		$self->dt->datetime(" "),
		$self->from_account->AccountRefShort,
		$self->from_account->AccountName,
		$self->from_account->Owner->name,
		$self->amount,
		$self->currency,
		$self->value,
		$self->value_currency,
		$self->to_account->Owner->name,
		$self->to_account->AccountName,
		$self->to_account->AccountRefShort,
		substr($self->{hash},0,6) . ".." . substr($self->{hash},-6,6),
	);
	print "\n";
}

sub _def_currency {
	my $self = shift;
	return $self->currency;
}
sub _def_balance_change {
	my $self = shift;
	return $self->tran_type eq 'Exchange' ? 'N' : 'Y';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
