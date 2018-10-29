package Transaction;

use lib '.';
use Person;
use Account;

use Moose;
use Moose::Util::TypeConstraints;

class_type 'DateTime'; # Moose doesn't know about non-Moose based classes
#class_type 'Account'; # Moose doesn't know about non-Moose based classes
#class_type 'Person'; # Moose doesn't know about non-Moose based classes

enum 'Currency' => [qw( BCH BTC ETC ETH USD GBP EUR DASH)];

has 'tran_type' 	=> (is => 'rw', isa => 'Str');
has 'tran_subtype' 	=> (is => 'rw', isa => 'Str');
has 'dt' 			=> (is => 'rw', isa => 'DateTime',);
has 'from_account' 	=> (is => 'ro', isa => 'Account', required => 1,);
has 'to_account' 	=> (is => 'ro',	isa => 'Account', required => 1,);
has 'currency' 		=> (is => 'ro',	isa => 'Currency', required => 1,);
has 'amount' 		=> (is => 'rw',	isa => 'Num', required => 1,);
has 'hash' 			=> (is => 'rw', isa => 'Str', required => 1,);
has 'owner' 		=> (is => 'rw',	isa => 'Person', lazy => 1, default => \&_def_owner);
has 'value' 		=> (is => 'rw',	isa => 'Num', default => 0,);
has 'value_currency'=> (is => 'rw', isa => 'Currency', lazy => 1, default => \&_def_currency);
has 'rate' 			=> (is => 'rw', isa => 'Num', default => 0,);
has 'rate_currency' => (is => 'rw', isa => 'Currency', lazy => 1, default => \&_def_currency);
has 'fee' 			=> (is => 'rw', isa => 'Num', default => 0,);
has 'fee_currency' 	=> (is => 'rw', isa => 'Currency', lazy => 1, default => \&_def_currency);

sub printMySQLHeader {
	my $self = shift;
    print "TradeType,Subtype,DateTime,Account,ToAccount,Amount,AmountCcy,ValueX,ValueCcy,Rate,RateCcy,Fee,FeeCcy,Owner,Hash\n";
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
		$self->currency,
		$self->value,
		$self->value_currency,
		$self->rate,
		$self->rate_currency,
		$self->fee,
		$self->fee_currency,
		$self->from_account->Owner->name,
		$self->hash
		);
	print "\n";
}

sub _def_owner {
	my $self = shift;
	return $self->from_account->Owner;
}
sub _def_currency {
	my $self = shift;
	return $self->currency;
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;
