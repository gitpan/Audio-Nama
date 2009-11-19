# ---------- Track -----------
package Audio::Nama::Track;
use Modern::Perl;
no warnings qw(uninitialized redefine);
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
#use Exporter qw(import);
#our @EXPORT_OK = qw(track);
use Audio::Nama::Assign qw(join_path);
use Audio::Nama::Wav;
use Carp;
use IO::All;
use vars qw($n %by_name @by_index %track_names %by_index @all);
our @ISA = 'Audio::Nama::Wav';

initialize();

# attributes offset, loop, delay for entire setup
# attribute  modifiers
# new attribute will be 
use Audio::Nama::Object qw(

					class 			
					n   			
					name
					group 			
					rw				
					active			
					width			
					ops 			
					vol				
					pan				
					latency			
					offset
					old_vol_level	
					old_pan_level
					playat			
					region_start	
					region_end
					modifiers		
					looping			
					hide			
					source_id		
					source_type		
					send_id			
					send_type
					target			
					project			
					rec_defeat		
					inserts			
					effect_chain_stack 
					cache_map		


);
# Note that ->vol return the effect_id 
# ->old_volume_level is the level saved before muting
# ->old_pan_level is the level saved before pan full right/left
# commands

sub initialize {
	$n = 0; 	# incrementing numeric key
	@all = ();
	%by_index = ();	# return ref to Track by numeric key
	%by_name = ();	# return ref to Track by name
	%track_names = (); 
}

sub idx { # return first free track index
	my $n = 0;
	while (++$n){
		return $n if not $by_index{$n}
	}
}
	

sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter

	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	if (my $track = $by_name{$vals{name}}){
		#if ($track->hide) { $track->set(hide => 0); } 
		#print("track name already in use: $vals{name}\n"); 
		return $track;
	}
	print("reserved track name: $vals{name}\n"), return
	 if  ! $Audio::Nama::mastering_mode 
		and grep{$vals{name} eq $_} @Audio::Nama::mastering_track_names ; 

	my $n = $vals{n} ? $vals{n} : idx(); 
	my $object = bless { 


		## 		defaults ##
					class	=> $class,
					name 	=> "Audio_$n", 
					group	=> 'Main', 
		#			rw   	=> 'REC', # Audio::Nama::add_track() sets REC if necessary
					n    	=> $n,
					ops     => [],
					active	=> undef,
					width => 1,
					vol  	=> undef,
					pan 	=> undef,

					modifiers => q(), # start, reverse, audioloop, playat
					
					looping => undef, # do we repeat our sound sample

					source_type => q(soundcard),
					source_id   => 1,

					send_type => undef,
					send_id   => undef,
					inserts => {},
					effect_chain_stack => [],
					cache_map => {},
					

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	#print "names used: ", Audio::Nama::yaml_out( \%track_names );
	$by_index{$n} = $object;
	$by_name{ $object->name } = $object;
	push @all, $object;
	#Audio::Nama::add_latency_compensation($n);	
	Audio::Nama::add_pan_control($n);
	Audio::Nama::add_volume_control($n);

	#my $group = $Audio::Nama::Group::by_name{ $object->group }; 

	# create group if necessary
	#defined $group or $group = Audio::Nama::Group->new( name => $object->group );
	#my @existing = $group->tracks ;
	#$group->set( tracks => [ @existing, $object->name ]);
	$Audio::Nama::this_track = $object;
	$object;
	
}


sub dir {
	my $self = shift;
	 $self->project  
		? join_path(Audio::Nama::project_root(), $self->project, '.wav')
		: Audio::Nama::this_wav_dir();
}

sub basename {
	my $self = shift;
	$self->target || $self->name
}

sub full_path { my $track = shift; join_path($track->dir, $track->current_wav) }

sub group_last {
	my $track = shift;
	my $group = $Audio::Nama::Group::by_name{$track->group}; 
	#print join " ", 'searching tracks:', $group->tracks, $/;
	$group->last;
}

# seems to be missing.. and needed for track-based version numbering
sub last {
	my $track = shift;
	my @versions;
	@versions =  @{ $track->versions };
	$versions[-1] || 0;
}
	

