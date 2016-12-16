package Local::TCP::Calc;
use Exporter 'import';
our @EXPORT = qw(TYPE_START_WORK TYPE_CHECK_WORK TYPE_CONN_ERR TYPE_CONN_OK STATUS_NEW STATUS_WORK STATUS_DONE STATUS_ERROR);

use strict;
use warnings;
use DDP;

sub TYPE_START_WORK {1}
sub TYPE_CHECK_WORK {2}
sub TYPE_CONN_ERR   {3}
sub TYPE_CONN_OK    {4}

sub STATUS_NEW   {1}
sub STATUS_WORK  {2}
sub STATUS_DONE  {3}
sub STATUS_ERROR {4}

sub input {
	my $w = shift;
	my $type = shift;
	my $pkg_ref = shift;
	
	syswrite($w, pack('C', $type));
	syswrite($w, $$pkg_ref) if $pkg_ref;
}

sub read_type {
	my $r = shift;
	
	my $pkg;
	die "Не удалось прочесть тип подключения " unless sysread($r, $pkg, 1) == 1;
	return unpack 'C', $pkg;
}

sub pack_message {
	my $message = shift;
	return pack 'L/a*', $message;
}

sub read_message {
	my $r = shift;
	
	my $pkg;
	die 'Не удалось прочесть длину сообщения' unless sysread($r, $pkg, 4) == 4;
	my $len = unpack 'L', $pkg;
	die 'Не удалось прочесть сообщение' unless sysread($r, $pkg, $len) == $len;
	return unpack 'a*', $pkg;
}

sub pack_messages {
	my $messages = shift;
	my $pkg = pack 'L', scalar @$messages;
	for (@$messages) { $pkg .= pack_message($_); }
	return $pkg;
}

sub read_messages {
	my $r = shift;
	
	my $pkg;
	die 'Не удалось прочесть количество сообщений' unless sysread($r, $pkg, 4) == 4;
	my $n = unpack 'L', $pkg;
	my @messages;
	for (my $i = 0; $i < $n; $i++) { push @messages, read_message($r) }
	return \@messages;
}

sub pack_id {
	my $id = shift;
	return pack 'L', $id;
}

sub read_id {
	my $r = shift;
	
	my $pkg;
	die 'Не удалось прочесть id' unless sysread($r, $pkg, 4) == 4;
	return unpack 'L', $pkg;
}

sub pack_time {
	my $time = shift;
	return pack 'L', $time;
}

sub read_time {
	my $r = shift;
	
	my $pkg;
	die 'Не удалось прочесть время' unless sysread($r, $pkg, 4) == 4;
	return unpack 'L', $pkg;
}

sub pack_status {
	my $status = shift;
	return pack 'C', $status;
}

sub read_status {
	my $r = shift;
	
	my $pkg;
	die 'Не удалось прочесть статус' unless sysread($r, $pkg, 1) == 1;
	return unpack 'C', $pkg;
}

sub ceil($) { 
  	my $x = shift;
	return int($x) < $x ? int($x)+1 : $x
}

1;
