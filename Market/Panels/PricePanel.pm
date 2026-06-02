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
    
    # Líneas guía
    $self->{crosshair}->{vline} = $c->createLine(0, 0, 0, 0, -fill => '#9598a1', -dash => '.', -state => 'hidden');
    $self->{crosshair}->{hline} = $c->createLine(0, 0, 0, 0, -fill => '#9598a1', -dash => '.', -state => 'hidden');
    
    # Eje Y (Precio) - Fondo y Texto
    # CORRECCIÓN: Usamos el mismo azul oscuro (#2962FF) en lugar de 'none'
    $self->{crosshair}->{y_bg}   = $c->createRectangle(0, 0, 0, 0, -fill => '#2962FF', -outline => '#2962FF', -state => 'hidden');
    $self->{crosshair}->{y_text} = $c->createText(0, 0, -text => '', -fill => 'white', -anchor => 'e', -state => 'hidden');
    
    # Eje X (Tiempo) - Fondo y Texto
    # CORRECCIÓN: Usamos el mismo azul oscuro (#2962FF) en lugar de 'none'
    $self->{crosshair}->{x_bg}   = $c->createRectangle(0, 0, 0, 0, -fill => '#2962FF', -outline => '#2962FF', -state => 'hidden');
    $self->{crosshair}->{x_text} = $c->createText(0, 0, -text => '', -fill => 'white', -anchor => 's', -state => 'hidden');

    # NUEVO: Texto OHLC (Superior Izquierda)
    $self->{crosshair}->{ohlc_text} = $c->createText(
        10, 10, 
        -text => '', 
        -fill => '#d1d4dc', # Gris claro
        -anchor => 'nw',    # Noroeste
        -font => ['Helvetica', 10, 'bold']
    );
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
    
    # NUEVO: Guardamos el fragmento actual para que el crosshair pueda leer las fechas
    $self->{current_slice} = $data_slice; 
    
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    return unless $s && @$data_slice;

    # 1. Limpiar TODO el canvas antes de repintar
    $c->delete('candle'); 
    $c->delete('volume'); # <-- NUEVO: Limpiamos el volumen viejo
    
    # 2. Dibujar el eje, el fondo y el volumen PRIMERO (Capas inferiores)
    $self->draw_time_axis($data_slice);
    $self->draw_volume($data_slice); # <-- NUEVO: Invocamos el dibujo del volumen

    # 3. Dibujar las velas (Capa superior)
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
    my $c = $self->{canvas};

    # 1. Limpiar cualquier etiqueta de precio anterior dibujada
    $c->delete('last_price_label');

    return unless @$data_slice;

    # Extraer datos de la última vela visible
    my $last_candle = $data_slice->[-1];
    my $price = $last_candle->{close};
    my $y_pos = $self->{scale}->value_to_y($price);
    my $width = $self->{scale}->{width};

    # 2. Determinar el color: Verde si el cierre es mayor o igual a la apertura, Rojo si es menor
    my $color = ($price >= $last_candle->{open}) ? '#089981' : '#F23645';

    # Formatear el precio a 4 decimales
    my $display_val = sprintf("%.4f", $price);

    # 3. Dibujar el texto primero para poder obtener sus dimensiones (bbox)
    my $text_id = $c->createText(
        $width - 5, $y_pos,
        -text   => $display_val,
        -fill   => 'white',
        -anchor => 'e', # Alineado al este (derecha)
        -font   => ['Helvetica', 10, 'bold'],
        -tags   => 'last_price_label'
    );

    # 4. Obtener la caja delimitadora (bbox) que ocupa el texto para dibujar su fondo
    my @bbox = $c->bbox($text_id);
    if (@bbox) {
        # Agregar padding: 4px a los lados, 2px arriba y abajo
        my ($x1, $y1, $x2, $y2) = ($bbox[0] - 4, $bbox[1] - 2, $bbox[2] + 4, $bbox[3] + 2);

        # Dibujar el rectángulo de fondo
        my $bg_id = $c->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill    => $color,
            -outline => $color,
            -tags    => 'last_price_label'
        );

        # 5. Mover el rectángulo detrás del texto para que este sea visible
        $c->lower($bg_id, $text_id);
    }
}

