package Market::Indicators::SMC_Structures;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        depth => $args{depth} || 3, # k=3 para los pivotes estructurales internos
        data  => [],
    };
    bless $self, $class;
    return $self;
}

sub calculate {
    my ($self, $market_data) = @_;
    my $size = $market_data->size();
    
    # Calcular capa interna (Micro: depth standard, ej: 3)
    my $internal_data = $self->_calculate_layer($market_data, $self->{depth});
    # Calcular capa swing / externa (Macro: depth mayor, ej: 10)
    my $swing_data    = $self->_calculate_layer($market_data, $self->{depth} * 3);
    
    $self->{data} = [];
    for my $i (0 .. $size - 1) {
        push @{$self->{data}}, {
            internal => $internal_data->[$i],
            swing    => $swing_data->[$i],
        };
    }
}

sub _calculate_layer {
    my ($self, $market_data, $k) = @_;
    my $size = $market_data->size();
    
    my @layer_data;
    for (0 .. $size - 1) {
        push @layer_data, {
            state  => 'none', # HH, HL, LH, LL
            events => [],     # BOS, CHOCH
            fvgs   => [],     # FVGs creados en esta barra
            active_fvgs => [], # FVGs activos en esta barra
            obs    => [],     # OBs creados en esta barra
            active_obs  => [], # OBs activos en esta barra
        };
    }

    # 1. DETECCIÓN DE FAIR VALUE GAPS (FVG) Y MITIGACIÓN
    my @active_fvgs;
    for my $i (2 .. $size - 1) {
        my $c1 = $market_data->get_candle($i - 2);
        my $c2 = $market_data->get_candle($i - 1);
        my $c3 = $market_data->get_candle($i);

        # Bullish FVG
        if ($c3->{low} > $c1->{high}) {
            my $fvg = { type => 'bullish_fvg', top => $c3->{low}, bottom => $c1->{high}, start_idx => $i - 1, mitigated_idx => undef };
            push @{$layer_data[$i - 1]->{fvgs}}, $fvg;
            push @active_fvgs, $fvg;
        }
        # Bearish FVG
        elsif ($c3->{high} < $c1->{low}) {
            my $fvg = { type => 'bearish_fvg', top => $c1->{low}, bottom => $c3->{high}, start_idx => $i - 1, mitigated_idx => undef };
            push @{$layer_data[$i - 1]->{fvgs}}, $fvg;
            push @active_fvgs, $fvg;
        }

        # Mitigación FVG
        my @remaining_fvgs;
        for my $fvg (@active_fvgs) {
            my $mitigated = 0;
            if ($i > $fvg->{start_idx} + 1) {
                if ($fvg->{type} eq 'bullish_fvg' && $c3->{low} <= $fvg->{top}) {
                    $fvg->{mitigated_idx} = $i; 
                    $mitigated = 1;
                }
                elsif ($fvg->{type} eq 'bearish_fvg' && $c3->{high} >= $fvg->{bottom}) {
                    $fvg->{mitigated_idx} = $i;
                    $mitigated = 1;
                }
            }
            push @remaining_fvgs, $fvg if !$mitigated;
        }
        @active_fvgs = @remaining_fvgs;
        if (scalar(@active_fvgs) > 30) {
            splice(@active_fvgs, 0, scalar(@active_fvgs) - 30);
        }
        $layer_data[$i]->{active_fvgs} = [ @active_fvgs ];
    }

    # 2. DETECCIÓN DE ESTRUCTURA Y MÁQUINA DE ESTADOS (HH, HL, LH, LL)
    my $last_high = undef;
    my $last_low  = undef;
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
            my $state = 'HH';
            if (defined $last_high && $current->{high} < $last_high->{price}) { $state = 'LH'; }
            $layer_data[$i]->{state} = $state;
            $layer_data[$i]->{price} = $current->{high};
            $last_high = { index => $i, price => $current->{high}, state => $state };
        }
        elsif ($is_swing_low) {
            my $state = 'HL';
            if (defined $last_low && $current->{low} < $last_low->{price}) { $state = 'LL'; }
            $layer_data[$i]->{state} = $state;
            $layer_data[$i]->{price} = $current->{low};
            $last_low = { index => $i, price => $current->{low}, state => $state };
        }
    }

    # 3. DETECCIÓN DE RUPTURAS INSTITUCIONALES (BOS, CHOCH) + ORDER BLOCKS
    my $trend = 'bullish';
    my $active_strong_high = undef;
    my $active_strong_low  = undef;
    my @active_obs;

    for my $i (0 .. $size - 1) {
        my $candle = $market_data->get_candle($i);
        my $state = $layer_data[$i]->{state};

        if ($state ne 'none') {
            if ($state eq 'HH' || $state eq 'LH') {
                $active_strong_high = { index => $i, price => $layer_data[$i]->{price}, state => $state, crossed => 0 };
            } elsif ($state eq 'HL' || $state eq 'LL') {
                $active_strong_low = { index => $i, price => $layer_data[$i]->{price}, state => $state, crossed => 0 };
            }
        }

        # Mitigación de OBs
        my @remaining_obs;
        for my $ob (@active_obs) {
            my $mitigated = 0;
            if ($ob->{bias} eq 'bullish' && $candle->{low} < $ob->{low}) {
                $ob->{mitigated_idx} = $i;
                $mitigated = 1;
            }
            elsif ($ob->{bias} eq 'bearish' && $candle->{high} > $ob->{high}) {
                $ob->{mitigated_idx} = $i;
                $mitigated = 1;
            }
            push @remaining_obs, $ob if !$mitigated;
        }
        @active_obs = @remaining_obs;

        # Evaluar rupturas
        if ($trend eq 'bullish') {
            # BOS
            if (defined $active_strong_high && !$active_strong_high->{crossed} && $candle->{close} > $active_strong_high->{price}) {
                push @{$layer_data[$i]->{events}}, { type => 'BOS', dir => 'bullish', origin => $active_strong_high->{index}, price => $active_strong_high->{price} };
                $active_strong_high->{crossed} = 1;
                
                # Crear Bullish OB: vela con el Low más bajo
                my $start_p = $active_strong_high->{index};
                my $min_idx = $start_p;
                my $min_val = $market_data->get_candle($start_p)->{low};
                for my $idx ($start_p .. $i) {
                    my $c = $market_data->get_candle($idx);
                    if ($c->{low} < $min_val) {
                        $min_val = $c->{low};
                        $min_idx = $idx;
                    }
                }
                my $ob_candle = $market_data->get_candle($min_idx);
                my $ob = {
                    bias => 'bullish',
                    high => $ob_candle->{high},
                    low  => $ob_candle->{low},
                    start_idx => $min_idx,
                    mitigated_idx => undef
                };
                push @{$layer_data[$min_idx]->{obs}}, $ob;
                push @active_obs, $ob;
                $active_strong_high = undef;
            }
            # CHOCH
            elsif (defined $active_strong_low && $active_strong_low->{state} eq 'HL' && $candle->{close} < $active_strong_low->{price}) {
                push @{$layer_data[$i]->{events}}, { type => 'CHOCH', dir => 'bearish', origin => $active_strong_low->{index}, price => $active_strong_low->{price} };
                
                # Crear Bearish OB: vela con el High más alto
                my $start_p = $active_strong_low->{index};
                my $max_idx = $start_p;
                my $max_val = $market_data->get_candle($start_p)->{high};
                for my $idx ($start_p .. $i) {
                    my $c = $market_data->get_candle($idx);
                    if ($c->{high} > $max_val) {
                        $max_val = $c->{high};
                        $max_idx = $idx;
                    }
                }
                my $ob_candle = $market_data->get_candle($max_idx);
                my $ob = {
                    bias => 'bearish',
                    high => $ob_candle->{high},
                    low  => $ob_candle->{low},
                    start_idx => $max_idx,
                    mitigated_idx => undef
                };
                push @{$layer_data[$max_idx]->{obs}}, $ob;
                push @active_obs, $ob;
                
                $active_strong_low = undef;
                $trend = 'bearish';
            }
        }
        elsif ($trend eq 'bearish') {
            # BOS
            if (defined $active_strong_low && !$active_strong_low->{crossed} && $candle->{close} < $active_strong_low->{price}) {
                push @{$layer_data[$i]->{events}}, { type => 'BOS', dir => 'bearish', origin => $active_strong_low->{index}, price => $active_strong_low->{price} };
                $active_strong_low->{crossed} = 1;
                
                # Crear Bearish OB
                my $start_p = $active_strong_low->{index};
                my $max_idx = $start_p;
                my $max_val = $market_data->get_candle($start_p)->{high};
                for my $idx ($start_p .. $i) {
                    my $c = $market_data->get_candle($idx);
                    if ($c->{high} > $max_val) {
                        $max_val = $c->{high};
                        $max_idx = $idx;
                    }
                }
                my $ob_candle = $market_data->get_candle($max_idx);
                my $ob = {
                    bias => 'bearish',
                    high => $ob_candle->{high},
                    low  => $ob_candle->{low},
                    start_idx => $max_idx,
                    mitigated_idx => undef
                };
                push @{$layer_data[$max_idx]->{obs}}, $ob;
                push @active_obs, $ob;
                
                $active_strong_low = undef;
            }
            # CHOCH
            elsif (defined $active_strong_high && $active_strong_high->{state} eq 'LH' && $candle->{close} > $active_strong_high->{price}) {
                push @{$layer_data[$i]->{events}}, { type => 'CHOCH', dir => 'bullish', origin => $active_strong_high->{index}, price => $active_strong_high->{price} };
                
                # Crear Bullish OB
                my $start_p = $active_strong_high->{index};
                my $min_idx = $start_p;
                my $min_val = $market_data->get_candle($start_p)->{low};
                for my $idx ($start_p .. $i) {
                    my $c = $market_data->get_candle($idx);
                    if ($c->{low} < $min_val) {
                        $min_val = $c->{low};
                        $min_idx = $idx;
                    }
                }
                my $ob_candle = $market_data->get_candle($min_idx);
                my $ob = {
                    bias => 'bullish',
                    high => $ob_candle->{high},
                    low  => $ob_candle->{low},
                    start_idx => $min_idx,
                    mitigated_idx => undef
                };
                push @{$layer_data[$min_idx]->{obs}}, $ob;
                push @active_obs, $ob;
                
                $active_strong_high = undef;
                $trend = 'bullish';
            }
        }
        if (scalar(@active_obs) > 30) {
            splice(@active_obs, 0, scalar(@active_obs) - 30);
        }
        $layer_data[$i]->{active_obs} = [ @active_obs ];
    }
    
    return \@layer_data;
}

sub update_last {
    my ($self, $market_data) = @_;
    push @{$self->{data}}, {
        internal => { state => 'none', events => [], fvgs => [], active_fvgs => [], obs => [], active_obs => [] },
        swing    => { state => 'none', events => [], fvgs => [], active_fvgs => [], obs => [], active_obs => [] },
    };
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