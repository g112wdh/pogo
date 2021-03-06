package Pogo::Client::Commandline;

use common::sense;

use Data::Dumper;

use Getopt::Long qw(:config bundling no_ignore_case pass_through);
use JSON qw(encode_json decode_json);
use Log::Log4perl qw(:easy);
use Log::Log4perl::Level;
use Pod::Find qw(pod_where);
use Pod::Usage qw(pod2usage);
use POSIX qw(strftime);
use Sys::Hostname qw(hostname);
use Time::HiRes qw(gettimeofday tv_interval);

use Pogo::Client;

use constant POGO_GLOBAL_CONF => '/usr/local/etc/pogo/client.conf';
use constant POGO_USER_CONF   => $ENV{ HOME } . '/.pogoconf';

sub run_from_commandline {
    my $class = shift;

    # get basics on how we were invoked
    my $self = {
        epoch      => [ gettimeofday ],
        invoked_as => quote_array( " ", $0, @ARGV ),
        userid     => scalar getpwuid( $< ),
    };

    bless $self, $class;

    # determine command
    my $cmd = $self->process_options
        or $self->cmd_usage;

    DEBUG 'API: ' . $self->{ api };
    DEBUG "command: $cmd";
    DEBUG "global options set:\n\t"
        . join( "\n\t",
        map { "$_: " . $self->{ opts }->{ $_ } } keys %{ $self->{ opts } } );

    $self->{ api } = delete $self->{ opts }->{ api };

    my $method = 'cmd_' . $cmd;
    if ( !$self->can( $method ) ) {
        die "no such command: $cmd\n";
    }

    return $self->$method;
}

sub cmd_ping {
    my ( $self ) = @_;

    my $elapsed = tv_interval( $self->{ epoch }, [ gettimeofday ] );

    my $resp         = $self->_client()->ping( 'pong' );
    my $decoded_data = $self->decode_api_response( $resp );

    if ( !defined $decoded_data ) {
        return 1;
    } elsif ( !$decoded_data->{ response } ) {
        printf "ERROR %s: no 'response' element in HTTP Response\n",
            $self->{ api };
        return 1;
    } elsif ( !$decoded_data->{ response }->{ ping } ) {
        printf "ERROR %s: no 'ping' in response data\n", $self->{ api };
        return 1;
    } elsif ( $decoded_data->{ response }->{ ping } ne 'pong' ) {
        printf "ERROR %s: expected 'pong' in response, got '%s'\n",
            $decoded_data->{ response }->{ ping };
        return 1;
    }

    printf "OK %s %0dms\n", $self->{ api }, $elapsed * 1000;
    return 0;
}

sub cmd_status {
    my ( $self ) = @_;
    my $jobid = shift @ARGV;

    my $resp         = $self->_client()->get_job( $jobid );
    my $decoded_data = $self->decode_api_response( $resp );

    if ( !defined $decoded_data ) {
        return 1;
    }

    print Dumper( $decoded_data )
        ;    # TODO figure out actual format for status command
    return 0;
}

sub cmd_jobs {
    my ( $self, $args ) = @_;

    GetOptions( my $cmdline_opts = {}, 'max=i', 'offset=i' );

    DEBUG "'jobs' command options:\n\t"
        . join( "\n\t",
        map { "$_: " . $cmdline_opts->{ $_ } } keys %{ $cmdline_opts } );

    my $resp         = $self->_client()->listjobs( $cmdline_opts );
    my $decoded_data = $self->decode_api_response( $resp );

    if ( !defined $decoded_data ) {
        return 1;
    }

    print Dumper( $resp );    # TODO: figure out actual format for jobs command
    return 0;
}

sub process_options {
    my ( $self ) = @_;

    my $command;
    my $opts         = {};
    my $cmdline_opts = {};

    # first, process global options and see if we have an alt config file
    GetOptions( $cmdline_opts, 'help|?', 'api=s', 'configfile|c=s', 'debug', );

    Log::Log4perl::get_logger->level( $DEBUG )
        if $cmdline_opts->{ debug };

    $self->cmd_usage
        if $cmdline_opts->{ help };

    # our next @ARGV should be our command
    $command = shift @ARGV || return;
    if ( $command =~ m/^-/ ) {
        ERROR "Unknown option: $command";
        return;
    }

    # deal with config file options (possibly specified on command line)
    $opts->{ configfile } ||= $cmdline_opts->{ configfile };
    $opts->{ configfile } ||= POGO_GLOBAL_CONF;

    # start $opts based on what's in global config file ( YAML::LoadFile() )
    # overwrite with user config file ( YAML::LoadFile() )
    # finally overwrite with commandline opts

    $opts = $cmdline_opts;      # XXX TEMPORARY
    $self->{ opts } = $opts;    # XXX TEMPORARY

    return $command;
}

sub cmd_help {
    return cmd_man();
}

sub cmd_man {
    return pod2usage(
        -verbose => 2,
        -exitval => 0,
        -input   => pod_where( { -inc => 1, }, __PACKAGE__ ),
    );
}

sub cmd_usage {
    my $self = shift;
    return pod2usage(
        -verbose  => 99,
        -exitval  => shift || 1,
        -sections => 'USAGE|MORE INFO',
        -input    => pod_where( { -inc => 1 }, __PACKAGE__ ),
    );
}

sub decode_api_response {
    my ( $self, $http_response ) = @_;

    my $decoded_data = eval 'decode_json $http_response->content';

    if ( $@ ) {
        # problem decoding JSON
        printf "ERROR %s: %s HTTP status: %s\n", $self->{ api }, $@,
            $http_response->status_line;
        return undef;

    } elsif ( !$http_response->is_success ) {
        # JSON was returned, but the API responded with error(s)
        my $errors = join( "\n\t", @{ $decoded_data->{ errors } } );
        printf "ERROR(S) %s: %s\n\t%s\n", $self->{ api },
            $http_response->status_line,
            $errors;
        return undef;
    }

    return $decoded_data;
}

sub quote_array {
    my ( $sep, @array ) = @_;
    foreach my $elem ( @array ) {
        if ( $elem !~ m/^[a-z0-9+_\.\/-]+$/i ) {
            $elem = "'$elem'";
        }
    }
    my $str .= join( $sep, @array );
    $str .= $sep;
    return $str;
}

sub merge_hash {
    my ( $onto, $from ) = @_;

    while ( my ( $key, $value ) = each %$from ) {
        if ( defined $onto->{ $key } ) {
            DEBUG sprintf "Overwriting key '%s' with '%s', was '%s'", $key,
                $value, $onto->{ $key };
        }
        $onto->{ $key } = $value;
    }

    return $onto;
}

sub _client {
    my ( $self ) = @_;
    if ( !defined $self->{ pogoclient } ) {
        $self->{ pogoclient } = Pogo::Client->new( $self->{ api } );
        Log::Log4perl->get_logger( "Pogo::Client" )->level( $DEBUG )
            if ( $self->{ opts }->{ debug } );
    }

    return $self->{ pogoclient };
}

sub to_jobid {
    my ( $self, $jobid ) = @_;
    my $new_jobid = $jobid;
    # TODO
    return $new_jobid;
}

1;
