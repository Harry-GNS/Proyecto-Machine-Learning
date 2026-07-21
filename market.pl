#!/usr/bin/perl

use strict;
use warnings;
# use lib '/home/davidandresvm/Documentos/ProyectoMLv2';


use FindBin;
use lib $FindBin::Bin;
use utf8;

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
my $toolbar = $mw->Frame(-bg => '#F8F9FD')->pack(-fill => 'x', -side => 'top');

# 1. Bloque de Temporalidades
my $tf_frame = $toolbar->Frame(-bg => '#F8F9FD')->pack(-side => 'left', -padx => 10, -pady => 5);
my @timeframes = ('1m', '5m', '15m', '1h', '2h', '4h', 'D', 'W');
foreach my $tf (@timeframes) {
    $tf_frame->Button(
        -text => $tf, 
        -command => sub { $engine->set_timeframe($tf) },
        -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#2962FF', -activeforeground => '#FFFFFF', -relief => 'flat', -font => 'Helvetica 9'
    )->pack(-side => 'left', -padx => 1);
}

# Separador Visual
$toolbar->Label(-text => '|', -bg => '#F8F9FD', -fg => '#BEC1CC')->pack(-side => 'left', -padx => 5);

# 2. Bloque Controles del Sistema Replay 
my $replay_frame = $toolbar->Frame(-bg => '#F8F9FD')->pack(-side => 'left', -padx => 5);

$replay_frame->Button(-text => '✂ Inicio Replay', -command => sub { $engine->enable_replay_selection() }, 
    -bg => '#2962FF', -fg => 'white', -relief => 'flat', -font => 'Helvetica 9 bold')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏮ Step Back', -command => sub { $engine->step_replay(-1) }, 
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#BEC1CC', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '▶ Play', -command => sub { $engine->play_replay() }, 
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#BEC1CC', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏸ Pause', -command => sub { $engine->pause_replay() }, 
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#BEC1CC', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏭ Step Fwd', -command => sub { $engine->step_replay(1) }, 
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#BEC1CC', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '⏩ Fast Fwd', -command => sub { $engine->fast_forward_replay() }, 
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#BEC1CC', -relief => 'flat')->pack(-side => 'left', -padx => 2);

$replay_frame->Button(-text => '✖ Exit Replay', -command => sub { $engine->stop_replay() }, 
    -bg => '#F23645', -fg => 'white', -relief => 'flat', -font => 'Helvetica 9')->pack(-side => 'left', -padx => 10);

# Separador Visual
$toolbar->Label(-text => '|', -bg => '#F8F9FD', -fg => '#BEC1CC')->pack(-side => 'left', -padx => 5);

# 3. Bloque Herramientas de Escala
my $modo_texto = "Modo: Automatico";
$toolbar->Button(
    -textvariable => \$modo_texto, 
    -command => sub { 
        my $es_auto = $engine->toggle_auto_scale();
        $modo_texto = $es_auto ? "Modo: Automatico" : "Modo: Manual";
    },
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#BEC1CC', -relief => 'flat'
)->pack(-side => 'left', -padx => 5);

$toolbar->Button(
    -text => 'Reset', 
    -command => sub { 
        $engine->reset_view(); 
        $modo_texto = "Modo: Automatico"; 
    },
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#BEC1CC', -relief => 'flat'
)->pack(-side => 'left', -padx => 5);

# ==============================================================================
# NUEVO: Bloque de Visibilidad de Capas Analíticas (SMC)
# ==============================================================================
$toolbar->Label(-text => '|', -bg => '#F8F9FD', -fg => '#BEC1CC')->pack(-side => 'left', -padx => 5);

my $smc_texto = "SMC: VISIBLE";
$toolbar->Button(
    -textvariable => \$smc_texto, 
    -command => sub { 
        my $visible = $engine->toggle_smc();
        $smc_texto = $visible ? "SMC: VISIBLE" : "SMC: OCULTO";
    },
    -bg => '#E0E3EB', -fg => '#2A2E39', -activebackground => '#2962FF', -activeforeground => '#FFFFFF', -relief => 'flat', -font => 'Helvetica 9 bold'
)->pack(-side => 'left', -padx => 5);

# Layout principal: barra lateral izquierda + canvases
my $main_frame = $mw->Frame(-bg => '#FFFFFF')
    ->pack(-side => 'top', -fill => 'both', -expand => 1);

