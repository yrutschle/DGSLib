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

package DGSQBot;

use strict;

use Moose;
use DGSQClient;
use Carp;
use GTP;
use GoQLib;

has name           => ( is => 'rw', isa => 'Str' );
has sgffile        => ( is => 'rw', isa => 'Str' );
has sgfout         => ( is => 'rw', isa => 'Str' );
has finished_games => ( is => 'rw', isa => 'Str' );
has error_games    => ( is => 'rw', isa => 'Str' );
has logfile        => ( is => 'rw', isa => 'Str' );
has pidfile        => ( is => 'rw', isa => 'Str' );
has throttle_file  => ( is => 'rw', isa => 'Str' );
has login          => ( is => 'rw', isa => 'Str' );
has passwd         => ( is => 'rw', isa => 'Str' );
has cookies        => ( is => 'rw', isa => 'Str' ); # filename where HTTP::Cookies are stored
has gtp_engine     => ( is => 'rw', isa => 'Str' );
has dgsclient      => ( is => 'rw', isa => 'DGSQClient' );
has badsize_msg    => ( is => 'rw', isa => 'Str' );
has board_ok       => ( is => 'rw', isa => 'CodeRef' );
has pre_run        => ( is => 'rw', isa => 'CodeRef' );
has verbose        => ( is => 'rw', isa => 'Bool' );
has dont_move      => ( is => 'rw', isa => 'Bool' );
has logging        => ( is => 'rw', isa => 'Bool' );


# prints/logs messages according to preferences
sub message {
    my ($self, $msg) = @_;

    $msg = Encode::encode_utf8($msg);
    warn $msg if $self->verbose;

    open my $log_file, ">> ". $self->logfile if $self->logging;
    croak $self->logfile.": $!\n" unless defined $log_file;
    print $log_file "$msg" if $self->logging;
}

# Formats the current date in a string
sub get_date {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime(time);
    return sprintf "%02d/%02d %02d:%02d", $mon,$mday,$hour,$min;
}


sub new {
    my ($class, %opts) = @_;

    my $self = bless \%opts, $class;

    warn "debugging on: I am not doing any moves\n" if $self->dont_move;

# Locking: check we're not already running
    my $PIDFILE = $self->pidfile;
    my $f;
    if (-e $PIDFILE) {
        my $pid = `cat $PIDFILE`;
        chop $pid;
        if ($pid) {
            my $proc = `ps $pid`;
            if ($proc =~ /$pid/) {
                $self->message("Already running as PID $pid\n");
                exit(1);
            }
        }
    }
    `echo $$ > $PIDFILE`;
#end locking

    my $dgs = new DGSQClient;
    $dgs->login($self->login);
    $dgs->passwd($self->passwd);
    $dgs->cookiefile($self->cookies);
    $dgs->verbose($self->verbose);
    $dgs->throttle_file($self->throttle_file);
#    $dgs->url("http://dragongoserver.sourceforge.net");
    $dgs->url('https://www.dragongoserver.net');
    $dgs->do_login;
   
    $self->dgsclient($dgs);

    return $self;
}

# Call the callback board_ok to see if the game conditions (boardsize, komi,
# etc) is acceptable
sub check_board {
    my ($self, $board) = @_;
    my $sub = $self->board_ok;

    # Trying to get rid of warnings, don't know where that comes from... 01OC2012
    return undef unless defined $board->handicap_type;

    # Reject games with handicap negociation
    return undef unless $board->handicap_type =~ /conv|proper|nigiri|double|black|white/;

    # Call further custom checks
    &$sub($board);
}

# Call the callback pre_run
sub do_pre_run {
    my ($self, $engine, $board) = @_;
    my $sub = $self->pre_run;
    &$sub($engine, $board);
}


# Reads a file containing a list of things, returned as a hash
sub read_list {
    my ($filename) = @_;

    my %out;
    if (open my $fh, $filename) { 
        chop, $out{$_} = 1 while <$fh>;
    } 
    return %out;
}

# Adds a game ID to a file
sub add_game_to_list {
    my ($filename, $b) = @_;
    open my $fh, ">> ".$filename or die "$filename: $!\n";
    print $fh $b->id."\n";;
}

