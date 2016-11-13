use FindBin;
use lib "$FindBin::Bin/../lib";
use Local::TCP::Calc;
use Local::TCP::Calc::Client;
use Local::TCP::Calc::Server;

unless (fork) {
Local::TCP::Calc::Server->start_server(1235, max_queue_task => 5, max_worker => 3, max_forks_per_task => 8, max_receiver => 2);
}
sleep 2;
my $srv = Local::TCP::Calc::Client->set_connect('127.0.0.1', 1235);
Local::TCP::Calc::Client->do_request($srv, Local::TCP::Calc::TYPE_START_WORK(), [1+2,2+3]);
