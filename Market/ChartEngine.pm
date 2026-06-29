package Market::ChartEngine;

use strict;
use warnings;
use lib '/home/davidandresvm/Documentos/ProyectoMLv2'; # <-- Añade esta línea

use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;

use Market::Overlays::Liquidity;
use Market::Overlays::SMC_Structures;
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

        # Escala vertical independiente para el panel ATR
        auto_scale_atr  => 1,
        manual_min_atr  => 0,
        manual_max_atr  => 0,
        drag_start_atr  => 0,
    };
    bless $self, $class;

    # Ajustar a los límites si por algún motivo hay muy poca data
    $self->_clamp_offset();

    $self->{price_panel} = Market::Panels::PricePanel->new(canvas => $self->{price_canvas});
    $self->{atr_panel}   = Market::Panels::ATRPanel->new(canvas => $self->{atr_canvas});

    # NUEVO: Inicializar el Overlay de Liquidez
    $self->{liquidity_overlay} = Market::Overlays::Liquidity->new(canvas => $self->{price_canvas});
    $self->{smc_overlay} = Market::Overlays::SMC_Structures->new(canvas => $self->{price_canvas});
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
    # =========================================================
    # NUEVO: Renderizar Overlay de Liquidez
    # =========================================================
    my $liq_slice = $self->{indicators}->slice_array('Liquidity', $start, $end);
    $self->{liquidity_overlay}->render($scale, $liq_slice);
    # ========================================================
    # NUEVO: Renderizar Overlay de Estructuras SMC
    # ========================================================
    my $smc_slice = $self->{indicators}->slice_array('SMC_Structures', $start, $end);
    $self->{smc_overlay}->render($scale, $smc_slice);
    
    # Panel Secundario (ATR)
    my $atr_width  = $self->{atr_canvas}->width;
    my $atr_height = $self->{atr_canvas}->height;

    my ($atr_min, $atr_max);
    if ($self->{auto_scale_atr}) {
        ($atr_min, $atr_max) = $self->{atr_panel}->get_y_range($atr_slice);
    } else {
        $atr_min = $self->{manual_min_atr};
        $atr_max = $self->{manual_max_atr};
    }

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

    # evitar que la línea se quede "congelada" cuando el ratón sale del canvas
    $self->{price_canvas}->Tk::bind('<Leave>', sub {
        $self->_on_mouse_move(undef, undef, 'price');
    });

    $self->{atr_canvas}->Tk::bind('<Leave>', sub {
        $self->_on_mouse_move(undef, undef, 'atr');
    });

    # =========================================================
    # 1. Zoom Horizontal Normal (Sin teclas, anclado a la derecha)
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
        $self->_horizontal_zoom(1, $c->XEvent->x); 
        Tk->break; 
    });
    
    $self->{price_canvas}->Tk::bind('<Control-Button-5>', sub { 
        my ($c) = @_; 
        $self->_horizontal_zoom(-1, $c->XEvent->x); 
        Tk->break; 
    });

    # =========================================================
    # 3. Zoom Vertical de Precios (Shift + Scroll)
    # =========================================================
    $self->{price_canvas}->Tk::bind('<Shift-Button-4>', sub { 
        my ($c) = @_; 
        $self->_vertical_zoom(1, $c->XEvent->y); 
        Tk->break; 
    });
    
    $self->{price_canvas}->Tk::bind('<Shift-Button-5>', sub { 
        my ($c) = @_; 
        $self->_vertical_zoom(-1, $c->XEvent->y); 
        Tk->break; 
    });

    # =========================================================
    # EVENTOS DE ARRASTRE PRINCIPAL (PRECIOS)
    # =========================================================
    $self->{price_canvas}->Tk::bind('<ButtonPress-1>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        # Enviamos la posición X, Y, y el ancho total de la pantalla
        $self->_on_drag_start($ev->x, $ev->y, $c->width);
    });

    $self->{price_canvas}->Tk::bind('<B1-Motion>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->_on_drag_motion($ev->x, $ev->y);
        $self->_on_mouse_move($ev->x, $ev->y, 'price');
    });

    

    # Evento: Clic derecho (Ancla para arrastre vertical)
    $self->{price_canvas}->Tk::bind('<ButtonPress-3>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->{drag_start_y} = $ev->y;
        
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

    # =========================================================
    # ARRASTRE HORIZONTAL EN EL PANEL ATR
    # =========================================================
    
    # =========================================================
    # EVENTOS DE ARRASTRE SECUNDARIO (ATR)
    # =========================================================
    $self->{atr_canvas}->Tk::bind('<ButtonPress-1>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        # Si el clic es sobre la escala derecha → modo zoom vertical ATR
        my $escala_sensible = 70;
        if ($ev->x > ($c->width - $escala_sensible)) {
            $self->{drag_mode}    = 'atr_vertical';
            $self->{drag_start_atr} = $ev->y;
            if ($self->{auto_scale_atr}) {
                my ($start, $end) = $self->compute_window();
                my $atr_slice = $self->{indicators}->slice_array('ATR', $start, $end);
                ($self->{manual_min_atr}, $self->{manual_max_atr}) = $self->{atr_panel}->get_y_range($atr_slice);
                $self->{auto_scale_atr} = 0;
            }
        } else {
            $self->_on_drag_start($ev->x, undef, undef);
        }
    });

    $self->{atr_canvas}->Tk::bind('<B1-Motion>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        if (defined $self->{drag_mode} && $self->{drag_mode} eq 'atr_vertical') {
            $self->_vertical_drag_atr($ev->y);
        } else {
            $self->_on_drag_motion($ev->x, undef);
        }
        $self->_on_mouse_move($ev->x, $ev->y, 'atr');
    });

    # Clic derecho en ATR: ancla para zoom vertical con arrastre
    $self->{atr_canvas}->Tk::bind('<ButtonPress-3>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->{drag_start_atr} = $ev->y;

    });

    $self->{atr_canvas}->Tk::bind('<B3-Motion>', sub {
        my ($c) = @_;
        my $ev = $c->XEvent;
        $self->_vertical_drag_atr($ev->y);
    });

    # Doble clic en ATR: restaurar escala automática
    $self->{atr_canvas}->Tk::bind('<Double-Button-1>', sub {
        $self->{auto_scale_atr} = 1;
        $self->request_render();
    });

    # Zoom horizontal en ATR (scroll normal y Ctrl+scroll)
    $self->{atr_canvas}->Tk::bind('<Button-4>', sub {
        $self->_horizontal_zoom(1, 'right');
        Tk->break;
    });

    $self->{atr_canvas}->Tk::bind('<Button-5>', sub {
        $self->_horizontal_zoom(-1, 'right');
        Tk->break;
    });

    $self->{atr_canvas}->Tk::bind('<Control-Button-4>', sub {
        my ($c) = @_;
        $self->_horizontal_zoom(1, $c->XEvent->x);
        Tk->break;
    });

    $self->{atr_canvas}->Tk::bind('<Control-Button-5>', sub {
        my ($c) = @_;
        $self->_horizontal_zoom(-1, $c->XEvent->x);
        Tk->break;
    });

    # Zoom vertical en ATR (Shift+scroll)
    $self->{atr_canvas}->Tk::bind('<Shift-Button-4>', sub {
        my ($c) = @_;
        $self->_vertical_zoom_atr(1, $c->XEvent->y);
        Tk->break;
    });

    $self->{atr_canvas}->Tk::bind('<Shift-Button-5>', sub {
        my ($c) = @_;
        $self->_vertical_zoom_atr(-1, $c->XEvent->y);
        Tk->break;
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
        # El ratón está en los Precios: Cruz completa aquí, solo vertical en el ATR
        $self->{price_panel}->draw_crosshair($x, $y);
        $self->{atr_panel}->draw_crosshair($x, undef); 
    } else {
        # El ratón está en el ATR: Cruz completa aquí, solo vertical en los Precios
        $self->{atr_panel}->draw_crosshair($x, $y);
        $self->{price_panel}->draw_crosshair($x, undef);
    }
}