sub do_everything {
    my ($self) = @_;

    warn(get_date." checking state\n") if $self->verbose;

    my $done_something = 0;
    # Accept all new games
    my @messages = $self->dgsclient->messages;
    foreach my $m (@messages)
    {
        $m->verbose($self->verbose);
        $self->message(get_date." message ".$m->num_id." from ".$m->sender.": ".$m->subject."\n");
        if ($m->message_type eq "INVITATION") {
            if ($self->check_board($m)) {
                $m->accept_game("Have a nice game!") unless $self->dont_move;
                $self->message("accepting game from ".$m->sender."\n");
            } else {
                $m->reject_game($self->badsize_msg) unless $self->dont_move;
                $m->boardsize(0) if not defined $m->boardsize;
                $m->handicap(0) if not defined $m->handicap; # Workaround undefined values, don't know where they come from 01OCT2012
                $m->rated(0) if not defined $m->rated; # I still get undefined values, wtf? 16JUL2017
                $self->message("reject game (size ".$m->boardsize." handicap ".$m->handicap." rated ".$m->rated.")\n");
            }
        } else {
            $m->delete;
        }
        $done_something++;
    }

    # load list of finished and error games
    my %finished = read_list($self->finished_games);
    my %error = read_list($self->error_games);

    my @turns = $self->dgsclient->my_turn;
    return unless defined scalar @turns; # Probably couldn't connect
    foreach my $b (@turns)
    {
        next if $finished{$b->id} or $error{$b->id};

        $b->load_info;

        warn "board ".($b->id)."\n" if $self->verbose;

        if ($b->state eq 'FINISHED') {
            $self->message("board ".$b->id." is finished\n");
            $b->finish_game;
            next;
        }

        $self->message(get_date." ".$b->id." (".$b->black->name."-".$b->white->name."): ");

        if ($b->state eq 'handicap') {
            $self->message("placing standard handicap\n");
            $b->place_standard_handicap;
            next;
        }

        my $sgf = $b->sgf;

        open my $f, "> ".$self->sgffile or die $self->sgffile.": $!\n";
        print $f $sgf;
        close $f;

        # 'SCORE': my turn to mark dead stones
        if ($b->state eq 'SCORE') {
            warn "SCORE: opponent hasn't marked, I'm doing it\n" if $self->verbose;
            unless ($b->mark_dead($self->sgffile, $self->sgfout)) {
                warn "SCORE: no dead stones, finishing game\n" if $self->verbose;
                $b->finish_game;
            }
            next;
        }

        # 'SCORE2': my turn to check dead stones marked by opponent
        if ($b->state eq 'SCORE2') {
            warn "SCORE2: checking agreement\n" if $self->verbose;
            if (not $b->mark_game($self->sgffile, $self->sgfout)) {
                # Disagreement -- board will stay around to be finished
                # manually
                $finished{$b->id}++;
                add_game_to_list($self->finished_games, $b);
                $self->message("marking ".$b->id.": disagreement\n");
            } else {
                $self->message("marking ".$b->id.": game finished\n");
            }
            next;
        }

        # Perform a normal move!
        my $engine = new GTP $self->gtp_engine, $b;
        my $colour = $engine->loadsgf($self->sgffile);
        $self->do_pre_run($engine, $b);
        my $move = $engine->next_move($colour);
        my $res;
        if (defined $move) {
            my $coord2;
            if ($move =~ /\w\d/i) {
                $coord2 = convert_coord_std_to_letters $b->size, $move;
            } elsif ($move =~ /pass/i) {
                $coord2 = 'pass';
            } elsif ($move =~ /resign/i) {
                $coord2 = 'resign';
            } else {
                $self->message("Unknown move '$move' -- aborting\n");
                die;
            }
            $self->message($self->name . " says: '$move' ($coord2)\n");

            $res = $b->move($coord2) unless $self->dont_move;
        } else {
            $res->{error} = "GTP engine crashed?";
        }

        if (defined $res and $res->{error}) {
            add_game_to_list($self->error_games, $b);
            $self->message("Error on game ".$b->id.": $res->{error}\n");
        }
        $done_something++;
    }
    unlink $self->sgffile;
}

1;
