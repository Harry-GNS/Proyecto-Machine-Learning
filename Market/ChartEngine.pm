package Market::ChartEngine;
use strict;
use warnings;

use FindBin;           
use lib $FindBin::Bin; 

# Importamos las dependencias internas de la capa de renderizado
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;
use Market::Panels::Scales;



sub new {
    my ($class, %args) = @_;
    
    # Inicializamos el estado base del motor (Exigido en la sección 4 de la guía)
    my $self = {
        market_data       => $args{market_data},
        indicator_manager => $args{indicator_manager},
        canvases          => $args{canvases},
        
        # Variables de control de la ventana de visualización (Estado interno)
        visible_bars      => 100,  # Cantidad de velas visibles simultáneamente
        offset            => 0,    # Desplazamiento horizontal para el scroll
        crosshair_x       => -1,   # Posición X del cursor sincronizado
        crosshair_y       => -1,   # Posición Y del cursor sincronizado
        render_pending    => 0,    # Bandera para optimización O(1) de renderizado

        # --- AÑADIDO: Estado interno para el arrastre del mouse ---
        drag_start_x      => 0,
        drag_accum_x      => 0,

    };
    
    bless $self, $class;
    
    # 1. Instanciar los paneles de forma desacoplada
    $self->{price_panel} = Market::Panels::PricePanel->new();
    $self->{atr_panel}   = Market::Panels::ATRPanel->new();
    
    # 2. Inicializar las escalas independientes por cada panel (Ejes verticales)
    $self->{scales} = {
        price => Market::Panels::Scales->new(),
        atr   => Market::Panels::Scales->new(),
    };
    #Activamos el enlace de eventos para ambos canvas
    $self->bind_events();
    
    return $self;
}

# --- MÉTODOS DEL MOTOR EXIGIDOS POR LA PLANTILLA DOCENTE ---

sub compute_window {
    my ($self) = @_;
    my $total_candles = $self->{market_data}->size();
    
    # Calcula qué porción de datos se encuentra dentro de la ventana visible
    my $end_idx = $total_candles - 1 - $self->{offset};
    $end_idx = $total_candles - 1 if $end_idx >= $total_candles;
    
    my $start_idx = $end_idx - $self->{visible_bars} + 1;
    $start_idx = 0 if $start_idx < 0;
    
    return ($start_idx, $end_idx);
}

sub round {
    my ($self, $value) = @_;
    return int($value + 0.5);
}

sub request_render {
    my ($self) = @_;
    # En entornos de interfaces complejas, evita llamadas redundantes.
    # Llama directamente al método principal por ahora:
    $self->render();
}

sub render {
    my ($self) = @_;
    
    my $data = $self->{market_data};
    return if $data->size() == 0;
    
    # Determinar los límites indexados de la ventana
    my ($start_idx, $end_idx) = $self->compute_window();
    
    # --- Actualizar y Renderizar Panel de Precios ---
    my ($min_p, $max_p) = $self->{price_panel}->get_y_range($data, $start_idx, $end_idx);
    
    $self->{scales}->{price}->{start_index}   = $start_idx; # ¡CRUCIAL!
    $self->{scales}->{price}->{min_value}     = $min_p;
    $self->{scales}->{price}->{max_value}     = $max_p;
    $self->{scales}->{price}->{canvas_height} = $self->{canvases}->{price}->height() || 400;
    
    # Renderizar velas y su respectivo eje Y
    $self->{price_panel}->render($self->{canvases}->{price}, $data, $self->{scales}->{price}, $start_idx, $end_idx);
    $self->{scales}->{price}->_draw_y_scale($self->{canvases}->{price});
    
    # --- Actualizar y Renderizar Panel ATR ---
    if (defined $self->{indicator_manager}) {
        my $atr_values = $self->{indicator_manager}->get('ATR');
        my ($min_a, $max_a) = $self->{atr_panel}->get_y_range($atr_values, $start_idx, $end_idx);
        
        $self->{scales}->{atr}->{start_index}   = $start_idx; # ¡CRUCIAL!
        $self->{scales}->{atr}->{min_value}     = $min_a;
        $self->{scales}->{atr}->{max_value} = $max_a;
        $self->{scales}->{atr}->{canvas_height} = $self->{canvases}->{atr}->height() || 150;
        
        # Renderizar línea ATR y su respectivo eje Y independiente
        $self->{atr_panel}->render($self->{canvases}->{atr}, $atr_values, $self->{scales}->{atr}, $start_idx, $end_idx);
        $self->{scales}->{atr}->_draw_y_scale($self->{canvases}->{atr});
    }
}

sub bind_events {
    my ($self) = @_;
    
    # Aplicamos la misma interacción a todos los paneles (Precios y ATR)
    foreach my $panel_name (keys %{$self->{canvases}}) {
        my $canvas = $self->{canvases}->{$panel_name};
        
        # Evento 1: Usuario presiona el botón izquierdo del mouse (<ButtonPress-1>)
        $canvas->Tk::bind('<ButtonPress-1>', sub {
            my $e = $canvas->XEvent;
            $self->{drag_start_x} = $e->x; # Guardamos el píxel de origen
            $self->{drag_accum_x} = 0;     # Reiniciamos la inercia
        });
        
        # Evento 2: Usuario mueve el mouse mientras mantiene el clic presionado (<B1-Motion>)
        $canvas->Tk::bind('<B1-Motion>', sub {
            my $e = $canvas->XEvent;
            my $current_x = $e->x;
            
            # Calculamos cuántos píxeles se movió el mouse
            my $delta_x = $current_x - $self->{drag_start_x};
            
            # Sabemos por Scales.pm que cada vela ocupa 10 píxeles de ancho
            my $bar_width = 10; 
            
            $self->{drag_accum_x} += $delta_x;
            
            # Si el arrastre es mayor al grosor de una vela, desplazamos el gráfico
            if (abs($self->{drag_accum_x}) >= $bar_width) {
                # Calculamos cuántas velas enteras debemos desplazar
                my $bars_to_move = int($self->{drag_accum_x} / $bar_width);
                
                # Lógica de TradingView: 
                # Arrastrar a la derecha (delta > 0) revela datos del pasado (offset aumenta)
                $self->{offset} += $bars_to_move;
                
                # Validamos no salirnos de los límites del dataset (Evitar un "Index Out of Bounds")
                my $max_offset = $self->{market_data}->size() - $self->{visible_bars};
                $self->{offset} = $max_offset if $self->{offset} > $max_offset;
                $self->{offset} = 0 if $self->{offset} < 0;
                
                # Descontamos el movimiento procesado del acumulador
                $self->{drag_accum_x} -= ($bars_to_move * $bar_width);
                
                # Repintamos la pantalla con el nuevo offset temporal
                $self->request_render();
            }
            
            # Actualizamos el origen para el siguiente frame continuo
            $self->{drag_start_x} = $current_x;
        });
    }
}

# --- Esqueletos para Interacción y Eventos (Siguiente fase) ---

sub _bind_all_canvas       { my ($self) = @_; }
sub _horizontal_zoom       { my ($self, $delta) = @_; }
sub _vertical_drag         { my ($self, $dy) = @_; }
sub _vertical_zoom         { my ($self, $factor) = @_; }
sub _on_mouse_move         { my ($self, $event) = @_; }
sub _draw_crosshair_all    { my ($self) = @_; }
sub set_timeframe          { my ($self, $tf) = @_; }
sub reset_view             { my ($self) = @_; }
sub compute_intraday_labels { my ($self) = @_; }
sub get_all_timestamps     { my ($self) = @_; }

1;