sub draw_crosshair {
    my ($self, $x, $y) = @_;
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
# Si el ratón sale de la pantalla o está oculto por un zoom
    if (!defined $x || !defined $y || !$s || !$self->{current_slice}) {
        
        # 1. Mostrar el OHLC de la última vela visible por defecto
        if ($self->{current_slice} && @{$self->{current_slice}}) {
            my $last = $self->{current_slice}->[-1];
            my $ohlc_str = sprintf("O: %.4f   H: %.4f   L: %.4f   C: %.4f", 
                                    $last->{open}, $last->{high}, $last->{low}, $last->{close});
            $c->itemconfigure($self->{crosshair}->{ohlc_text}, -text => $ohlc_str);
            $c->raise($self->{crosshair}->{ohlc_text}); # Mantener por encima de todo
        }

        # 2. Ocultar el resto del crosshair
        my @hide_keys = qw(vline hline y_bg y_text x_bg x_text);
        foreach my $key (@hide_keys) {
            $c->itemconfigure($self->{crosshair}->{$key}, -state => 'hidden') if exists $self->{crosshair}->{$key};
        }
        return;
    }

    my $width  = $s->{width};
    my $height = $s->{height};

    # 1. Mover Líneas
    $c->coords($self->{crosshair}->{vline}, $x, 0, $x, $height);
    $c->coords($self->{crosshair}->{hline}, 0, $y, $width, $y);

    # NUEVO: Forzar el estado a normal para que se dibujen
    $c->itemconfigure($self->{crosshair}->{vline}, -state => 'normal');
    $c->itemconfigure($self->{crosshair}->{hline}, -state => 'normal');

    # 2. Configurar Etiqueta Y (Precio)
    my $val = $s->y_to_value($y);
    my $display_val = sprintf("%.4f", $val);
    
    $c->coords($self->{crosshair}->{y_text}, $width - 5, $y);
    $c->itemconfigure($self->{crosshair}->{y_text}, -text => $display_val, -state => 'normal');
    
    # 3. Configurar Etiqueta X (Tiempo)
    # Calculamos el índice local de la vela bajo el cursor
    my $candle_width = $width / $s->{visible_bars};
    my $local_index = int(($x / $candle_width) + $s->{offset});
    
    my $ts = "";
    my $slice = $self->{current_slice};
    
    if ($local_index >= 0 && $local_index < @$slice) {
        my $hovered_candle = $slice->[$local_index];
        $ts = $hovered_candle->{timestamp};
        if ($ts =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}:\d{2})/) {
            $ts = "$3/$2 $4"; 
        }
        
        # NUEVO: Actualizar el OHLC con la vela que el ratón está tocando
        my $ohlc_str = sprintf("O: %.4f   H: %.4f   L: %.4f   C: %.4f", 
                                $hovered_candle->{open}, $hovered_candle->{high}, 
                                $hovered_candle->{low}, $hovered_candle->{close});
        $c->itemconfigure($self->{crosshair}->{ohlc_text}, -text => $ohlc_str);
    }
    
    $c->coords($self->{crosshair}->{x_text}, $x, $height - 10);
    $c->itemconfigure($self->{crosshair}->{x_text}, -text => $ts, -state => 'normal');

    # 4. Ajustar los Fondos (Bounding Box)
    # Extraemos las coordenadas de la caja de los textos y le damos 4 píxeles de "padding"
    my @y_bbox = $c->bbox($self->{crosshair}->{y_text});
    if (@y_bbox) {
        $c->coords($self->{crosshair}->{y_bg}, $y_bbox[0]-4, $y_bbox[1]-2, $y_bbox[2]+4, $y_bbox[3]+2);
        $c->itemconfigure($self->{crosshair}->{y_bg}, -state => 'normal');
    }
    
    my @x_bbox = $c->bbox($self->{crosshair}->{x_text});
    if (@x_bbox && $ts ne "") {
        $c->coords($self->{crosshair}->{x_bg}, $x_bbox[0]-4, $x_bbox[1]-2, $x_bbox[2]+4, $x_bbox[3]+2);
        $c->itemconfigure($self->{crosshair}->{x_bg}, -state => 'normal');
    } else {
        $c->itemconfigure($self->{crosshair}->{x_bg}, -state => 'hidden');
    }

    # 5. FORZAR CAPA SUPERIOR: Asegurarnos que el crosshair no quede tapado por las velas
    $c->raise($self->{crosshair}->{vline});
    $c->raise($self->{crosshair}->{hline});
    $c->raise($self->{crosshair}->{y_bg});
    $c->raise($self->{crosshair}->{y_text});
    $c->raise($self->{crosshair}->{x_bg});
    $c->raise($self->{crosshair}->{x_text});
    $c->raise($self->{crosshair}->{ohlc_text}); # <-- NUEVO
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

sub draw_volume {
    my ($self, $data_slice) = @_;
    my $c = $self->{canvas};
    my $s = $self->{scale};
    
    return unless @$data_slice;

    my $max_vol = 0;
    foreach my $candle (@$data_slice) {
        $max_vol = $candle->{volume} if $candle->{volume} > $max_vol;
    }
    
    return if $max_vol == 0; 

    my $height = $s->{height};
    
    # 1. MARGEN INFERIOR: Reservamos 25 píxeles en la base del canvas para las fechas
    my $bottom_padding = 25;
    
    # Calculamos la altura máxima del volumen respetando el margen
    my $max_bar_height = ($height - $bottom_padding) * 0.20;

    for my $i (0 .. $#{$data_slice}) {
        my $candle = $data_slice->[$i];
        my $vol = $candle->{volume};
        
        next unless $vol > 0;

        my $bar_height = ($vol / $max_vol) * $max_bar_height;

        my $x_left   = $s->index_to_x($i);
        my $x_right  = $s->index_to_x($i + 1) - 1; 
        
        # 2. NUEVA BASE: Las barras aterrizan sobre el margen, no sobre el fondo total
        my $y_bottom = $height - $bottom_padding; 
        my $y_top    = $y_bottom - $bar_height;

        my $color = ($candle->{close} >= $candle->{open}) ? '#1d5c4d' : '#7a2524';

        $c->createRectangle(
            $x_left, $y_top, $x_right, $y_bottom, 
            -fill    => $color, 
            -outline => $color, 
            -tags    => 'volume'
        );
    }
}

1;