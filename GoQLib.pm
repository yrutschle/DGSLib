# DGSLib: A Library to access dragongoserver.net
# Copyright (C) 2006-2010  Yves Rutschle
#
# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later
# version.
# 
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE.  See the GNU General Public License for more
# details.
# 
# The full text for the General Public License is here:
# http://www.gnu.org/licenses/gpl.html

package GoQLib;

use strict;
use Exporter;

use Carp qw/cluck/;

use vars qw( @EXPORT @ISA );
@ISA = qw(Exporter);
@EXPORT = qw( 
        convert_coord_std_to_letters 
        convert_coord_letters_to_std 

        get_marked_dead_from_gnugo 

        make_accessors
        is_coord_list_identical
        ldiff
);

# A19 -> aa
sub convert_coord_std_to_letters {
    my ($board_size, $c) = @_;

    $c =~ /(\w)(\d+)/;
    my ($column, $line) = ($1, $2);

    $column =~ tr/A-HJ-T/a-s/;
    $line = ('a'..'s')[$board_size-$line];

    return "$column$line";
}

# aa -> A19
sub convert_coord_letters_to_std {
    my ($board_size, @c) = @_;
    my @out;

    cluck "convert_coord_letters_to_std: undefined argument"
       unless defined $c[0];

    foreach my $c (@c) {
        $c =~ /(.)(.)/;
        my ($column, $line) = ($1, $2);

        $column =~ tr/a-s/A-HJ-T/;
        $line = ($board_size - (ord($line)-ord('a')));
        push @out, "$column$line";
    }
    return wantarray ? @out : shift @out;
}

# This returns the list of stones marked dead by GnuGO
sub get_marked_dead_from_gnugo {
    my (@sgf) = @_;
    my @dead_stones;

    foreach my $line (@sgf) {
        while ($line =~ s/\[(\w\w):X\]//) {
            push @dead_stones, $1;
        }
    }
    return @dead_stones;
}

#############################################################################
# Generic functions that aren't even Go related

sub cdr {
    my @r = @{$_[0]};
    shift @r;
    return \@r;
}

# Given two refs to sorted stone lists, compare if they're identical
sub is_coord_list_identical {
    my ($r1, $r2) = @_;

    (not defined $r1->[0] and not defined $r2->[0]) or 
        ($r1->[0] eq $r2->[0]) and 
            is_coord_list_identical(
                (cdr $r1), 
                (cdr $r2));  # and I don't even *know* lisp
}


# List of elements that aren't in both lists
sub ldiff {
    my ($r1, $r2) = @_;
    my @out;

    foreach my $e (@$r1) {
        push @out, $e unless grep {$e eq $_ } @$r2;
    }
    foreach my $e (@$r2) {
        push @out, $e unless grep {$e eq $_ } @$r1;
    }
    return @out;
}

# Create accessors in a package, using a prefix in the hash string, and
# optional tracing of value assigns.
# E.g.:
#
# my @l = qw( login passwd );
# make_accessors(
#     package => "MyClass",
#     prefix  => "cls_",
#     trace_assigns => 1,
#     accessors => \@l,
# );
# Default is no prefix, no trace. package and accessors are mandatory.
sub make_accessors {
    my (%opts) = @_;
    my $trace = $opts{trace_assigns} || 0;
    my $prefix = $opts{prefix} || "";
    my $package = $opts{package};
    my @list = @{$opts{accessors}};

    my $subs;
    foreach my $data ( @list ) {
        $subs .= qq{
            package $package;
            sub $data {
                warn "$prefix$data = \$_[1]\\n" if $trace and defined \$_[1] ;
                \$_[0]->{$prefix$data} =  defined \$_[1] ? 
                                                \$_[1] : 
                                                \$_[0]->{$prefix$data};
            }
        }
    }
    eval $subs;
}

1;

