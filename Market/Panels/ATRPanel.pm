package Market::Panels::ATRPanel;

use strict;
use warnings;
use List::Util qw(min max);

sub new {
    my ($class, %args) = @_;
    my $self = {
        canvas    => $args{canvas},
        scale     => undef,
        crosshair => {},
    };
    bless $self, $class;
    
    $self->_init_crosshair_objects();
    return $self;
}

sub _init_crosshair_objects {
    my ($self) = @_;
    my $c = $self->{canvas};
    $self->{crosshair}->{vline} = $c->createLine(0, 0, 0, 0, -fill => 'gray', -dash => '.', -state => 'hidden');
    $self->{crosshair}->{hline} = $c->createLine(0, 0, 0, 0, -fill => 'gray', -dash => '.', -state => 'hidden');
    $self->{crosshair}->{text}  = $c->createText(0, 0, -text => '', -fill => 'white', -state => 'hidden');
}

sub get_y_range {
    my ($self, $data_slice) = @_;
    
    # Filtramos los valores no definidos (el ATR no tiene valor en las primeras 'n' velas)
    my @valid_values = grep { defined $_ } @$data_slice;
    return (0, 1) unless @valid_values;

    my $min_val = $valid_values[0];
    my $max_val = $valid_values[0];

    foreach my $val (@valid_values) {
        $min_val = min($min_val, $val);
        $max_val = max($max_val, $val);
    }

    # Damos un margen del 10% para que la línea no golpee el techo/piso del canvas
    my $padding = ($max_val - $min_val) * 0.10;
    $padding = 0.0001 if $padding == 0; # Protección rango plano
    
    return ($min_val - $padding, $max_val + $padding);
}

sub set_scale {
    my ($self, $scale) = @_;
    $self->{scale} = $scale;
}

sub render {
    my ($self, $data_slice) = @_;
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    return unless $s && @$data_slice;

    # Limpiar fotograma anterior
    $c->delete('atr_line'); 

    my @coords;
    
    for my $i (0 .. $#{$data_slice}) {
        my $val = $data_slice->[$i];
        
        # Saltamos el dibujo si estamos en el inicio histórico donde el ATR aún no se calcula
        next unless defined $val; 
        
        my $x = $s->index_to_center_x($i);
        my $y = $s->value_to_y($val);
        
        push @coords, $x, $y;
    }
    
    # Dibujar la línea continua si tenemos al menos 2 puntos (4 coordenadas: x1, y1, x2, y2)
    if (@coords >= 4) {
        $c->createLine(
            @coords,
            -fill  => '#2962FF', # Color Azul clásico de indicadores en TradingView
            -width => 2,
            -tags  => 'atr_line'
        );
    }
    
    # Dibujar escala de valores del ATR a la derecha
    $s->_draw_y_scale($c);
}

sub draw_crosshair {
    my ($self, $x, $y) = @_;
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    # 1. Si no hay X (el ratón salió del programa), ocultamos todo
    if (!defined $x || !$s) {
        $c->itemconfigure($self->{crosshair}->{vline}, -state => 'hidden');
        $c->itemconfigure($self->{crosshair}->{hline}, -state => 'hidden');
        $c->itemconfigure($self->{crosshair}->{text},  -state => 'hidden');
        return;
    }

    my $width  = $s->{width};
    my $height = $s->{height};

    # ==========================================
    # EJE X: Siempre se dibuja (Sincronizado)
    # ==========================================
    $c->coords($self->{crosshair}->{vline}, $x, 0, $x, $height);
    $c->itemconfigure($self->{crosshair}->{vline}, -state => 'normal');

    # ==========================================
    # EJE Y: Solo se dibuja si el ratón está aquí
    # ==========================================
    if (defined $y) {
        $c->coords($self->{crosshair}->{hline}, 0, $y, $width, $y);
        $c->itemconfigure($self->{crosshair}->{hline}, -state => 'normal');
        
        my $val = $s->y_to_value($y);
        my $display_val = sprintf("%.4f", $val);
        
        $c->coords($self->{crosshair}->{text}, $width - 5, $y - 10);
        $c->itemconfigure($self->{crosshair}->{text}, -text => $display_val, -state => 'normal');
    } else {
        # Si el ratón está en el panel de arriba, ocultamos la línea horizontal del ATR
        $c->itemconfigure($self->{crosshair}->{hline}, -state => 'hidden');
        $c->itemconfigure($self->{crosshair}->{text},  -state => 'hidden');
    }

    # ==========================================
    # ORGANIZACIÓN DE CAPAS FRONTALES
    # ==========================================
    $c->raise($self->{crosshair}->{vline});
    
    if (defined $y) {
        $c->raise($self->{crosshair}->{hline});
        $c->raise($self->{crosshair}->{text});
    }
}

1;