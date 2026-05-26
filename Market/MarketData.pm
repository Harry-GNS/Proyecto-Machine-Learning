package Market::MarketData;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    my $self = {
        data => [], # Arreglo principal para acceso por índice
        current_tf => '1m', # Timeframe por defecto
    };
    bless $self, $class;
    return $self;
}

sub add_candle {
    my ($self, $candle) = @_;
    # $candle debería ser un HashRef: { timestamp => ..., open => ..., high => ..., low => ..., close => ..., volume => ... }
    push @{$self->{data}}, $candle;
}

sub get_candle {
    my ($self, $index) = @_;
    return $self->{data}->[$index];
}

sub size {
    my ($self) = @_;
    return scalar @{$self->{data}};
}
