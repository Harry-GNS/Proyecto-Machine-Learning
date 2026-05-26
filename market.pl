#!/usr/bin/perl
use strict;
use warnings;

use FindBin;           
use lib $FindBin::Bin; 

use Tk; # Librería necesaria para MainWindow y Canvas
use Text::CSV;

use Market::MarketData;
use Market::IndicatorManager;
use Market::ChartEngine;
use Market::Indicators::ATR;

# 1. Crear ventana principal
my $mw = MainWindow->new;
$mw->title("Motor de Charting ML");
$mw->geometry("1024x768");

# 2. Instanciar Capa de Datos y Gestor de Indicadores
my $data = Market::MarketData->new();
my $indicator_mgr = Market::IndicatorManager->new();

# Registramos el ATR antes de procesar los datos
$indicator_mgr->register('ATR', Market::Indicators::ATR->new(14));

# 3. Lectura del dataset
open my $fh, '<', '2026_03.csv' or die "No se pudo abrir el archivo: $!";
my $header = <$fh>; # Saltar la cabecera si existe

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
    
    # Actualizar los indicadores en tiempo O(1)
    $indicator_mgr->update_last($data);
}
close $fh;

# 4. Crear los Canvas (Paneles de Precio y ATR)
my $price_canvas = $mw->Canvas(-background => 'white')->pack(-expand => 1, -fill => 'both');
my $atr_canvas   = $mw->Canvas(-background => '#f0f0f0', -height => 150)->pack(-fill => 'x');

# 5. Inicializar Motor (Asegúrate de pasarle el indicator_manager)
my $engine = Market::ChartEngine->new(
    market_data       => $data,
    indicator_manager => $indicator_mgr,
    canvases          => { price => $price_canvas, atr => $atr_canvas }
);

# 6. Dibujar primer chart y arrancar
$engine->request_render();
MainLoop;