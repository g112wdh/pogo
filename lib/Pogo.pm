###########################################
package Pogo;
###########################################

use strict;
use warnings;

our $VERSION = "0.01";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        %options,
    };

    bless $self, $class;
}

1;

__END__

=head1 NAME

Pogo - Run commands on many hosts in a controlled manner

=head1 DESCRIPTION

Pogo is a highly scalable system for running arbitrary commands on 
many hosts in a controlled manner. 

It is mostly used for quick mass software deployments on server farms while
making sure only an allowed number of nodes are upgraded in parallel to
ensure business continuity.

=head1 LICENSE

Copyright (c) 2010-2012 Yahoo! Inc. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
imitations under the License.

=head1 AUTHORS

Mike Schilli <m@perlmeister.com>
Ian Bettinger <ibettinger@yahoo.com>
