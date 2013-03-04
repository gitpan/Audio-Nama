# -------- CacheTrack ------
# TODO: wisely handle uncaching a sub-bus mix track 
package Audio::Nama;
use Modern::Perl;
use Audio::Nama::Globals qw(:all);

# some common variables for cache_track and merge_track
# related routines

{ # begin shared lexicals for cache_track and merge_edits

	my ($track, 
		$additional_time, 
		$processing_time, 
		$orig_version, 
		$complete_caching_ref,
		$output_wav,
		$orig_volume,
		$orig_pan);

sub initialize_caching_vars {
	map{ undef $_ } ($track, 
					$additional_time, 
					$processing_time, 
					$orig_version, 
					$complete_caching_ref,
					$output_wav,
					$orig_volume,
					$orig_pan);
}

sub cache_track { # launch subparts if conditions are met

	local $this_track;
	initialize_caching_vars();

	($track, $additional_time) = @_;
	$additional_time //= 0;
	say $track->name, ": preparing to cache.";
	
	# abort if sub-bus mix track and bus is OFF 
	if( my $bus = $bn{$track->name}
		and $track->rec_status eq 'REC' 
	 ){ 
		$bus->rw eq 'OFF' and say(
			$bus->name, ": status is OFF. Aborting."), return;

	# check conditions for normal track
	} else { 
		$track->rec_status eq 'MON' or say(
			$track->name, ": track caching requires MON status. Aborting."), return;
	}
	say($track->name, ": no effects to cache!  Skipping."), return 
		unless 	$track->fancy_ops 
				or $track->has_insert
				or $bn{$track->name};

	if ( prepare_to_cache() )
	{ 
		deactivate_vol_pan();
		cache_engine_run();
		reactivate_vol_pan();
		return $output_wav
	}
	else
	{ 
		say("Empty routing graph. Aborting."); 
		return;
	}

}

sub deactivate_vol_pan {
	unity($track, 'save_old_vol');
	pan_check($track, 50);
}
sub reactivate_vol_pan {
	pan_back($track);
	vol_back($track);
}

sub prepare_to_cache {
	# uses shared lexicals
	
 	my $g = Audio::Nama::ChainSetup::initialize();
	$orig_version = $track->monitor_version;

	#   We route the signal thusly:
	#
	#   Target track --> CacheRecTrack --> wav_out
	#
	#   CacheRecTrack slaves to target target
	#     - same name
	#     - increments track version by one
	
	my $cooked = Audio::Nama::CacheRecTrack->new(
		name   => $track->name . '_cooked',
		group  => 'Temp',
		target => $track->name,
		hide   => 1,
	);

	$g->add_path($track->name, $cooked->name, 'wav_out');

	# save the output file name to return later
	
	$output_wav = $cooked->current_wav;

	# set WAV output format
	
	$g->set_vertex_attributes(
		$cooked->name, 
		{ format => signal_format($config->{cache_to_disk_format},$cooked->width),
		}
	); 

	# Case 1: Caching a standard track
	
	if($track->rec_status eq 'MON')
	{
		# set the input path
		$g->add_path('wav_in',$track->name);
		logpkg(__FILE__,__LINE__,'debug', "The graph after setting input path:\n$g");

		$complete_caching_ref = \&update_cache_map;
	}

	# Case 2: Caching a sub-bus mix track

	elsif($track->rec_status eq 'REC'){

		# apply all sub-buses (unneeded ones will be pruned)
		map{ $_->apply($g) } grep{ (ref $_) =~ /Sub/ } Audio::Nama::Bus::all()
	}

	logpkg(__FILE__,__LINE__,'debug', "The graph after bus routing:\n$g");
	Audio::Nama::ChainSetup::prune_graph();
	logpkg(__FILE__,__LINE__,'debug', "The graph after pruning:\n$g");
	Audio::Nama::Graph::expand_graph($g); 
	logpkg(__FILE__,__LINE__,'debug', "The graph after adding loop devices:\n$g");
	Audio::Nama::Graph::add_inserts($g);
	logpkg(__FILE__,__LINE__,'debug', "The graph with inserts:\n$g");
	my $success = Audio::Nama::ChainSetup::process_routing_graph();
	if ($success) 
	{ 
		Audio::Nama::ChainSetup::write_chains();
		Audio::Nama::ChainSetup::remove_temporary_tracks();
	}
	$success
}
sub cache_engine_run { # uses shared lexicals

	connect_transport('quiet')
		or say("Couldn't connect engine! Aborting."), return;

	# remove fades from target track
	
	Audio::Nama::Effects::remove_op($track->fader) if defined $track->fader;

	$processing_time = $setup->{audio_length} + $additional_time;
	# ??? where is $setup->{audio_length} set??

	say $/,$track->name,": processing time: ". d2($processing_time). " seconds";
	print "Starting cache operation. Please wait.";
	
	revise_prompt(" "); 

	# we try to set processing time this way
	eval_iam("cs-set-length $processing_time"); 

	eval_iam("start");

	# ensure that engine stops at completion time
 	$engine->{events}->{poll_engine} = AE::timer(1, 0.5, \&poll_cache_progress);

	# complete_caching() contains the remainder of the caching code.
	# It is triggered by stop_polling_cache_progress()
}
sub complete_caching {
	# uses shared lexicals
	
	my $name = $track->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		
		&$complete_caching_ref if defined $complete_caching_ref;
		post_cache_processing();

	} else { say "track cache operation failed!"; }
}
sub update_cache_map {

		logpkg(__FILE__,__LINE__,'debug', "updating track cache_map");
		logpkg(__FILE__,__LINE__,'debug',
			sub {
				join "\n","cache map", 
				map{json_out($_)} Audio::Nama::EffectChain::find(track_cache => 1)
			});
		my @inserts_list = Audio::Nama::Insert::get_inserts($track->name);
		my @ops_list = $track->fancy_ops;
		if ( @inserts_list or @ops_list )
		{
			my $ec = Audio::Nama::EffectChain->new(
				track_cache => 1,
				track_name	=> $track->name,
				track_version_original => $orig_version,
				track_version_result => $track->last,
				project => 1,
				system => 1,
				ops_list => \@ops_list,
				inserts_data => \@inserts_list,
			);
			map{ remove_effect($_) } @ops_list;
			map{ $_->remove        } @inserts_list;

		say qq(Saving effects for cached track "), $track->name, '".';
		say qq('uncache' will restore effects and set version $orig_version\n);
		}
}

sub post_cache_processing {

		# only set to MON tracks that would otherwise remain
		# in a REC status
		#
		# track:REC bus:MON -> keep current state
		# track:REC bus:REC -> set track to MON

		$track->set(rw => 'MON') if $track->rec_status eq 'REC';

		$ui->global_version_buttons(); # recreate
		$ui->refresh();
		reconfigure_engine();
		revise_prompt("default"); 
}
sub poll_cache_progress {

	print ".";
	my $status = eval_iam('engine-status'); 
	my $here   = eval_iam("getpos");
	update_clock_display();
	logpkg(__FILE__,__LINE__,'debug', "engine time:   ". d2($here));
	logpkg(__FILE__,__LINE__,'debug', "engine status:  $status");

	return unless 
		   $status =~ /finished|error|stopped/ 
		or $here > $processing_time;

	say "Done.";
	logpkg(__FILE__,__LINE__,'debug', engine_status(current_position(),2,1));
	#revise_prompt();
	stop_polling_cache_progress();
}
sub stop_polling_cache_progress {
	$engine->{events}->{poll_engine} = undef; 
	$ui->reset_engine_mode_color_display();
	complete_caching();

}
} # end shared lexicals for cache_track and merge_edits

