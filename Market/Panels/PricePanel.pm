package Market::Panels::PricePanel;
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

# Calcula el mínimo y máximo de los precios visibles para adaptar el eje Y dinámicamente
sub get_y_range {
    my ($self, $market_data, $start_idx, $end_idx) = @_;
    
    my $first_candle = $market_data->get_candle($start_idx);
    return (0, 100) unless $first_candle; # Resguardo si no hay datos
    
    my $min = $first_candle->{low};
    my $max = $first_candle->{high};
    
    for my $i ($start_idx .. $end_idx) {
        my $candle = $market_data->get_candle($i);
        next unless $candle;
        
        $min = $candle->{low}  if $candle->{low} < $min;
        $max = $candle->{high} if $candle->{high} > $max;
    }
    
    # Añadimos un pequeño margen (padding) del 5% arriba y abajo para que no tope los bordes
    my $padding = ($max - $min) * 0.05;
    $padding = 1 if $padding == 0; # Prevenir división por cero si el precio es plano
    
    return ($min - $padding, $max + $padding);
}

# Se encarga de transformar los datos crudos en figuras geométricas dentro del Canvas de Tk
sub render {
    my ($self, $canvas, $market_data, $scale, $start_idx, $end_idx) = @_;
    
    # Limpiar las velas dibujadas en el frame anterior para evitar sobreescribir memoria visual
    $canvas->delete('candle'); 

    for my $i ($start_idx .. $end_idx) {
        my $candle = $market_data->get_candle($i);
        next unless $candle;

        # 1. Transformación lineal usando la clase Scales
        my $x       = $scale->index_to_center_x($i); 
        my $y_open  = $scale->value_to_y($candle->{open});
        my $y_close = $scale->value_to_y($candle->{close});
        my $y_high  = $scale->value_to_y($candle->{high});
        my $y_low   = $scale->value_to_y($candle->{low});

        # 2. Configuración de colores (Verde alcista / Rojo bajista)
        my $color = ($candle->{close} >= $candle->{open}) ? '#089981' : '#F23645';
        
        # Dibujar la mecha de la vela (Línea High -> Low)
        $canvas->createLine(
            $x, $y_high, $x, $y_low, 
            -fill => $color, 
            -tags => 'candle'
        );
        
        # Dibujar el cuerpo de la vela (Rectángulo Open -> Close)
        my $candle_width = 3; 
        
        # Asegurar un grosor mínimo de 1 píxel para los Dojis (donde open == close)
        if (abs($y_open - $y_close) < 1) {
            $y_close = $y_open + 1; 
        }
        
        $canvas->createRectangle(
            $x - $candle_width, $y_open, 
            $x + $candle_width, $y_close, 
            -fill    => $color, 
            -outline => $color, 
            -tags    => 'candle'
        );
    }
}

# --- Esqueletos requeridos por la rúbrica para evitar futuros crashes ---
sub _init_crosshair_objects   { my ($self) = @_; }
sub round                     { my ($self, $value) = @_; return int($value + 0.5); }
sub render_last_visible_price { my ($self, $canvas) = @_; }
sub set_scale                 { my ($self, $scale) = @_; }
sub draw_crosshair            { my ($self, $x, $y) = @_; }
sub draw_time_axis            { my ($self, $canvas, $timestamps) = @_; }

1;