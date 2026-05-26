#!/usr/bin/perl
use strict;
use warnings;

use strict;
use warnings;
use Tk;
use Market::MarketData;
use Market::ChartEngine;

# 1. Crear ventana principal
my $mw = MainWindow->new;
$mw->title("Motor de Charting ML");
$mw->geometry("1024x768");

# 2. Instanciar Capa de Datos
my $data = Market::MarketData->new();
# Aquí cargarías un CSV simulado haciendo un bucle y llamando a $data->add_candle(...) [cite: 610]

# 3. Crear los Canvas (Paneles de Precio y ATR)
my $price_canvas = $mw->Canvas(-background => 'white')->pack(-expand => 1, -fill => 'both');
my $atr_canvas   = $mw->Canvas(-background => '#f0f0f0', -height => 150)->pack(-fill => 'x');

# 4. Inicializar Motor
my $engine = Market::ChartEngine->new(
    market_data => $data,
    canvases    => { price => $price_canvas, atr => $atr_canvas }
);

# 5. Dibujar primer chart y arrancar
$engine->request_render(); [cite: 497, 613]
MainLoop;
