
use warnings;
use strict;
use Test::More;
use Log::Log4perl qw(:easy);
use Pogo::Util::Bucketeer;

# three groups of hosts in the sequence, but no hosts in the 
# middle tier

my $nof_tests = 6;

plan tests => $nof_tests;

BEGIN {
    use FindBin qw( $Bin );
    use lib "$Bin/lib";
    use PogoTest;
}

use Pogo::Scheduler::Classic;
my $scheduler = Pogo::Scheduler::Classic->new();

my $cv = AnyEvent->condvar();

$scheduler->config_load( \ <<'EOT' );
tag:
  colo:
    one:
      - host1
      - host2
      - host3
    two:
      - host4
      - host5
      - host6
    three:
      - host7
      - host8
      - host9
sequence:
  - $colo.one
  - $colo.two
  - $colo.three
EOT
 
my $bck = Pogo::Util::Bucketeer->new(
    buckets => [
  [ qw( host1 host2 host3 ) ],
  [ qw( host7 host8 host9 ) ],
] );

my @timers = ();

$scheduler->reg_cb( "task_run", sub {
    my( $c, $task ) = @_;

    my $host = $task->{ host };

    ok $bck->item( $host ), "host $host in seq";

    my $w = AnyEvent->timer( after => 0.1, cb => sub {
          # Crunch, crunch, crunch. Task done. Report back.
        DEBUG "Sending task_mark_done for task $task back to scheduler";
        $scheduler->event( "task_mark_done", $task );
    } );

    push @timers, $w;

    $bck->all_done and $cv->send(); # quit
} );

  # schedule all hosts
$scheduler->schedule( [ map { "host$_" } qw( 9 8 7 1 2 3 ) ] );

$cv->recv;
