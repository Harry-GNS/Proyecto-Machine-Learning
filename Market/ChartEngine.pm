package Market::ChartEngine;

use strict;
use warnings;
use lib '/home/davidandresvm/Documentos/Proyecto_IB_G'; # <-- Añade esta línea

use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;

sub new {
    my ($class, %args) = @_;
    
    # Empezamos asumiendo 100 velas y un margen del 15%
    my $total_candles = $args{market_data}->size();
    my $visible_bars = 100;
    my $margin = $visible_bars * 0.15;
    
    my $self = {
        mw           => $args{mw},
        market_data  => $args{market_data},
        indicators   => $args{indicators},
        price_canvas => $args{price_canvas},
        atr_canvas   => $args{atr_canvas},
        
        # INICIO AL FINAL DE LA DATA + MARGEN
        offset       => $total_candles - $visible_bars + $margin, 
        visible_bars => $visible_bars,
        render_flag  => 0,
        
        drag_start_x      => 0,
        drag_start_offset => 0,

        auto_scale_y   => 1, 
        manual_min_y   => 0,
        manual_max_y   => 0,
        drag_start_y   => 0,
    };
    bless $self, $class;

    # Ajustar a los límites si por algún motivo hay muy poca data
    $self->_clamp_offset();

    $self->{price_panel} = Market::Panels::PricePanel->new(canvas => $self->{price_canvas});
    $self->{atr_panel}   = Market::Panels::ATRPanel->new(canvas => $self->{atr_canvas});

    $self->bind_events();
    return $self;
}

sub compute_window {
    my ($self) = @_;
    
    my $total_candles = $self->{market_data}->size();
    my $start = int($self->{offset});
    
    # Protecciones estrictas para no pedir índices inexistentes en el arreglo
    $start = 0 if $start < 0;
    $start = $total_candles - 1 if $start >= $total_candles;
    
    my $end = $start + $self->{visible_bars} + 1;
    $end = $total_candles - 1 if $end >= $total_candles;
    
    return ($start, $end);
}

sub request_render {
    my ($self) = @_;
    # Solicita un render diferido 
    # Optimización clave para rendimiento en Tk [cite: 500]
    return if $self->{render_flag};
    $self->{render_flag} = 1;

    # Encola la ejecución del renderizado cuando la aplicación esté inactiva (Idle)
    $self->{mw}->afterIdle(sub { $self->render() });
}

sub render {
    my ($self) = @_;
    $self->{render_flag} = 0;

    my ($start, $end) = $self->compute_window();
    my $data_slice = $self->{market_data}->get_slice($start, $end);
    my $atr_slice  = $self->{indicators}->slice_array('ATR', $start, $end);

    my $width  = $self->{price_canvas}->width;
    my $height = $self->{price_canvas}->height;
    
    my ($min_y, $max_y);
    if ($self->{auto_scale_y}) {
        ($min_y, $max_y) = $self->{price_panel}->get_y_range($data_slice);
    } else {
        $min_y = $self->{manual_min_y};
        $max_y = $self->{manual_max_y};
    }
    
    # LA MAGIA DE LOS MÁRGENES: La diferencia entre lo que pide el programa
    # y lo que realmente extrajo, genera el espacio en blanco automáticamente.
    my $scale_offset = $self->{offset} - $start;

    my $scale = Market::Panels::Scales->new(
        width        => $width,
        height       => $height,
        min_val      => $min_y,
        max_val      => $max_y,
        visible_bars => $self->{visible_bars},
        offset       => $scale_offset, 
    );

    $self->{price_panel}->set_scale($scale);
    $self->{price_panel}->render($data_slice);
    
    # Panel Secundario (ATR)
    my $atr_width  = $self->{atr_canvas}->width;
    my $atr_height = $self->{atr_canvas}->height;
    my ($atr_min, $atr_max) = $self->{atr_panel}->get_y_range($atr_slice);

    my $atr_scale = Market::Panels::Scales->new(
        width        => $atr_width,
        height       => $atr_height,
        min_val      => $atr_min,
        max_val      => $atr_max,
        visible_bars => $self->{visible_bars},
        offset       => $scale_offset, 
    );

    $self->{atr_panel}->set_scale($atr_scale);
    $self->{atr_panel}->render($atr_slice);
}