my $sidebar = $main_frame->Frame(-bg => '#F8F9FD', -width => 168)
    ->pack(-side => 'left', -fill => 'y');
$sidebar->packPropagate(0);   # mantener el ancho fijo aunque los hijos sean pequeños

my $charts_frame = $main_frame->Frame(-bg => '#FFFFFF')
    ->pack(-side => 'right', -fill => 'both', -expand => 1);

my $price_canvas = $charts_frame->Canvas(-bg => '#FFFFFF', -height => 600)
    ->pack(-fill => 'both', -expand => 1);
my $atr_canvas   = $charts_frame->Canvas(-bg => '#FFFFFF', -height => 200)
    ->pack(-fill => 'x');

# ==============================================================================
# 2. Inicialización de Capas de Datos e Indicadores
# ==============================================================================
my $market = Market::MarketData->new();
my $indicators = Market::IndicatorManager->new();

# Registrar el indicador ATR con un periodo estándar de 14 [cite: 612]
$indicators->register('ATR', Market::Indicators::ATR->new(14));

# Registrar el motor analítico de Liquidez (Paso 1)
use Market::Indicators::Liquidity;
$indicators->register('Liquidity', Market::Indicators::Liquidity->new(depth => 3));

# Registrar el motor analítico de Estructuras SMC (Paso 2)
use Market::Indicators::SMC_Structures;
$indicators->register('SMC_Structures', Market::Indicators::SMC_Structures->new(depth => 3));

# Registrar el detector de tendencia ZigZag macro (ChartPrime port, MPL-2.0)
use Market::Indicators::ZigZag_Trend;
$indicators->register('ZigZag_Trend', Market::Indicators::ZigZag_Trend->new(prd => 2));
$indicators->register('ZigZag_Trend_External', Market::Indicators::ZigZag_Trend->new(prd => 12));

# ==============================================================================
# Fase 2: Infraestructura Analítica de Volumen y VWAP
# ==============================================================================

# Perfil de Volumen Avanzado (Sección 7)
# mode: 'session' | 'bos_choch' | 'historical'
use Market::Indicators::Volume_Profile;
$indicators->register('Volume_Profile',
    Market::Indicators::Volume_Profile->new(
        mode           => 'session',  # Reinicio en cada nueva sesión
        price_levels   => 100,        # Resolución de cuadrícula de precio
        value_area_pct => 0.70,       # 70% del volumen para el Value Area
        context_bars   => 500,        # Ventana de contexto indexado (Sección 2)
    )
);

# VWAP Multi-Pivot Anclado (Sección 8)
# Todos los disparadores habilitados por defecto
use Market::Indicators::Anchored_VWAP;
$indicators->register('Anchored_VWAP',
    Market::Indicators::Anchored_VWAP->new(
        anchor_session     => 1,  # Disparador 1: Inicio de Sesión
        anchor_market_open => 1,  # Disparador 2: Apertura oficial de mercado
        anchor_bos         => 1,  # Disparador 3: Break of Structure confirmado
        anchor_choch       => 1,  # Disparador 4: Change of Character confirmado
        anchor_poc         => 1,  # Disparador 5: POC del Volume Profile
        context_bars       => 500,
    )
);

# ==============================================================================
# DEPURACIÓN: Verificar detección de BOS y CHOCH
# ==============================================================================
print "\n--- DEPURACION: Estructuras SMC ---\n";
$indicators->recalculate_all($market);
my $smc_data = $indicators->slice_array('SMC_Structures', 0, $market->size() - 1);

for my $i (0 .. $#$smc_data) {
    my $punto = $smc_data->[$i];
    if (defined $punto && exists $punto->{events} && @{$punto->{events}}) {
        my $timestamp = $market->get_timestamp($i);
        for my $ev (@{$punto->{events}}) {
            print "[$timestamp] Evento: $ev->{type} ($ev->{dir}) detectado en precio $ev->{price}\n";
        }
    }
}
print "--- FIN DE DEPURACION ---\n\n";

