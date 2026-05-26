package Market::Panels::Scales;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        min_value     => 0,
        max_value     => 100,
        canvas_height => 400,
        start_index   => 0,   # ¡AÑADIDO! Para calcular posiciones relativas
        bar_width     => 10,  # Grosor de cada vela + separación
        %args,
    };
    bless $self, $class;
    return $self;
}

# Proyección matemática relativa: Convierte el índice de la vela a coordenadas X de pantalla
sub index_to_center_x {
    my ($self, $index) = @_;
    # Restamos start_index para que la primera vela visible siempre aparezca al inicio izquierdo
    my $relative_index = $index - $self->{start_index};
    return ($relative_index * $self->{bar_width}) + 50; # 50px de margen izquierdo
}

# Transformación lineal: Mapea el precio/valor al eje píxel Y del Canvas
sub value_to_y {
    my ($self, $value) = @_;
    my $min = $self->{min_value};
    my $max = $self->{max_value};
    my $height = $self->{canvas_height};
    
    return $height if ($max - $min) == 0; # Prevenir indeterminación matemática
    
    # Dejar un 10% de margen arriba y abajo para que las velas no toquen los bordes
    my $padded_height = $height * 0.8;
    my $y = $height - ((($value - $min) / ($max - $min)) * $padded_height + ($height * 0.1));
    return $y;
}

# Dibuja la escala vertical Y (Precios o valores del Indicador) a la derecha
sub _draw_y_scale {
    my ($self, $canvas) = @_;
    
    # Limpiar la escala y líneas horizontales previas
    $canvas->delete('y_scale');
    
    my $min = $self->{min_value};
    my $max = $self->{max_value};
    my $width = $canvas->width() || 1024;
    
    # Generar 5 niveles de precios/valores distribuidos uniformemente
    for my $i (0 .. 4) {
        my $fraction = $i / 4;
        my $current_value = $min + $fraction * ($max - $min);
        my $y = $self->value_to_y($current_value);
        
        # 1. Dibujar línea de cuadrícula horizontal (Gridline atenuada)
        $canvas->createLine(
            0, $y, $width - 80, $y, 
            -fill => '#E0E3EB', 
            -dash => '.', 
            -tags => 'y_scale'
        );
        
        # 2. Dibujar la etiqueta de texto con el precio/valor formateado
        $canvas->createText(
            $width - 40, $y,
            -text => sprintf("%.2f", $current_value),
            -fill => '#707a8a',
            -font => 'Arial 9',
            -tags => 'y_scale'
        );
    }
    
    # Dibujar la línea divisoria vertical del eje de precios
    $canvas->createLine(
        $width - 80, 0, $width - 80, $self->{canvas_height},
        -fill => '#E0E3EB',
        -tags => 'y_scale'
    );
}

# --- Conversiones inversas para la interacción de cursor ---
sub x_to_index { 
    my ($self, $x) = @_; 
    return int(($x - 50) / $self->{bar_width}) + $self->{start_index}; 
}

sub x_to_index_float { 
    my ($self, $x) = @_; 
    return (($x - 50) / $self->{bar_width}) + $self->{start_index}; 
}

sub y_to_value { 
    my ($self, $y) = @_; 
    my $min = $self->{min_value};
    my $max = $self->{max_value};
    my $height = $self->{canvas_height};
    my $padded_height = $height * 0.8;
    
    my $raw_fraction = ($height - $y - ($height * 0.1)) / $padded_height;
    return $min + $raw_fraction * ($max - $min);
}

1;