#!/usr/bin/perl

# Copyright 2010-2011 H.Merijn Brand

require 5.008;
use strict;

use ExtUtils::MakeMaker;

my %wm = (
    NAME         => "Tie::Hash::DBD",
    DISTNAME     => "Tie-Hash-DBD",
    ABSTRACT     => "Tie a hash to a database",
    AUTHOR       => "H.Merijn Brand <h.m.brand\@xs4all.nl>",
    LICENSE	 => "perl",
    VERSION_FROM => "lib/Tie/Hash/DBD.pm",
    PREREQ_PM	 => {
	"Carp"			=> 0,
	"Test::More"		=> 0.90,
	"DBI"			=> 1.613,
	"Storable"		=> 0,
	},
    );

my $rv = WriteMakefile (%wm);

if ($rv && -s "Makefile") {
    open my $mf, "<", "Makefile" or die "Cannot read Makefile: $!\n";
    my @MF = <$mf>;
    close $mf;
    s/\bPERL_DL_NONLAZY=\d+\s+// for @MF;
    open  $mf, ">", "Makefile"   or die "Cannot modify Makefile: $!\n";
    print $mf @MF;
    close $mf;
    }

1;

package MY;

sub postamble
{
    my $valgrind = join " ", qw(
	PERL_DESTRUCT_LEVEL=2 PERL_DL_NONLAZY=1
	    valgrind
		--suppressions=sandbox/perl.supp
		--leak-check=yes
		--leak-resolution=high
		--show-reachable=yes
		--num-callers=50
		--log-fd=3
		$(FULLPERLRUN) "-MExtUtils::Command::MM" "-e"
		    "test_harness($(TEST_VERBOSE), '$(INST_LIB)', '$(INST_ARCHLIB)')"
		    $(TEST_FILES) 3>valgrind.log
		    );
    join "\n" =>
	'cover test_cover:',
	'	ccache -C',
	'	cover -test',
	'',
	'leakcheck:',
	"	$valgrind",
	'	-@tail -5 valgrind.log',
	'',
	'leaktest:',
	q{	sandbox/leaktest $(FULLPERLRUN) "test_harness($(TEST_VERBOSE), '$(INST_LIB)', '$(INST_ARCHLIB)')" $(TEST_FILES)},
	'',
	'spellcheck:',
	'	pod-spell-check --aspell',
	'',
	'checkmeta:	spellcheck',
	'	perl sandbox/genMETA.pl -c',
	'',
	'fixmeta:	distmeta',
	'	perl sandbox/genMETA.pl',
	'	ls -l */META.yml',
	'',
	'tgzdist:	checkmeta fixmeta $(DISTVNAME).tar.gz distcheck',
	'	-@mv -f $(DISTVNAME).tar.gz $(DISTVNAME).tgz',
	'	-@cpants_lint.pl $(DISTVNAME).tgz',
	'	-@rm -f Debian_CPANTS.txt',
	'';
    } # postamble
