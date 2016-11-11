package Local::TCP::Calc::Server::Worker;

use strict;
use warnings;
use Mouse;
use Local::TCP::Calc;

has cur_task_id => (is => 'ro', isa => 'Int', required => 1);
has forks       => (is => 'rw', isa => 'HashRef', default => sub {return {}});
has calc_ref    => (is => 'ro', isa => 'CodeRef', required => 1);
has max_forks   => (is => 'ro', isa => 'Int', required => 1);

my $len_msg_size = Local::TCP::Calc::LEN_MSG_SIZE;

sub write_err {
	my $self = shift;
	my $error = shift;
	...
	# Записываем ошибку возникшую при выполнении задания
}

sub write_res {
	my $self = shift;
	my $res = shift;
	...
	# Записываем результат выполнения задания
}

sub child_fork {
	my $self = shift;
	...
	# Обработка сигнала CHLD, не забываем проверить статус завершения процесс и при надобности убить оставшихся
}

sub start {
	my $self = shift;
	my $tasks = shift;
	
	my $port = 1234;
	
	# Создаю соккет через который дочерние процессы будут связываться с родителем
	my $server = IO::Socket::INET->new(
		LocalPort => $port,
		Type      => SOCK_STREAM,
		ReuseAddr => 1,
		Listen    => 10) 
	or die "Can't create server on port $port : $@ $/";

	
	# Начинаем выполнение задания. Форкаемся на нужное кол-во форков для обработки массива примеров
    my @pids;
	for (my $i = 0; $i < $self->max_forks; $i++) {
		if (my $pid = fork()) {
    		push @pids, $pid;
    	} else {
    		die "Cannot fork $!" unless defined $pid;
    		# Дочерний процесс
    	
    		my $socket = IO::Socket::INET->new(			# Подключаюсь к родителю
				PeerAddr => 'localhost',
				PeerPort => $port,
				Proto => "tcp",
				Type => SOCK_STREAM
			) or die "Can`t connect $/";
			
			while ($socket)
				# Читаю задачу от родителя
				my $len;
				die "Не могу прочесть размер сообщения" 
					unless sysread ($socket, $len, $len_msg_size) == $len_msg_size;	
				my $msg;	
				Local::TCP::Calc::unpack_message($pkg, \$msg);
				
					# Получаю ответ
					my $answer;
					die "Не могу прочесть размер сообщения" unless sysread($socket, $answer, 4) == 4;
					my $len = unpack 'L', $answer;
					die "Не могу прочесть сообщение" unless sysread($socket, $answer, $len) == $len;	
					# Записываю результат в файл	
					open(my $fh, ">>", $result_file) or die "Can't open >> $result_file: $!";
					syswrite($fh, pack('SL/a*', $j, $answer));
					close($fh);
					
					syswrite($w, pack('SS/a*', $$, 'done'));		# Передаю статус
					
					close $socket;
					
					my $socket = IO::Socket::INET->new(			# Подключаюсь к родителю
						PeerAddr => 'localhost',
						PeerPort => $port,
						Proto => "tcp",
						Type => SOCK_STREAM
					);
				
    		} while ()
    		exit;
    	}
	}
	
	# Отправляю детям задачи
	while(my $client = $server->accept() && @$tasks){
		my $child = fork();
		if($child){
			close ($client); next;
		}
		if(defined $child){
			close($server);
			$client->autoflush(1);
			syswrite $client, pack 'L/a*', shift @$tasks;
			close( $client );
			exit;
		} else { die "Can't fork: $!"; }
	}
	close $server;
	# Вызов блокирующий, ждём  пока не завершатся все форки
	# В форках записываем результат в файл, не забываем про локи, чтобы форки друг другу не портили результат
}

sub ceil($) { 
  	my $x = shift;
	return int($x) < $x ? int($x)+1 : $x
}

no Mouse;
__PACKAGE__->meta->make_immutable();

1;
