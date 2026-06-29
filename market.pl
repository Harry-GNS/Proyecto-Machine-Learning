#!/usr/bin/perl

use strict;
use warnings;
use lib '/home/davidandresvm/Documentos/ProyectoMLv2';


use FindBin;
use lib $FindBin::Bin;

use Tk;
use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::ChartEngine;

# ==============================================================================
# 1. Configuración de la Ventana Principal Tk
# ==============================================================================
my $mw = MainWindow->new;
$mw->title("Motor de Graficos Financieros - Visualizacion de Datos");
$mw->attributes('-zoomed' => 1);

# ==============================================================================
# NUEVO: Barra de Herramientas Superior
# ==============================================================================


# Declaramos la variable de forma adelantada para que los botones sepan que existirá
my $engine; 

# ==============================================================================
# NUEVO: Barra de Herramientas Estilo TradingView (Timeframes y Replay)
# ==============================================================================
my $toolbar = $mw->Frame(-bg => '#131722')->pack(-fill => 'x', -side => 'top');

# 1. Bloque de Temporalidades
my $tf_frame = $toolbar->Frame(-bg => '#131722')->pack(-side => 'left', -padx => 10, -pady => 5);
my @timeframes = ('1m', '5m', '15m', '1h', '2h', '4h', 'D', 'W');
foreach my $tf (@timeframes) {
    $tf_frame->Button(
        -text => $tf, 
        -command => sub { $engine->set_timeframe($tf) },
        -bg => '#2A2E39', -fg => '#d1d4dc', -activebackground => '#2962FF', -relief => 'flat', -font => 'Helvetica 9'
    )->pack(-side => 'left', -padx => 1);
}

# Separador Visual
$toolbar->Label(-text => '|', -bg => '#131722', -fg => '#363c4e')->pack(-side => 'left', -padx => 5);

# 2. Bloque Controles del Sistema Replay 
my $replay_frame = $toolbar->Frame(-bg => '#131722')->pack(-side => 'left', -padx => 5);

$replay_frame->Button(-text => '✂ Inicio Replay', -command => sub { $engine->enable_replay_selection() }, 
    -bg => '#2962FF', -fg => 'white', -relief => 'flat', -font => 'Helvetica 9 bold')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏮ Step Back', -command => sub { $engine->step_replay(-1) }, 
    -bg => '#2A2E39', -fg => '#d1d4dc', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '▶ Play', -command => sub { $engine->play_replay() }, 
    -bg => '#2A2E39', -fg => '#d1d4dc', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏸ Pause', -command => sub { $engine->pause_replay() }, 
    -bg => '#2A2E39', -fg => '#d1d4dc', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏭ Step Fwd', -command => sub { $engine->step_replay(1) }, 
    -bg => '#2A2E39', -fg => '#d1d4dc', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏩ Fast Fwd', -command => sub { $engine->fast_forward_replay() }, 
    -bg => '#2A2E39', -fg => '#d1d4dc', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '✖ Exit Replay', -command => sub { $engine->stop_replay() }, 
    -bg => '#F23645', -fg => 'white', -relief => 'flat', -font => 'Helvetica 9')->pack(-side => 'left', -padx => 10);

# Separador Visual
$toolbar->Label(-text => '|', -bg => '#131722', -fg => '#363c4e')->pack(-side => 'left', -padx => 5);

# 3. Bloque Herramientas de Escala
my $modo_texto = "Modo: Automatico";
$toolbar->Button(
    -textvariable => \$modo_texto, 
    -command => sub { 
        my $es_auto = $engine->toggle_auto_scale();
        $modo_texto = $es_auto ? "Modo: Automatico" : "Modo: Manual";
    },
    -bg => '#2A2E39', -fg => '#d1d4dc', -relief => 'flat'
)->pack(-side => 'left', -padx => 5);

$toolbar->Button(
    -text => 'Reset', 
    -command => sub { 
        $engine->reset_view(); 
        $modo_texto = "Modo: Automatico"; 
    },
    -bg => '#2A2E39', -fg => '#d1d4dc', -relief => 'flat'
)->pack(-side => 'left', -padx => 5);

# Creación de los Canvases (Paneles Visuales)
my $price_canvas = $mw->Canvas(-bg => '#131722', -height => 600)->pack(-fill => 'both', -expand => 1);
my $atr_canvas   = $mw->Canvas(-bg => '#131722', -height => 200)->pack(-fill => 'x');

# ==============================================================================
# 2. Inicialización de Capas de Datos e Indicadores
# ==============================================================================
my $market = Market::MarketData->new();
my $indicators = Market::IndicatorManager->new();

# Registrar el indicador ATR con un periodo estándar de 14 [cite: 612]
$indicators->register('ATR', Market::Indicators::ATR->new(14));

# ==============================================================================
# 3. Lectura y Carga de Datos (CSV) [cite: 610]
# ==============================================================================
my $csv_file = $FindBin::Bin . '/Data/datos.csv'; # <-- CAMBIA ESTO AL NOMBRE EXACTO DE TU ARCHIVO

print "Iniciando lectura de datos desde '$csv_file'...\n";
open(my $fh, '<', $csv_file) or die "Error: No se pudo abrir el archivo CSV '$csv_file': $!\n";

# Leer y descartar la primera línea si contiene las cabeceras (Timestamp, Open...)
my $header = <$fh>; 

while (my $line = <$fh>) {
    chomp $line;
    
    # Parsear las columnas (Ajustar el split a ';' si tu CSV está delimitado por punto y coma)
    my ($ts, $open, $high, $low, $close, $volume) = split(/,/, $line);
    
    # Invocar la entrada de datos asegurando que los valores se traten como números [cite: 610]
    $market->add_candle({
        timestamp => $ts,
        open      => $open + 0,
        high      => $high + 0,
        low       => $low  + 0,
        close     => $close + 0,
        volume    => $volume + 0,
    });
    
    # Invocar la actualización de indicadores en streaming (vela por vela) [cite: 612]
    $indicators->update_last($market);
}
close($fh);

print "Carga completada. Total de velas base: " . $market->size() . "\n";

# Invocar la actualización del mercado construyendo las agregaciones temporales [cite: 611]
$market->build_timeframes();

# ==============================================================================
# 4. Inicialización del Motor de Renderizado y Bucle de Eventos [cite: 608]
# ==============================================================================
$engine = Market::ChartEngine->new(
    mw           => $mw,
    market_data  => $market,
    indicators   => $indicators,
    price_canvas => $price_canvas,
    atr_canvas   => $atr_canvas,
);

# Obligar a Tk a calcular las dimensiones internas de la ventana antes de dibujar
$mw->update();

# Dibuja el primer chart en la interfaz [cite: 613]
$engine->request_render();

# Iniciar el ciclo principal de ejecución de la interfaz gráfica [cite: 608]
MainLoop;
