package Market::Panels::PricePanel;

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
    
    # Objetos gráficos del crosshair ocultos por defecto
    $self->{crosshair}->{vline} = $c->createLine(0, 0, 0, 0, -fill => 'gray', -dash => '.', -state => 'hidden');
    $self->{crosshair}->{hline} = $c->createLine(0, 0, 0, 0, -fill => 'gray', -dash => '.', -state => 'hidden');
    $self->{crosshair}->{text}  = $c->createText(0, 0, -text => '', -fill => 'white', -state => 'hidden');
}

sub get_y_range {
    my ($self, $data_slice) = @_;
    return (0, 1) unless @$data_slice;

    my $min_price = $data_slice->[0]->{low};
    my $max_price = $data_slice->[0]->{high};

    foreach my $candle (@$data_slice) {
        $min_price = min($min_price, $candle->{low});
        $max_price = max($max_price, $candle->{high});
    }

    my $padding = ($max_price - $min_price) * 0.05;
    return ($min_price - $padding, $max_price + $padding);
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

    # 1. Limpiar TODO el canvas antes de repintar
    $c->delete('candle'); 
    
    # 2. DIBUJAR EL EJE Y FONDO PRIMERO (Para que quede detrás de las velas)
    $self->draw_time_axis($data_slice);

    # 3. Dibujar las velas
    for my $i (0 .. $#{$data_slice}) {
        my $candle = $data_slice->[$i];
        
        my $x_left   = $s->index_to_x($i);
        my $x_right  = $s->index_to_x($i + 1) - 1; 
        my $x_center = $s->index_to_center_x($i);
        
        my $y_open  = $s->value_to_y($candle->{open});
        my $y_close = $s->value_to_y($candle->{close});
        my $y_high  = $s->value_to_y($candle->{high});
        my $y_low   = $s->value_to_y($candle->{low});

        my $color = ($candle->{close} >= $candle->{open}) ? 'green' : 'red';
        
        $c->createLine(
            $x_center, $y_high, $x_center, $y_low, 
            -fill => $color, 
            -tags => 'candle'
        );
        
        $c->createRectangle(
            $x_left, $y_open, $x_right, $y_close, 
            -fill => $color, 
            -outline => $color, 
            -tags => 'candle'
        );
    }
    
    # 4. Dibujar la escala vertical de precios
    $s->_draw_y_scale($c);
    $self->render_last_visible_price($data_slice);
}

sub render_last_visible_price {
    my ($self, $data_slice) = @_;
    return unless @$data_slice;
    my $last_candle = $data_slice->[-1];
    my $y_pos = $self->{scale}->value_to_y($last_candle->{close});
}

sub draw_crosshair {
    my ($self, $x, $y) = @_;
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    if (!defined $x || !defined $y) {
        $c->itemconfigure($self->{crosshair}->{vline}, -state => 'hidden');
        $c->itemconfigure($self->{crosshair}->{hline}, -state => 'hidden');
        $c->itemconfigure($self->{crosshair}->{text},  -state => 'hidden');
        return;
    }

    my $price = $s->y_to_value($y);
    my $display_price = sprintf("%.4f", $price);

    my $width  = $s->{width};
    my $height = $s->{height};

    $c->coords($self->{crosshair}->{vline}, $x, 0, $x, $height);
    $c->coords($self->{crosshair}->{hline}, 0, $y, $width, $y);
    
    $c->coords($self->{crosshair}->{text}, $width - 5, $y - 10);
    $c->itemconfigure($self->{crosshair}->{text}, -text => $display_price);

    $c->itemconfigure($self->{crosshair}->{vline}, -state => 'normal');
    $c->itemconfigure($self->{crosshair}->{hline}, -state => 'normal');
    $c->itemconfigure($self->{crosshair}->{text},  -state => 'normal');
}

sub draw_time_axis {
    my ($self, $data_slice) = @_;
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    return unless @$data_slice;

    my $height = $s->{height};
    
    $c->delete('time_axis');
    
    # 1. Reducimos el máximo de etiquetas de 8 a 5 o 6 para darles más "aire"
    my $max_labels = 16; 
    
    my $step = int(scalar(@$data_slice) / $max_labels);
    $step = 1 if $step < 1;

    for (my $i = 0; $i < @$data_slice; $i += $step) {
        my $candle = $data_slice->[$i];
        
        my $x = $s->index_to_center_x($i);
        my $ts = $candle->{timestamp};
        
        # 2. TRUCO DE FORMATO: Acortar la cadena de texto (Regex)
        # Busca el patrón YYYY-MM-DD HH:MM:SS
        # y captura solo el Mes ($2), el Día ($3) y la Hora:Minuto ($4)
        if ($ts =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}:\d{2})/) {
            # Lo transformamos a formato corto legible: "DD/MM HH:MM"
            $ts = "$3/$2 $4"; 
        }
        # (Si tu CSV tiene fechas con separador '/', ajusta el guion '-' por '\/' en el regex)
        
        # Dibujar línea de fondo
        $c->createLine(
            $x, 0, $x, $height, 
            -fill => '#2a2e39', 
            -dash => '.', 
            -tags => 'time_axis'
        );
        
        # Dibujar texto
        $c->createText(
            $x, $height - 10, 
            -text => $ts, 
            -fill => '#d1d4dc', 
            -anchor => 's',     
            -tags => 'time_axis'
        );
    }
}


1;