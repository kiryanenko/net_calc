package Local::TCP::Calc::Server::Worker;

use strict;
use warnings;
use Mouse;
use Local::TCP::Calc;
use JSON::XS;
use POSIX;
use IO::Socket;

use 5.010;
BEGIN{
	if ($] < 5.018) {
		package experimental;
		use warnings::register;
	}
}
no warnings 'experimental';

#has cur_task_id => (is => 'ro', isa => 'Int', required => 1);
has forks       => (is => 'rw', isa => 'HashRef', default => sub {return {}});
has error       => (is => 'rw', isa => 'Bool', default => sub {return ''});
has calc_ref    => (is => 'ro', isa => 'CodeRef', required => 1);
has max_forks   => (is => 'ro', isa => 'Int', required => 1);
has filename 	=> (is => 'ro', isa => 'Str', required => 1);

sub write_err {
	my $self = shift;
	my $i = shift;
	my $error = shift;
	
	# Записываем ошибку возникшую при выполнении задания
	$self->error = 1;
	write_res $i, $error;
}

sub write_res {
	my $self = shift;
	my $i = shift;
	my $res = shift;
	
	# Записываем результат выполнения задания
	open(my $fh, '+<', $self->filename) or die "Can't open +< ".$self->filename.": $!";
	flock($fh, 2);
	$/ = undef;
	my $json = <$fh>;
	my $results = JSON::XS::decode_json($json);
	$results->{$i} = $res;
	seek $fh, 0, 0;
	print $fh JSON::XS::encode_json($results);
	close $fh;
}

sub child_fork {
	my $self = shift;
	
	# Обработка сигнала CHLD, не забываем проверить статус завершения процесс и при надобности убить оставшихся
	while( my $pid = waitpid(-1, WNOHANG)) {
		last if $pid == -1;
		if( WIFEXITED($?) ){
			if ($? > 0) {
				$self->error = 1;
				for (keys $self->forks) { system("kill $_"); }				
			}
		}
	}
}

sub start {
	my $self = shift;
	my $tasks = shift;
	my $port = shift;
	
	my $i = 0;
	$SIG{CHLD} = $self->child_fork;
	
	# Создаю пустой filename
	open(my $fh, '>', $self->filename) or die "Can't open > ".$self->filename.": $!";
	print $fh JSON::XS::encode_json({});
	close $fh;

	# Создаю соккет через который дочерние процессы будут связываться с родителем
	my $server = IO::Socket::INET->new(
		LocalPort => $port,
		Type      => SOCK_STREAM,
		ReuseAddr => 1,
		Listen    => 10) 
	or die "Can't create server on port $port : $@ $/";

	# Начинаем выполнение задания. Форкаемся на нужное кол-во форков для обработки массива примеров
	for (; $i < $self->max_forks && $i < scalar @$tasks; $i++) {
		if (my $pid = fork()) {
			$self->forks->{$pid} = $pid;
		} else {
			die "Cannot fork $!" unless defined $pid;
			# Дочерний процесс
			close $server;
		
			my $socket = IO::Socket::INET->new(		# Подключаюсь к родителю
				PeerAddr => 'localhost',
				PeerPort => $port,
				Proto => "tcp",
				Type => SOCK_STREAM
			);
			
			while ($socket) {
				eval {
					# Читаю задачу от родителя
					my $i = Local::TCP::Calc::read_id $socket;
					my $ex = Local::TCP::Calc::read_message $socket;
			
					my $res = $self->calc_ref($ex);
					# В форках записываем результат в файл, не забываем про локи, чтобы форки друг другу не портили результат
					write_res $i, $res;
				1} or do { 
					write_err $i, $!;
				};
						
				close $socket;					
				$socket = IO::Socket::INET->new(	# Подключаюсь к родителю
					PeerAddr => 'localhost',
					PeerPort => $port,
					Proto => "tcp",
					Type => SOCK_STREAM
				);
			}
			exit;
		}
	}
	
	# Отправляю детям задачи
	my $n = scalar @$tasks;
	for( my $i = 0; $i < $n and my $client = $server->accept(); $i++ ) {
		my $child = fork();
		if ($child) { 
			close ($client); next;
		}
		if (defined $child) {
			close($server);
			$client->autoflush(1);
			syswrite $client, Local::TCP::Calc::pack_id($i);
			syswrite $client, Local::TCP::Calc::pack_message(@$tasks[$i]);
			close( $client );
			exit;
		} else { die "Can't fork: $!"; }
	}
	close $server;
	# Вызов блокирующий, ждём  пока не завершатся все форки
	while (waitpid(-1, 0)) {}
	return $self->error;
}

no Mouse;
__PACKAGE__->meta->make_immutable();

1;
