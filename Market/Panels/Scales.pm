package Market::Panels::Scales;

use strict;
use warnings;

# ========================================================
# NUEVO: Definimos el margen derecho reservado para la escala
# ========================================================
use constant RIGHT_MARGIN => 70;

sub new {
    my ($class, %args) = @_;
    my $self = {
        width        => $args{width} || 1,        
        height       => $args{height} || 1,       
        min_val      => $args{min_val} || 0,      
        max_val      => $args{max_val} || 1,      
        visible_bars => $args{visible_bars} || 1, 
        offset       => $args{offset} || 0,       
    };
    bless $self, $class;
    return $self;
}

# ========================================================
# FUNCIÓN AUXILIAR: Área donde realmente se dibujan las velas
# ========================================================
sub _drawable_width {
    my ($self) = @_;
    my $w = $self->{width} - RIGHT_MARGIN;
    return $w > 0 ? $w : 1; # Evitar que sea cero o negativo
}

# ========================================================
# Transformaciones del Eje X (Tiempo) 
# (Ahora utilizan _drawable_width en lugar de width)
# ========================================================
sub index_to_x {
    my ($self, $index) = @_;
    my $candle_width = $self->_drawable_width() / $self->{visible_bars};
    return ($index - $self->{offset}) * $candle_width;
}

sub x_to_index_float {
    my ($self, $x) = @_;
    my $candle_width = $self->_drawable_width() / $self->{visible_bars};
    return ($x / $candle_width) + $self->{offset};
}

sub x_to_index {
    my ($self, $x) = @_;
    return int($self->x_to_index_float($x));
}

sub index_to_center_x {
    my ($self, $index) = @_;
    my $candle_width = $self->_drawable_width() / $self->{visible_bars};
    my $x_start = $self->index_to_x($index);
    return $x_start + ($candle_width / 2);
}

# ========================================================
# Transformaciones del Eje Y (Valores/Precios)
# ========================================================
sub value_to_y {
    my ($self, $value) = @_;
    my $range = $self->{max_val} - $self->{min_val};
    
    return $self->{height} / 2 if $range == 0; 
    
    my $normalized_val = ($value - $self->{min_val}) / $range;
    return $self->{height} - ($normalized_val * $self->{height});
}

sub y_to_value {
    my ($self, $y) = @_;
    my $range = $self->{max_val} - $self->{min_val};
    
    if ($self->{height} == 0) { return 0; } 
    
    my $normalized_y = ($self->{height} - $y) / $self->{height};
    return $self->{min_val} + ($normalized_y * $range);
}

# ========================================================
# RENDERIZADO DEL EJE ESTÁTICO DE LA DERECHA
# ========================================================
sub _draw_y_scale {
    my ($self, $canvas) = @_;
    
    $canvas->delete('y_scale');
    
    # Calculamos dónde termina el área de las velas y empieza la barra
    my $chart_end_x = $self->{width} - RIGHT_MARGIN;
    
    # 1. DIBUJAR FONDO SÓLIDO Y BORDE SEPARADOR
    $canvas->createRectangle(
        $chart_end_x, 0, 
        $self->{width}, $self->{height},
        -fill    => '#131722',  # Color oscuro de fondo para la barra
        -outline => '#2a2e39',  # Línea vertical separadora entre la gráfica y la barra
        -tags    => 'y_scale'
    );
    
    # 2. DIBUJAR LOS TEXTOS (CON DOS DECIMALES)
    my $num_labels = 10;
    my $range = $self->{max_val} - $self->{min_val};
    $range = 1 if $range == 0; # Protección contra división por cero
    
    my $step = $range / $num_labels;
    
    for my $i (0 .. $num_labels) {
        my $val = $self->{min_val} + ($i * $step);
        my $y_pos = $self->value_to_y($val);
        
        my $display_val = sprintf("%.2f", $val);
        
        $canvas->createText(
            $self->{width} - 5, $y_pos, 
            -text => $display_val, 
            -anchor => 'e', 
            -fill => '#d1d4dc', 
            -tags => 'y_scale' 
        );
    }
}

1;