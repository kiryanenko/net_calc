package Local::TCP::Calc::Server::Worker;

use strict;
use warnings;
use Mouse;
use Local::TCP::Calc;
use JSON::XS;
use POSIX;
use IO::Socket::INET;
use DDP;
use Fcntl qw (:flock);

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
	$self->error(1);
	$self->write_res($i, $error);
}

sub write_res {
	my $self = shift;
	my $i = shift;
	my $res = shift;


	# Записываем результат выполнения задания
	open(my $fh, '+<', $self->filename) or die "Can't open +< ".$self->filename.": $!";
	flock($fh, LOCK_EX) or die "can't flock: $!";
	$/ = undef;
	my $json = <$fh>;
	$/ = "\n";
	my $results = JSON::XS::decode_json($json);
	$results->{$i} = $res;
	seek $fh, 0, 0;
	print $fh JSON::XS::encode_json($results);
	truncate($fh, tell($fh));
	close $fh;
}

sub child_fork {
	my $self = shift;
	
	# Обработка сигнала CHLD, не забываем проверить статус завершения процесс и при надобности убить оставшихся
	while( my $pid = waitpid(-1, WNOHANG)) {
		last if $pid == -1;
		if( WIFEXITED($?) ){
			if ($? > 0) {
				$self->error(1);
				for (keys $self->forks) { 
					system("kill $_"); 
					delete $self->forks->{$_};	
				}				
			}
		}
	}
}

sub start {
	my $self = shift;
	my $tasks = shift;
	
	my $cnt = scalar @$tasks;
	
	$SIG{CHLD} = $self->child_fork;
	
	# Создаю пустой filename
	open(my $fh, '>', $self->filename) or die "Can't open > ".$self->filename.": $!";
	print $fh JSON::XS::encode_json({});
	close $fh;
	
	# расчитываем сколько заданий приходится на 1 обработчик
    my $cnt_per_proc = Local::TCP::Calc::ceil(1.0 * $cnt / $self->max_forks);
	# Начинаем выполнение задания. Форкаемся на нужное кол-во форков для обработки массива примеров
	for (my $i = 0; $i < $self->max_forks && $i < $cnt; $i++) {
		if (my $pid = fork()) {
			$self->forks->{$pid} = $pid;
		} else {
			die "Cannot fork $!" unless defined $pid;
			# Дочерний процесс
			for (my $j = $i * $cnt_per_proc; ($j < $cnt_per_proc * ($i + 1)) && ($j < $cnt); $j++) {
				my $ex = $$tasks[$j];
				eval {					
					my $res = $self->calc_ref->($ex);
					# В форках записываем результат в файл, не забываем про локи, чтобы форки друг другу не портили результат
					$self->write_res($j, "$ex == $res");
				1} or do { 
					$self->write_err($j, "$ex == NaN");
				};
			}
			exit;
		}
	}
	# Вызов блокирующий, ждём  пока не завершатся все форки
	while ( my $pid = waitpid(-1, 0) ) { last if $pid == -1; }
	return $self->error;
}


no Mouse;
__PACKAGE__->meta->make_immutable();

1;
