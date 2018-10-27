use feature qw(state say);
#use warnings;
use English;
use strict;
# https://github.com/DavidLittle/bitstamp-banana.git
use Data::Dumper;
use lib '.';
use Person;

package Account;
use Carp qw(carp croak);

use Class::Tiny qw(idAccounts AccountRef AccountName Description AccountOwner Currency AccountType Follow Accountable ShapeShift Source BananaCode Owner AccountRefUnique AccountRefShort);

sub BUILD {
	my ($self, $args) = @_;
	carp "AccountRef attribute required for account $args->{idAccounts}" if ! $self->AccountRef();
	carp "Currency attribute required for account $args->{idAccounts} $args->{AccountRef}" if ! $self->Currency();
    $self->Owner(Person->name($args->{AccountOwner}));
    $self->AccountRefUnique($args->{AccountRef});
    my $t = $args->{AccountRef};
    $t =~ s/-.*//;
    $self->AccountRef($t);
    $self->AccountRefShort(substr($args->{AccountRef},0,8));
}

return 1;
