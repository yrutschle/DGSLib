# DGSLib: A Library to access dragongoserver.net
# Copyright (C) 2006-2012  Yves Rutschle
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

package DGSQBoard;

use strict;
use Carp;
use DGSQUser;
use GoQLib;
use JSON;

use Moose;
use Moose::Util::TypeConstraints;


use Data::Dumper;

# The most important field of the DGS Board is its ID. The other properties
# (e.g. SGF for the game) will act as cache: load from the site if unknown yet,
# or stay as is. Use the method 'reload' to invalidate all caches (you
# shouldn't need to do that if you control the player whose turn it is to move,
# however remember the other player can play at any time).

subtype 'Float'
    => as 'Str'
    => where { /\d+(.(\d+))?/ };


has id => ( is => 'ro', isa => 'Int', required => 1 );
has black => (is => 'rw', isa => 'DGSQUser' );
has white => (is => 'rw', isa => 'DGSQUser' );
has handicap => (is => 'rw', isa => 'Int' );
has komi => (is => 'rw', isa => 'Float' );
has size => (is => 'rw', isa => 'Int' );
has moveid => (is => 'rw', isa => 'Int' );
has loader => (is => 'rw', isa => 'LWPThrottled', required => 1 );
has white_prisoners => (is => 'rw', isa => 'Int' );
has black_prisoners => (is => 'rw', isa => 'Int' );
has black_time => (is => 'rw', isa => 'Str' );
has white_time => (is => 'rw', isa => 'Str' );
has rated => (is => 'rw', isa => 'Bool' );
enum 'GameState' => qw(KOMI SETUP PLAY PASS SCORE SCORE2 FINISHED handicap);
has state => (is => 'rw', isa => 'GameState' );
has verbose => (is => 'ro', isa => 'Bool' );

# $board->load_info(); 
sub load_info {
    my ($self) = @_;

    my $url = $self->loader->url . "/quick_do.php?obj=game&cmd=info&with=user_id&gid=".$self->id;
    my $response = $self->loader->request(HTTP::Request->new(GET=> $url));;

    my $info = decode_json $response->content;

    $self->black(new DGSQUser($info->{black_user}));
    $self->white(new DGSQUser($info->{white_user}));

    $self->komi($info->{komi});
    $self->size($info->{size});
    $self->handicap($info->{handicap});
    $self->black_time($info->{black_gameinfo}->{remtime});
    $self->white_time($info->{white_gameinfo}->{remtime});
    $self->black_prisoners($info->{black_gameinfo}->{prisoners});
    $self->white_prisoners($info->{white_gameinfo}->{prisoners});
    $self->rated($info->{rated});
    $self->state($info->{status});
    $self->moveid($info->{move_id});
    $self->state('handicap') if ($info->{game_action} == 1);
}

sub sgf {
    my ($self) = @_;

    return $self->{dgsb_sgf} if exists $self->{dgsb_sgf};

    my $id = $self->id;
    my $request = new HTTP::Request(GET => $self->loader->url . "/sgf.php?gid=$id");

    my $response = $self->loader->request($request);
    $self->{dgsb_sgf} = $response->content;
    return $self->{dgsb_sgf};
}

sub reload {
    my ($self) = @_;

    $self->load_info;
    delete $self->{dgsb_sgf};
}

# Perform a move on the board
# move: 'aa'..'ss' or 'pass' or 'resign'
sub move {
    my ($self, $move) = @_;

    my $id = $self->id;

    if ($move =~ /resign/i) {
        return $self->resign;
    } 

    my $mid = $self->moveid;
    $self->loader->do_quick("obj=game&cmd=move&gid=$id&move_id=$mid&move=$move");
}


# Place handicap following standard placement
sub place_standard_handicap {
    my ($self) = @_;
    my $std_h1 = "pddpppddjj";  # For h up to 5
    my $std_h2 = "pddpppdddjpjjjjdjp"; # for h 6 and up

    my $id = $self->id;
    my $h = $self->handicap;

    my $move = substr(($h < 6 ? $std_h1 : $std_h2), 0, $h * 2);

    my $str = $self->loader->url . "/quick_do.php?obj=game&cmd=set_handicap&gid=$id&move_id=0&move=$move";

    my $request = new HTTP::Request(GET => $str);

    my $response = $self->loader->request($request);

    return 1;
}

