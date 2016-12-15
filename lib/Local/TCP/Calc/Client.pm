package Local::TCP::Calc::Client;

use strict;
use IO::Socket;
use Local::TCP::Calc;
use 5.010;
use DDP;
BEGIN{
	if ($] < 5.018) {
		package experimental;
		use warnings::register;
	}
}
no warnings 'experimental';

sub set_connect {
	my $pkg = shift;
	my $ip = shift;
	my $port = shift;
	
	
	# read header before read message
	# check on Local::TCP::Calc::TYPE_CONN_ERR();
	my $server = IO::Socket::INET->new(
		PeerAddr => $ip,
		PeerPort => $port,
		Proto => "tcp",
		Type => SOCK_STREAM
	) or die "Ошибка подключения $!";
	if (Local::TCP::Calc::read_type($server) == Local::TCP::Calc::TYPE_CONN_ERR) {
		die "Ошибка: " . Local::TCP::Calc::read_message($server);
	}
	return $server;
}

sub do_request {
	my $pkg = shift;
	my $server = shift;
	my $type = shift;
	my $messages = shift;
	my @res;
	return 0 unless $server and $server->connected;
	# Проверить, что записанное/прочитанное количество байт равно длинне сообщения/заголовка
	# Принимаем и возвращаем перловые структуры
	my $msg;
	given ($type) {
		when (Local::TCP::Calc::TYPE_START_WORK) { $msg = Local::TCP::Calc::pack_messages($messages); }
		when (Local::TCP::Calc::TYPE_CHECK_WORK) { $msg = Local::TCP::Calc::pack_id($messages); }
	}
	Local::TCP::Calc::input( $server, $type, \$msg );
	
	if (Local::TCP::Calc::read_type($server) == Local::TCP::Calc::TYPE_CONN_OK) {
		given ($type) {
			when (Local::TCP::Calc::TYPE_START_WORK) { 
				push @res, Local::TCP::Calc::read_id $server; 
			}
			when (Local::TCP::Calc::TYPE_CHECK_WORK) { 
				my $status = $msg = Local::TCP::Calc::read_status $server;
				given ($status) {
					when ([Local::TCP::Calc::STATUS_NEW(), Local::TCP::Calc::STATUS_WORK()]) {
						push @res, Local::TCP::Calc::read_time $server;
					}
					when ([Local::TCP::Calc::STATUS_DONE(), Local::TCP::Calc::STATUS_ERROR()]) {
						push @res, Local::TCP::Calc::read_messages $server;
					}
				}
			}
		}
	} else {
		return 0;
	}
	close $server;
	
	return @res;
}

1;

