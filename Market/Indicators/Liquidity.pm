package Market::Indicators::Liquidity;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        depth => $args{depth} || 3, 
        data  => [],
    };
    bless $self, $class;
    return $self;
}

# =====================================================================
# MOTOR LÓGICO PRINCIPAL
# =====================================================================
sub calculate {
    my ($self, $market_data) = @_;
    my $size = $market_data->size();
    my $k = $self->{depth};
    
    $self->{data} = []; 

    for my $i (0 .. $size - 1) {
        my $current = $market_data->get_candle($i);

        # Margen de seguridad en los extremos
        if ($i < $k || $i >= $size - $k) {
            push @{$self->{data}}, { state => 'none' };
            next;
        }

        my $is_swing_high = 1;
        my $is_swing_low  = 1;

        # Evaluar la vecindad [i-k ... i-1] y [i+1 ... i+k]
        for my $j (1 .. $k) {
            my $left  = $market_data->get_candle($i - $j);
            my $right = $market_data->get_candle($i + $j);

            if ($left->{high} >= $current->{high} || $right->{high} >= $current->{high}) {
                $is_swing_high = 0;
            }
            if ($left->{low} <= $current->{low} || $right->{low} <= $current->{low}) {
                $is_swing_low = 0;
            }
        }

        # Almacenar el estado
        if ($is_swing_high) {
            push @{$self->{data}}, { state => 'swing_high', price => $current->{high}, index => $i };
        } elsif ($is_swing_low) {
            push @{$self->{data}}, { state => 'swing_low', price => $current->{low}, index => $i };
        } else {
            push @{$self->{data}}, { state => 'none' };
        }
    }
}

# =====================================================================
# INTERFAZ ESTÁNDAR PARA IndicatorManager.pm
# =====================================================================

# 1. Llamado en streaming (vela por vela)
sub update_last {
    my ($self, $market_data) = @_;
    # La vela actual aún no puede ser un Swing Point porque necesita velas futuras
    push @{$self->{data}}, { state => 'none' };
}

# 2. Llamado para recalcular todo el historial (Replay / Cambio temporalidad)
sub calculate_batch {
    my ($self, $market_data) = @_;
    $self->calculate($market_data);
}

# 3. Devuelve los valores (Requerido por slice_array en el Manager)
sub get_values {
    my ($self) = @_;
    return $self->{data};
}

# 4. Limpia la memoria (Requerido al cambiar temporalidad)
sub reset {
    my ($self) = @_;
    $self->{data} = [];
}

1;