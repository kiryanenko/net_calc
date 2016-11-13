package Local::TCP::Calc::Server;

use strict;
use Local::TCP::Calc;
use Local::TCP::Calc::Server::Queue;
use Local::TCP::Calc::Server::Worker;
use JSON::XS;
use POSIX;
use IO::Socket;
use FindBin;
use DDP;
require "$FindBin::Bin/../lib/Local/Calculator/evaluate.pl";
require "$FindBin::Bin/../lib/Local/Calculator/rpn.pl";

use 5.010;
BEGIN{
	if ($] < 5.018) {
		package experimental;
		use warnings::register;
	}
}
no warnings 'experimental';

my $max_worker;
my $in_process = 0;

my $pids_master = {};
my $receiver_count = 0;
my $max_forks_per_task = 0;
my $max_queue_task = 0;

sub REAPER {
	# Функция для обработки сигнала CHLD
	while( my $pid = waitpid(-1, WNOHANG)) {
		last if $pid == -1;
		if( WIFEXITED($?) ){
			$receiver_count--;
		}
	}
};
$SIG{CHLD} = \&REAPER;

sub start_server {
	my ($pkg, $port, %opts) = @_;
	$max_queue_task     = $opts{max_queue_task} // die "max_queue_task required"; 
	$max_worker         = $opts{max_worker} // die "max_worker required"; 
	$max_forks_per_task = $opts{max_forks_per_task} // die "max_forks_per_task required";
	my $max_receiver    = $opts{max_receiver} // die "max_receiver required"; 
	
	# Инициализируем сервер my $server = IO::Socket::INET->new(...);
	my $server = IO::Socket::INET->new(
		LocalPort => $port,
		Type      => SOCK_STREAM,
		ReuseAddr => 1,
		Listen    => 10
	) or die "Can't create server on port $port : $@ $/";
	
	# Инициализируем очередь my $q = Local::TCP::Calc::Server::Queue->new(...);
	my $q = Local::TCP::Calc::Server::Queue->new( max_task => $max_queue_task);
	$q->init();
	check_queue_workers($q);
warn "________________start_____________________";	
	# Начинаем accept-тить подключения
	while (my $client = $server->accept()) {
		my $child;
warn "________________accept_____________________";
		eval {
			# Проверяем, что количество принимающих форков не вышло за пределы допустимого ($max_receiver)
			if ($receiver_count < $max_receiver) {
				if ($child = fork()) {
					$receiver_count++;
				}
				if (defined $child) {
					close($server);
					$client->autoflush(1);
					my $result;
					
					# В каждом форке читаем сообщение от клиента, анализируем его тип (TYPE_START_WORK(), TYPE_CHECK_WORK()) 
					# Не забываем проверять количество прочитанных/записанных байт из/в сеть
warn "____________read type___________";
					my $type = Local::TCP::Calc::read_type($client);
warn "____________type___________";		
p $type;
					given ($type) {
						when (Local::TCP::Calc::TYPE_START_WORK) {
							# Если необходимо добавляем задание в очередь (проверяем получилось или нет)						
							my @tasks = Local::TCP::Calc::read_messages($client);
							my $id = $q->add(\@tasks);
							die "Очередь переполнена" unless defined $id;
							$result = Local::TCP::Calc::pack_id($id);
						}
						when (Local::TCP::Calc::TYPE_CHECK_WORK) {
							# Если пришли с проверкой статуса, получаем статус из очереди и отдаём клиенту
							my $id = Local::TCP::Calc::read_id $client;
							my ($status, $msg) = $q->get_status($id);
							
							$result = Local::TCP::Calc::pack_status $status;
							given ($status) {
								when ([Local::TCP::Calc::STATUS_NEW(), Local::TCP::Calc::STATUS_WORK()]) {
									$result .= Local::TCP::Calc::pack_time $msg;
								}
								when ([Local::TCP::Calc::STATUS_DONE(), Local::TCP::Calc::STATUS_ERROR()]) {
									# В случае если статус DONE или ERROR возвращаем на клиент содержимое файла с результатом выполнения
									open(my $fh, '<', $msg) or die "Can't open < $msg: $!";
									$/ = undef;
									my $json = <$fh>;
									$/ = "\n";
									my %answers = JSON::XS::decode_json($json);
									close $fh;
									
									my @res;
									while (my ($key, $value) = each %answers) {
										$res[$key] = $value;
									}
									
									$result .= Local::TCP::Calc::pack_messages \@res;
									# После того, как результат передан на клиент зачищаем файл с результатом
									$q->delete($id);
									unlink($msg);
								}
								default { die "Неизвестная ошибка статуса" }
							}
						}
						default { die "Неизвестный тип подключения" }
					}
					# Если все нормально отвечаем клиенту TYPE_CONN_OK() в противном случае TYPE_CONN_ERR()
p $result;
					Local::TCP::Calc::input( $client, Local::TCP::Calc::TYPE_CONN_OK(), \$result );
				} else { die "Can't fork: $!"; }
			} else {
				# Когда форки закончились, отправляем сообщение об ошибке
				die 'Количество принимающих форков вышло за пределы допустимого';
			}
		1} or do { 
			my $msg = Local::TCP::Calc::pack_message("Error: $@");
p $msg;
			Local::TCP::Calc::input( $client, Local::TCP::Calc::TYPE_CONN_ERR(), \$msg );
		};
		#close ($client);
		exit if !$child && defined $child;
	}
}

sub check_queue_workers {
	my $q = shift;
	# Функция в которой стартует обработчик задания
	# Должна следить за тем, чтобы кол-во обработчиков не превышало мексимально разрешённого ($max_worker)
	# Но и простаивать обработчики не должны
	for (1..$max_worker) {
		unless (my $pid = fork) {
			die "Can't fork $!" unless defined $pid;
			
			while (1) {
				my ($id, $tasks) = $q->get;
				if (defined $id) {
					my $filename = "$id-".time;
	
					my $worker = Local::TCP::Calc::Server::Worker->new(
						calc_ref => sub { 
							my $ex = shift;
							my $rpn = rpn($ex);
							return evaluate($rpn); 
						},
						max_forks => $max_forks_per_task,
						filename => $filename
					);
	
					$q->to_work($tasks);
	
					if ($worker->start($tasks, 1200+$_)) { $q->to_err($id, $filename);} 
					else { $q->to_done($id, $filename); }
				}
			}
			exit;
		}
	}	
}

1;
