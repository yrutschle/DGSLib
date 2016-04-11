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

package DGSQClient;

use strict;
use Moose;
extends 'LWPThrottled';


use JSON;

use HTTP::Cookies;
use LWPThrottled;
use HTML::TreeBuilder;
use HTML::Form;
use DGSQBoard;
use DGSQMessage;
use DGSQUser;
use Carp;
use Encode;
use utf8;

use Data::Dumper;

has login  => ( is => 'rw', isa => 'Str' );
has passwd => ( is => 'rw', isa => 'Str' );
has verbose => ( is => 'rw', isa => 'Bool' );
has cookiefile => ( is => 'rw', isa => 'Str' );
has url => (is => 'rw', isa => 'Str' );

# Contains the 'quick_status', used to get messages and games
has status => (is => 'rw', isa => 'Str');

# Logs in. Caller can override login and passwd
# do_login needs to be called prior to making any calls that require the user
# object
sub do_login {
    my ($self, $login, $passwd) = @_;
    my ($cookie_jar, $request, $response);

    $self->login = $login if defined $login;
    $self->passwd = $passwd if defined $passwd;
    my $verbose = $self->verbose;

    my $cookie_file = $self->cookiefile;
    if (-e $cookie_file) {
        my $mode = (stat $cookie_file)[2];
        croak "$cookie_file must be 0600" if (($mode&0777) != 0600);

        $cookie_jar = HTTP::Cookies->new;
        $cookie_jar->load($cookie_file);
        croak "$cookie_file: $!" unless defined $cookie_jar;
        $self->cookie_jar($cookie_jar);
    } 

    my $res = $self->_get_status;

    # If an error happened, it's probably because we're not logged in
    # (the cookies expired or something).
    if (not defined $res) {
        warn "loggin in..\n" if $verbose;
        my $response = $self->do_http("login.php?quick_mode=1&userid=".$self->login."&passwd=".$self->passwd);

        # Get login cookies
        $cookie_jar = HTTP::Cookies->new;
        $cookie_jar->extract_cookies($response);
        $cookie_jar->save($self->cookiefile);

        $self->cookie_jar($cookie_jar);
        chmod 0600, $self->cookiefile;
        
        if ($response->content =~ /wrong_password/) {
            die "wrong password";
            return undef;
        }

        $self->_get_status;
    }

    if (not defined $self->status) {
        die "Error getting status";
    }

    return 1;
}

sub _get_status {
    my ($self) = @_;

    # get the status page
    my $response = $self->do_http('quick_status.php?version=2&order=0');

    return undef if not defined $response;

    warn $response->as_string if $self->verbose;

    return undef if $response->as_string =~ /Error/;

    $self->status($response->as_string);
}


=item my_turn

Returns a list of DGS::Board objects containing all the games for which the
connected player has to play.

=cut
sub my_turn {
    my ($self) = @_;
    my ($request, $response, @out, @param_names);

    foreach my $line (split /\n/, $self->status) {
        # Use the names of parameters from the output stream to populate a hash
        # with the game's parameters (pretty cool, auto-adapts to shifting
        # specifications!)
        @param_names = split /,/, $line if $line =~ /^## G/;
        next unless $line =~ /^G/;
        my $i = 0;
        my %game = map { $param_names[$i++] => $_ } split /,/, $line;

        my $g = DGSQBoard->new(
            id => $game{game_id},
            loader => $self,
            verbose => $self->verbose,
        );
        push @out, $g;
    }
    return @out;
}

# Return a list of all messages
sub messages {
    my ($self) = @_;
    my ($request, $response, @out, @param_names);

    foreach my $line (split /\n/, $self->status) {
        @param_names = split /,/, $line if $line =~ /## M/;
        next unless $line =~ /^M/;
        my $i = 0;
        my %msg = map { $param_names[$i++] => $_ } split /,/, $line;

        push @out, DGSQMessage->new(
            num_id => $msg{message_id},
            useragent => $self
        );

        $out[-1]->load_info;
    }
    return @out;
}

# Generic HTTP request (prints error message)
# Returns HTTP response, undef on error
sub do_http {
    my ($self, $rq) = @_;

    my $str = $self->url . "/$rq";
    warn "$str\n" if $self->verbose;
    my $request = new HTTP::Request(GET => $str);

    my $response = $self->request($request);
    if (not $response->is_success) {
        warn "$rq: HTTP error ".$response->status_line."\n";
        return undef;
    }
    return $response;
}

# Perform a 'quick_do': HTTP request, process HTTP response, extract and
# process JSON output or undef if error
sub do_quick {
    my ($self, $rq) = @_;

    my $response = $self->do_http("quick_do.php?$rq");

    return unless defined $response;

    my $json;
    eval { $json = decode_json $response->content };
    if (not defined $json) {
        warn "$rq: Unable to parse response `".$response->content."' as JSON\n";
        return undef;
    }

    if ($json->{error}) {
        warn "$rq: Error $json->{error} ($json->{error_msg})\nFull response:\n".
             $response->content;
    }

    return $json;
}


1;

