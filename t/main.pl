use FindBin;
use lib "$FindBin::Bin/../lib";
use Local::TCP::Calc;
use Local::TCP::Calc::Client;
use Local::TCP::Calc::Server;
use DDP;
use IO::Socket;

my $sock = IO::Socket::INET->new(
		Type      => SOCK_STREAM,
		ReuseAddr => 1,
		Listen    => 10
	) or die "Can't create server on port : $@ $/";
my $port = $sock->sockport();
close($sock);
print("Listening to port $port.\n");


unless (fork) {
Local::TCP::Calc::Server->start_server($port, max_queue_task => 5, max_worker => 3, max_forks_per_task => 8, max_receiver => 2);
exit;
}
sleep 2;
my $srv = Local::TCP::Calc::Client->set_connect('127.0.0.1', $port);
my @a = Local::TCP::Calc::Client->do_request($srv, Local::TCP::Calc::TYPE_START_WORK(), ['1+2','2+3']);
p @a;
