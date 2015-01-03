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

package DGSQUser;

use strict;
use Carp;
use Moose;

has id => (is => 'rw', isa => 'Int', required => 1 );
has userid => (is => 'rw', isa => 'Str' );
has name => (is => 'rw', isa => 'Str' );
has useragent => (is => 'rw', isa => 'LWPThrottled' );
has verbose => (is => 'rw', isa => 'Bool' );
has refreshed => (is => 'rw', isa => 'Bool' );


1;
