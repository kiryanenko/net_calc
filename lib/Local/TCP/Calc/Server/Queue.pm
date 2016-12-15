package Local::TCP::Calc::Server::Queue;

use strict;
use warnings;

use Mouse;
use Local::TCP::Calc;
use JSON::XS;
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

#has f_handle       => (is => 'rw', isa => 'FileHandle');
has queue_filename => (is => 'ro', isa => 'Str', default => 'local_queue.log');
has max_task       => (is => 'rw', isa => 'Int', default => 0);

my $fh;

sub init {
	my $self = shift;
	
	# Подготавливаем очередь к первому использованию если это необходимо
	# Создаю пустой queue_filename
	$self->open(">");
	$self->close([]);
}

sub open {
	my $self = shift;
	my $open_type = shift;

	# Открваем файл с очередью, не забываем про локи, возвращаем содержимое (перловая структура)
	open($fh, $open_type, $self->queue_filename) 
		or die "Can't open $open_type ".$self->queue_filename.": $!";
	flock($fh, LOCK_EX) or die "can't flock: $!";
	# Считываю структуру из queue_filename
	if ($open_type ~~ ['<', '+<']) {
		$/ = undef;
	  	my $json = <$fh>;
		$/ = "\n";
#p $json;
		return JSON::XS::decode_json($json);
    }
}

sub close {
	my $self = shift;
	my $struct = shift;

	# Перезаписываем файл с данными очереди (если требуется), снимаем лок, закрываем файл.
	if (defined $struct) {
		seek $fh, 0, 0;
		print $fh JSON::XS::encode_json($struct);
		truncate($fh, tell($fh));
	}
	close $fh;
}

sub find_and_set {
	my $self = shift;
	my $id = shift;
	my $func = shift;
	
	my $res;
	my $queue = $self->open('+<');
	for (@$queue) {
		if ($_->{id} == $id) {
			$res = &$func(\$_);
			last;
		}
	}
	$self->close($queue);
	return $res;
}

sub to_done {
	my $self = shift;
	my $id = shift;
	my $file_name = shift;
	
	# Переводим задание в статус DONE, сохраняем имя файла с резуьтатом работы
	$self->find_and_set( $id, \sub {
		my $el = shift;
		$el->{status} = Local::TCP::Calc::STATUS_DONE;
		$el->{file_name} = $file_name;	
	});
}

sub to_err {
	my $self = shift;
	my $id = shift;
	my $file_name = shift;
	
	# Переводим задание в статус DONE, сохраняем имя файла с резуьтатом работы
	$self->find_and_set( $id, \sub {
		my $el = shift;
		$el->{status} = Local::TCP::Calc::STATUS_ERR();
		$el->{file_name} = $file_name;	
	});
}

sub to_work {
	my $self = shift;
	my $id = shift;
	
	# Переводим задание в статус DONE, сохраняем имя файла с резуьтатом работы
	$self->find_and_set( $id, \sub {
		my $el = shift;
		$el->{status} = Local::TCP::Calc::STATUS_WORK;
		$el->{'time'} = time;	
	});
}

sub get_status {
	my $self = shift;
	my $id = shift;
	
	# Возвращаем статус задания по id, и в случае DONE или ERROR имя файла с результатом
	my ($status, $msg) = $self->find_and_set( $id, \sub {
		my $el = shift;
		my $status = $el->{status};
		my $msg;
		given ($status) {
			when ([Local::TCP::Calc::STATUS_NEW(), Local::TCP::Calc::STATUS_WORK()]) {
				$msg = time - $el->{'time'};
			}
			when ([Local::TCP::Calc::STATUS_DONE(), Local::TCP::Calc::STATUS_ERROR()]) {
				$msg = $el->{file_name};
			}
		}
		return ($status, $msg);
	});
	return ($status, $msg);
}

sub delete {
	my $self = shift;
	my $id = shift;
	#my $status = shift;
	# Удаляем задание из очереди в соответствующем статусе
	my $queue = $self->open('+<');
	for (my $i = 0; $i < scalar @$queue; $i++) {
		if ($$queue[$i]{id} == $id) {
			delete $$queue[$i];
			last;
		}
	}
	$self->close($queue);
}

sub get {
	my $self = shift;
	
	# Возвращаем задание, которое необходимо выполнить (id, tasks)
	my ($id, $tasks);
	my $queue = $self->open('<');
	for (@$queue) {
		if ($_->{status} == Local::TCP::Calc::STATUS_NEW) {
			$id = $_->{id};
			$tasks = $_->{tasks};
			last;
		}
	}
	$self->close;
	return ($id, $tasks);
}

sub add {
	my $self = shift;
	my $new_work = shift;
	
	# Добавляем новое задание с проверкой, что очередь не переполнилась
	my $queue = $self->open('+<');

	return if scalar(@$queue) + 1 > $self->max_task;
	my $id = $$queue[scalar(@$queue)-1] if scalar(@$queue);
	push @$queue, { 
		id => ++$id, 
		tasks => @$new_work, 
		status => Local::TCP::Calc::STATUS_NEW(),
		'time' => time
	};
	$self->close($queue);
	return $id;
}

no Mouse;
__PACKAGE__->meta->make_immutable();

1;
