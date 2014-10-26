package Tie::Array::DBD;

our $VERSION = "0.13";

use strict;
use warnings;

use Carp;

use DBI;
use Storable qw( nfreeze thaw );

my $dbdx = 0;

my %DB = (
    Pg		=> {
	temp	=> "temp",
	t_key	=> "bigint not null primary key",
	t_val	=> "bytea",
	clear	=> "truncate table",
	autoc	=> 0,
	},
    Unify	=> {
	temp	=> "",
	t_key	=> "numeric (9) not null primary key",
	t_val	=> "binary",
	clear	=> "delete from",
	},
    Oracle	=> {
	temp	=> "global temporary",	# Only as of Ora-9
	t_key	=> "number (38) not null primary key",
	t_val	=> "blob",
	clear	=> "truncate table",
	autoc	=> 0,
	},
    mysql	=> {
	temp	=> "temporary",
	t_key	=> "bigint not null primary key",
	t_val	=> "blob",
	clear	=> "truncate table",
	autoc	=> 0,
	},
    SQLite	=> {
	temp	=> "temporary",
	t_key	=> "integer not null primary key",
	t_val	=> "text",
	clear	=> "delete from",
	pbind	=> 0, # TYPEs in SQLite are text, bind_param () needs int
	autoc	=> 0,
	},
    CSV		=> {
	temp	=> "temporary",
	t_key	=> "integer not null primary key",
	t_val	=> "text",
	clear	=> "delete from",
	},
    Firebird	=> {
	temp	=> "",
	t_key	=> "integer not null primary key",
	t_val	=> "varchar (8192)",
	clear	=> "delete from",
	},
    );

sub _create_table
{
    my ($cnf, $tmp) = @_;
    $cnf->{tmp} = $tmp;

    my $dbh = $cnf->{dbh};
    my $dbt = $cnf->{dbt};

    my $exists = 0;
    eval {
	local $dbh->{PrintError} = 0;
	my $sth = $dbh->prepare ("select $cnf->{f_k}, $cnf->{f_v} from $cnf->{tbl}");
	$sth->execute;
	$cnf->{tmp} = 0;
	$exists = 1;
	};
    $exists and return;	# Table already exists

    my ($temp, $t_key, $t_val) = @{$DB{$dbt}}{qw( temp t_key t_val )};
    $cnf->{tmp} or $temp = "";
    local $dbh->{AutoCommit} = 1 unless $dbt eq "CSV" || $dbt eq "Unify";
    $dbh->do (
	"create $temp table $cnf->{tbl} (".
	    "$cnf->{f_k} $t_key,".
	    "$cnf->{f_v} $t_val)"
	);
    $dbt eq "Unify" and $dbh->commit;
    } # create table

