package Market::ChartEngine;

use strict;
use warnings;
use lib '/home/davidandresvm/Documentos/Proyecto_IB_G'; # <-- Añade esta línea

use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;

sub new {
    my ($class, %args) = @_;
    my $self = {
        mw           => $args{mw},            # MainWindow de Tk
        market_data  => $args{market_data},   # Referencia a la capa de datos
        indicators   => $args{indicators},    # Referencia al IndicatorManager
        price_canvas => $args{price_canvas},  # Widget Tk
        atr_canvas   => $args{atr_canvas},    # Widget Tk
        
        # Estado interno de la vista [cite: 486]
        offset       => 0,   # Desplazamiento horizontal
        visible_bars => 100, # Zoom horizontal (velas en pantalla)
        render_flag  => 0,   # Flag para evitar renders redundantes 
        
        # Variables para el arrastre del ratón
        drag_start_x      => 0,
        drag_start_offset => 0,

        # Estado de escala vertical
        auto_scale_y   => 1, # 1 = Automático, 0 = Manual
        manual_min_y   => 0,
        manual_max_y   => 0,
        drag_start_y   => 0, # Ancla vertical para el ratón
    };
    bless $self, $class;

    # Instanciar los paneles [cite: 487]
    $self->{price_panel} = Market::Panels::PricePanel->new(canvas => $self->{price_canvas});
    $self->{atr_panel}   = Market::Panels::ATRPanel->new(canvas => $self->{atr_canvas});

    $self->bind_events();
    return $self;
}