sub _on_drag_start {
    my ($self, $x, $y, $width) = @_;
    
    # =========================================================
    # NUEVO: INTERCEPTOR DE SELECCIÓN DE VELA (MODO REPLAY)
    # =========================================================
    if ($self->{awaiting_replay_selection}) {
        # Calcular el ancho de cada vela en píxeles
        my $candle_width = $width / $self->{visible_bars};
        
        # Calcular el índice exacto sumando el offset izquierdo más las velas desplazadas
        my $clicked_idx = int($self->{offset}) + int($x / $candle_width);
        
        # Proteger los límites (evitar clics fuera de rango)
        my $max_idx = $self->{market_data}->size() - 1;
        $clicked_idx = 0 if $clicked_idx < 0;
        $clicked_idx = $max_idx if $clicked_idx > $max_idx;
        
        # Iniciar el replay exactamente en esa vela
        $self->start_replay($clicked_idx);
        return; # Abortar el resto de la función para que no inicie un arrastre
    }

    # =========================================================
    # Resto del código original de _on_drag_start...
    # =========================================================
    my $escala_sensible = 70;
    
    if (defined $width && defined $y && $x > ($width - $escala_sensible)) {
        $self->{drag_mode} = 'vertical';
        $self->{drag_start_y} = $y;
        
        if ($self->{auto_scale_y}) {
            my ($start, $end) = $self->compute_window();
            my $slice = $self->{market_data}->get_slice($start, $end);
            ($self->{manual_min_y}, $self->{manual_max_y}) = $self->{price_panel}->get_y_range($slice);
            $self->{auto_scale_y} = 0; 
        }
    } else {
        $self->{drag_mode} = 'horizontal';
        $self->{drag_start_x} = $x;
        $self->{drag_start_offset} = $self->{offset};
    }
}