sub current_wav {
	my $track = shift;
	my $last = $track->current_version;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		$track->name . '_' . $last . '.wav'
	} elsif ( $track->rec_status eq 'MON'){ 
		my $filename = $track->targets->{ $track->monitor_version } ;
		$filename
	} else {
		$debug and print "track ", $track->name, ": no current version\n" ;
		undef; 
	}
}

sub full_wav_path {  
	my $track = shift; 
	join_path $track->dir, $track->current_wav
}

sub current_version {	
	my $track = shift;
	my $last = $Audio::Nama::use_group_numbering 
					? $track->group_last
					: $track->last;
	my $status = $track->rec_status;
	#$debug and print "last: $last status: $status\n";
	if 	($status eq 'REC'){ return ++$last}
	elsif ( $status eq 'MON'){ return $track->monitor_version } 
	else { return 0 }
}

sub monitor_version {
	my $track = shift;

	my $group = $Audio::Nama::Group::by_name{$track->group};
	return $track->active if $track->active 
				and grep {$track->active  == $_ } @{$track->versions} ;
	return $group->version if $group->version 
				and grep {$group->version  == $_ } @{$track->versions};
	return undef if $group->version;
	$track->last;
}

sub rec_status {
#	$Audio::Nama::debug2 and print "&rec_status\n";
	my $track = shift;
	my $bug = shift;
	local $debug;
	$debug //= $bug;
	
	#my $source_id = $track->source_id;
	my $monitor_version = $track->monitor_version;

	my $group = $Audio::Nama::Group::by_name{$track->group};
	$debug and say join " ", "group:",$group->name, $group->rw;
	$debug and print "track: ", $track->name, ", source: ",
		$track->source_id, ", monitor version: $monitor_version\n";

	# first, check for conditions resulting in status 'OFF'

	if ( $group->rw eq 'OFF'
		or $track->rw eq 'OFF'
		# or $track->hide 
	){ 	return			  'OFF' }

	# having reached here, we know $group->rw and $track->rw are REC or MON
	# so the result will be REC or MON if conditions are met

	# second, set REC status if possible
	
	elsif (	$track->rw eq 'REC' and $group->rw eq 'REC') {
		given( $track->source_type){
			when('jack_client'){
				Audio::Nama::jack_client($track->source_id,'output')
					?  return 'REC'
					:  return maybe_monitor($monitor_version)
			}
			when('soundcard'){ return 'REC' }
			when('track'){ return 'REC' } # maybe $track->rw ??
			default { croak $track->name. ": missing source type" }
			# fall back to MON
			#default {  maybe_monitor($monitor_version)  }
		}
	}
	# third, set MON status if possible
	
	else { 			maybe_monitor($monitor_version)

	}
}

sub rec_status_display {
	my $track = shift;
	my $status = $track->rec_status;
	$track->rec_defeat ? "[$status]" : $status;
}

sub maybe_monitor { # ordinary sub, not object method
	my $monitor_version = shift;
	return 'MON' if $monitor_version and ! ($Audio::Nama::preview eq 'doodle');
	return 'OFF';
}

# the following methods handle effects
sub remove_effect { # doesn't touch %cops or %copp data structures 
	my $track = shift;
	my @ids = @_;
	$track->set(ops => [ grep { my $existing = $_; 
									! grep { $existing eq $_
									} @ids }  
							@{$track->ops} ]);
}

# the following methods are for channel routing

sub mono_to_stereo { 
	my $track = shift;
	my $cmd = "file " .  $track->full_path;
	if ( 	$track->width == 2 and $track->rec_status eq 'REC'
		    or  -e $track->full_path
				and qx(which file)
				and qx($cmd) =~ /stereo/i ){ 
		return q(); 
	} elsif ( $track->width == 1 and $track->rec_status eq 'REC'
				or  -e $track->full_path
				and qx(which file)
				and qx($cmd) =~ /mono/i ){ 
		return " -chcopy:1,2 " 
	} else { # do nothing for higher channel counts
	} # carp "Track ".$track->name.": Unexpected channel count\n"; 
}

