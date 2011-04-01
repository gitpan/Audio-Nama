# ---------- Persistent State Support -------------


package Audio::Nama;
use Modern::Perl;
use File::Slurp;
use Audio::Nama::Assign qw(quote_yaml_scalars);
no warnings 'uninitialized';

our (

	$saved_version,
	$cop_id,
	%cops,
	%copp,
	%copp_exp,
	$unit,
	%oid_status,
	@tracks_data,
	@bus_data,
	@groups_data,
	@marks_data,
	@fade_data,
	@edit_data,
	@inserts_data,
	@loop_endpoints,
	$loop_enable,
	$length,
	%bunch,
	@command_history,
	$mastering_mode,
	$main_out,
	%old_vol,
	$this_track_name,
	$this_op,


# autosave

	$autosave_interval,
	%event_id,

);

our (
	$state_store_file,
	$effect_chain_file,
	$effect_profile_file,
	%effect_chain,
	%effect_profile,
	%tn,
	%ti,
	%bn,
	$term,
	$this_track,
	$this_bus,
	@persistent_vars,
	$ui,
	$VERSION,
	%opts,
	$debug, 
	$debug2,
	$debug3
);

sub save_state {
	my $file = shift || $state_store_file; 
	$debug2 and print "&save_state\n";
	$saved_version = $VERSION;


	# some stuff get saved independently of our state file
	
	$debug and print "saving palette\n";
	$ui->save_palette;

	# do nothing more if only Master and Mixdown
	
	if (scalar @Audio::Nama::Track::all == 2 ){
		print "No user tracks, skipping...\n";
		return;
	}

	print "\nSaving state as ",
	save_system_state($file), "\n";
	save_effect_chains();
	save_effect_profiles();

	# store alsa settings

	if ( $opts{a} ) {
		my $file = $file;
		$file =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $file.alsa store);
	}
}
sub initialize_serialization_arrays {
	@tracks_data = (); # zero based, iterate over these to restore
	@bus_data = (); # 
	@marks_data = ();
	@fade_data = ();
	@inserts_data = ();
	@edit_data = ();
	@command_history = ();
}

