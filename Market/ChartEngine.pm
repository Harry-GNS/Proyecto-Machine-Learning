package Market::ChartEngine;
use strict;
use warnings;


sub render {
    my ($self) = @_;
    
    my $data = $self->{market_data};
    my $total_candles = $data->size();
    return if $total_candles == 0;

    my $visible_bars = 100; 
    my $end_idx = $total_candles - 1;
    my $start_idx = $end_idx - $visible_bars;
    $start_idx = 0 if $start_idx < 0;

    # --- 1. RENDERIZAR PANEL DE PRECIOS ---
    my ($min_p, $max_p) = $self->{price_panel}->get_y_range($data, $start_idx, $end_idx);
    
    # Asegúrate de instanciar un objeto de Market::Panels::Scales diferente para Y
    $self->{scales}->{price}->{min_value} = $min_p;
    $self->{scales}->{price}->{max_value} = $max_p;
    
    $self->{price_panel}->render(
        $self->{canvases}->{price}, 
        $data, 
        $self->{scales}->{price}, 
        $start_idx, 
        $end_idx
    );

    # --- 2. RENDERIZAR PANEL DE ATR ---
    my $atr_values = $self->{indicator_manager}->get('ATR');
    my ($min_atr, $max_atr) = $self->{atr_panel}->get_y_range($atr_values, $start_idx, $end_idx);
    
    $self->{scales}->{atr}->{min_value} = $min_atr;
    $self->{scales}->{atr}->{max_value} = $max_atr;
    
    $self->{atr_panel}->render(
        $self->{canvases}->{atr}, 
        $atr_values, 
        $self->{scales}->{atr}, 
        $start_idx, 
        $end_idx
    );
}

1;