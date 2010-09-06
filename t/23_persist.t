#!/pro/bin/perl

use strict;
use warnings;

use Test::More;
use Tie::Hash::DBD;

require "t/util.pl";

my %hash;
my $DBD = "SQLite";
cleanup ($DBD);
my $tbl = "t_tie_$$"."_persist";
eval { tie %hash, "Tie::Hash::DBD", dsn ($DBD), { tbl => $tbl } };

unless (tied %hash) {
    my $reason = DBI->errstr;
    $reason or ($reason = $@) =~ s/:.*//s;
    $reason and substr $reason, 0, 0, " - ";
    plan skip_all => "DBD::$DBD$reason";
    }

ok (tied %hash,				"Hash tied");

my %data = (
    UND => undef,
    IV  => 1,
    NV  => 3.14159265358979,
    PV  => "string",
    );

ok (%hash = %data,			"Set data");
is_deeply (\%hash, \%data,		"Get data");

ok (untie %hash,			"Untie");
is (tied %hash, undef,			"Untied");

is_deeply (\%hash, {},			"Empty");

untie %hash;

tie %hash, "Tie::Hash::DBD", _dsn ($DBD), { tbl => $tbl };

ok (tied %hash,				"Hash re-tied");

is_deeply (\%hash, \%data,		"Get data again");
ok ((tied %hash)->drop,			"Make table temp");

# clear
%hash = ();
is_deeply (\%hash, {},			"Clear");

untie %hash;
cleanup ($DBD);

done_testing;