# Tell DGS what we think is dead, and returns the number of stones we think are
# dead. If no stone is dead, do nothing towards DGS.
sub mark_dead {
    my ($self, $sgffile, $sgfout) = @_;

    my $id = $self->id;

    my $e = `/usr/games/gnugo -O d -l $sgffile -o $sgfout 2>&1`;
    print "$@" if defined $@;
    my @gnu_dead = get_marked_dead_from_gnugo `cat $sgfout`;
    if (@gnu_dead) {
        @gnu_dead = convert_coord_letters_to_std $self->size, 
        @gnu_dead = sort @gnu_dead;
        warn "gnugo reckons:   @gnu_dead\n" if $self->verbose;

        my $moves = join ',', @gnu_dead;
        $moves =~ tr/A-Z/a-z/;
        my $info = $self->loader->do_quick(
            "obj=game&cmd=score&gid=$id&move_id=".
            $self->moveid."&move=$moves&toggle=uniq&fmt=board&agree=0");
    }
    return scalar @gnu_dead;
}

# If we agree with the opponent's dead stones, finish the game
sub finish_game {
    my ($self, @dead) = @_;

    my $id = $self->id;

    return $self->loader->do_quick("obj=game&cmd=score&gid=$id&move_id=".
              $self->moveid."&move=&toggle=uniq&fmt=board&agree=1");
}

sub resign {
    my ($self) = @_;
    my $id = $self->id;
    my $mid = $self->moveid;
    return $self->loader->do_quick("obj=game&cmd=resign&gid=$id&move_id=$mid");
}

sub get_marked_dead_from_dgs {
    my ($self) = @_;

    my $id = $self->id;
    my $mid = $self->moveid;
    my $ref = $self->loader->do_quick("obj=game&cmd=status_score&gid=$id&move_id=$mid");

    my $list = $ref->{black_dead}.$ref->{white_dead};
    my @out;
    while ($list) {
        push @out, substr $list, 0, 2, "";
    }
    return @out;
}

# After both have passed, check opponent agrees with GnuGo on what stones are
# dead and finish the game in case of agreement. Returns true if the game is
# effectively finished, and false if there is disagreement.
sub mark_game {
    my ($b, $sgffile, $sgfout) = @_;
    $b->load_info;

    my $sgf = $b->sgf;
    open my $f, "> $sgffile" or die "$sgffile: $!\n";
    print $f $sgf;
    close $f;

    my @dgs_dead = $b->get_marked_dead_from_dgs;
    warn "opponent marked: @dgs_dead\n" if $b->verbose;
    if (@dgs_dead) {
        local $"; $" = ',';
        @dgs_dead = convert_coord_letters_to_std $b->size, @dgs_dead;
        warn "opponent marked: @dgs_dead\n" if $b->verbose;
        @dgs_dead = sort @dgs_dead;
        warn "opponent marked: @dgs_dead\n" if $b->verbose;
    }

    my $e = `/usr/games/gnugo -O d -l $sgffile -o $sgfout 2>&1`;
    print "$@" if defined $@;
    my @gnu_dead = get_marked_dead_from_gnugo `cat $sgfout`;
    if (@gnu_dead) {
        local $"; $" = ',';
        @gnu_dead = convert_coord_letters_to_std $b->size, @gnu_dead;
        @gnu_dead = sort @gnu_dead;
        warn "gnugo reckons:   @gnu_dead\n" if $b->verbose;
    }

    if (not @dgs_dead) {
        warn "opponent hasn't marked, I'm doing it (should have been done though\n" if $b->verbose;
        $b->mark_dead($sgffile, $sgfout);
    } elsif (is_coord_list_identical(\@gnu_dead, \@dgs_dead)) {
        warn "we both agree\n" if $b->verbose;
        $b->finish_game;
    } else {
        warn "I don't agree with my opponent on board ".$b->id.": ".(join ' ', ldiff \@gnu_dead, \@dgs_dead)."\n" if $b->verbose;
        return undef;
    }
}

1;
