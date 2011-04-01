# ------- Jack port connect routines -------
package Audio::Nama;
use Modern::Perl;
use File::Slurp;
no warnings 'uninitialized';

our (
	$debug,
	$jack_running,
	%jack,
	$jack_lsp,
	$use_jack_plumbing,
	%event_id,
	%opts,
);

# general functions

sub poll_jack { $event_id{poll_jack} = AE::timer(0,5,\&jack_update) }

sub jack_update {
	# cache current JACK status
	return if engine_running();
	if( $jack_running =  process_is_running('jackd') ){
		my $jack_lsp = qx(jack_lsp -Ap 2> /dev/null); 
		%jack = %{jack_ports($jack_lsp)}
	} else { %jack = () }
}

sub jack_client {

	# returns array of ports if client and direction exist
	
	my ($name, $direction)  = @_;
	$jack{$name}{$direction} // []
}

sub jack_ports {
	my $j = shift || $jack_lsp; 
	#say "jack_lsp: $j";

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,
	#fluidsynth:left properties: output,
	#fluidsynth:right properties: output,
	my %jack = ();

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @port_aliases = /
			\s* 			# zero or more spaces
			([^:]+:[^:]+?) # non-colon string, colon, non-greedy non-colon string
			(?=[-+.\w]+:|\s+$) # zero-width port name or spaces to end-of-string
		/gx;
		map { 
				s/ $//; # remove trailing space
				push @{ $jack{ $_ }{ $direction } }, $_;
				my ($client, $port) = /(.+?):(.+)/;
				push @{ $jack{ $client }{ $direction } }, $_; 

		 } @port_aliases;

	} 
	grep{ ! /^jack:/i } # skip spurious jackd diagnostic messages
	split "\n",$j;
	#print yaml_out \%jack;
	\%jack
}

# connect jack ports via jack.plumbing or jack_connect

sub jack_plumbing_conf {
	join_path( $ENV{HOME} , '.jack.plumbing' )
}

{ 
  my $fh;
  my $plumbing_tag = q(BEGIN NAMA CONNECTIONS LIST);
  my $plumbing_header = qq(;### $plumbing_tag
;## The following lines are automatically generated.
;## DO NOT place any connection data below this line!!
;
); 
sub initialize_jack_plumbing_conf {  # remove nama lines

		return unless -f -r jack_plumbing_conf();

		my $user_plumbing = read_file(jack_plumbing_conf());

		# keep user data, deleting below tag
		$user_plumbing =~ s/;[# ]*$plumbing_tag.*//gs;

		write_file(jack_plumbing_conf(), $user_plumbing);
}

my $jack_plumbing_code = sub 
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $config_line = qq{(connect $port1 $port2)};
		say $fh $config_line; # $fh in lexical scope
		$debug and say $config_line;
	};
my $jack_connect_code = sub
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $cmd = qq(jack_connect $port1 $port2);
		$debug and say $cmd;
		system $cmd;
	};
sub connect_jack_ports_list {

	my @source_tracks = 
		grep{ 	$_->source_type eq 'jack_ports_list' and
	  	  		$_->rec_status  eq 'REC' 
			} Audio::Nama::ChainSetup::engine_tracks();

	my @send_tracks = 
		grep{ $_->send_type eq 'jack_ports_list' } Audio::Nama::ChainSetup::engine_tracks();

	# we need JACK
	return if ! $jack_running;

	# We need tracks to configure
	return if ! @source_tracks and ! @send_tracks;

	sleeper(0.3); # extra time for ecasound engine to register JACK ports

	if( $use_jack_plumbing )
	{

		# write config file
		initialize_jack_plumbing_conf();
		open $fh, ">>", jack_plumbing_conf();
		print $fh $plumbing_header;
		make_connections($jack_plumbing_code, \@source_tracks, 'in' );
		make_connections($jack_plumbing_code, \@send_tracks,   'out');
		close $fh; 

		# run jack.plumbing
		start_jack_plumbing();
		sleeper(3); # time for jack.plumbing to launch and poll
		kill_jack_plumbing();
		initialize_jack_plumbing_conf();
	}
	else 
	{
		make_connections($jack_connect_code, \@source_tracks, 'in' );
		make_connections($jack_connect_code, \@send_tracks,   'out');
	}
}
}
sub quote { $_[0] =~ /^"/ ? $_[0] : qq("$_[0]")}

sub make_connections {
	my ($code, $tracks, $direction) = @_;
	my $ports_list = $direction eq 'in' ? 'source_id' : 'send_id';
	map{  
		my $track = $_; 
 		my $name = $track->name;
 		my $ecasound_port = "ecasound:$name\_$direction\_";
		my $file = join_path(project_root(), $track->$ports_list);
		say($track->name, 
			": JACK ports file $file not found. No sources connected."), 
			return if ! -e -r $file;
		my $line_number = 0;
		my @lines = read_file($file);
		for my $external_port (@lines){   
			# $external_port is the source port name
			chomp $external_port;
			$debug and say "port file $file, line $line_number, port $external_port";
			# setup shell command
			
			if(! $jack{$external_port}){
				say $track->name, qq(: port "$external_port" not found. Skipping.);
				next
			}
		
			# ecasound port index
			
			my $index = $track->width == 1
				?  1 
				: $line_number % $track->width + 1;

		my @ports = map{quote($_)} $external_port, $ecasound_port.$index;

			  $code->(
						$direction eq 'in'
							? @ports
							: reverse @ports
					);
			$line_number++;
		};
 	 } @$tracks
}
sub kill_jack_plumbing {
	qx(killall jack.plumbing >/dev/null 2>&1)
	unless $opts{A} or $opts{J};
}
sub start_jack_plumbing {
	
	if ( 	$use_jack_plumbing				# not disabled in namarc
			and ! ($opts{J} or $opts{A})	# we are not testing   

	){ system('jack.plumbing >/dev/null 2>&1 &') }
}
1;
__END__
	