sub _on_drag_motion {
    my ($self, $x, $y) = @_;
    
    if ($self->{drag_mode} eq 'vertical') {
        # =============================================
        # LÓGICA DE ESTIRAMIENTO VERTICAL (ZOOM Y)
        # =============================================
        return unless defined $y;
        
        # Distancia en píxeles que moviste el ratón desde el ancla
        my $dy = $y - $self->{drag_start_y};
        my $height = $self->{price_canvas}->height;
        return if $height == 0;
        
        my $current_range = $self->{manual_max_y} - $self->{manual_min_y};
        return if $current_range <= 0;
        
        # Factor de deformación proporcional al rango visible
        my $zoom_factor = ($dy / $height) * $current_range;
        
        # Arrastrar arriba estira los precios (zoom in), abajo los comprime (zoom out)
        $self->{manual_max_y} += $zoom_factor;
        $self->{manual_min_y} -= $zoom_factor;
        
        # Protección de seguridad para evitar que el gráfico se invierta si arrastraste mucho
        if ($self->{manual_max_y} <= $self->{manual_min_y}) {
            $self->{manual_max_y} -= $zoom_factor;
            $self->{manual_min_y} += $zoom_factor;
        }
        
        # Reiniciar el punto de inicio para que el movimiento arrastrado sea fluido fotograma a fotograma
        $self->{drag_start_y} = $y;
        $self->request_render();
        
    } else {
        # =============================================
        # LÓGICA DE PANEO HORIZONTAL (TIEMPO NORMAL)
        # =============================================
        my $dx = $self->{drag_start_x} - $x;
        my $width = $self->{price_canvas}->width;
        return if $width == 0;
        
        my $candle_width = $width / $self->{visible_bars};
        my $fractional_shift = $dx / $candle_width;
        my $new_offset = $self->{drag_start_offset} + $fractional_shift;
        
        if ($new_offset != $self->{offset}) {
            $self->{offset} = $new_offset;
            $self->_clamp_offset(); 
            $self->request_render();
        }
    }
}