sub save_system_state {

	my $file = shift;

	# save stuff to state file

	$file = join_path(project_dir(), $file) unless $file =~ m(/); 
	$file =~ /\.yml$/ or $file .= '.yml';	

	sync_effect_parameters(); # in case a controller has made a change

	# remove null keys in %cops and %copp
	
	delete $cops{''};
	delete $copp{''};

	initialize_serialization_arrays();
	
	# prepare tracks for storage
	
	$this_track_name = $this_track->name;

	$debug and print "copying tracks data\n";

	map { push @tracks_data, $_->hashref } Audio::Nama::Track::all();
	# print "found ", scalar @tracks_data, "tracks\n";

	# delete unused fields
	map { my $t = $_;
				map{ delete $t->{$_} } 
					qw(ch_r ch_m source_select send_select jack_source jack_send);
	} @tracks_data;

	$debug and print "copying bus data\n";

	map{ push @bus_data, $_->hashref } Audio::Nama::Bus::all();

	# prepare inserts data for storage
	
	$debug and print "copying inserts data\n";
	
	while (my $k = each %Audio::Nama::Insert::by_index ){ 
		push @inserts_data, $Audio::Nama::Insert::by_index{$k}->hashref;
	}

	# prepare marks data for storage (new Mark objects)

	$debug and print "copying marks data\n";
	push @marks_data, map{ $_->hashref } Audio::Nama::Mark::all();

	push @fade_data,  map{ $_->hashref } values %Audio::Nama::Fade::by_index;

	push @edit_data,  map{ $_->hashref } values %Audio::Nama::Edit::by_index;

	# save history -- 50 entries, maximum

	my @history = $Audio::Nama::term->GetHistory;
	my %seen;
	map { push @command_history, $_ 
			unless $seen{$_}; $seen{$_}++ } @history;
	my $max = scalar @command_history;
	$max = 50 if $max > 50;
	@command_history = @command_history[-$max..-1];
	$debug and print "serializing\n";

	serialize(
		file => $file, 
		format => 'yaml',
		vars => \@persistent_vars,
		class => 'Audio::Nama',
		);


	$file
}
sub restore_state {
	$debug2 and print "&restore_state\n";
	my $file = shift;
	$file = $file || $state_store_file;
	$file = join_path(project_dir(), $file)
		unless $file =~ m(/);
	$file .= ".yml" unless $file =~ /yml$/;
	! -f $file and (print "file not found: $file\n"), return;
	$debug and print "using file: $file\n";
	
	my $yaml = read_file($file);

	# remove empty key hash lines # fixes YAML::Tiny bug
	$yaml = join $/, grep{ ! /^\s*:/ } split $/, $yaml;

	# rewrite obsolete null hash/array substitution
	$yaml =~ s/~NULL_HASH/{}/g;
	$yaml =~ s/~NULL_ARRAY/[]/g;

	# rewrite %cops 'owns' field to []
	
	$yaml =~ s/owns: ~/owns: []/g;

	$yaml = quote_yaml_scalars( $yaml );
	
	# start marshalling with clean slate	
	
	initialize_serialization_arrays();

	# restore persistent variables

	assign_var($yaml, @persistent_vars );

	restore_effect_chains();
	restore_effect_profiles();

	##  print yaml_out \@groups_data; 
	# %cops: correct 'owns' null (from YAML) to empty array []
	
	# backward compatibility fixes for older projects

	if (! $saved_version ){

		# Tracker group is now called 'Main'
	
		map{ $_->{name} = 'Main'} grep{ $_->{name} eq 'Tracker' } @groups_data;
		
		for my $t (@tracks_data){
			$t->{group} =~ s/Tracker/Main/;
			if( $t->{source_select} eq 'soundcard'){
				$t->{source_type} = 'soundcard' ;
				$t->{source_id} = $t->{ch_r}
			}
			elsif( $t->{source_select} eq 'jack'){
				$t->{source_type} = 'jack_client' ;
				$t->{source_id} = $t->{jack_source}
			}
			if( $t->{send_select} eq 'soundcard'){
				$t->{send_type} = 'soundcard' ;
				$t->{send_id} = $t->{ch_m}
			}
			elsif( $t->{send_select} eq 'jack'){
				$t->{send_type} = 'jack_client' ;
				$t->{send_id} = $t->{jack_send}
			}
		}
	}
	if( $saved_version < 0.9986){
	
		map { 	# store insert without intermediate array

				my $t = $_;

				# use new storage format for inserts
				my $i = $t->{inserts};
				if($i =~ /ARRAY/){ 
					$t->{inserts} = scalar @$i ? $i->[0] : {}  }
				
				# initialize inserts effect_chain_stack and cache_map

				$t->{inserts} //= {};
				$t->{effect_chain_stack} //= [];
				$t->{cache_map} //= {};

				# set class for Mastering tracks

				$t->{class} = 'Audio::Nama::MasteringTrack' if $t->{group} eq 'Mastering';
				$t->{class} = 'Audio::Nama::SimpleTrack' if $t->{name} eq 'Master';

				# rename 'ch_count' field to 'width'
				
				$t->{width} = $t->{ch_count};
				delete $t->{ch_count};

				# set Mixdown track width to 2
				
				$t->{width} = 2 if $t->{name} eq 'Mixdown';
				
				# remove obsolete fields
				
				map{ delete $t->{$_} } qw( 
											delay 
											length 
											start_position 
											ch_m 
											ch_r
											source_select 
											jack_source   
											send_select
											jack_send);
		}  @tracks_data;
	}

	# jack_manual is now called jack_port
	if ( $saved_version <= 1){
		map { $_->{source_type} =~ s/jack_manual/jack_port/ } @tracks_data;
	}
	if ( $saved_version <= 1.053){ # convert insert data to object
		my $n = 0;
		@inserts_data = ();
		for my $t (@tracks_data){
			my $i = $t->{inserts};
			next unless keys %$i;
			$t->{postfader_insert} = ++$n;
			$i->{class} = 'Audio::Nama::PostFaderInsert';
			$i->{n} = $n;
			$i->{wet_name} = $t->{name} . "_wet";
			$i->{dry_name} = $t->{name} . "_dry";
			delete $t->{inserts};
			delete $i->{tracks};
			push @inserts_data, $i;
		} 
	}
	if ( $saved_version <= 1.054){ 

		for my $t (@tracks_data){

			# source_type 'track' is now  'bus'
			$t->{source_type} =~ s/track/bus/;

			# convert 'null' bus to 'Null' (which is eliminated below)
			$t->{group} =~ s/null/Null/;
		}

	}

	if ( $saved_version <= 1.055){ 

	# get rid of Null bus routing
	
		map{$_->{group}       = 'Main'; 
			$_->{source_type} = 'null';
			$_->{source_id}   = 'null';
		} grep{$_->{group} eq 'Null'} @tracks_data;

	}

	if ( $saved_version <= 1.064){ 
		map{$_->{version} = $_->{active};
			delete $_->{active}}
			grep{$_->{active}}
			@tracks_data;
	}

	$debug and print "inserts data", yaml_out \@inserts_data;


	# make sure Master has reasonable output settings
	
	map{ if ( ! $_->{send_type}){
				$_->{send_type} = 'soundcard',
				$_->{send_id} = 1
			}
		} grep{$_->{name} eq 'Master'} @tracks_data;

	if ( $saved_version <= 1.064){ 

		map{ 
			my $default_list = Audio::Nama::IO::default_jack_ports_list($_->{name});

			if( -e join_path(project_root(),$default_list)){
				$_->{source_type} = 'jack_ports_list';
				$_->{source_id} = $default_list;
			} else { 
				$_->{source_type} = 'jack_manual';
				$_->{source_id} = ($_->{target}||$_->{name}).'_in';
			}
		} grep{ $_->{source_type} eq 'jack_port' } @tracks_data;
	}
	if ( $saved_version <= 1.067){ 

		map{ $_->{current_edit} or $_->{current_edit} = {} } @tracks_data;
		map{ 
			delete $_->{active};
			delete $_->{inserts};
			delete $_->{prefader_insert};
			delete $_->{postfader_insert};
			
			# eliminate field is_mix_track
			if ($_->{is_mix_track} ){
				 $_->{source_type} = 'bus';
				 $_->{source_id}   = undef;
			}
			delete $_->{is_mix_track};

 		} @tracks_data;
	}
	if ( $saved_version <= 1.068){ 

		# initialize version_comment field
		map{ $_->{version_comment} or $_->{version_comment} = {} } @tracks_data;

		# convert existing comments to new format
		map{ 
			while ( my($v,$comment) = each %{$_->{version_comment}} )
			{ 
				$_->{version_comment}{$v} = { user => $comment }
			}
		} grep { $_->{version_comment} } @tracks_data;
	}
	# convert to new MixTrack class
	if ( $saved_version < 1.069){ 
		map {
		 	$_->{was_class} = $_->{class};
			$_->{class} = $_->{'Audio::Nama::MixTrack'};
		} 
		grep { 
			$_->{source_type} eq 'bus' or 
		  	$_->{source_id}   eq 'bus'
		} 
		@tracks_data;
	}

	#  destroy and recreate all buses

	Audio::Nama::Bus::initialize();	

	create_system_buses(); 

	# restore user buses
		
	map{ my $class = $_->{class}; $class->new( %$_ ) } @bus_data;

	my $main = $bn{Main};

	# bus should know its mix track
	
	$main->set( send_type => 'track', send_id => 'Master')
		unless $main->send_type;

	# restore user tracks
	
	my $did_apply = 0;

	# temporary turn on mastering mode to enable
	# recreating mastering tracksk

	my $current_master_mode = $mastering_mode;
	$mastering_mode = 1;

	map{ 
		my %h = %$_; 
		my $class = $h{class} || "Audio::Nama::Track";
		my $track = $class->new( %h );
	} @tracks_data;

	$mastering_mode = $current_master_mode;

	# restore inserts
	
	Audio::Nama::Insert::initialize();
	
	map{ 
		bless $_, $_->{class};
		$Audio::Nama::Insert::by_index{$_->{n}} = $_;
	} @inserts_data;

	$ui->create_master_and_mix_tracks();

	$this_track = $tn{$this_track_name} if $this_track_name;
	set_current_bus();

	map{ 
		my $n = $_->{n};

		# create gui
		$ui->track_gui($n) unless $n <= 2;

		# restore effects
		
		for my $id (@{$ti{$n}->ops}){
			$did_apply++ 
				unless $id eq $ti{$n}->vol
					or $id eq $ti{$n}->pan;
			
			add_effect({
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		}
	} @tracks_data;


	#print "\n---\n", $main->dump;  
	#print "\n---\n", map{$_->dump} Audio::Nama::Track::all();# exit; 
	$did_apply and $ui->manifest;
	$debug and print join " ", 
		(map{ ref $_, $/ } Audio::Nama::Track::all()), $/;


	# restore Alsa mixer settings
	if ( $opts{a} ) {
		my $file = $file; 
		$file =~ s/\.yml$//;
		print "restoring ALSA settings\n";
		print qx(alsactl -f $file.alsa restore);
	}

	# text mode marks 
		
	map{ 
		my %h = %$_; 
		my $mark = Audio::Nama::Mark->new( %h ) ;
	} @marks_data;


	$ui->restore_time_marks();
	$ui->paint_mute_buttons;

	# track fades
	
	map{ 
		my %h = %$_; 
		my $fade = Audio::Nama::Fade->new( %h ) ;
	} @fade_data;

	# edits 
	
	map{ 
		my %h = %$_; 
		my $edit = Audio::Nama::Edit->new( %h ) ;
	} @edit_data;

	# restore command history
	
	$term->SetHistory(@command_history);
} 
sub assign_var {
	my ($source, @vars) = @_;
	assign_vars(
				source => $source,
				vars   => \@vars,
		#		format => 'yaml', # breaks
				class => 'Audio::Nama');
}

sub save_effect_chains { # if they exist
	my $file = shift || $effect_chain_file;
	if (keys %effect_chain){
		serialize (
			file => join_path(project_root(), $file),
			format => 'yaml',
			vars => [ qw( %effect_chain ) ],
			class => 'Audio::Nama');
	}
}
sub save_effect_profiles { # if they exist
	my $file = shift || $effect_profile_file;
	if (keys %effect_profile){
		serialize (
			file => join_path(project_root(), $file),
			format => 'yaml',
			vars => [ qw( %effect_profile ) ],
			class => 'Audio::Nama');
	}
}
sub restore_effect_chains {

	my $file = join_path(project_root(), $effect_chain_file);
	return unless -e $file;

	# don't overwrite them if already present
	assign_var($file, qw(%effect_chain)) unless keys %effect_chain
}
sub restore_effect_profiles {

	my $file = join_path(project_root(), $effect_profile_file);
	return unless -e $file;

	# don't overwrite them if already present
	assign_var($file, qw(%effect_profile)) unless keys %effect_profile; 
}

# autosave

sub schedule_autosave { 
	# one-time timer 
	my $seconds = (shift || $autosave_interval) * 60;
	$event_id{autosave} = undef; # cancel any existing timer
	return unless $seconds;
	$event_id{autosave} = AE::timer($seconds,0, \&autosave);
}
sub autosave {
	if (engine_running()){ 
		schedule_autosave(1); # try again in 60s
		return;
	}
 	my $file = 'State-autosave-' . time_tag();
 	save_system_state($file);
	my @saved = autosave_files();
	my ($next_last, $last) = @saved[-2,-1];
	schedule_autosave(); # standard interval
	return unless defined $next_last and defined $last;
	if(files_are_identical($next_last, $last)){
		unlink $last;
		undef; 
	} else { 
		$last 
	}
}
sub autosave_files {
	sort File::Find::Rule  ->file()
						->name('State-autosave-*')
							->maxdepth(1)
						 	->in( project_dir());
}
sub files_are_identical {
	my ($filea,$fileb) = @_;
	my $a = read_file($filea);
	my $b = read_file($fileb);
	$a eq $b
}

1;
__END__