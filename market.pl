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
$mw->title("Motor de Charting ML");
$mw->geometry("1024x768");

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
    
    # Actualizar las features (indicadores) en complejidad O(1) de forma incremental
    $indicator_mgr->update_last($data);
}
close $fh;

# 5. Crear los Canvas arquitectónicos (Paneles de Precio y ATR)
my $price_canvas = $mw->Canvas(-background => 'white')->pack(-expand => 1, -fill => 'both');
my $atr_canvas   = $mw->Canvas(-background => '#f0f0f0', -height => 150)->pack(-fill => 'x');

# 6. Inicializar el Motor de Gráficos Financieros
# ¡CORRECCIÓN! Se inyectó indicator_manager => $indicator_mgr
my $engine = Market::ChartEngine->new(
    market_data       => $data,
    indicator_manager => $indicator_mgr,
    canvases          => { price => $price_canvas, atr => $atr_canvas }
);

# 7. Renderizar el estado inicial de la ventana y arrancar el ciclo de vida de Tk
$engine->request_render();
MainLoop;