sub bind_events {
    my ($self) = @_;
    # Registra eventos de mouse/teclado [cite: 509, 510]
    
    # Movimiento del ratón para el crosshair
    $self->{price_canvas}->Tk::bind('<Motion>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->_on_mouse_move($ev->x, $ev->y, 'price');
    });

    $self->{atr_canvas}->Tk::bind('<Motion>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->_on_mouse_move($ev->x, $ev->y, 'atr');
    });

    # =========================================================
    # 1. Zoom Horizontal Normal (Anclado a la vela más reciente)
    # =========================================================
    $self->{price_canvas}->Tk::bind('<Button-4>', sub { 
        $self->_horizontal_zoom(1, 'right'); 
        Tk->break; 
    });
    
    $self->{price_canvas}->Tk::bind('<Button-5>', sub { 
        $self->_horizontal_zoom(-1, 'right'); 
        Tk->break; 
    });

    # =========================================================
    # 2. Zoom Horizontal Fijo al Puntero (Ctrl + Scroll)
    # =========================================================
    $self->{price_canvas}->Tk::bind('<Control-Button-4>', sub { 
        my ($c) = @_; 
        my $x = $c->XEvent->x; 
        $self->_horizontal_zoom(1, $x); 
        Tk->break; 
    });
    
    $self->{price_canvas}->Tk::bind('<Control-Button-5>', sub { 
        my ($c) = @_; 
        my $x = $c->XEvent->x; 
        $self->_horizontal_zoom(-1, $x); 
        Tk->break; 
    });

    # =========================================================
    # 3. Zoom Vertical de Precios (Shift + Scroll)
    # =========================================================
    $self->{price_canvas}->Tk::bind('<Shift-Button-4>', sub { 
        my ($c) = @_; 
        my $y = $c->XEvent->y; 
        $self->_vertical_zoom(1, $y); 
        Tk->break; 
    });
    
    $self->{price_canvas}->Tk::bind('<Shift-Button-5>', sub { 
        my ($c) = @_; 
        my $y = $c->XEvent->y; 
        $self->_vertical_zoom(-1, $y); 
        Tk->break; 
    });
    
    $self->{price_canvas}->Tk::bind('<Control-Button-5>', sub { 
        my ($c) = @_; 
        my $y = $c->XEvent->y; # Extraemos la coordenada Y del ratón
        $self->_vertical_zoom(-1, $y); 
        Tk->break; 
    });

    # Evento: Clic izquierdo (Establecer el ancla)
    $self->{price_canvas}->Tk::bind('<ButtonPress-1>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->_on_drag_start($ev->x);
    });

    # Evento: Arrastre con clic izquierdo sostenido (Mover el gráfico)
    $self->{price_canvas}->Tk::bind('<B1-Motion>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->_on_drag_motion($ev->x);
        
        # Opcional: Actualizar el crosshair mientras se arrastra
        $self->_on_mouse_move($ev->x, $ev->y, 'price');
    });

    # Evento: Clic derecho (Ancla para arrastre vertical)
    $self->{price_canvas}->Tk::bind('<ButtonPress-3>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->{drag_start_y} = $ev->y;
        
        # Si estábamos en automático, congelamos el rango actual como punto de partida
        if ($self->{auto_scale_y}) {
            my ($start, $end) = $self->compute_window();
            my $slice = $self->{market_data}->get_slice($start, $end);
            ($self->{manual_min_y}, $self->{manual_max_y}) = $self->{price_panel}->get_y_range($slice);
            
            $self->{auto_scale_y} = 0; # Desactivar modo automático
        }
    });

    # Evento: Arrastre sostenido con clic derecho
    $self->{price_canvas}->Tk::bind('<B3-Motion>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->_vertical_drag($ev->y);
    });

    # Evento: Doble clic izquierdo (Restablecer vista automática)
    $self->{price_canvas}->Tk::bind('<Double-Button-1>', sub {
        $self->reset_view();
    });

    # NUEVO: Navegación por teclado (Flechas)
    # =========================================================
    # El bind se hace al MainWindow para capturarlo sin necesidad de dar clic previo
    $self->{mw}->Tk::bind('<Left>',  sub { $self->_pan_horizontal(1); });  # Ver pasado
    $self->{mw}->Tk::bind('<Right>', sub { $self->_pan_horizontal(-1); }); # Ver futuro
    $self->{mw}->Tk::bind('<Up>',    sub { $self->_pan_vertical(-1); });   # Desplazar gráfico arriba
    $self->{mw}->Tk::bind('<Down>',  sub { $self->_pan_vertical(1); });    # Desplazar gráfico abajo


}

sub _on_mouse_move {
    my ($self, $x, $y, $panel_type) = @_;
    
    if ($panel_type eq 'price') {
        # Si estamos en precios, actualizamos completo
        $self->{price_panel}->draw_crosshair($x, $y);
        
        # En el ATR, pasamos "undef" en Y para ocultar la línea horizontal,
        # pero esto puede causar que la vertical desaparezca. Por ahora 
        # mantenemos las cajas de cruz de forma independiente al tocar su canvas:
        $self->{atr_panel}->draw_crosshair(undef, undef); 
    } else {
        # Si estamos en el ATR
        $self->{atr_panel}->draw_crosshair($x, $y);
        $self->{price_panel}->draw_crosshair(undef, undef);
    }
}