sub rec_route {
	no warnings qw(uninitialized);
	my $track = shift;
	
	# applies to soundcard input via ALSA
	
	return unless $track->source_type eq 'soundcard'
		and ! $Audio::Nama::jack_running;

	# no need to route a signal at channel 1
	return if ! $track->source_id or $track->source_id == 1; 
	
	my $route = "-chmove:" . $track->source_id . ",1"; 
	if ( $track->width == 2){
		$route .= " -chmove:" . ($track->source_id + 1) . ",2";
	}
	return $route;
	
}
sub route {

	# routes signals 1,2,3,...$width to $dest + 0, $dest + 1, $dest + 2,... 
	
	my ($width, $dest) = @_;
	return undef if $dest == 1 or $dest == 0;
	# print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $map ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$map .= " -chmove:$c," . ( $c + $offset);
		#$map .= " -eac:0,"  . $c;
	}
	$map;
}

# channel shifting for multi rule 
#
sub pre_send {
	#$debug2 and print "&pre_send\n";
	my $track = shift;

	# we channel shift only to soundcard channel numbers higher than 3,
	# not when the send is to a jack client
	 
	return q() if $track->send_type eq 'jack_client'  or ! $track->aux_output;           
	route(2,$track->aux_output); # stereo signal
}

sub remove {
	my $track = shift;
#	$Audio::Nama::ui->remove_track_gui($track->n); TODO
	my $n = $track->n;
	map{ Audio::Nama::remove_effect($_) } @{ $track->ops };
	delete $by_index{$track->n};
	delete $by_name{$track->name};
	@all = grep{ $_->n != $n} @all;
}

# for graph-style routing

sub input_path { # signal path, not file path

	my $track = shift;

	# create edge representing live sound source input
	
	if($track->rec_status eq 'REC'){

		if ($track->source_type =~ /soundcard|jack_client/){
			( $track->source_type . '_in' , $track->name)
		} 

	} elsif($track->rec_status eq 'MON' and $Audio::Nama::preview ne 'doodle'){

	# create edge representing WAV file input

		('wav_in', $track->name) 

	}
}

# The following two subroutines are not object methods.

sub all { @all }

{ my %non_user = map{ $_, 1} qw( Master Mixdown Eq Low Mid High Boost );
sub user {
	grep{ ! $non_user{$_} } map{$_->name} @all
}
}
	

### Commands and their support functions

# The conditional-laced code allows user to use 'source'
# and 'send' commands in JACK and ALSA modes.