sub TIEARRAY
{
    my $pkg = shift;
    my $usg = qq{usage: tie \@a, "$pkg", \$dbh [, { tbl => "tbl", key => "f_key", fld => "f_value" }];};
    my $dsn = shift or croak $usg;
    my $opt = shift;

    my $dbh = ref $dsn
	? $dsn->clone
	: DBI->connect ($dsn, undef, undef, {
	    PrintError       => 1,
	    RaiseError       => 1,
	    PrintWarn        => 0,
	    FetchHashKeyName => "NAME_lc",
	    }) or croak DBI->errstr;

    my $dbt = $dbh->{Driver}{Name} || "no DBI handle";
    my $cnf = $DB{$dbt} or croak "I don't support database '$dbt'";
    my $f_k = "h_key";
    my $f_v = "h_value";
    my $tmp = 0;

    $dbh->{PrintWarn}   = 0;
    $dbh->{AutoCommit}  = $cnf->{autoc} if exists $cnf->{autoc};
    $dbh->{LongReadLen} = 4_194_304     if $dbt eq "Oracle";

    my $h = {
	dbt => $dbt,
	dbh => $dbh,
	tbl => undef,
	tmp => $tmp,
	str => undef,
	};

    if ($opt) {
	ref $opt eq "HASH" or croak $usg;

	$opt->{key} and $f_k      = $opt->{key};
	$opt->{fld} and $f_v      = $opt->{fld};
	$opt->{tbl} and $h->{tbl} = $opt->{tbl};
	$opt->{str} and $h->{str} = $opt->{str};
	}

    $h->{f_k} = $f_k;
    $h->{f_v} = $f_v;

    unless ($h->{tbl}) {	# Create a temporary table
	$tmp = ++$dbdx;
	$h->{tbl} = "t_tie_dbda_$$" . "_$tmp";
	}
    _create_table ($h, $tmp);
    _setmax ($h);

    my $tbl = $h->{tbl};

    $h->{ins} = $dbh->prepare ("insert into $tbl values (?, ?)");
    $h->{del} = $dbh->prepare ("delete from $tbl where $f_k = ?");
    $h->{upd} = $dbh->prepare ("update $tbl set $f_v = ? where $f_k = ?");
    $h->{sel} = $dbh->prepare ("select $f_v from $tbl where $f_k = ?");
    $h->{cnt} = $dbh->prepare ("select count(*) from $tbl");
    $h->{ctv} = $dbh->prepare ("select count(*) from $tbl where $f_k = ?");
    $h->{uky} = $dbh->prepare ("update $tbl set $f_k = ? where $f_k = ?");

    unless (exists $cnf->{pbind} && !$cnf->{pbind}) {
	my $sth = $dbh->prepare ("select $f_k, $f_v from $tbl");
	$sth->execute;
	my @typ = @{$sth->{TYPE}};

	$h->{ins}->bind_param (1, undef, $typ[0]);
	$h->{ins}->bind_param (2, undef, $typ[1]);
	$h->{del}->bind_param (1, undef, $typ[0]);
	$h->{upd}->bind_param (1, undef, $typ[1]);
	$h->{upd}->bind_param (2, undef, $typ[0]);
	$h->{sel}->bind_param (1, undef, $typ[0]);
	$h->{ctv}->bind_param (1, undef, $typ[0]);
	$h->{uky}->bind_param (1, undef, $typ[0]);
	$h->{uky}->bind_param (2, undef, $typ[0]);
	}

    bless $h, $pkg;
    } # TIEARRAY

sub _stream
{
    my ($self, $val) = @_;
    defined $val or return undef;
    $self->{str} or return $val;

    $self->{str} eq "Storable" and return nfreeze ({ val => $val });
    return $val;
    } # _stream

sub _unstream
{
    my ($self, $val) = @_;
    defined $val or return undef;
    $self->{str} or return $val;

    $self->{str} eq "Storable" and return thaw ($val)->{val};
    return $val;
    } # _unstream

sub _setmax
{
    my $self = shift;
    my $sth = $self->{dbh}->prepare ("select max($self->{f_k}) from $self->{tbl}");
    $sth->execute;
    if (my $r = $sth->fetch) {
	$self->{max} = defined $r->[0] ? $r->[0] : -1;
	}
    else {
	$self->{max} = -1;
	}
    $self->{max};
    } # _setmax

sub STORE
{
    my ($self, $key, $value) = @_;
    my $v = $self->_stream ($value);
    $self->EXISTS ($key)
	? $self->{upd}->execute ($v, $key)
	: $self->{ins}->execute ($key, $v);
    $key > $self->{max} and $self->{max} = $key;
    } # STORE

sub DELETE
{
    my ($self, $key) = @_;
    $self->{sel}->execute ($key);
    my $r = $self->{sel}->fetch or return;
    $self->{del}->execute ($key);
    $key >= $self->{max} and $self->_setmax;
    $self->_unstream ($r->[0]);
    } # DELETE

sub STORESIZE
{
    my ($self, $size) = @_; # $size = $# + 1
    $size--;
    $self->{dbh}->do ("delete from $self->{tbl} where $self->{f_k} > $size");
    $self->{max} = $size;
    } # STORESIZE

sub CLEAR
{
    my $self = shift;
    $self->{dbh}->do ("$DB{$self->{dbt}}{clear} $self->{tbl}");
    $self->{max} = -1;
    } # CLEAR