sub _on_drag_start {
    my ($self, $x) = @_;
    # Guardamos la posición exacta en píxeles donde el usuario hizo clic
    $self->{drag_start_x} = $x;
    # Guardamos en qué vela (índice) estaba posicionado el gráfico
    $self->{drag_start_offset} = $self->{offset};
}

sub _on_drag_motion {
    my ($self, $x) = @_;
    
    my $dx = $self->{drag_start_x} - $x;
    
    my $canvas_width = $self->{price_canvas}->width;
    my $candle_width = $canvas_width / $self->{visible_bars};
    
    return if $candle_width == 0; 
    
    # Mantenemos el desplazamiento como un valor decimal continuo (flotante)
    my $fractional_shift = $dx / $candle_width;
    my $new_offset = $self->{drag_start_offset} + $fractional_shift;
    
    if ($new_offset != $self->{offset}) {
        $self->{offset} = $new_offset;
        $self->_clamp_offset(); # <-- Usa la nueva función
        $self->request_render();
    }
}

sub _vertical_drag {
    my ($self, $y) = @_;
    
    # ¿Cuántos píxeles se movió el ratón en el eje Y?
    my $dy = $y - $self->{drag_start_y};
    
    my $canvas_height = $self->{price_canvas}->height;
    return if $canvas_height == 0;
    
    # Calcular cuánto "precio" vale 1 píxel actualmente
    my $price_range = $self->{manual_max_y} - $self->{manual_min_y};
    my $price_per_pixel = $price_range / $canvas_height;
    
    # Como el eje Y está invertido (Y=0 arriba), al mover el ratón hacia abajo (dy positivo),
    # desplazamos el rango de precios hacia arriba para que el gráfico baje.
    my $price_shift = $dy * $price_per_pixel;
    
    $self->{manual_min_y} += $price_shift;
    $self->{manual_max_y} += $price_shift;
    
    # Actualizar ancla y repintar
    $self->{drag_start_y} = $y;
    $self->request_render();
}

sub reset_view {
    my ($self) = @_;
    $self->{auto_scale_y} = 1;
    $self->{visible_bars} = 100;
    
    my $total_candles = $self->{market_data}->size();
    my $margin = $self->{visible_bars} * 0.15;
    
    # Volver al presente y dejar margen derecho
    $self->{offset} = $total_candles - $self->{visible_bars} + $margin;
    $self->_clamp_offset();
    
    $self->request_render();
}

sub set_timeframe {
    my ($self, $tf) = @_;

    $self->{market_data}->set_timeframe($tf);
    $self->{indicators}->reset_all();
    $self->{indicators}->recalculate_all($self->{market_data});

    # reset_view() ahora calcula y se posiciona solo al final de la data
    $self->reset_view();
}

sub _horizontal_zoom {
    my ($self, $delta, $x_or_right) = @_;
    
    # BLOQUEO DE VIEWPORT
    $self->{price_canvas}->yviewMoveto(0);
    $self->{price_canvas}->xviewMoveto(0);
    $self->{atr_canvas}->yviewMoveto(0);
    $self->{atr_canvas}->xviewMoveto(0);
    
    $self->{price_panel}->draw_crosshair(undef, undef);
    $self->{atr_panel}->draw_crosshair(undef, undef);

    my $width = $self->{price_canvas}->width;
    return if $width == 0;

    # EVALUAR EL RATIO: Si es 'right', forzamos el 1.0 (Borde derecho)
    # Si es un número, calculamos la proporción de la pantalla
    my $ratio;
    if ($x_or_right eq 'right') {
        $ratio = 1.0;
    } else {
        $ratio = $x_or_right / $width;
        $ratio = 0 if $ratio < 0;
        $ratio = 1 if $ratio > 1;
    }

    my $old_visible = $self->{visible_bars};
    my $step = 10; 

    # Aplicar el zoom a la cantidad de velas
    if ($delta > 0) {
        $self->{visible_bars} -= $step; # Acercar
    } else {
        $self->{visible_bars} += $step; # Alejar
    }

    $self->{visible_bars} = 10 if $self->{visible_bars} < 10;
    my $max_bars = $self->{market_data}->size();
    $self->{visible_bars} = $max_bars if $self->{visible_bars} > $max_bars && $max_bars > 0;

    # Compensar el offset según el ratio calculado
    my $bar_diff = $old_visible - $self->{visible_bars};
    $self->{offset} += ($bar_diff * $ratio);

    $self->_clamp_offset(); # <-- Usa la nueva función
    $self->request_render();
}

