#!/usr/bin/perl
use strict;
use warnings;

use FindBin;           # Localiza el directorio exacto donde está guardado market.pl
use lib $FindBin::Bin; # Añade ese directorio a la variable @INC

# 1. Importar librerías del sistema y módulos personalizados
use Tk;                # ¡CORRECCIÓN! Necesario para MainWindow y Canvas
use Text::CSV; 

use Market::MarketData;
use Market::IndicatorManager;
use Market::ChartEngine;
use Market::Indicators::ATR;

# 2. Crear ventana principal de la interfaz gráfica
my $mw = MainWindow->new;
$mw->title("Gráficos Financieros con Perl y Tk - Proyecto de Machine Learning");

# Eliminado $mw->geometry y uso el atributo zoomed
$mw->attributes('-zoomed' => 1);

# 3. Instanciar Capa de Datos y Gestor de Indicadores
# ¡CORRECCIÓN! Se unificó y eliminó la doble declaración de $data
my $data = Market::MarketData->new();
my $indicator_mgr = Market::IndicatorManager->new();

# Registramos el indicador ATR antes de procesar los datos históricos
$indicator_mgr->register('ATR', Market::Indicators::ATR->new(14));

# 4. Ingesta y lectura del dataset histórico
open my $fh, '<', '2026_03.csv' or die "No se pudo abrir el archivo: $!";
my $header = <$fh>; # Saltar la cabecera del archivo CSV

while (my $line = <$fh>) {
    chomp $line;
    my ($timestamp, $open, $high, $low, $close, $volume) = split /,/, $line;
    
    $data->add_candle({
        timestamp => $timestamp,
        open      => $open,
        high      => $high,
        low       => $low,
        close     => $close,
        volume    => $volume
    });
    
    
}
close $fh;
# Preprocesamiento: Construir las matrices de 5m y 15m
$data->build_timeframes();

# Calcular los indicadores completos de la temporalidad por defecto (1m)
$indicator_mgr->recompute_all($data);


# 5. Crear la Barra de Herramientas (Toolbar) en la parte superior
my $toolbar = $mw->Frame(-background => '#E0E3EB')->pack(-side => 'top', -fill => 'x');

# 6. Crear los Canvas (Paneles de Precio y ATR) justo debajo del Toolbar
my $price_canvas = $mw->Canvas(-background => 'white')->pack(-expand => 1, -fill => 'both');
my $atr_canvas   = $mw->Canvas(-background => '#f0f0f0', -height => 150)->pack(-fill => 'x');

# 7. Inicializar el Motor de Gráficos Financieros
my $engine = Market::ChartEngine->new(
    market_data       => $data,
    indicator_manager => $indicator_mgr,
    canvases          => { price => $price_canvas, atr => $atr_canvas }
);

# 8. Agregar Botones de Temporalidad al Toolbar
# Los botones se empaquetan a la izquierda (-side => 'left') y llaman al método del motor
$toolbar->Button(
    -text    => "1m", 
    -command => sub { $engine->set_timeframe('1m'); },
    -relief  => 'groove'
)->pack(-side => 'left', -padx => 5, -pady => 5);

$toolbar->Button(
    -text    => "5m", 
    -command => sub { $engine->set_timeframe('5m'); },
    -relief  => 'groove'
)->pack(-side => 'left', -padx => 2, -pady => 5);

$toolbar->Button(
    -text    => "15m", 
    -command => sub { $engine->set_timeframe('15m'); },
    -relief  => 'groove'
)->pack(-side => 'left', -padx => 2, -pady => 5);

# 9. Renderizar el estado inicial de la ventana y arrancar el ciclo de vida de Tk
$mw->update; # <--- Obliga a calcular el tamaño real de la pantalla)
$engine->request_render();
MainLoop;