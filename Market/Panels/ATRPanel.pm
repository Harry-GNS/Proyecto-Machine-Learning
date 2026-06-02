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
    
    # Líneas guía
    $self->{crosshair}->{vline} = $c->createLine(0, 0, 0, 0, -fill => '#9598a1', -dash => '.', -state => 'hidden');
    $self->{crosshair}->{hline} = $c->createLine(0, 0, 0, 0, -fill => '#9598a1', -dash => '.', -state => 'hidden');
    
    # Etiqueta Y (Valor en el eje derecho) - Fondo y Texto
    $self->{crosshair}->{y_bg}   = $c->createRectangle(0, 0, 0, 0, -fill => '#2962FF', -outline => '#2962FF', -state => 'hidden');
    $self->{crosshair}->{y_text} = $c->createText(0, 0, -text => '', -fill => 'white', -anchor => 'e', -state => 'hidden');

    # NUEVO: Texto en la esquina superior izquierda para el valor exacto de la vela
    $self->{crosshair}->{info_text} = $c->createText(
        10, 10, 
        -text => '', 
        -fill => '#2962FF', 
        -anchor => 'nw',
        -font => ['Helvetica', 10, 'bold']
    );
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
    
    # NUEVO: Guardamos los datos para leerlos luego con el cursor
    $self->{current_slice} = $data_slice;
    
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    return unless $s && @$data_slice;

    # Limpiar fotograma anterior
    $c->delete('atr_line'); 

    my @coords;
    for my $i (0 .. $#{$data_slice}) {
        my $val = $data_slice->[$i];
        next unless defined $val; 
        
        my $x = $s->index_to_center_x($i);
        my $y = $s->value_to_y($val);
        push @coords, $x, $y;
    }
    
    if (@coords >= 4) {
        $c->createLine(
            @coords,
            -fill  => '#2962FF',
            -width => 2,
            -tags  => 'atr_line'
        );
    }
    
    $s->_draw_y_scale($c);
}

sub draw_crosshair {
    my ($self, $x, $y) = @_;
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    # 1. Si el ratón sale, ocultar todo
    if (!defined $x || !$s) {
        my @hide_keys = qw(vline hline y_bg y_text);
        foreach my $key (@hide_keys) {
            $c->itemconfigure($self->{crosshair}->{$key}, -state => 'hidden') if exists $self->{crosshair}->{$key};
        }
        return;
    }

    my $width  = $s->{width};
    my $height = $s->{height};

    # ==========================================
    # EJE X (Sincronizado con PricePanel)
    # ==========================================
    $c->coords($self->{crosshair}->{vline}, $x, 0, $x, $height);
    $c->itemconfigure($self->{crosshair}->{vline}, -state => 'normal');
    
    # Extraer el valor exacto del ATR para la vela actual (Esquina superior izquierda)
    if ($self->{current_slice}) {
        my $candle_width = $width / $s->{visible_bars};
        my $local_index = int(($x / $candle_width) + $s->{offset});
        
        if ($local_index >= 0 && $local_index < @{$self->{current_slice}}) {
            my $val = $self->{current_slice}->[$local_index];
            my $str = defined $val ? sprintf("ATR: %.4f", $val) : "ATR: N/A";
            $c->itemconfigure($self->{crosshair}->{info_text}, -text => $str);
        }
    }

    # ==========================================
    # EJE Y (Valor en el lado derecho)
    # ==========================================
    if (defined $y) {
        $c->coords($self->{crosshair}->{hline}, 0, $y, $width, $y);
        $c->itemconfigure($self->{crosshair}->{hline}, -state => 'normal');
        
        my $val = $s->y_to_value($y);
        my $display_val = sprintf("%.4f", $val);
        
        # Etiqueta posicionada en el borde derecho, alineada exactamente al puntero ($y)
        $c->coords($self->{crosshair}->{y_text}, $width - 5, $y);
        $c->itemconfigure($self->{crosshair}->{y_text}, -text => $display_val, -state => 'normal');
        
        # Crear la caja de fondo azul dinámica
        my @y_bbox = $c->bbox($self->{crosshair}->{y_text});
        if (@y_bbox) {
            $c->coords($self->{crosshair}->{y_bg}, $y_bbox[0]-4, $y_bbox[1]-2, $y_bbox[2]+4, $y_bbox[3]+2);
            $c->itemconfigure($self->{crosshair}->{y_bg}, -state => 'normal');
        }
    } else {
        # Ocultar etiquetas horizontales si el puntero está en el panel de arriba
        $c->itemconfigure($self->{crosshair}->{hline}, -state => 'hidden');
        $c->itemconfigure($self->{crosshair}->{y_bg},  -state => 'hidden');
        $c->itemconfigure($self->{crosshair}->{y_text}, -state => 'hidden');
    }

    # ==========================================
    # ORDEN DE CAPAS FRONTALES
    # ==========================================
    $c->raise($self->{crosshair}->{vline});
    $c->raise($self->{crosshair}->{info_text});
    
    if (defined $y) {
        $c->raise($self->{crosshair}->{hline});
        $c->raise($self->{crosshair}->{y_bg});
        $c->raise($self->{crosshair}->{y_text});
    }
}

1;