sub EXISTS
{
    my ($self, $key) = @_;
    $key <= $self->{max} or return 0;
    $self->{sel}->execute ($key);
    return $self->{sel}->fetch ? 1 : 0;
    } # EXISTS

sub FETCH
{
    my ($self, $key) = @_;
    $key <= $self->{max} or return undef;
    $self->{sel}->execute ($key);
    my $r = $self->{sel}->fetch or return;
    $self->_unstream ($r->[0]);
    } # STORE

sub PUSH
{
    my ($self, @val) = @_;
    for (@val) {
	$self->STORE (++$self->{max}, $_);
	}
    return $self->FETCHSIZE;
    } # PUSH

sub POP
{
    my $self = shift;
    $self->{max} >= 0 or return;
    $self->DELETE ($self->{max});
    } # POP

sub SHIFT
{
    my $self = shift;
    my $val  = $self->DELETE (0);
    $self->{uky}->execute ($_ - 1, $_) for 1 .. $self->{max};
    $self->{max}--;
    return $val;
    } # SHIFT

sub UNSHIFT
{
    my ($self, @val) = @_;
    @val or return;
    my $incr = scalar @val;
    $self->{uky}->execute ($_ + $incr, $_) for reverse 0 .. $self->{max};
    $self->{max} += $incr;
    $self->STORE ($_, $val[$_]) for 0 .. $#val;
    return $self->FETCHSIZE;
    } # UNSHIFT

# splice ARRAY, OFFSET, LENGTH, LIST
# splice ARRAY, OFFSET, LENGTH
# splice ARRAY, OFFSET
# splice ARRAY
#
#   Removes the elements designated by OFFSET and LENGTH from an array, and
#   replaces them with the elements of LIST, if any.
#
#   In list   context, returns the elements removed from the array.
#   In scalar context, returns the last element removed, or "undef" if
#    no elements are removed.
#
#   The array grows or shrinks as necessary.
#
#   If OFFSET is negative then it starts that far from the end of the array.
#   If LENGTH is omitted, removes everything from OFFSET onward.
#   If LENGTH is negative, removes the elements from OFFSET onward except for
#     -LENGTH elements at the end of the array.
#   If both OFFSET and LENGTH are omitted, removes everything.
#   If OFFSET is past the end of the array, Perl issues a warning, and splices
#     at the end of the array.

sub SPLICE
{
    my $nargs = $#_;
    my ($self, $off, $len, @new, @val) = @_;

    # splice @array;
    if ($nargs == 0) {
	if (wantarray) {
	    @val = map { $self->FETCH ($_) } 0 .. $self->{max};
	    $self->CLEAR;
	    return @val;
	    }
	$val[0] = $self->FETCH ($self->{max});
	$self->CLEAR;
	return $val[0];
	}

    # Take care of negative offset, count from tail
    $off < 0 and $off = $self->{max} + 1 + $off;
    $off < 0 and
	croak "Modification of non-creatable array value attempted, subscript $_[1]";

    # splice @array, off;
    if ($nargs == 1) {
	$off > $self->{max} and return;

	if (wantarray) {
	    @val = map { $self->FETCH ($_) } $off .. $self->{max};
	    $self->STORESIZE ($off);
	    return @val;
	    }
	$val[0] = $self->FETCH ($self->{max});
	$self->STORESIZE ($off);
	return $val[0];
	}

    # splice @array, off, len;
    $nargs == 2 && $off  > $self->{max} and return;

    my $last = $len < 0 ? $self->{max} + $len : $off + $len - 1;
    $nargs == 2 && $last > $self->{max} and return $self->SPLICE ($off);

    @val = map { $self->DELETE ($_) } $off .. $last;
    $len = @val;
    $self->{uky}->execute ($_ - $len, $_) for ($last + 1) .. $self->{max};
    $self->{max} -= $len;

    # splice @array, off, len, replacement-list;
    if (@new) {
	my $new = @new;
	$self->{uky}->execute ($_ + $new, $_) for reverse $off .. $self->{max};
	$self->STORE ($off + $_, $new[$_]) for 0..$#new;
	$self->{max} += $new;
	}

    return wantarray ? @val : $val[-1];
    } # SPLICE

