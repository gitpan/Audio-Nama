use Test::More tests => 3;
use strict;

BEGIN { 
	use_ok('Audio::Nama::Wav') ;
}
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");
my $wav = Audio::Nama::Wav->new( qw(	name  	track01.cdda 
							dir   	/media/sessions/test-abc
							)) ;
is ($wav->name, 'track01.cdda', "name assignment");
is ($wav->dir, '/media/sessions/test-abc', "directory assignment");
#is (shift @{$wav->versions}, 1, "locating .wav files");
1;
__END__