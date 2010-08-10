#!/usr/bin/perl

use Test::More;

eval "use Test::Pod::Coverage tests => 1";
plan skip_all => "Test::Pod::Covarage required for testing POD Coverage" if $@;
pod_coverage_ok ("Tie::Hash::DBD",
    { also_private => [ qr{^ SCALAR $}x ], }, # Probably a bug in Pod::Coverage
    "Tie::Hash::DBD is covered");