sub FIRSTKEY
{
    my $self = shift;
    $self->{max} >= 0 or return;
    $self->{min} = 0;
    } # FIRSTKEY

sub NEXTKEY
{
    my $self = shift;
    exists $self->{min} && $self->{min} < $self->{max} and return ++$self->{min};
    delete $self->{min};
    return;
    } # FIRSTKEY

sub FETCHSIZE
{
    my $self = shift;
    return $self->{max} + 1;
    } # FETCHSIZE

sub EXTEND
{
    # no-op
    } # EXTEND

sub drop
{
    my $self = shift;
    $self->{tmp} = 1;
    } # drop

sub _dump_table
{
    my $self = shift;
    my $sth = $self->{dbh}->prepare ("select $self->{f_k}, $self->{f_v} from $self->{tbl} order by $self->{f_k}");
    $sth->execute;
    $sth->bind_columns (\my ($k, $v));
    while ($sth->fetch) {
	printf STDERR "%6d: '%s'\n", $k, $self->_unstream ($v);
	}
    } # _dump_table

sub DESTROY
{
    my $self = shift;
    my $dbh = $self->{dbh} or return;
    for (qw( sel ins upd del cnt ctv uky )) {
	$self->{$_} or next;
	$self->{$_}->finish;
	undef $self->{$_}; # DESTROY handle
	}
    if ($self->{tmp}) {
	$dbh->{AutoCommit} or $dbh->rollback;
	$dbh->do ("drop table ".$self->{tbl});
	$dbh->{AutoCommit} or $dbh->commit;
	}
    else {
	$dbh->{AutoCommit} or $dbh->commit;
	}
    $dbh->disconnect;
    undef $self->{dbh};
    } # DESTROY

1;

__END__

=head1 NAME

Tie::Array::DBD - tie a plain array to a database table

=head1 SYNOPSIS

  use DBI;
  use Tie::Array::DBD;

  my $dbh = DBI->connect ("dbi:Pg:", ...);

  tie my @array, "Tie::Array::DBD", "dbi:SQLite:dbname=db.tie";
  tie my @array, "Tie::Array::DBD", $dbh;
  tie my @array, "Tie::Array::DBD", $dbh, {
      tbl => "t_tie_analysis",
      key => "h_key",
      fld => "h_value",
      str => "Storable",
      };

  $array[42] = $value;  # INSERT
  $array[42] = 3;       # UPDATE
  delete $array[42];    # DELETE
  $value = $array[42];  # SELECT
  @array = ();          # CLEAR

  @array = (1..42);
  $array[-2] = 42;
  $_ = pop @array;
  push @array, $_;
  $_ = shift @array;
  unshift @array, $_;
  @a = splice @array, 2, -2, 5..9;
  @k = keys   @array;   # $] >= 5.011
  @v = values @array;   # $] >= 5.011

=head1 DESCRIPTION

This module ties an array to a database table using B<only> an C<index>
and a C<value> field. If no tables specification is passed, this will
create a temporary table with C<h_key> for the key field and a C<h_value>
for the value field.

I think it would make sense  to merge the functionality that this module
provides into C<Tie::DBI>.

=head1 tie

The tie call accepts two arguments:

=head2 Database

The first argument is the connection specifier.  This is either and open
database handle or a C<DBI_DSN> string.

If this argument is a valid handle, this module does not open a database
all by itself, but uses the connection provided in the handle.

If the first argument is a scalar, it is used as DSN for DBI->connect ().

Supported DBD drivers include DBD::Pg, DBD::SQLite, DBD::CSV, DBD::mysql,
DBD::Oracle, and DBD::Unify.

DBD::Pg and DBD::SQLite have an unexpected great performance when server
is the local system. DBD::SQLite is even almost as fast as DB_File.

