#!/pro/bin/perl

use strict;
use warnings;

use Test::More;
use Tie::Hash::DBD;

require "t/util.pl";

my %hash;
my $DBD = "Oracle";
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
ok ((tied %hash)->{dbh}{AutoCommit},    "AutoCommit ON");

untie %hash;
cleanup ($DBD);

done_testing;
