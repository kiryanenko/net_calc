package Local::TCP::Calc;

use strict;

sub TYPE_START_WORK {1}
sub TYPE_CHECK_WORK {2}
sub TYPE_CONN_ERR   {3}
sub TYPE_CONN_OK    {4}

sub STATUS_NEW   {1}
sub STATUS_WORK  {2}
sub STATUS_DONE  {3}
sub STATUS_ERROR {4}

sub HEADER_SIZE {5}		# Размер заголовка
sub LEN_MSG_SIZE {4}	# Размер длины сообщения

sub pack_header {
	my $pkg = shift;
	my $type = shift;
	my $size = shift;	
	
	$$pkg = pack 'CL', $type, $size;	
	return $$pkg;
}

sub unpack_header {
	my $pkg = shift;
	my $header = shift;	# Размер или количество сообщений
	
	my @h = unpack 'CL', $pkg;
	$$header = @h[1];
	return @h[0];		# Возвращаем тип
}

sub pack_message {
	my $pkg = shift;
	my $messages = shift;
	
	$$pkg = pack '(L/a*)*', @$messages;
	return $$pkg;
}

sub unpack_message {
	my $pkg = shift;
	my $message = shift;
	
	$$message = unpack 'a*', $pkg;
	return $$message;
}

sub read_message {
	my $r = shift;
	
	my $pkg;
	die 'Не удалось прочесть длину сообщения' unless sysread($r, $pkg, LEN_MSG_SIZE) == LEN_MSG_SIZE;
	my $len = unpack 'L', $pkg;
	die 'Не удалось прочесть сообщение' unless sysread($r, $pkg, $len) == $len;
	return unpack 'a*', $pkg;
}

1;