The current implementation appears to be extremely slow CSV, as expected,
mysql, and Unify. For Unify and mysql that is because these do not allow
indexing on the key field so they cannot be set to be primary key.

=head2 Options

The second argument is optional and should - if passed - be a hashref to
options. The following options are recognized:

=over 2

=item tbl

Defines the name of the table to be used. If none is passed, a new table
is created with a unique name like C<t_tie_dbda_42253_1>. When possible,
the table is created as I<temporary>. After the session, this table will
be dropped.

If a table name is provided, it will be checked for existence. If found,
it will be used with the specified C<key> and C<fld>.  Otherwise it will
be created with C<key> and C<fld>, but it will not be dropped at the end
of the session.

=item key

Defines the name of the key field in the database table.  The default is
C<h_key>.

=item fld

Defines the name of the value field in the database table.   The default
is C<h_value>.

=item str

Defines the required persistence module. Currently only supports the use
of C<Storable>.  The default is undefined.  Passing unsupported streamer
module names will be silently ignored.

Note that C<Storable> does not support persistence of perl types C<CODE>, 
C<REGEXP>, C<IO>, C<FORMAT>, and C<GLOB>.

If you want to preserve Encoding on the array values, you should use this
feature.

Also note that this module does not yet support dynamic deep structures.
See L</Nesting and deep structues>.

=back

=head2 Encoding

C<Tie::Array::DBD> stores values as binary data. This means that
all Encoding and magic is lost when the data is stored, and thus is also
not available when the data is restored,  hence all internal information
about the data is also lost, which includes the C<UTF8> flag.

If you want to preserve the C<UTF8> flag you will need to store internal
flags and use the streamer option:

  tie my @array, "Tie::Array::DBD", { str => "Storable" };

=head2 Nesting and deep structures

C<Tie::Array::DBD> stores values as binary data. This means that
all structure is lost when the data is stored and not available when the
data is restored. To maintain deep structures, use the streamer option:

  tie my @array, "Tie::Array::DBD", { str => "Storable" };

Note that changes inside deep structures do not work. See L</TODO>.

=head1 METHODS

=head2 drop ()

If a table was used with persistence, the table will not be dropped when
the C<untie> is called.  Dropping can be forced using the C<drop> method
at any moment while the array is tied:

  (tied @array)->drop;

=head1 PREREQUISITES

The only real prerequisite is DBI but of course that uses the DBD driver
of your choice. Some drivers are (very) actively maintained.  Be sure to
to use recent Modules.  DBD::SQLite for example seems to require version
1.29 or up.

=head1 RESTRICTIONS and LIMITATIONS

=over 2

=item *

C<DBD::Oracle> limits the size of BLOB-reads to 4kb by default, which is
too small for reasonable data structures. Tie::Array::DBD locally raises
this value to 4Mb, which is still an arbitrary limit.

=item *

C<Storable> does not support persistence of perl types C<IO>, C<REGEXP>,
C<CODE>, C<FORMAT>, and C<GLOB>.  Future extensions might implement some
alternative streaming modules, like C<Data::Dump::Streamer> or use mixin
approaches that enable you to fit in your own.

=back

=head1 TODO

=over 2

=item Update on deep changes

Currently,  nested structures do not get updated when it is an change in
a deeper part.

  tie my @array, "Tie::Array::DBD", $dbh, { str => "Storable" };

  @array = (
      [ 1, "foo" ],
      [ 2, "bar" ],
      );

  $array[1][0]++; # No effect :(

=item Documentation

Better document what the implications are of storing  I<data> content in
a database and restoring that. It will not be fool proof.

=item Mixins

Maybe: implement a feature that would enable plugins or mixins to do the
streaming or preservation of other data attributes.

=back

=head1 AUTHOR

H.Merijn Brand <h.m.brand@xs4all.nl>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2014 H.Merijn Brand

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 SEE ALSO

DBI, Tie::DBI, Tie::Hash, Tie::Hash::DBD, DBM::Deep

=cut

":ex:se gw=72";
