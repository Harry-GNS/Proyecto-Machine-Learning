package Market::Indicators::Liquidity;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        depth => $args{depth} || 3,
        n_run => $args{n_run} || 3,
        data  => [],
    };
    bless $self, $class;
    return $self;
}

sub calculate {
    my ($self, $market_data) = @_;
    my $size = $market_data->size();
    my $k = $self->{depth};
    my $n_run = $self->{n_run};

    $self->{data} = [];

    # Inicializar estructuras base
    for (0 .. $size - 1) {
        push @{$self->{data}}, { state => 'none', events => [] };
    }

    # FASE 1: Detección de Swing Points 
    for my $i ($k .. $size - $k - 1) {
        my $current = $market_data->get_candle($i);
        my $is_swing_high = 1;
        my $is_swing_low  = 1;

        for my $j (1 .. $k) {
            my $left  = $market_data->get_candle($i - $j);
            my $right = $market_data->get_candle($i + $j);
            if ($left->{high} >= $current->{high} || $right->{high} >= $current->{high}) { $is_swing_high = 0; }
            if ($left->{low} <= $current->{low} || $right->{low} <= $current->{low}) { $is_swing_low = 0; }
        }

        if ($is_swing_high) {
            $self->{data}->[$i]->{state} = 'swing_high';
            $self->{data}->[$i]->{price} = $current->{high};
        } elsif ($is_swing_low) {
            $self->{data}->[$i]->{state} = 'swing_low';
            $self->{data}->[$i]->{price} = $current->{low};
        }
    }

    # FASE 2 OPTIMIZADA: Escáner Lineal de Alta Velocidad (Single-Pass)
    # Solo procesamos los niveles que sigan "vivos"
    my @active_highs;
    my @active_lows;

    for my $i (0 .. $size - 1) {
        my $type = $self->{data}->[$i]->{state};
        
        # Registrar nuevos niveles que acaban de aparecer
        if ($type eq 'swing_high') { push @active_highs, $i; }
        elsif ($type eq 'swing_low') { push @active_lows, $i; }

        my $candle = $market_data->get_candle($i);

        # --- Evaluar Rupturas de BSL (Altos) ---
        my @new_active_highs;
        for my $origin_idx (@active_highs) {
            # Ignorar si el nivel acaba de formarse (esperar el margen k)
            if ($i <= $origin_idx + $k) {
                push @new_active_highs, $origin_idx;
                next;
            }

            my $level_price = $self->{data}->[$origin_idx]->{price};
            
            if ($candle->{high} > $level_price) {
                # ¡Nivel barrido! Resolvamos la máquina de estados sin loops largos
                my $resolved = 0;
                
                # 1. Sweep
                if ($candle->{close} < $level_price) {
                    $self->{data}->[$origin_idx]->{end_index} = $i;
                    $self->{data}->[$origin_idx]->{resolution} = 'sweep';
                    push @{$self->{data}->[$i]->{events}}, { type => 'sweep_up', price => $level_price, origin => $origin_idx };
                    $resolved = 1;
                }
                
                # 2. Run
                if (!$resolved && $i + $n_run - 1 < $size) {
                    my $is_run = 1;
                    for my $m (0 .. $n_run - 1) {
                        if ($market_data->get_candle($i + $m)->{close} <= $level_price) {
                            $is_run = 0; last;
                        }
                    }
                    if ($is_run) {
                        $self->{data}->[$origin_idx]->{end_index} = $i;
                        $self->{data}->[$origin_idx]->{resolution} = 'run';
                        push @{$self->{data}->[$i]->{events}}, { type => 'run_up', price => $level_price, origin => $origin_idx };
                        $resolved = 1;
                    }
                }
                
                # 3. Grab
                if (!$resolved) {
                    my $is_grab = 0;
                    my $grab_end_idx = $i;
                    for my $m (1 .. 3) {
                        if ($i + $m < $size) {
                            if ($market_data->get_candle($i + $m)->{close} < $level_price) {
                                $is_grab = 1;
                                $grab_end_idx = $i + $m;
                                last;
                            }
                        }
                    }
                    if ($is_grab) {
                        $self->{data}->[$origin_idx]->{end_index} = $grab_end_idx;
                        $self->{data}->[$origin_idx]->{resolution} = 'grab';
                        push @{$self->{data}->[$grab_end_idx]->{events}}, { type => 'grab_up', price => $level_price, origin => $origin_idx };
                        $resolved = 1;
                    }
                }

                # Si cruzó pero estamos ciegos del futuro (por estar en Replay), truncamos la línea aquí
                if (!$resolved) {
                    $self->{data}->[$origin_idx]->{end_index} = $i;
                }
            } else {
                # El nivel sobrevivió a esta vela, lo guardamos para evaluarlo en el futuro
                push @new_active_highs, $origin_idx;
            }
        }
        @active_highs = @new_active_highs;

        # --- Evaluar Rupturas de SSL (Bajos) ---
        my @new_active_lows;
        for my $origin_idx (@active_lows) {
            if ($i <= $origin_idx + $k) {
                push @new_active_lows, $origin_idx;
                next;
            }

            my $level_price = $self->{data}->[$origin_idx]->{price};
            
            if ($candle->{low} < $level_price) {
                my $resolved = 0;
                
                # 1. Sweep
                if ($candle->{close} > $level_price) {
                    $self->{data}->[$origin_idx]->{end_index} = $i;
                    $self->{data}->[$origin_idx]->{resolution} = 'sweep';
                    push @{$self->{data}->[$i]->{events}}, { type => 'sweep_down', price => $level_price, origin => $origin_idx };
                    $resolved = 1;
                }
                
                # 2. Run
                if (!$resolved && $i + $n_run - 1 < $size) {
                    my $is_run = 1;
                    for my $m (0 .. $n_run - 1) {
                        if ($market_data->get_candle($i + $m)->{close} >= $level_price) {
                            $is_run = 0; last;
                        }
                    }
                    if ($is_run) {
                        $self->{data}->[$origin_idx]->{end_index} = $i;
                        $self->{data}->[$origin_idx]->{resolution} = 'run';
                        push @{$self->{data}->[$i]->{events}}, { type => 'run_down', price => $level_price, origin => $origin_idx };
                        $resolved = 1;
                    }
                }
                
                # 3. Grab
                if (!$resolved) {
                    my $is_grab = 0;
                    my $grab_end_idx = $i;
                    for my $m (1 .. 3) {
                        if ($i + $m < $size) {
                            if ($market_data->get_candle($i + $m)->{close} > $level_price) {
                                $is_grab = 1;
                                $grab_end_idx = $i + $m;
                                last;
                            }
                        }
                    }
                    if ($is_grab) {
                        $self->{data}->[$origin_idx]->{end_index} = $grab_end_idx;
                        $self->{data}->[$origin_idx]->{resolution} = 'grab';
                        push @{$self->{data}->[$grab_end_idx]->{events}}, { type => 'grab_down', price => $level_price, origin => $origin_idx };
                        $resolved = 1;
                    }
                }

                if (!$resolved) {
                    $self->{data}->[$origin_idx]->{end_index} = $i;
                }
            } else {
                push @new_active_lows, $origin_idx;
            }
        }
        @active_lows = @new_active_lows;
    }

    # Limpieza: Los niveles que nunca fueron rotos se extienden hasta el final del gráfico
    for my $origin_idx (@active_highs, @active_lows) {
        $self->{data}->[$origin_idx]->{end_index} = $size - 1;
        $self->{data}->[$origin_idx]->{resolution} = 'active';
    }
}

sub update_last {
    my ($self, $market_data) = @_;
    push @{$self->{data}}, { state => 'none', events => [] };
}

sub calculate_batch {
    my ($self, $market_data) = @_;
    $self->calculate($market_data);
}

sub get_values {
    my ($self) = @_;
    return $self->{data};
}

sub reset {
    my ($self) = @_;
    $self->{data} = [];
}

1;