# ==============================================================================
# 3. Lectura y Carga de Datos (PostgreSQL 'fedora' con Fallback a CSV) [cite: 610]
# ==============================================================================
my $db_loaded = 0;
eval {
    require DBI;
    my @hosts_to_try = ("", "localhost", "10.255.255.254");
    my $port = 5432;
    my $user = 'postgres';
    my $password = 'postgres';
    my $dbname = 'fedora';
    
    my $dbh;
    my $connected = 0;
    foreach my $try_host (@hosts_to_try) {
        eval {
            print "Intentando conectar a base de datos '$dbname' en host '$try_host'...\n";
            my $dsn = ($try_host eq "") 
                ? "dbi:Pg:dbname=$dbname" 
                : "dbi:Pg:dbname=$dbname;host=$try_host;port=$port";
            $dbh = DBI->connect($dsn, $user, $password, {
                RaiseError => 1, PrintError => 0, AutoCommit => 1
            });
            $connected = 1;
        };
        last if $connected;
    }
    
    if ($connected) {
        print "Conexion a PostgreSQL ('$dbname') establecida con exito.\n";
        print "Cargando velas desde la tabla 'datos'...\n";
        
        my $sth = $dbh->prepare("SELECT time, open, high, low, close, volume FROM datos ORDER BY id ASC");
        $sth->execute();
        
        while (my $row = $sth->fetchrow_hashref()) {
            $market->add_candle({
                timestamp => $row->{time},
                open      => $row->{open} + 0,
                high      => $row->{high} + 0,
                low       => $row->{low} + 0,
                close     => $row->{close} + 0,
                volume    => $row->{volume} + 0,
            });
            $indicators->update_last($market);
        }
        $sth->finish();
        $dbh->disconnect();
        $db_loaded = 1;
        print "Carga desde PostgreSQL completada con exito.\n";
    }
};

if ($@ || !$db_loaded) {
    print "Conexion a PostgreSQL fallida o no disponible. Detalles: $@" if $@;
    print "Aplicando fallback: cargando datos desde CSV...\n";
    
    my $csv_file = $FindBin::Bin . '/Data/datos.csv';
    print "Iniciando lectura de datos desde '$csv_file'...\n";
    open(my $fh, '<', $csv_file) or die "Error: No se pudo abrir el archivo CSV '$csv_file': $!\n";
    
    # Leer y descartar la primera línea si contiene las cabeceras
    my $header = <$fh>; 
    
    while (my $line = <$fh>) {
        chomp $line;
        my ($ts, $open, $high, $low, $close, $volume) = split(/,/, $line);
        
        $market->add_candle({
            timestamp => $ts,
            open      => $open + 0,
            high      => $high + 0,
            low       => $low  + 0,
            close     => $close + 0,
            volume    => $volume + 0,
        });
        
        $indicators->update_last($market);
    }
    close($fh);
}

print "Carga completada. Total de velas base: " . $market->size() . "\n";

# Invocar la actualización del mercado construyendo las agregaciones temporales [cite: 611]
$market->build_timeframes();
# ==============================================================================
# DEPURACIÓN: Verificar detección de Swing Points en la temporalidad base
# ==============================================================================

$indicators->recalculate_all($market);
my $liq_data = $indicators->slice_array('Liquidity', 0, $market->size() - 1);

for my $i (0 .. $#$liq_data) {
    my $punto = $liq_data->[$i];
    if (defined $punto && $punto->{state} ne 'none') {
        my $timestamp = $market->get_timestamp($i);
        if ($punto->{state} eq 'swing_high') {
            print "[$timestamp] SWING HIGH detectado en precio: $punto->{price}\n";
        } elsif ($punto->{state} eq 'swing_low') {
            print "[$timestamp] SWING LOW detectado en precio: $punto->{price}\n";
        }
    }
}


# ==============================================================================
# 4. Inicialización del Motor de Renderizado y Bucle de Eventos [cite: 608]
# ==============================================================================
$engine = Market::ChartEngine->new(
    mw           => $mw,
    market_data  => $market,
    indicators   => $indicators,
    price_canvas => $price_canvas,
    atr_canvas   => $atr_canvas,
    sidebar      => $sidebar,   # Frame para la barra lateral de controles
);

# Obligar a Tk a calcular las dimensiones internas de la ventana antes de dibujar
$mw->update();

# Dibuja el primer chart en la interfaz [cite: 613]
$engine->request_render();

# Iniciar el ciclo principal de ejecución de la interfaz gráfica [cite: 608]
MainLoop;
