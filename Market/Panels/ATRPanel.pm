package Market::Panels::ATRPanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
    };
    bless $self, $class;
    return $self;
}

sub get_y_range {
    my ($self, $indicator_values, $start_idx, $end_idx) = @_;
    
    # Encontrar el valor mínimo y máximo del ATR en la ventana visible
    my $min = $indicator_values->[$start_idx] || 0;
    my $max = $min;
    
    for my $i ($start_idx .. $end_idx) {
        my $val = $indicator_values->[$i];
        next unless defined $val;
        $min = $val if $val < $min;
        $max = $val if $val > $max;
    }
    
    # Añadimos un pequeño margen (padding) visual del 10%
    my $padding = ($max - $min) * 0.1;
    return ($min - $padding, $max + $padding);
}

sub render {
    my ($self, $canvas, $indicator_values, $scale, $start_idx, $end_idx) = @_;
    
    # Limpiamos solo la línea del indicador anterior
    $canvas->delete('atr_line'); 
    
    my @coords;
    for my $i ($start_idx .. $end_idx) {
        my $val = $indicator_values->[$i];
        next unless defined $val; # Ignorar si no hay valor (ej. primeras 14 velas)
        
        # Transformación lineal a pixeles usando tu clase Scales
        my $x = $scale->index_to_center_x($i);
        my $y = $scale->value_to_y($val);
        
        push @coords, $x, $y;
    }
    
    # Dibuja la línea solo si hay suficientes puntos
    if (@coords >= 4) { 
        $canvas->createLine(
            @coords,
            -fill  => '#2962FF', # Azul característico de TradingView
            -width => 1.5,
            -tags  => 'atr_line'
        );
    }
}

1;