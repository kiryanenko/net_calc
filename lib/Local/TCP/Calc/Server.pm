package Local::TCP::Calc::Server;

use strict;
use Local::TCP::Calc;
use Local::TCP::Calc::Server::Queue;
use Local::TCP::Calc::Server::Worker;

my $max_worker;
my $in_process = 0;

my $pids_master = {};
my $receiver_count = 0;
my $max_forks_per_task = 0;

my $header_size = Local::TCP::Calc::HEADER_SIZE;
my $len_msg_size = Local::TCP::Calc::LEN_MSG_SIZE;

sub REAPER {
	
	# Функция для обработки сигнала CHLD
};
$SIG{CHLD} = \&REAPER;

sub start_server {
	my ($pkg, $port, %opts) = @_;
	$max_worker         = $opts{max_worker} // die "max_worker required"; 
	$max_forks_per_task = $opts{max_forks_per_task} // die "max_forks_per_task required";
	my $max_receiver    = $opts{max_receiver} // die "max_receiver required"; 
	
	# Инициализируем сервер my $server = IO::Socket::INET->new(...);
	my $server = IO::Socket::INET->new(
		LocalPort => $port,
		Type      => SOCK_STREAM,
		ReuseAddr => 1,
		Listen    => 10) 
	or die "Can't create server on port $port : $@ $/";
	
	# Инициализируем очередь my $q = Local::TCP::Calc::Server::Queue->new(...);
	my $q = Local::TCP::Calc::Server::Queue->new();
  	
	$q->init(\check_queue_workers);
	
	# Начинаем accept-тить подключения
	while (my $client = $server->accept()) {
		# Проверяем, что количество принимающих форков не вышло за пределы допустимого ($max_receiver)
		if ($receiver_count < $max_worker) {
			my $child = fork();
			if ($child) {
				$receiver_count++;
			}
			if (defined $child) {
				close($server);
				$client->autoflush(1);
				# Если все нормально отвечаем клиенту TYPE_CONN_OK() в противном случае TYPE_CONN_ERR()
				my $header;
				Local::TCP::Calc::pack_header(\$header, Local::TCP::Calc::TYPE_CONN_OK, 0);
				syswrite $client, $header;
				
				# В каждом форке читаем сообщение от клиента, анализируем его тип (TYPE_START_WORK(), TYPE_CHECK_WORK()) 
				# Не забываем проверять количество прочитанных/записанных байт из/в сеть
				my $type;
				die 'Не удалось прочесть заголовок' unless 
					sysread($client, $header, $header_size) == $header_size;
				my $size;
				my $type = Local::TCP::Calc::unpack_header($header, $size);
				
				given ($type) {
					when (Local::TCP::Calc::TYPE_START_WORK) {
						# Если необходимо добавляем задание в очередь (проверяем получилось или нет)						
						my @tasks;
						for (my $i = 0; $i < $size; $i++) {
							push @tasks, Local::TCP::Calc::read_message($client);
						}
						
						my $id = $q->add \@tasks
						
						my $msg = pack 'I', $id;
						Local::TCP::Calc::pack_header(\$header, 
							Local::TCP::Calc::STATUS_NEW, length $msg);
						syswrite $client, $header.$msg;
					}
					when (Local::TCP::Calc::TYPE_CHECK_WORK) {
						# Если пришли с проверкой статуса, получаем статус из очереди и отдаём клиенту
						my $pkg;
						die 'Не удалось прочесть длину сообщения' unless 
								sysread($client, $pkg, $size) == $size;
						my $id = unpack 'I', $pkg;
						
						my ($status, $msg) = $q->get_status $id;
						given ($status) {
							when ([Local::TCP::Calc::STATUS_NEW, Local::TCP::Calc::STATUS_WORK]) {
								my $pkg = pack 'L', $msg;
								Local::TCP::Calc::pack_header(\$header, $status, length $pkg);
								syswrite $client, $header.$pkg;
							}
							when ([Local::TCP::Calc::STATUS_DONE, Local::TCP::Calc::STATUS_ERROR]) {
								# В случае если статус DONE или ERROR возвращаем на клиент содержимое файла с результатом выполнения
								my $pkg;
								Local::TCP::Calc::pack_message(\$pkg, $msg);
								Local::TCP::Calc::pack_header(\$header, $status, scalar @$msg);
								syswrite $client, $header.$pkg;
								# После того, как результат передан на клиент зачищаем файл с результатом
							
							}
						}
					}
				}
				
				close( $client );
				exit;
				# $receiver_count--
			} else { die "Can't fork: $!"; }
		} else {
			# Когда форки закончились, отправляем сообщение об ошибке
			my $msg = pack 'a*', 'Количество принимающих форков вышло за пределы допустимого';
			syswrite $client, Local::TCP::Calc::pack_header($msg, 
				Local::TCP::Calc::TYPE_CONN_ERR, length $msg);
		}
		close ($client);
	}
}

sub check_queue_workers {
	my $self = shift;
	#my $q = shift;
	
	# Функция в которой стартует обработчик задания
	# Должна следить за тем, что бы кол-во обработчиков не превышало мексимально разрешённого ($max_worker)
	# Но и простаивать обработчики не должны
	my $worker = Local::TCP::Calc::Server::Worker->new(...);
	$worker->start(...);
	$self->to_done
}

1;