sub soundcard_channel { $_[0] // 1 }
sub set_io {
	my ($track, $direction, $id) = @_;
	# $direction: send | source
	
	# these are the field names
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";

	# respond to a query (no argument)
	if ( ! $id ){ return $track->$type_field ? $track->$id_field : undef }

	
	# set values, returning new setting
	
	given ( Audio::Nama::dest_type( $id ) ){
		when ('jack_client'){
			if ( $Audio::Nama::jack_running ){
				$track->set($type_field => 'jack_client',
							$id_field   => $id);
				my $name = $track->name;
				print <<CLIENT if ! Audio::Nama::jack_client($id, 'output');
$name: $direction port for JACK client "$id" not found. 
CLIENT
				return $track->source_id;
			} else {
		say "JACK server not running! Cannot set JACK client as track source.";
				return $track->source_id;
			} 
		}

		when('soundcard'){ 
			$track->set( $id_field => $id, 
						 $type_field => 'soundcard');
			return soundcard_channel( $id )
		}
		when('loop'){ 
			$track->set( $id_field => $id, 
						 $type_field => 'loop');
			return $id;
		}
	}
} 

# the following subroutines support IO objects

sub soundcard_input {
	my $track = shift;
	if ($Audio::Nama::jack_running) {
		my $start = $track->source_id;
		my $end   = $start + $track->width - 1;
		['jack_multi' , join q(,),q(jack_multi),
			map{"system:capture_$_"} $start..$end]
	} else { ['device' , $Audio::Nama::capture_device] }
}
sub soundcard_output {
 	$Audio::Nama::jack_running 
		? [qw(jack_client system)]  
		: ['device', $Audio::Nama::alsa_playback_device] 
}
sub source_input {
	my $track = shift;
	given ( $track->source_type ){
		when ( 'soundcard'  ){ return $track->soundcard_input }
		when ( 'jack_client'){
			if ( $Audio::Nama::jack_running ){ return ['jack_client', $track->source_id] }
			else { 	say($track->name. ": cannot set source ".$track->source_id
				.". JACK not running."); return [undef, undef] }
		}
		when ( 'loop'){ return ['loop',$track->source_id ] } 
	}
}

sub send_output {
	my $track = shift;
	given ($track->send_type){
		when ( 'soundcard' ){ 
			if ($Audio::Nama::jack_running) {
				my $start = $track->send_id; # Assume channel will be 3 or greater
				my $end   = $start + 1; # Assume stereo
				return ['jack_multi', join q(,),q(jack_multi),
					map{"system:playback_$_"} $start..$end]
			} else {return [ 'device', $Audio::Nama::alsa_playback_device] }
		}
		when ('jack_client') { 
			if ($Audio::Nama::jack_running){return [ 'jack_client', $track->send_id] }
			else { carp $track->name . 
					q(: auxilary send to JACK client specified,) .
					q( but jackd is not running.  Skipping.);
					return [qw(undef  undef)];
			}
		}
		when ('loop') { return [ 'loop', $track->send_id ] }
			
		carp $track->name, ": missing or illegal send_type: ", 
			$track->send_type, $/;
	}
 };

sub source { # command for setting, showing track source
	my ($track, $id) = @_;
	$track->set_io( 'source', $id);
}
sub send { # command for setting, showing track source
	my ($track, $id) = @_;
	$track->set_io( 'send', $id);
}
sub set_source { # called from parser 
	my $track = shift;
	my $source = shift;

# Special handling for 'null', used for non-input (i.e. metronome) tracks

	if ($source eq 'null'){
		$track->set(group => 'null');
		return
	}

	my $old_source = $track->source;
	my $new_source = $track->source($source);
	my $object = $track->input_object;
	if ( $old_source  eq $new_source ){
		print $track->name, ": input unchanged, $object\n";
	} else {
		print $track->name, ": input set to $object\n";
	}
}

sub set_version {
	my ($track, $n) = @_;
	my $name = $track->name;
	if ($n == 0){
		print "$name: following latest version\n";
		$track->set(active => $n)
	} elsif ( grep{ $n == $_ } @{$track->versions} ){
		print "$name: anchoring version $n\n";
		$track->set(active => $n)
	} else { 
		print "$name: version $n does not exist, skipping.\n"
	}
}

sub set_send { # wrapper
	my ($track, $output) = @_;
	my $old_send = $track->send;
	my $new_send = $track->send($output);
	my $object = $track->output_object;
	if ( $old_send  eq $new_send ){
		print $track->name, ": send unchanged, ",
			( $object ?  $object : 'off'), "\n";
	} else {
		print $track->name, ": aux output ",
		($object ? "to $object" : 'is off.'), "\n";
	}
}

# input channel number, may not be used in current setup


sub input {   	
	my $track = shift;
	$track->ch_r ? $track->ch_r : 1
}

# send channel number, may not be used in current setup

sub aux_output { 
	my $track = shift;
	$track->send_id > 2 ? $track->send_id : undef 
}

sub object_as_text {
	my ($track, $direction) = @_; # $direction: source | send
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";
	
	my $output;
	given ($track->$type_field){
		when('soundcard')  { $output = "soundcard channel "}
		when('jack_client'){ $output = "JACK client "}
		when('loop')       { $output = "loop device "}
	}
	$output .= $track->$id_field
}

sub input_object { # for text display
	my $track = shift;
	$track->object_as_text('source');
}

sub output_object {   # text for user display
	my $track = shift;
	$track->object_as_text('send');

}
sub client_status {
	my ($track_status, $client, $direction) = @_;
	my $type = Audio::Nama::dest_type($client);
	if ($type eq 'loop'){
		my ($bus) =  $client =~ /loop,(\w+)/;
		$track_status eq 'REC' ? $bus : undef;  
	}
	elsif ($track_status eq 'OFF') {"[$client]"}
	elsif ($type eq 'jack_client'){ 
		Audio::Nama::jack_client($client, $direction) 
			? $client 
			: "[$client]" 
	} elsif ($type eq 'soundcard'){ 
		$client 
			?  ($track_status eq 'REC' 
				?  $client 
				: "[$client]")
			: undef
	} else { q() }
}
sub source_status {
	my $track = shift;
	return if (ref $track) =~ /MasteringTrack/;
	client_status($track->rec_status, $track->source, 'output')
}
sub send_status {
	my $track = shift;
	client_status('REC', $track->send, 'input')
}

sub set_rec {
	my $track = shift;
	if (my $t = $track->target){
		my  $msg  = $track->name;
			$msg .= qq( is an alias to track "$t");
			$msg .=  q( in project ") . $track->project . q(") 
				if $track->project;
			$msg .= qq(.\n);
			$msg .= "Can't set a track alias to REC.\n";
		print $msg;
		return;
	}
	$track->set(rw => 'REC');
	$track->rec_status eq 'REC'	or print $track->name, 
		": set to REC, but current status is ", $track->rec_status, "\n";
}
sub set_mon {
	my $track = shift;
	$track->set(rw => 'MON');
	$track->rec_status eq 'MON'	or print $track->name, 
		": set to MON, but current status is ", $track->rec_status, "\n";
}
sub set_off {
	my $track = shift;
	$track->set(rw => 'OFF');
	print $track->name, ": set to OFF\n";
}

sub normalize {
	my $track = shift;
	if ($track->rec_status ne 'MON'){
		print $track->name, ": You must set track to MON before normalizing, skipping.\n";
		return;
	} 
	# track version will exist if MON status
	my $cmd = 'ecanormalize ';
	$cmd .= $track->full_path;
	print "executing: $cmd\n";
	system $cmd;
}
sub fixdc {
	my $track = shift;
	if ($track->rec_status ne 'MON'){
		print $track->name, ": You must set track to MON before fixing dc level, skipping.\n";
		return;
	} 

	my $cmd = 'ecafixdc ';
	$cmd .= $track->full_path;
	print "executing: $cmd\n";
	system $cmd;
}
sub mute {
	package Audio::Nama;
	my $track = shift;
	my $nofade = shift;
	$track or $track = $Audio::Nama::this_track;
	# do nothing if already muted
	return if $track->old_vol_level();

	# mute if non-zero volume
	if ( $Audio::Nama::copp{$track->vol}[0]){   
		$track->set(old_vol_level => $Audio::Nama::copp{$track->vol}[0]);
		if ( $nofade ){ 
			effect_update_copp_set( $track->vol, 0, 0  );
		} else { 
			fadeout( $track->vol );
		}
	}
}
sub unmute {
	package Audio::Nama;
	my $track = shift;
	my $nofade = shift;
	$track or $track = $Audio::Nama::this_track;

	# do nothing if we are not muted
#	return if $Audio::Nama::copp{$track->vol}[0]; 
	return if ! $track->old_vol_level;

	if ( $nofade ){ 
		effect_update_copp_set($track->vol, 0, $track->old_vol_level);
	} else { 
		fadein( $track->vol, $track->old_vol_level);
	}
	$track->set(old_vol_level => 0);
}

sub ingest  { # i believe 'import' has a magical meaning
	my $track = shift;
	my ($path, $frequency) = @_;
	my $version  = ${ $track->versions }[-1] + 1;
	if ( ! -r $path ){
		print "$path: non-existent or unreadable file. No action.\n";
		return;
	} else {
		my $type = qx(file $path);
		my $channels;
		if ($type =~ /mono/i){
			$channels = 1;
		} elsif ($type =~ /stereo/i){
			$channels = 2;
		} else {
			print "$path: unknown channel count. Assuming mono. \n";
			$channels = 1;
		}
	my $format = Audio::Nama::signal_format($Audio::Nama::raw_to_disk_format, $channels);
	my $cmd = qq(ecasound -f:$format -i:resample-hq,$frequency,$path -o:).
		join_path(Audio::Nama::this_wav_dir(),$track->name."_$version.wav\n");
		print $cmd;
		system $cmd or print "error: $!\n";
	} 
	Audio::Nama::rememoize();
}

sub playat_output {
	my $track = shift;
	if ( $track->playat ){
		"playat" , $track->playat
	}
}

sub select_output {
	my $track = shift;
	if ( $track->region_start and $track->region_end){
		my $end = $track->region_ending;
		my $start = $track->region_start;
		my $length = $end - $start;
		"select", $start, $length
	}
}

sub remove_insert {
	my $track = shift;
	if ( my $i = $track->inserts){
		map{ $Audio::Nama::tn{$_}->remove } @{ $i->{tracks} };
		$track->set(inserts => {});
	}
}

sub region_start {
	my $track = shift;
	Audio::Nama::Mark::mark_time( $track->{region_start} )
}
sub region_ending {
	my $track = shift;
	if ( $track->{region_end} eq 'END' ){
		return get_length($track->full_path);
	} else {
		Audio::Nama::Mark::mark_time( $track->{region_end} )
	}
}
sub playat {
	my $track = shift;
	Audio::Nama::Mark::mark_time( $track->{playat} )
}

# subroutine, not object method

sub get_length { 
	
	#$debug2 and print "&get_length\n";
	my $path = shift;
	package Audio::Nama;
	eval_iam('cs-disconnect') if eval_iam('cs-connected');
	eval_iam('cs-add gl');
	eval_iam('c-add g');
	eval_iam('ai-add ' . $path);
	eval_iam('ao-add null');
	eval_iam('cs-connect');
	eval_iam('engine-launch');
	eval_iam('ai-select '. $path);
	my $length = eval_iam('ai-get-length');
	eval_iam('cs-disconnect');
	eval_iam('cs-remove gl');
	sprintf("%.4f", $length);
}
sub fancy_ops { # returns list 
	my $track = shift;
	grep{ $_ ne $track->vol and $_ ne $track->pan } @{ $track->ops }
}
	
# subclass

package Audio::Nama::SimpleTrack; # used for Master track
use Modern::Perl;
no warnings qw(uninitialized redefine);
our @ISA = 'Audio::Nama::Track';
use Audio::Nama::Object qw(

					class 			
					n   			
					name
					group 			
					rw				
					active			
					width			
					ops 			
					vol				
					pan				
					latency			
					offset
					old_vol_level	
					old_pan_level
					playat			
					region_start	
					region_end
					modifiers		
					looping			
					hide			
					source_id		
					source_type		
					send_id			
					send_type
					target			
					project			
					rec_defeat		
					inserts			
					effect_chain_stack 
					cache_map		


						);

sub rec_status{

#	$Audio::Nama::debug2 and print "&rec_status (SimpleTrack)\n";
	my $track = shift;
	return 'MON' unless $track->rw eq 'OFF';
	'OFF';

}
sub ch_r {
	no warnings;
	my $track = shift;
	return '';
}
package Audio::Nama::MasteringTrack; # used for mastering chains 
use Modern::Perl;
no warnings qw(uninitialized redefine);
our @ISA = 'Audio::Nama::SimpleTrack';
use Audio::Nama::Object qw( 

					class 			
					n   			
					name
					group 			
					rw				
					active			
					width			
					ops 			
					vol				
					pan				
					latency			
					offset
					old_vol_level	
					old_pan_level
					playat			
					region_start	
					region_end
					modifiers		
					looping			
					hide			
					source_id		
					source_type		
					send_id			
					send_type
					target			
					project			
					rec_defeat		
					inserts			
					effect_chain_stack 
					cache_map		

						
						);

sub rec_status{
	my $track = shift;
	$Audio::Nama::mastering_mode ? 'MON' :  'OFF';
}
sub group_last {0}
sub version {0}

package Audio::Nama::SlaveTrack; # for instrument monitor bus
use Modern::Perl;
no warnings qw(uninitialized redefine);
our @ISA = 'Audio::Nama::Track';
use Audio::Nama::Object qw( 

					class 			
					n   			
					name
					group 			
					rw				
					active			
					width			
					ops 			
					vol				
					pan				
					latency			
					offset
					old_vol_level	
					old_pan_level
					playat			
					region_start	
					region_end
					modifiers		
					looping			
					hide			
					source_id		
					source_type		
					send_id			
					send_type
					target			
					project			
					rec_defeat		
					inserts			
					effect_chain_stack 
					cache_map		

						
);
sub width { $Audio::Nama::tn{$_[0]->target}->width }
sub rec_status { $Audio::Nama::tn{$_[0]->target}->rec_status }
sub mono_to_stereo { $Audio::Nama::tn{$_[0]->target}->mono_to_stereo }
sub rec_route { $Audio::Nama::tn{$_[0]->target}->rec_route }
sub source_input { $Audio::Nama::tn{$_[0]->target}->source_input} 
sub soundcard_input { $Audio::Nama::tn{$_[0]->target}->soundcard_input} 
sub full_path { $Audio::Nama::tn{$_[0]->target}->full_path} 
sub monitor_version { $Audio::Nama::tn{$_[0]->target}->monitor_version} 
sub inserts { $Audio::Nama::tn{$_[0]->target}->inserts} 
sub source_type { $Audio::Nama::tn{$_[0]->target}->source_type}
sub source_id { $Audio::Nama::tn{$_[0]->target}->source_id}
sub source_status { $Audio::Nama::tn{$_[0]->target}->source_status }
sub dir { $Audio::Nama::tn{$_[0]->target}->dir }

package Audio::Nama::CacheRecTrack; # for graph generation
our @ISA = qw(Audio::Nama::SlaveTrack Audio::Nama::Wav);
use Audio::Nama::Object qw( 

					class 			
					n   			
					name
					group 			
					rw				
					active			
					width			
					ops 			
					vol				
					pan				
					latency			
					offset
					old_vol_level	
					old_pan_level
					playat			
					region_start	
					region_end
					modifiers		
					looping			
					hide			
					source_id		
					source_type		
					send_id			
					send_type
					target			
					project			
					rec_defeat		
					inserts			
					effect_chain_stack 
					cache_map		


);
sub current_version {
	my $track = shift;
	my $target = $Audio::Nama::tn{$track->target};
		$target->last + 1
# 	if ($target->rec_status eq 'MON'
# 		or $target->rec_status eq 'REC' and $Audio::Nama::Group::by_name{$track->target}){
# 	}
}
sub current_wav {
	my $track = shift;
		$Audio::Nama::tn{$track->target}->name . '_' . $track->current_version . '.wav'
}
sub full_path { my $track = shift; Audio::Nama::join_path( $track->dir, $track->current_wav) }

# ---------- Group -----------

package Audio::Nama::Group;
use Modern::Perl;
no warnings qw(uninitialized redefine);
our $VERSION = 1.0;
#use Exporter qw(import);
#our @EXPORT_OK =qw(group);
use Carp;
use vars qw(%by_name);
our @ISA;
initialize();

use Audio::Nama::Object qw( 	name
					rw
					version 
					n	
					);

sub initialize {
	%by_name = ();
}

sub new {

	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "name missing" unless $vals{name};
	#(carp "group name already in use: $vals{name}\n"), 
		return ($by_name{$vals{name}}) if $by_name{$vals{name}};
	my $object = bless { 	
		rw   	=> 'REC', 
		@_ 			}, $class;
	$by_name{ $object->name } = $object;
	$object;
}


sub tracks { # returns list of track names in group 

	my $group = shift;
	my @all = Audio::Nama::Track::all;
	# map {print "type: ", ref $_, $/} Audio::Nama::Track::all; 
	map{ $_->name } grep{ $_->group eq $group->name } Audio::Nama::Track::all();
}

sub last {
	$debug and say "group: @_";
	my $group = shift;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last;
		$last = $track->last || 0;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	}	map { $Audio::Nama::Track::by_name{$_} } $group->tracks;
	$max;
}


sub all { values %by_name }

sub remove {
	my $group = shift;
	delete $by_name{$group->name};
}
		
# ---------- Op -----------

package Audio::Nama::Op;
use Modern::Perl;
no warnings qw(uninitialized redefine);
our $VERSION = 0.5;
our @ISA;
use Audio::Nama::Object qw(	op_id 
					chain_id 
					effect_id
					parameters
					subcontrollers
					parent
					parent_parameter_target
					
					);


1;

# We will treat operators and controllers both as Op
# objects. Subclassing so controller has special
# add_op  and remove_op functions. 
# 

__END__


