package Market::Panels::Scales;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        width        => $args{width} || 1,        # Ancho del canvas en píxeles
        height       => $args{height} || 1,       # Alto del canvas en píxeles
        min_val      => $args{min_val} || 0,      # V_min (Precio o ATR mínimo visible)
        max_val      => $args{max_val} || 1,      # V_max (Precio o ATR máximo visible)
        visible_bars => $args{visible_bars} || 1, # Cantidad de velas en pantalla
        offset       => $args{offset} || 0,       # Desplazamiento horizontal (scroll)
    };
    bless $self, $class;
    return $self;
}

# Transformaciones del Eje X (Tiempo)
sub index_to_x {
    my ($self, $index) = @_;
    # Convierte índice -> coordenada X [cite: 298, 299]
    my $candle_width = $self->{width} / $self->{visible_bars};
    return ($index - $self->{offset}) * $candle_width;
}

sub x_to_index_float {
    my ($self, $x) = @_;
    # Convierte X -> índice continuo. Más precisión para interacción [cite: 302, 303, 304]
    my $candle_width = $self->{width} / $self->{visible_bars};
    return ($x / $candle_width) + $self->{offset};
}

sub x_to_index {
    my ($self, $x) = @_;
    # Convierte X -> índice entero [cite: 300, 301]
    # Usamos int() para truncar el flotante y obtener el índice del array
    return int($self->x_to_index_float($x));
}

sub index_to_center_x {
    my ($self, $index) = @_;
    # Devuelve centro de una vela en X [cite: 305, 306]
    my $candle_width = $self->{width} / $self->{visible_bars};
    my $x_start = $self->index_to_x($index);
    return $x_start + ($candle_width / 2);
}

# Transformaciones del Eje Y (Valores/Precios)
sub value_to_y {
    my ($self, $value) = @_;
    # Convierte valor (precio/indicador) -> Y [cite: 307, 308]
    my $range = $self->{max_val} - $self->{min_val};
    
    # Evitar división por cero si el rango es plano (ej. todos los precios son iguales)
    return $self->{height} / 2 if $range == 0; 
    
    my $normalized_val = ($value - $self->{min_val}) / $range;
    
    # Invertimos el eje Y multiplicando por la altura y restando desde el máximo
    return $self->{height} - ($normalized_val * $self->{height});
}

sub y_to_value {
    my ($self, $y) = @_;
    # Convierte Y -> valor [cite: 309, 310]
    my $range = $self->{max_val} - $self->{min_val};
    
    if ($self->{height} == 0) { return 0; } # Protección de división por cero
    
    # Proceso inverso de la normalización
    my $normalized_y = ($self->{height} - $y) / $self->{height};
    return $self->{min_val} + ($normalized_y * $range);
}

sub _draw_y_scale {
    my ($self, $canvas) = @_;
    
    # 1. Limpiar los precios anteriores para evitar que se amontonen y se vean borrosos
    $canvas->delete('y_scale');
    
    my $num_labels = 10;
    my $range = $self->{max_val} - $self->{min_val};
    my $step = $range / $num_labels;
    
    for my $i (0 .. $num_labels) {
        my $val = $self->{min_val} + ($i * $step);
        my $y_pos = $self->value_to_y($val);
        
        my $display_val = sprintf("%.2f", $val);
        
        # 2. Dibujar el texto asegurándonos de asignarle el tag 'y_scale'
        $canvas->createText(
            $self->{width} - 5, $y_pos, 
            -text => $display_val, 
            -anchor => 'e', 
            -fill => '#d1d4dc', # Gris claro para unificar el diseño
            -tags => 'y_scale'  # <--- ETIQUETA CRÍTICA AÑADIDA
        );
    }
}

1;