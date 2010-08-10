#!/pro/bin/perl

use strict;
use warnings;

use Test::More;
use Time::HiRes qw( gettimeofday tv_interval );
use Tie::Hash::DBD;

require "t/util.pl";

my %hash;
my $DBD = "SQLite";
cleanup ($DBD);
eval { tie %hash, "Tie::Hash::DBD", dsn ($DBD) };

unless (tied %hash) {
    my $reason = DBI->errstr;
    $reason or ($reason = $@) =~ s/:.*//s;
    $reason and substr $reason, 0, 0, " - ";
    plan skip_all => "Cannot tie using DBD::$DBD$reason";
    }

ok (tied %hash,			"Hash tied");

foreach my $size (10, 100, 1000) {
    my %plain = map { ( $_ => $_ ) }
		map { ( $_, pack "l", $_ ) }
		-($size - 1) .. $size;

    my $s_size = 2 * $size;

    my $t0 = [ gettimeofday ];
    ok (%hash = %plain,		"Assign hash $s_size elements");
    my $elapsed = tv_interval ($t0);
    note (sprintf "Write %.3f recs/sec", $s_size / $elapsed);
    $t0 = [ gettimeofday ];
    is_deeply (\%hash, \%plain,	"Content $s_size");
    $elapsed = tv_interval ($t0);
    note (sprintf "Read  %.3f recs/sec", $s_size / $elapsed);
    }

untie %hash;
cleanup ($DBD);

done_testing;
