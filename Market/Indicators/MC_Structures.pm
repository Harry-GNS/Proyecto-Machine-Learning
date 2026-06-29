#!/usr/bin/perl
use strict;
use warnings;
use Tk;
use Tk::BrowseEntry;

# ==========================================
# ESTADO GLOBAL DEL SISTEMA
# ==========================================
my @market_data = (); # Aquí se cargarán los datos OHLCV
my $total_candles = 1000; # Simulación de total de datos cargados
my $replay_pointer = $total_candles - 1; # Puntero actual (índice del array)
my $is_replay_mode = 0;
my $is_playing = 0;
my $current_timeframe = '1h';
my $play_timer; # Almacena el evento del loop de reproducción

# ==========================================
# INTERFAZ GRÁFICA (Perl/Tk)
# ==========================================
my $mw = MainWindow->new;
$mw->title("Plataforma de Trading - Motor SMC & Replay");
$mw->geometry("1024x768");

# 1. BARRA SUPERIOR: Temporalidades 
my $frame_top = $mw->Frame(-background => '#1E222D')->pack(-side => 'top', -fill => 'x');

my @timeframes = qw(1m 5m 15m 1h 2h 4h D W);
foreach my $tf (@timeframes) {
    $frame_top->Button(
        -text => $tf,
        -background => '#2A2E39',
        -foreground => 'white',
        -activebackground => '#2962FF',
        -command => sub { change_timeframe($tf) }
    )->pack(-side => 'left', -padx => 2, -pady => 5);
}

# 2. ÁREA DE GRÁFICO (Canvas tipo TradingView)
my $canvas_frame = $mw->Frame(-background => '#131722')->pack(-side => 'top', -fill => 'both', -expand => 1);
my $canvas = $canvas_frame->Canvas(
    -background => '#131722', 
    -width => 1000, 
    -height => 600
)->pack(-side => 'top', -fill => 'both', -expand => 1);

# Etiqueta de estado en el gráfico
my $status_label = $canvas_frame->Label(
    -text => "Modo: EN VIVO | Temporalidad: $current_timeframe | Vela: $replay_pointer",
    -background => '#131722',
    -foreground => '#787B86'
)->pack(-side => 'bottom', -fill => 'x');

# 3. BARRA INFERIOR: Sistema Replay 
my $frame_replay = $mw->Frame(-background => '#1E222D')->pack(-side => 'bottom', -fill => 'x');

$frame_replay->Button(-text => "Inicio Replay", -command => \&start_replay)->pack(-side => 'left', -padx => 5, -pady => 5);
$frame_replay->Button(-text => "Step Backward", -command => \&step_backward)->pack(-side => 'left', -padx => 5, -pady => 5);
$frame_replay->Button(-text => "Play", -command => \&play_replay)->pack(-side => 'left', -padx => 5, -pady => 5);
$frame_replay->Button(-text => "Pause", -command => \&pause_replay)->pack(-side => 'left', -padx => 5, -pady => 5);
$frame_replay->Button(-text => "Step Forward", -command => \&step_forward)->pack(-side => 'left', -padx => 5, -pady => 5);
$frame_replay->Button(-text => "Fast Forward", -command => \&fast_forward)->pack(-side => 'left', -padx => 5, -pady => 5);
$frame_replay->Button(-text => "Exit Replay", -command => \&exit_replay)->pack(-side => 'right', -padx => 5, -pady => 5);

# ==========================================
# FUNCIONES DE LÓGICA Y CONTROL
# ==========================================

sub change_timeframe {
    my ($tf) = @_;
    $current_timeframe = $tf;
    # Aquí se invocaría la recarga de datos según la base de datos SQL o el dataset
    update_chart();
}

sub start_replay {
    $is_replay_mode = 1;
    # Para el ejemplo, iniciamos el replay 100 velas atrás
    $replay_pointer = $total_candles - 100; 
    update_chart();
}

sub exit_replay {
    pause_replay();
    $is_replay_mode = 0;
    $replay_pointer = $total_candles - 1; # Retorna a la vela actual
    update_chart();
}

sub step_forward {
    if ($is_replay_mode && $replay_pointer < $total_candles - 1) {
        $replay_pointer++;
        update_chart();
    }
}

sub step_backward {
    if ($is_replay_mode && $replay_pointer > 0) {
        $replay_pointer--;
        update_chart();
    }
}

sub play_replay {
    return if $is_playing || !$is_replay_mode;
    $is_playing = 1;
    # Bucle asíncrono en Tk (reproduce a velocidad normal, ej. 1000ms por vela)
    $play_timer = $mw->repeat(1000, \&step_forward);
}

sub fast_forward {
    return if !$is_replay_mode;
    pause_replay();
    $is_playing = 1;
    # Bucle asíncrono acelerado (ej. 100ms por vela)
    $play_timer = $mw->repeat(100, \&step_forward);
}

sub pause_replay {
    if ($is_playing && defined $play_timer) {
        $play_timer->cancel;
        $is_playing = 0;
    }
}

sub update_chart {
    # 1. Limpiar el Canvas
    $canvas->delete('all');
    
    # 2. Actualizar etiquetas
    my $modo = $is_replay_mode ? "REPLAY ACTIVO" : "EN VIVO";
    $status_label->configure(-text => "Modo: $modo | Temporalidad: $current_timeframe | Puntero Vela Visible: $replay_pointer");
    
    # 3. Restricción Estricta [cite: 32]
    # Extraer el slice de datos. NINGÚN indicador debe recibir datos más allá de $replay_pointer.
    # my @visible_data = @market_data[0 .. $replay_pointer];
    
    # 4. Renderizado Simulado (Aquí conectarías con Market/Overlays/SMC_Structures.pm) 
    # Se deben iterar y dibujar las velas contenidas en @visible_data.
    $canvas->createText(500, 300, -text => "Área de Renderizado de Velas y Liquidez\nSolo se procesan datos hasta el índice: $replay_pointer", -fill => '#787B86', -font => ['Arial', 14]);
}

# Inicialización
update_chart();
MainLoop;