# ------- WAV file info routines ---------

package Audio::Nama;
use Modern::Perl;

our (%wav_info);

### WAV file length/format/modify_time are cached in %wav_info 

sub ecasound_get_info {
	# get information about an audio object
	
	my ($path, $command) = @_;
	$path = qq("$path");
	teardown_engine();
	eval_iam('cs-add gl');
	eval_iam('c-add g');
	eval_iam('ai-add ' . $path);
	eval_iam('ao-add null');
	eval_iam('cs-connect');
	eval_iam('ai-select '. $path);
	my $result = eval_iam($command);
	teardown_engine();
	$result;
}
sub cache_wav_info {
	my @files = File::Find::Rule
		->file()
		->name( '*.wav' )
		->in( this_wav_dir() );	
	map{  get_wav_info($_) } @files;
}
sub get_wav_info {
	my $path = shift;
	#say "path: $path";
	$wav_info{$path}{length} = get_length($path);
	$wav_info{$path}{format} = get_format($path);
	$wav_info{$path}{modify_time} = get_modify_time($path);
}
sub get_length { 
	my $path = shift;
	my $length = ecasound_get_info($path, 'ai-get-length');
	sprintf("%.4f", $length);
}
sub get_format {
	my $path = shift;
	ecasound_get_info($path, 'ai-get-format');
}
sub get_modify_time {
	my $path = shift;
	my @stat = stat $path;
	$stat[9]
}
sub wav_length {
	my $path = shift;
	update_wav_cache($path);
	$wav_info{$path}{length}
}
sub wav_format {
	my $path = shift;
	update_wav_cache($path);
	$wav_info{$path}{format}
}
sub update_wav_cache {
	my $path = shift;
	return unless get_modify_time($path) != $wav_info{$path}{modify_time};
	say qq(WAV file $path has changed! Updating cache.);
	get_wav_info($path) 
}
1;
__END__
	