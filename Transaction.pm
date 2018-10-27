package Transaction;

use lib '.';
use Person;
use Account;

use Moose;
use Moose::Util::TypeConstraints;

class_type 'DateTime'; # Moose doesn't know about non-Moose based classes

enum 'Currency' => [qw( BCH BTC ETC ETH USD GBP EUR )];

has 'tran_type' 	=> (is => 'rw', isa => 'Str');
has 'tran_subtype' 	=> (is => 'rw', isa => 'Str');
has 'dt' 			=> (is => 'rw', isa => 'DateTime',);
has 'from_account' 	=> (is => 'rw', isa => 'Account', required => 1,);
has 'to_account' 	=> (is => 'rw',	isa => 'Account', required => 1,);
has 'currency' 		=> (is => 'rw',	isa => 'Currency', required => 1,);

has 'owner' => (
	is  => 'rw',
	isa => 'Person',
);

has 'amount' => (
	is  => 'rw',
	isa => 'Num',
);

has 'value' => (
	is  => 'rw',
	isa => 'Num',
);

has 'value_currency' => (
	is  => 'rw',
	isa => 'Currency',
	lazy => 1,
	default => sub {my $self = shift; return $self->currency},
);

has 'rate' => (
	is  => 'rw',
	isa => 'Num',
);

has 'rate_currency' => (
	is  => 'rw',
	isa => 'Currency',
	lazy => 1,
	default => sub {my $self = shift; return $self->currency},
);

has 'fee' => (
	is  => 'rw',
	isa => 'Num',
);

has 'fee_currency' => (
	is  => 'rw',
	isa => 'Currency',
	lazy => 1,
	default => sub {my $self = shift; return $self->currency},
);

has 'hash' => ( #must be present and unique
	is  => 'rw',
	isa => 'Str',
	required => 1,
);

no Moose;
__PACKAGE__->meta->make_immutable;

