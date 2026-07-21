#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use DBI;

my $dbname   = $ENV{DB_NAME} || "fedora";
my $host     = $ENV{DB_HOST} || "localhost";
my $port     = $ENV{DB_PORT} || 5432;
my $user     = $ENV{DB_USER} || "postgres";
my $password = $ENV{DB_PASS} || "postgres";

my $csv_file = "$FindBin::Bin/../Data/datos.csv";

print "--- IMPORTADOR DE DATOS FINANCIEROS A POSTGRESQL ---\n";
print "Origen: $csv_file\n";
print "Base de Datos Destino: $dbname en $host:$port\n\n";

# 1. Conectar primero a 'postgres' para verificar/crear la base de datos 'fedora'
print "Conectando al servidor PostgreSQL para verificar existencia de la BD...\n";
my $dbh_system;
my @hosts_to_try = ($host);
if ($host eq "localhost") {
    unshift @hosts_to_try, ""; # Agregar socket Unix local (vacio) primero
    # Si estamos en WSL, la IP del host de Windows es el nameserver en resolv.conf
    if (-e '/etc/resolv.conf') {
        open(my $rf, '<', '/etc/resolv.conf');
        while (my $line = <$rf>) {
            if ($line =~ /nameserver\s+([\d\.]+)/) {
                push @hosts_to_try, $1 unless $1 eq "127.0.0.1";
                last;
            }
        }
        close($rf);
    }
}

my $connected = 0;
my $last_error = "";
foreach my $try_host (@hosts_to_try) {
    eval {
        print "Intentando conectar a host: '$try_host'...\n";
        my $dsn = ($try_host eq "") 
            ? "dbi:Pg:dbname=postgres" 
            : "dbi:Pg:dbname=postgres;host=$try_host;port=$port";
        $dbh_system = DBI->connect($dsn, $user, $password, {
            RaiseError => 1, PrintError => 0, AutoCommit => 1
        });
        $host = $try_host; # guardar el que funcionó
        $connected = 1;
    };
    last if $connected;
    $last_error = $@;
}

if (!$connected) {
    die "Error: No se pudo conectar a PostgreSQL en ninguno de los hosts tentados (@hosts_to_try) puerto $port. Asegúrate de que el servidor esté activo.\nDetalles del error: $last_error\n";
}

# Verificar si la base de datos 'fedora' existe
my $db_exists = 0;
my $check_query = $dbh_system->prepare("SELECT 1 FROM pg_database WHERE datname = ?");
$check_query->execute($dbname);
if ($check_query->fetchrow_array()) {
    $db_exists = 1;
    print "La base de datos '$dbname' ya existe.\n";
} else {
    print "Creando la base de datos '$dbname'...\n";
    $dbh_system->do("CREATE DATABASE $dbname");
    print "Base de datos '$dbname' creada con éxito.\n";
}
$check_query->finish();
$dbh_system->disconnect();

# 2. Conectar a la base de datos 'fedora'
print "Conectando a la base de datos '$dbname'...\n";
my $target_dsn = ($host eq "") 
    ? "dbi:Pg:dbname=$dbname" 
    : "dbi:Pg:dbname=$dbname;host=$host;port=$port";
my $dbh = DBI->connect($target_dsn, $user, $password, {
    RaiseError => 1, PrintError => 0, AutoCommit => 1
}) or die "No se pudo conectar a la base de datos '$dbname': $DBI::errstr\n";

# 3. Crear la tabla 'datos' si no existe
print "Creando la tabla 'datos' si no existe...\n";
$dbh->do(q{
    CREATE TABLE IF NOT EXISTS datos (
        id SERIAL PRIMARY KEY,
        time VARCHAR(50) UNIQUE,
        open DOUBLE PRECISION,
        high DOUBLE PRECISION,
        low DOUBLE PRECISION,
        close DOUBLE PRECISION,
        volume DOUBLE PRECISION
    )
});
print "Tabla 'datos' lista.\n";

# 4. Leer el CSV e insertar datos
print "Abriendo el archivo CSV '$csv_file'...\n";
open(my $fh, '<', $csv_file) or die "Error: No se pudo abrir '$csv_file': $!\n";
my $header = <$fh>; # Descartar cabecera

my $insert_stmt = $dbh->prepare(q{
    INSERT INTO datos (time, open, high, low, close, volume)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT (time) DO UPDATE 
    SET open = EXCLUDED.open,
        high = EXCLUDED.high,
        low = EXCLUDED.low,
        close = EXCLUDED.close,
        volume = EXCLUDED.volume
});

my $count = 0;
$dbh->begin_work; # Iniciar transacción para rendimiento rápido
eval {
    while (my $line = <$fh>) {
        chomp $line;
        next unless $line =~ /\S/;
        
        my ($ts, $open, $high, $low, $close, $volume) = split(/,/, $line);
        
        $insert_stmt->execute(
            $ts,
            $open + 0,
            $high + 0,
            $low + 0,
            $close + 0,
            $volume + 0
        );
        $count++;
        if ($count % 1000 == 0) {
            print "Insertados $count registros...\n";
        }
    }
    $dbh->commit;
    print "Carga de datos completada con éxito. Total registros importados/actualizados: $count\n";
};

if ($@) {
    my $err = $@;
    $dbh->rollback;
    die "Error durante la inserción de datos. Transacción revertida.\nDetalle: $err\n";
}

close($fh);
$insert_stmt->finish();
$dbh->disconnect();
print "Proceso finalizado correctamente.\n";