sub compute_window {
    my ($self) = @_;
    
    # 1. Truncamos el offset flotante a entero para buscar en el arreglo
    my $start = int($self->{offset});
    
    # 2. Pedimos una vela extra (+1) en el límite derecho. 
    # Esto evita que aparezca un "hueco" negro en el borde mientras arrastras 
    # suavemente antes de que se cargue la siguiente vela.
    my $end = $start + $self->{visible_bars} + 1;
    
    # Protección de límite superior
    my $total_candles = $self->{market_data}->size();
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
    $self->{render_flag} = 0; # Reiniciamos el flag

    # 1. Calcular ventana visible [cite: 503]
    my ($start, $end) = $self->compute_window();
    my $data_slice = $self->{market_data}->get_slice($start, $end);
    my $atr_slice  = $self->{indicators}->slice_array('ATR', $start, $end);

    # 2. Configurar Escalas
    my $width  = $self->{price_canvas}->width;
    my $height = $self->{price_canvas}->height;
    
    my ($min_y, $max_y);
    
    if ($self->{auto_scale_y}) {
        # MODO AUTOMÁTICO: Calcula los límites basados en las velas en pantalla
        ($min_y, $max_y) = $self->{price_panel}->get_y_range($data_slice);
    } else {
        # MODO MANUAL: Usa los límites congelados
        $min_y = $self->{manual_min_y};
        $max_y = $self->{manual_max_y};
    }
    # Extraemos solo el residuo decimal (ej. de 100.4 extrae 0.4)
    my $fractional_offset = $self->{offset} - int($self->{offset});

    # Instanciamos la escala
    my $scale = Market::Panels::Scales->new(
        width        => $width,
        height       => $height,
        min_val      => $min_y,
        max_val      => $max_y,
        visible_bars => $self->{visible_bars},
        offset       => $fractional_offset, # <-- Aquí ocurre la transición fluida
    );

    # Asignamos la escala y llamamos al render de cada panel [cite: 504]
    $self->{price_panel}->set_scale($scale);
    $self->{price_panel}->render($data_slice);
    
    
    # (Aquí harías un proceso similar de instanciar y asignar una escala propia para el atr_panel)
    # ==========================================
    # Renderizado del Panel Secundario (ATR)
    # ==========================================
    my $atr_width  = $self->{atr_canvas}->width;
    my $atr_height = $self->{atr_canvas}->height;
    
    # Obtenemos los límites dinámicos del indicador
    my ($atr_min, $atr_max) = $self->{atr_panel}->get_y_range($atr_slice);

    # Creamos una escala independiente para el panel inferior.
    # Nota importante: Compartimos el mismo fractional_offset del panel de precios
    # para que la coordenada X esté sincronizada pixel a pixel.
    my $atr_scale = Market::Panels::Scales->new(
        width        => $atr_width,
        height       => $atr_height,
        min_val      => $atr_min,
        max_val      => $atr_max,
        visible_bars => $self->{visible_bars},
        offset       => $fractional_offset, 
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
    # Zoom Horizontal
    # =========================================================
    $self->{price_canvas}->Tk::bind('<Button-4>', sub { 
        $self->_horizontal_zoom(1); 
        Tk->break; # Sintaxis absoluta para matar el evento en Perl
    });
    
    $self->{price_canvas}->Tk::bind('<Button-5>', sub { 
        $self->_horizontal_zoom(-1); 
        Tk->break; 
    });

    # =========================================================
    # Zoom Vertical 
    # =========================================================
    $self->{price_canvas}->Tk::bind('<Control-Button-4>', sub { 
        $self->_vertical_zoom(1); 
        Tk->break; 
    });
    
    $self->{price_canvas}->Tk::bind('<Control-Button-5>', sub { 
        $self->_vertical_zoom(-1); 
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
    
    # Límites de seguridad para no hacer scroll más allá de los datos
    $new_offset = 0 if $new_offset < 0;
    my $max_offset = $self->{market_data}->size() - $self->{visible_bars};
    $new_offset = $max_offset if $new_offset > $max_offset && $max_offset > 0;
    
    if ($new_offset != $self->{offset}) {
        $self->{offset} = $new_offset;
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
    # Volver al modo automático
    $self->{auto_scale_y} = 1;
    $self->request_render();
}

sub set_timeframe {
    my ($self, $tf) = @_;

    # 1. Avisamos a la capa de datos que cambie su puntero interno
    $self->{market_data}->set_timeframe($tf);

    # 2. Reseteamos la memoria de todos los indicadores registrados
    $self->{indicators}->reset_all();
    
    # 3. Recalculamos los indicadores para el nuevo histórico completo
    $self->{indicators}->recalculate_all($self->{market_data});

    # 4. Reiniciamos la vista y el zoom a los valores por defecto
    $self->reset_view();
    $self->{offset} = 0;
    
    # 5. Forzamos un renderizado para actualizar la pantalla
    $self->request_render();
}

sub _horizontal_zoom {
    my ($self, $delta) = @_;
    
    # 1. BLOQUEO DE VIEWPORT: Forzar el canvas a no moverse de su origen
    $self->{price_canvas}->yviewMoveto(0);
    $self->{price_canvas}->xviewMoveto(0);
    $self->{atr_canvas}->yviewMoveto(0);
    $self->{atr_canvas}->xviewMoveto(0);
    
    # Ocultar el crosshair para evitar que se deforme
    $self->{price_panel}->draw_crosshair(undef, undef);
    $self->{atr_panel}->draw_crosshair(undef, undef);

    # Modificar la cantidad de velas visibles
    my $step = 10; 
    if ($delta > 0) {
        $self->{visible_bars} -= $step; # Acercar (Rueda arriba = menos velas)
    } else {
        $self->{visible_bars} += $step; # Alejar (Rueda abajo = más velas)
    }

    # Proteger contra límites lógicos
    $self->{visible_bars} = 10 if $self->{visible_bars} < 10;
    my $max_bars = $self->{market_data}->size();
    $self->{visible_bars} = $max_bars if $self->{visible_bars} > $max_bars && $max_bars > 0;

    $self->request_render();
}

sub _vertical_zoom {
    my ($self, $delta) = @_;
    
    # 1. BLOQUEO DE VIEWPORT: Prevenir el desajuste de la cuadrícula
    $self->{price_canvas}->yviewMoveto(0);
    $self->{price_canvas}->xviewMoveto(0);
    $self->{atr_canvas}->yviewMoveto(0);
    $self->{atr_canvas}->xviewMoveto(0);
    
    # Ocultar el crosshair
    $self->{price_panel}->draw_crosshair(undef, undef);
    $self->{atr_panel}->draw_crosshair(undef, undef);
    
    if ($self->{auto_scale_y}) {
        my ($start, $end) = $self->compute_window();
        my $slice = $self->{market_data}->get_slice($start, $end);
        ($self->{manual_min_y}, $self->{manual_max_y}) = $self->{price_panel}->get_y_range($slice);
        $self->{auto_scale_y} = 0; 
    }

    my $zoom_factor = 0.05;
    my $current_range = $self->{manual_max_y} - $self->{manual_min_y};
    
    return if $current_range <= 0.0001; 
    
    my $zoom_amount = $current_range * $zoom_factor;

    if ($delta > 0) {
        # Acercar (Control + Rueda Arriba)
        $self->{manual_max_y} -= $zoom_amount;
        $self->{manual_min_y} += $zoom_amount;
    } else {
        # Alejar (Control + Rueda Abajo)
        $self->{manual_max_y} += $zoom_amount;
        $self->{manual_min_y} -= $zoom_amount;
    }

    $self->request_render();
}


1;