sub _vertical_drag {
    my ($self, $y) = @_;
    
    # NUEVO: Abortar inmediatamente si estamos en modo automático
    return if $self->{auto_scale_y};
    
    # ¿Cuántos píxeles se movió el ratón en el eje Y?
    my $dy = $y - $self->{drag_start_y};
    
    my $canvas_height = $self->{price_canvas}->height;
    return if $canvas_height == 0;
    
    # Calcular cuánto "precio" vale 1 píxel actualmente
    my $price_range = $self->{manual_max_y} - $self->{manual_min_y};
    my $price_per_pixel = $price_range / $canvas_height;
    
    my $price_shift = $dy * $price_per_pixel;
    
    $self->{manual_min_y} += $price_shift;
    $self->{manual_max_y} += $price_shift;
    
    $self->{drag_start_y} = $y;
    $self->request_render();
}

sub reset_view {
    my ($self) = @_;
    $self->{auto_scale_y}   = 1;
    $self->{auto_scale_atr} = 1;
    $self->{visible_bars}   = 100;

    my $total_candles = $self->{market_data}->size();
    my $margin = $self->{visible_bars} * 0.15;

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

sub _vertical_zoom_atr {
    my ($self, $delta, $y) = @_;

    $self->{atr_canvas}->yviewMoveto(0);
    $self->{atr_canvas}->xviewMoveto(0);
    $self->{atr_panel}->draw_crosshair(undef, undef);

    if ($self->{auto_scale_atr}) {
        my ($start, $end) = $self->compute_window();
        my $atr_slice = $self->{indicators}->slice_array('ATR', $start, $end);
        ($self->{manual_min_atr}, $self->{manual_max_atr}) = $self->{atr_panel}->get_y_range($atr_slice);
        $self->{auto_scale_atr} = 0;
    }

    my $current_range = $self->{manual_max_atr} - $self->{manual_min_atr};
    return if $current_range <= 0.0001;

    my $height = $self->{atr_canvas}->height;
    return if $height == 0;

    my $ratio = $y / $height;
    $ratio = 0 if $ratio < 0;
    $ratio = 1 if $ratio > 1;

    my $zoom_amount = $current_range * 0.05;

    if ($delta > 0) {
        $self->{manual_max_atr} -= $zoom_amount * $ratio;
        $self->{manual_min_atr} += $zoom_amount * (1 - $ratio);
    } else {
        $self->{manual_max_atr} += $zoom_amount * $ratio;
        $self->{manual_min_atr} -= $zoom_amount * (1 - $ratio);
    }

    $self->request_render();
}

sub _vertical_drag_atr {
    my ($self, $y) = @_;

    my $dy = $y - $self->{drag_start_atr};
    my $canvas_height = $self->{atr_canvas}->height;
    return if $canvas_height == 0;

    my $price_range = $self->{manual_max_atr} - $self->{manual_min_atr};
    return if $price_range <= 0;

    my $value_per_pixel = $price_range / $canvas_height;
    my $shift = $dy * $value_per_pixel;

    $self->{manual_min_atr} += $shift;
    $self->{manual_max_atr} += $shift;

    $self->{drag_start_atr} = $y;
    $self->request_render();
}

sub _clamp_offset {
    my ($self) = @_;
    my $total_candles = $self->{market_data}->size();
    
    # Límite Izquierdo: Mantenemos el margen del 15% para cuando llegas al inicio del pasado
    my $margin_left = $self->{visible_bars} * 0.15; 
    my $min_offset = -$margin_left;
    
    # NUEVO LÍMITE DERECHO: 
    # Permitimos que la gráfica se desplace hasta que la vela número 0 de la pantalla
    # sea la penúltima vela de la data. Esto deja solo 2 velas pegadas a la izquierda.
    my $max_offset = $total_candles - 2;
    
    # Protección de seguridad por si el archivo carga con menos de 2 velas
    $max_offset = 0 if $max_offset < 0;
    
    # Evaluar qué valor es el techo y cuál es el piso
    my $lower_bound = $min_offset < $max_offset ? $min_offset : $max_offset;
    my $upper_bound = $min_offset > $max_offset ? $min_offset : $max_offset;
    
    # Aplicar el bloqueo (Clamp) al desplazamiento actual
    $self->{offset} = $lower_bound if $self->{offset} < $lower_bound;
    $self->{offset} = $upper_bound if $self->{offset} > $upper_bound;
}

# ==============================================================================
# SISTEMA REPLAY: Motor de Eventos y Callbacks
# ==============================================================================

sub enable_replay_selection {
    my ($self) = @_;
    # Activar la bandera de espera
    $self->{awaiting_replay_selection} = 1;
    # Feedback visual: Cambiamos el cursor del ratón a una cruz
    $self->{price_canvas}->configure(-cursor => 'crosshair');
    print "Modo Replay Seleccion: Haz clic sobre la vela donde deseas iniciar el corte.\n";
}

sub start_replay {
    my ($self, $index) = @_;
    
    # Limpiar el estado de espera y devolver el cursor a la normalidad
    $self->{awaiting_replay_selection} = 0;
    $self->{price_canvas}->configure(-cursor => 'arrow');

    # Enviar el índice exacto clickeado al backend de datos
    $self->{market_data}->start_replay($index);
    
    # Recalcular indicadores hasta el corte
    $self->{indicators}->reset_all();
    $self->{indicators}->recalculate_all($self->{market_data});
    
    $self->reset_view();
}

sub stop_replay {
    my ($self) = @_;
    $self->pause_replay();
    $self->{market_data}->stop_replay();
    
    # Al salir, recalculamos todos los indicadores con la data entera
    $self->{indicators}->reset_all();
    $self->{indicators}->recalculate_all($self->{market_data});
    
    $self->reset_view();
}

sub step_replay {
    my ($self, $steps) = @_;
    return unless $self->{market_data}->{replay_mode};

    $self->{market_data}->step_replay($steps);
    
    # Los indicadores y overlays se recalcularán dinámicamente hasta la última vela visible
    $self->{indicators}->reset_all();
    $self->{indicators}->recalculate_all($self->{market_data});
    
    # Auto-Desplazamiento (Auto-Scroll) si el precio en replay llega al borde de la pantalla
    my $current_last = $self->{market_data}->size() - 1;
    my $visible_end = $self->{offset} + $self->{visible_bars};
    
    if ($current_last >= $visible_end - 5) {
        $self->{offset} += $steps;
        $self->_clamp_offset();
    }
    
    $self->request_render();
}

sub play_replay {
    my ($self) = @_;
    return if $self->{replay_timer};
    $self->{replay_speed} = 1000; # Velocidad Normal: 1 segundo por vela
    $self->_replay_loop();
}

sub fast_forward_replay {
    my ($self) = @_;
    $self->{replay_speed} = 150; # Velocidad Rápida: 150 milisegundos por vela
    $self->_replay_loop() unless $self->{replay_timer};
}

sub pause_replay {
    my ($self) = @_;
    if ($self->{replay_timer}) {
        $self->{replay_timer}->cancel;
        $self->{replay_timer} = undef;
    }
}

sub _replay_loop {
    my ($self) = @_;
    $self->step_replay(1);
    
    # Creamos un bucle asíncrono utilizando el planificador de eventos after() de Perl/Tk
    $self->{replay_timer} = $self->{mw}->after($self->{replay_speed}, sub {
        $self->_replay_loop();
    });
}

1;
