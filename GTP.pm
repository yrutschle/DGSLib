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

package GTP;

use strict;
use IPC::Open2;
use Games::Go::SGF;
use GoQLib;

my $trace_gtp = 0;

# minimal implementation of Go Text Protocol for the DGS robot.
#
# GTP is specified at http://www.lysator.liu.se/~gunnar/gtp/gtp2-spec-draft2/gtp2-spec.html
#
# Create a new GTP Engine. Specify how to invoke the engine and some parameters
# support loading SGF:
# my $engine = new GTP "gnugo --mode gtp", $board;
# The engine string can contain a %d to specify the board size
sub new {
    my ($class, $engine, $board, %opts) = @_;

    $engine = sprintf($engine, $board->size);

    my ($in, $out);
    my $pid = open2($out, $in, $engine);
    die "open2: $!\n" unless defined $pid;

    my %e;
    $e{in} = $in;
    $e{out} = $out;
    $e{engine} = $engine;

    return bless \%e, $class;
}

# Internal function: performs a GTP transaction
sub gtp_transaction {
    my ($self, $command) = @_;

    my ($out, $in) = ($self->{out}, $self->{in});

    warn "GTP<- $command" if $trace_gtp;
    print $in $command;
    my $resp = <$out>;
    warn "GTP-> $resp" if $trace_gtp;
    die "Illegal GTP response <$resp>\n" unless $resp =~ /^= (.*)/;
    $resp = $1;
    <$out>; # throw out white line

    return $resp;
}

use Data::Dumper;

# If loadsgf is not available, simulate it with play commands
sub loadsgf{
    my ($self, $filename) = @_;
    my ($last_node);

    my $sgf = new Games::Go::SGF $filename;

    my $size = $sgf->size;

    $self->gtp_transaction("boardsize $size\n");

    my $node = $sgf;
    do {
        my ($m, $c);
        if (my $handi = $node->AB) {
            foreach $m (split /,/, $handi) {
                $c = convert_coord_letters_to_std $size, $m;
                $self->gtp_transaction("play black $c\n");
            }
        } 
        if (my $preset = $node->AW) {
            foreach $m (split /,/, $preset) {
                $c = convert_coord_letters_to_std $size, $m;
                $self->gtp_transaction("play white $c\n");
            }
        }
        if ($m = $node->W) {
            $c = convert_coord_letters_to_std  $size,$m;
            $self->gtp_transaction("play white $c\n");
        } elsif ($m = $node->B) {
            $c = convert_coord_letters_to_std  $size,$m;
            $self->gtp_transaction("play black $c\n");
        } else {
            # Probably first node with no handicap
            #print "unknown: ". Dumper $node;
        }
        $last_node = $node;
    } while ($node = $node->next);

    # return whose turn it is to play
    return 'black' unless defined $last_node->colour;
    return $last_node->colour eq 'W' ? 'black' : 'white' ;
}

# Ask the engine the next move for the specified colour
# $move = $engine->next_move('white');
sub next_move {
    my ($self, $colour) = @_;

    #my $colour = $self->gtp_transaction("loadsgf $sgf\n");
    #my $colour = $self->loadsgf($sgf);

    die "<$colour> not valid GTP response\n" unless $colour =~ /^(black|white)$/;
    my $move = $self->gtp_transaction("genmove $colour\n");
    return $move;
}


1;