sub _vertical_zoom {
    my ($self, $delta, $y) = @_;
    
    # 1. BLOQUEO DE VIEWPORT
    $self->{price_canvas}->yviewMoveto(0);
    $self->{price_canvas}->xviewMoveto(0);
    $self->{atr_canvas}->yviewMoveto(0);
    $self->{atr_canvas}->xviewMoveto(0);
    
    $self->{price_panel}->draw_crosshair(undef, undef);
    $self->{atr_panel}->draw_crosshair(undef, undef);
    
    if ($self->{auto_scale_y}) {
        my ($start, $end) = $self->compute_window();
        my $slice = $self->{market_data}->get_slice($start, $end);
        ($self->{manual_min_y}, $self->{manual_max_y}) = $self->{price_panel}->get_y_range($slice);
        $self->{auto_scale_y} = 0; 
    }

    my $current_range = $self->{manual_max_y} - $self->{manual_min_y};
    return if $current_range <= 0.0001; 

    # --- NUEVA MATEMÁTICA DE ZOOM ANCLADO ---
    
    my $height = $self->{price_canvas}->height;
    return if $height == 0;

    # Calculamos la proporción del ratón en la pantalla (0.0 es el techo, 1.0 es el piso)
    my $ratio = $y / $height;
    
    # Protegemos los límites por si el cursor está justo en el borde exterior
    $ratio = 0 if $ratio < 0;
    $ratio = 1 if $ratio > 1;

    my $zoom_factor = 0.05;
    my $zoom_amount = $current_range * $zoom_factor;

    if ($delta > 0) {
        # Acercar (Estirar) -> Reducimos el rango total
        # Al techo (max_y) le quitamos la parte proporcional de arriba
        $self->{manual_max_y} -= $zoom_amount * $ratio;
        # Al piso (min_y) le sumamos el resto proporcional de abajo
        $self->{manual_min_y} += $zoom_amount * (1 - $ratio);
    } else {
        # Alejar (Aplastar) -> Aumentamos el rango total
        $self->{manual_max_y} += $zoom_amount * $ratio;
        $self->{manual_min_y} -= $zoom_amount * (1 - $ratio);
    }

    $self->request_render();
}
# ==============================================================================
# NUEVAS FUNCIONES: Auto/Manual y Paneo por Teclado
# ==============================================================================

sub toggle_auto_scale {
    my ($self) = @_;
    
    if ($self->{auto_scale_y}) {
        # Si estaba en automático, pasamos a manual congelando el rango visual actual
        my ($start, $end) = $self->compute_window();
        my $slice = $self->{market_data}->get_slice($start, $end);
        ($self->{manual_min_y}, $self->{manual_max_y}) = $self->{price_panel}->get_y_range($slice);
        
        $self->{auto_scale_y} = 0; # Cambiar a Manual
    } else {
        # Si estaba en manual, volvemos a automático
        $self->{auto_scale_y} = 1;
    }
    
    $self->request_render();
    return $self->{auto_scale_y};
}

sub _pan_horizontal {
    my ($self, $direction) = @_;
    
    # Nos movemos un 10% de la cantidad de velas que se ven en pantalla
    my $step = $self->{visible_bars} * 0.1;
    $step = 1 if $step < 1; # Mínimo moverse 1 vela
    
    my $new_offset = $self->{offset} + ($direction * $step);
    
    if ($new_offset != $self->{offset}) {
        $self->{offset} = $new_offset;
        $self->_clamp_offset(); # <-- Usa la nueva función
        $self->request_render();
    }
}

sub _pan_vertical {
    my ($self, $direction) = @_;
    
    # El paneo vertical (arriba/abajo) solo tiene sentido si estamos en MODO MANUAL
    return if $self->{auto_scale_y};
    
    my $rango = $self->{manual_max_y} - $self->{manual_min_y};
    
    # Desplazamos la vista un 10% del rango de precios actual
    my $shift = $rango * 0.1 * $direction;
    
    $self->{manual_min_y} += $shift;
    $self->{manual_max_y} += $shift;
    
    $self->request_render();
}

sub _clamp_offset {
    my ($self) = @_;
    my $total_candles = $self->{market_data}->size();
    
    # Calculamos un margen equivalente al 15% de las velas en pantalla
    my $margin = $self->{visible_bars} * 0.15; 
    
    # El mínimo ya no es 0, ahora es negativo para dejar espacio a la izquierda
    my $min_offset = -$margin;
    
    # El máximo se excede intencionalmente para dejar espacio a la derecha
    my $max_offset = $total_candles - $self->{visible_bars} + $margin;
    
    # Protección: Si la pantalla tiene más zoom que datos existentes, no cruzamos los límites
    my $lower_bound = $min_offset < $max_offset ? $min_offset : $max_offset;
    my $upper_bound = $min_offset > $max_offset ? $min_offset : $max_offset;
    
    $self->{offset} = $lower_bound if $self->{offset} < $lower_bound;
    $self->{offset} = $upper_bound if $self->{offset} > $upper_bound;
}


1;