sub uncache_track { 
	my $track = shift;
	local $this_track;
	# skip unless MON;
	throw($track->name, ": cannot uncache unless track is set to MON"), return
		unless $track->rec_status eq 'MON';
	my $version = $track->monitor_version;
	my ($ec) = is_cached($track, $version);
	defined $ec or throw($track->name, ": version $version is not cached"),
		return;

		# blast away any existing effects, TODO: warn or abort	
		say $track->name, ": removing user effects" if $track->fancy_ops;
		map{ remove_effect($_)} $track->fancy_ops;

	# CASE 1: an ordinary track, 
	#
	# * toggle to the old version
	# * load the effect chain 
	#
			$track->set(version => $ec->track_version_original);
			print $track->name, ": setting uncached version ", $track->version, 
$/;
	# CASE 2: a sub-bus mix track, set to REC for caching operation.

	if( my $bus = $bn{$track->name}){
			$track->set(rw => 'REC') ;
			say $track->name, ": setting sub-bus mix track to REC";
	}

		$ec->add($track) if defined $ec;
}
sub is_cached {
	my ($track, $version) = @_;
	my @results = Audio::Nama::EffectChain::find(
		project 				=> 1, 
		track_cache 			=> 1,
		track_name 				=> $track->name, 
		track_version_result 	=> $version,
	);
	scalar @results > 1 
		and warn ("more than one EffectChain matching query!, found", 
			map{ json_out($_) } @results);
	$results[-1]
}
1;
__END__