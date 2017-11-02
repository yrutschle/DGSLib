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

package DGSQMessage;

use strict;
use Carp;

use JSON;
use Moose;
use Data::Dumper;

has num_id => (is => 'rw', isa => 'Int', required => 1);
has useragent => (is => 'rw', isa => 'LWPThrottled', required => 1 );
has message_type => (is => 'rw', isa => 'Str' );
has text => (is => 'rw', isa => 'Str' );
has sender => (is => 'rw', isa => 'Str' );
has handicap => (is => 'rw', isa => 'Int' );
has handicap_type => ( is => 'rw', isa => 'Str' );
has game_type => (is => 'rw', isa => 'Str' );
has komi => (is => 'rw', isa => 'Str' );
has ruleset => (is => 'rw', isa => 'Str' );
has boardsize => (is => 'rw', isa => 'Int' );
has rated => (is => 'rw', isa => 'Bool' );
has weekend_clocked => (is => 'rw', isa => 'Bool' );
has subject => (is => 'rw', isa => 'Str' );
has verbose => (is => 'rw', isa => 'Bool' );
has opp_started_games => (is => 'rw', isa => 'Int' );
has time_mode => (is => 'rw', isa => 'Str' );
has time_main => (is => 'rw', isa => 'Int' );
has time_byo => (is => 'rw', isa => 'Int' );
has time_periods => (is => 'rw', isa => 'Int' );


# $board->load_info(); 
sub load_info {
    my ($self) = @_;

    my $id = $self->num_id;
    my $url = $self->useragent->url . "/quick_do.php?obj=message&cmd=info&mid=$id";
    my $request = new HTTP::Request( GET =>  $url );

    my $response = $self->useragent->request($request);
    my $info = decode_json $response->content;

    $self->subject($info->{subject});
    $self->sender($info->{user_from}->{id});
    $self->message_type($info->{message_type} // $info->{type});
    $self->text($info->{text});

    if ($self->message_type eq 'INVITATION') {
        return unless defined $info->{game_settings};
        $self->boardsize($info->{game_settings}->{size});
        $self->handicap($info->{game_settings}->{calc_handicap});
        $self->weekend_clocked($info->{game_settings}->{time_weekend_clock});
        $self->komi($info->{game_settings}->{calc_komi});
        for my $field (qw/opp_started_games time_mode time_main time_byo time_periods 
            rated ruleset handicap_type game_type/) {
            $self->$field($info->{game_settings}->{$field});
        }
    }

    # Trying to fix undefined value warnings that I can't find... 01OCT2012
    $self->handicap(0) if not defined $self->handicap;
    $self->handicap_type("undef") if not defined $self->handicap_type;
}

sub accept_game {
    my ($self, $msg) = @_;
    $self->_process_msg('accept_inv', $msg);
}

# Reject a game, with message
sub reject_game {
    my ($self, $msg) = @_;
    $self->_process_msg('decline_inv', $msg);
}

# Deletes a message
sub delete {
    my ($self) = @_;
    my $mid = $self->num_id;
    $self->useragent->do_quick("obj=message&cmd=delete_msg&mid=$mid");
}

# Accepts/rejects an invite (private API)
sub _process_msg {
    my ($self, $cmd, $msg) = @_;

    my $id = $self->num_id;
    my $url = $self->useragent->url . "/quick_do.php?obj=message&cmd=$cmd&mid=$id&msg=$msg";
    my $request = new HTTP::Request( GET =>  $url );
    my $response = $self->useragent->request($request);
    
    return 1;
}

1;

