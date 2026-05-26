package Market::Panels::PricePanel;
use strict;
use warnings;

# ... (constructor new)

sub render {
    my ($self, $canvas, $market_data, $scale, $start_idx, $end_idx) = @_;
    
    # Limpiar únicamente los elementos del gráfico, no los ejes
    $canvas->delete('candle'); 

    for my $i ($start_idx .. $end_idx) {
        my $candle = $market_data->get_candle($i);
        next unless $candle;

        # 1. Transformación de dominio de datos a dominio de pantalla
        my $x = $scale->index_to_center_x($i); 
        my $y_open  = $scale->value_to_y($candle->{open});
        my $y_close = $scale->value_to_y($candle->{close});
        my $y_high  = $scale->value_to_y($candle->{high});
        my $y_low   = $scale->value_to_y($candle->{low});

        # 2. Lógica de renderizado financiero
        my $color = ($candle->{close} >= $candle->{open}) ? '#089981' : '#F23645'; # Verde y Rojo estilo TradingView
        
        # Dibujar la mecha (High to Low)
        $canvas->createLine(
            $x, $y_high, $x, $y_low, 
            -fill => $color, 
            -tags => 'candle'
        );
        
        # Dibujar el cuerpo (Open to Close)
        my $candle_width = 3; # Este valor deberá conectarse luego al nivel de zoom
        # Asegurar que el cuerpo tenga al menos 1 pixel de altura para Dojis
        if (abs($y_open - $y_close) < 1) {
            $y_close = $y_open + 1; 
        }
        
        $canvas->createRectangle(
            $x - $candle_width, $y_open, 
            $x + $candle_width, $y_close, 
            -fill => $color, 
            -outline => $color, 
            -tags => 'candle'
        );
    }
}
1;