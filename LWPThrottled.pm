# LWPThrottled: A rate-limiting LWP
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

package LWPThrottled;

use strict;

# overloads LWP::UserAgent->request to limit the number of accesses
use Moose;
extends 'LWP::UserAgent';

# Settings specific to DGS;
# there should be accessors for these to make LWPThrottled more generic...
    #  less than 400 request an hour
    my $PERIOD = 3600;
    my $MAX_PER_PERIOD = 400;

    # if URL contain any of these, don't throttle
    my @NO_QUOTA = ('sgf', 'quick_status');
# /Settings

my $data_file;

sub throttle_file {
    $data_file = $_[1];
    open my $f, "> $data_file" unless -e $data_file;
}

use Data::Dumper;

sub request {
    my ($class, @params) = @_;

    open my $f, $data_file or die "$data_file: $!\n";
    my @times = <$f>;

    # If the URI requested doesn't match NO_QUOTA expressions, throttle the
    # access
    unless (grep { $params[0]->uri =~ /$_/ } @NO_QUOTA) {
        my $time;
        do {
            $time = time;
            # Remove entries that have expired
            @times = map { $_->[1] }
            grep { $_->[0] > $time - $PERIOD } 
            map { [(split / /,$_)[0], $_] } @times;
            if ((scalar @times) > $MAX_PER_PERIOD) {
                my $sleep = (split / /,$times[0])[0] - ($time - $PERIOD);
#            warn "asleep for $sleep seconds\n";
                sleep ($sleep);
            }
        } while ((scalar @times) > $MAX_PER_PERIOD);

        $time = time;
        push @times, "$time (".(scalar gmtime).") ".$params[0]->uri."\n";
        open $f, "> $data_file" or die "$data_file: $!\n";
        print $f @times;
        close $f;
    }

    $class->SUPER::request(@params);
}

1;
