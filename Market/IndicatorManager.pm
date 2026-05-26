package Market::IndicatorManager;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    my $self = {
        indicators => {},
    };
    bless $self, $class;
    return $self;
}

sub register {
    my ($self, $name, $indicator) = @_;
    $self->{indicators}->{$name} = $indicator;
}

sub update_last {
    my ($self, $market_data) = @_;
    foreach my $name (keys %{$self->{indicators}}) {
        $self->{indicators}->{$name}->update_last($market_data);
    }
}

sub get {
    my ($self, $name) = @_;
    return $self->{indicators}->{$name}->get_values();
}

sub reset_all {
    my ($self) = @_;
    foreach my $name (keys %{$self->{indicators}}) {
        $self->{indicators}->{$name}->reset();
    }
}

sub recompute_all {
    my ($self, $market_data) = @_;
    foreach my $name (keys %{$self->{indicators}}) {
        if ($self->{indicators}->{$name}->can('compute_all')) {
            $self->{indicators}->{$name}->compute_all($market_data);
        }
    }
}
1;
