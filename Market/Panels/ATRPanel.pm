package Market::Panels::ATRPanel;
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

sub get_y_range {
    my ($self, $indicator_values, $start_idx, $end_idx) = @_;
    
    # Encontrar el valor mínimo y máximo del ATR en la ventana visible
    my $min = $indicator_values->[$start_idx] || 0;
    my $max = $min;
    
    for my $i ($start_idx .. $end_idx) {
        my $val = $indicator_values->[$i];
        next unless defined $val;
        $min = $val if $val < $min;
        $max = $val if $val > $max;
    }
    
    # Añadimos un pequeño margen (padding) visual del 10%
    my $padding = ($max - $min) * 0.1;
    return ($min - $padding, $max + $padding);
}

sub render {
    my ($self, $canvas, $indicator_values, $scale, $start_idx, $end_idx) = @_;
    
    # Limpiamos solo la línea del indicador anterior
    $canvas->delete('atr_line'); 
    
    my @coords;
    for my $i ($start_idx .. $end_idx) {
        my $val = $indicator_values->[$i];
        next unless defined $val; # Ignorar si no hay valor (ej. primeras 14 velas)
        
        # Transformación lineal a pixeles usando tu clase Scales
        my $x = $scale->index_to_center_x($i);
        my $y = $scale->value_to_y($val);
        
        push @coords, $x, $y;
    }
    
    # Dibuja la línea solo si hay suficientes puntos
    if (@coords >= 4) { 
        $canvas->createLine(
            @coords,
            -fill  => '#2962FF', # Azul característico de TradingView
            -width => 1.5,
            -tags  => 'atr_line'
        );
    }
}

sub draw_crosshair {
    my ($self, $canvas, $x, $y, $is_active_panel, $scale) = @_;
    
    # Limpiamos el crosshair del frame anterior
    $canvas->delete('crosshair');
    
    # Si las coordenadas son negativas (mouse fuera de pantalla), abortamos
    return if $x < 0 || $y < 0;
    
    my $height = $scale->{canvas_height};
    my $width  = $canvas->width() || 1024;
    
    # 1. DIBUJAR LÍNEA VERTICAL (Tiempo)
    # Se dibuja siempre en ambos paneles para mantener la sincronización visual
    $canvas->createLine(
        $x, 0, $x, $height, 
        -dash => '-', 
        -fill => '#707a8a', 
        -tags => 'crosshair'
    );
    
    # 2. DIBUJAR LÍNEA HORIZONTAL Y VALOR EXACTO (Precios/Indicadores)
    # Solo se dibuja en el panel donde el usuario tiene el mouse
    if ($is_active_panel) {
        $canvas->createLine(
            0, $y, $width - 80, $y, 
            -dash => '-', 
            -fill => '#707a8a', 
            -tags => 'crosshair'
        );
        
        # Calcular el valor exacto usando la transformación inversa de Scales.pm
        my $exact_value = $scale->y_to_value($y);
        
        # Dibujar un pequeño recuadro oscuro sobre el eje Y con el valor exacto
        $canvas->createRectangle(
            $width - 80, $y - 12, $width, $y + 12, 
            -fill => '#2A2E39', 
            -tags => 'crosshair'
        );
        $canvas->createText(
            $width - 40, $y, 
            -text => sprintf("%.2f", $exact_value), 
            -fill => 'white', 
            -font => 'Arial 9 bold',
            -tags => 'crosshair'
        );
    }
}

1;