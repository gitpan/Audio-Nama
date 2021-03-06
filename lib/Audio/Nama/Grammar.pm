# --------------------- Command Grammar ----------------------

package Audio::Nama;
use Audio::Nama::Effect  qw(:all);
use Modern::Perl;

sub setup_grammar {

	### COMMAND LINE PARSER 

	logsub("&setup_grammar");

	$text->{commands_yml} = get_data_section("commands_yml");
	$text->{commands_yml} = quote_yaml_scalars($text->{commands_yml});
	$text->{commands} = yaml_in( $text->{commands_yml}) ;
	map
	{ 
		my $full_name = $_; 
		my $shortcuts = $text->{commands}->{$full_name}->{short};
		my @shortcuts = ();
		@shortcuts = split " ", $shortcuts if $shortcuts;
		map{ $text->{command_shortcuts}->{$_} = $full_name } @shortcuts;

	} keys %{$text->{commands}};

	$Audio::Nama::AUTOSTUB = 1;
	$Audio::Nama::RD_TRACE = 1;
	$Audio::Nama::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
	$Audio::Nama::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
	$Audio::Nama::RD_HINT   = 1; # Give out hints to help fix problems.

	$text->{grammar} = get_data_section('grammar');

	$text->{parser} = Parse::RecDescent->new($text->{grammar}) or croak "Bad grammar!\n";

	# Midish command keywords
	
	$midi->{keywords} = 
	{
			map{ $_, 1} split " ", get_data_section("midish_commands")
	};

}
sub process_line {
	state $total_effects_count;
	logsub("&process_line");
	no warnings 'uninitialized';
	my ($user_input) = @_;
	# convert hyphenated commands to underscore form
	while( my ($from, $to) = each %{$text->{hyphenated_commands}})
	{ $user_input =~ s/$from/$to/g }
	logpkg(__FILE__,__LINE__,'debug',"user input: $user_input");
	if (defined $user_input and $user_input !~ /^\s*$/) {
		$text->{term}->addhistory($user_input) 
			unless $user_input eq $text->{previous_cmd} or ! $text->{term};
		$text->{previous_cmd} = $user_input;
		if ($mode->{midish_terminal}){
				$user_input =~ /^\s*(midish_mode_off|mmx)/ 
					?  process_command($user_input)
					:  midish_command($user_input);	
		}
		else {
			my $context = context();
			my $success = process_command( $user_input );
			my $command_stamp = { context => $context, 
								  command => $user_input };
			push(@{$project->{command_buffer}}, $command_stamp);
			
			if ( 		$config->{autosave} eq 'undo'
					and $config->{use_git} 
					and $project->{name}
					and $project->{repo}
					and ! engine_running() 
			){
				local $quiet = 1;
				Audio::Nama::ChainSetup::remove_temporary_tracks();
				autosave() unless $config->{opts}->{R};
				reconfigure_engine(); # quietly, avoiding noisy reconfig below
			}
			reconfigure_engine();
		}
		# reset current track to Master if it is
		# undefined, or the track has been removed
		# from the index
		$this_track = $tn{Master} if ! $this_track or
			(ref $this_track and ! $tn{$this_track->name});
		setup_hotkeys() if $config->{hotkeys_always};
	}
	if (! engine_running() ){
		my $result = check_fx_consistency();
		logpkg(__FILE__,__LINE__,'logcluck',"Inconsistency found in effects data",
			Dumper ($result)) if $result->{is_error};
	}
	revise_prompt( $mode->{midish_terminal} and "Midish > " );
	my $output = delete $text->{output_buffer};
}
sub context {
	my $context = {};
	$context->{track} = $this_track->name;
	$context->{bus}   = $this_bus;
	$context->{op}    = $this_track->op;
	$context
}
sub process_command {
	my $input = shift;
	my $input_was = $input;

	# parse repeatedly until all input is consumed
	# return true on complete success
	# return false if any part of command fails
	
	my $was_error = 0;
	
	try {
		while (do { no warnings 'uninitialized'; $input =~ /\S/ }) { 
			logpkg(__FILE__,__LINE__,'debug',"input: $input");
			$text->{parser}->meta(\$input) or do
			{
				throw("bad command: $input_was\n"); 
				$was_error++;
				system($config->{beep_command}) if $config->{beep_command};
				last;
			};
		}
	}
	catch { $was_error++; warn "caught error: $_" };
		
	$ui->refresh; # in case we have a graphic environment
	set_current_bus();

	# select chain operator if appropriate
	# and there is a current track


	if ($this_track){
		my $FX = fxn($this_track->op);
		if ($FX and $this_track->n eq $FX->chain){
			eval_iam("c-select ".$this_track->n);
			eval_iam("cop-select ".  $FX->ecasound_effect_index);
		}
	}

	! $was_error
}
sub do_user_command {
	my($cmd, @args) = @_;
	$text->{user_command}->{$cmd}->(@args);
}	

sub do_script {

	my $name = shift;
	my $script;
	if ($name =~ / /){
		$script = $name
	}
	else {
		my $filename;
		# look in project_dir() and project_root()
		# if filename provided does not contain slash
		if( $name =~ m!/!){ $filename = $name }
		else {
			$filename = join_path(project_dir(),$name);
			if(-e $filename){}
			else{ $filename = join_path(project_root(),$name) }
		}
		-e $filename or throw("$filename: file not found. Skipping"), return;
		$script = read_file($filename)
	}
	my @lines = split "\n",$script;
	my $old_opt_r = $config->{opts}->{R};
	$config->{opts}->{R} = 1; # turn off auto reconfigure
	for my $input (@lines) { process_line($input) unless $input =~ /^\s*#/};
	$config->{opts}->{R} = $old_opt_r;
}

sub dump_all {
	my $tmp = ".dump_all";
	my $format = "json";
	my $fname = join_path( project_root(), $tmp);
	save_system_state($fname,$format);
	file_pager("$fname.$format");
}


sub user_set_current_track {
	my $cmd = shift;
	if( my $track = $tn{$cmd} || $ti{$cmd} ){
		logpkg(__FILE__,__LINE__,'debug',"Selecting track ",$track->name);
		$this_track = $track;
		set_current_bus();
		ecasound_select_chain( $this_track->n );
		1;
	}
		
}

### allow commands to abbreviate Audio::Nama::Class as ::Class # SKIP_PREPROC

{ my @namespace_abbreviations = qw(
	Assign 
	Track
	Bus
	Mark
	IO
	Graph
	Wav
	Insert
	Fade                                                      
	Edit
	Text
	Effect
	EffectChain
	ChainSetup
);

my $namespace_root = 'Audio::Nama';

sub eval_perl {
	my $code = shift;
	map{ $code =~ s/(^|[^A-Za-z])::$_/$1$namespace_root\::$_/ } @namespace_abbreviations; # SKIP_PREPROC
	my $err;
	undef $text->{eval_result};
	my @result = eval $code;
	if ($@){
		throw( "Perl command failed: \ncode: $code\nerror: $@");
		undef $@;
	}
	else { 
		no warnings 'uninitialized';
		@result = map{ dumper($_) } @result;
		$text->{eval_result} = join " ", @result;
		pager(join "\n", @result) 
	}	
}
} # end namespace abbreviations

#### Formatted text output

sub show_versions {
		no warnings 'uninitialized';
		if (@{$this_track->versions} ){
			"All versions: ". join(" ", 
				map { $_ . ( is_cached($this_track, $_)  and 'c') } @{$this_track->versions}
			). $/
		} else {}
}


sub show_send { "Send: ". $this_track->send_id. $/ 
					if $this_track->rec_status ne OFF
						and $this_track->send_id
}

sub show_bus { "Bus: ". $this_track->group. $/ if $this_track->group ne 'Main' }

sub show_effects {
	Audio::Nama::sync_effect_parameters();
	join "", map { show_effect($_) } @{ $this_track->ops };
}
sub list_effects {
	Audio::Nama::sync_effect_parameters();
	join "", "Effects on ", $this_track->name,":\n", map{ list_effect($_) } @{ $this_track->ops };
}

sub list_effect {
	my $op_id = shift;
	my $FX = fxn($op_id);
	my $line = $FX->nameline;
	$line .= q(, bypassed) if $FX->bypassed;
	($op_id eq $this_track->op ? ' *' : '  ') . $line;
}

sub show_effect {
 	my $op_id = shift;
	my $with_track = shift;
	my $FX = fxn($op_id);
	return unless $FX;
	my @lines = $FX->nameline;
	#EQ: GVerb, gverb, 1216, bypassed, famp5, neap
 	my $i = $FX->registry_index;
	my @pnames = @{$fx_cache->{registry}->[ $i ]->{params}};
	{
	no warnings 'uninitialized';
	map { push @lines, parameter_info_padded($op_id, $_) } (0..scalar @pnames - 1) 
	}
	map
	{ 	push @lines, parameter_info_padded($op_id, $_) 
	 	
	} (scalar @pnames .. (scalar @{$FX->params} - 1)  )
		if scalar @{$FX->params} - scalar @pnames - 1; 
	@lines
}
sub extended_name {
	no warnings 'uninitialized';
	my $op_id = shift;
	my $FX = fxn($op_id);
	return unless $FX;
	my $name = $FX->name;
	my $ladspa_id = $fx_cache->{ladspa_label_to_unique_id}->{$FX->type};
	$name .= " ($ladspa_id)" if $ladspa_id;
	$name .= " (bypassed)" if $FX->bypassed;
	$name;
}
sub parameter_info {
	no warnings 'uninitialized';
	my ($op_id, $parameter) = @_;  # zero based
	my $FX = fxn($op_id);
	return unless $FX;
	my $entry = $FX->about->{params}->[$parameter];
	my $name = $entry->{name};
	$name .= " (read-only)" if $entry->{dir} eq 'output';
	($parameter+1).q(. ) . $name . ": ".  $FX->params->[$parameter];
}
sub parameter_info_padded {
	" "x 4 . parameter_info(@_) . "\n";
}
sub named_effects_list {
	my @ops = @_;
	join("\n", map{ "$_ (" . fxn($_)->name. ")" } @ops), "\n";
}
 
sub show_modifiers {
	join "", "Modifiers: ",$this_track->modifiers, $/
		if $this_track->modifiers;
}
sub show_region {
	my $t = $Audio::Nama::this_track;
	return unless $t->rec_status eq PLAY;
	my @lines;
	push @lines,join " ",
		"Length:",time2($t->shifted_length),"\n";
	$t->playat and push @lines,join " ",
		"Play at:",time2($t->shifted_playat_time),
		join($t->playat, qw[ ( ) ])."\n";
	$t->region_start and push @lines,join " ",
		"Region start:",time2($t->shifted_region_start_time),
		join($t->region_start, qw[ ( ) ])."\n";
	$t->region_end and push @lines,join " ",
		"Region end:",time2($t->shifted_region_end_time),
		join($t->region_end, qw[ ( ) ])."\n";
	return(join "", @lines);
}
sub time2 {
	package Audio::Nama;
	my $n = shift;
	dn($n,3),"/",colonize(int ($n + 0.5));
}
sub show_status {
	package Audio::Nama;
	my @output;
	my @modes;
	push @modes, $mode->{preview} if $mode->{preview};
	push @modes, "master" if $mode->mastering;
	push @modes, "edit"   if Audio::Nama::edit_mode();
	push @modes, "offset run" if Audio::Nama::is_offset_run_mode();
	push @output, "Modes settings:   ", join(", ", @modes), $/ if @modes;
	my @actions;
	push @actions, "record" if grep{ ! /Mixdown/ } Audio::Nama::ChainSetup::really_recording();
	push @actions, "playback" if grep { $_->rec_status eq PLAY } 
		map{ $tn{$_} } $bn{Main}->tracks, q(Mixdown);

	# We only check Main bus for playback. 
	# buses will route their playback signals through the 
	# Main bus, however it may be that other bus mixdown
	# tracks are set to REC (with rec-to-file disabled)
	
	
	push @actions, "mixdown" if $tn{Mixdown}->rec_status eq REC;
	push @output, "Pending actions:  ", join(", ", @actions), $/ if @actions;
	push @output, "Main bus version: ",$bn{Main}->version, $/ if $bn{Main}->version;
	push @output, "Setup length is:  ", Audio::Nama::heuristic_time($setup->{audio_length}), $/; 
	push @output, "Run time limit:   ", Audio::Nama::heuristic_time($setup->{runtime_limit}), $/
      if $setup->{runtime_limit};
}
sub placeholder { 
	my $val = shift;
	return $val if defined $val and $val !~ /^\s*$/;
	$config->{use_placeholders} ? q(--) : q() 
}

sub show_inserts {
	my $output;
	$output = $Audio::Nama::Insert::by_index{$this_track->prefader_insert}->dump
		if $this_track->prefader_insert;
	$output .= $Audio::Nama::Insert::by_index{$this_track->postfader_insert}->dump
		if $this_track->postfader_insert;
	"Inserts:\n".join( "\n",map{" "x4 . $_ } split("\n",$output))."\n" if $output;
}

$text->{format_top} = <<TOP;
 No. Name            Status     Source            Destination   Vol   Pan
=========================================================================
TOP

$text->{format_divider} = '-' x 77 . "\n";

my $format_picture = <<PICTURE;
@>>  @<<<<<<<<<<<<<< @<<<<<<<<< @<<<<<<<<<<<<<<<< @<<<<<<<<<<< @>>>  @>>>
PICTURE

sub show_tracks_section {
    no warnings;
	#$^A = $text->{format_top};
    my @tracks = grep{ ref $_ } @_; # HACK! undef should not be passed
    map {   formline $format_picture, 
            $_->n,
            $_->name,
            $_->rec_status_display,
			placeholder($_->source_status),
			placeholder($_->destination),
			placeholder($_->vol_level),
			placeholder($_->pan_level),
        } @tracks;
        
	my $output = $^A;
	$^A = "";
	#$output .= show_tracks_extra_info();
	$output;
}
sub show_tracks {
	my @array_refs = @_;
	my @list = $text->{format_top};
	for( @array_refs ){
		my ($mix,$bus) = splice @$_, 0, 2;
		push @list, 
			Audio::Nama::Bus::settings_line($mix, $bus),
			show_tracks_section(@$_), 
	}
	@list
}
sub showlist {
	package Audio::Nama;

	my @list = grep{ ! $_->hide } Audio::Nama::all_tracks();
	my $section = [undef,undef,@list];
	my ($screen_lines, $columns);
	if( $text->{term} )
	{
		($screen_lines, $columns) = $text->{term}->get_screen_size();
	}

	return $section if scalar @list <= $screen_lines - 5
					or ! $screen_lines; 

	my @sections;

		push @sections, [undef,undef, map $tn{$_},qw(Master Mixdown)];
		push @sections, [$tn{Master},$bn{Main},map $tn{$_},$bn{Main}->tracks ];

	if( $mode->mastering ){

		push @sections, [undef,undef, map $tn{$_},$bn{Mastering}->tracks]

	} elsif($this_bus ne 'Main'){

		push @sections, [$tn{$this_bus},$bn{$this_bus},
					map $tn{$_}, $this_bus, $bn{$this_bus}->tracks]
	}
	@sections
}


#### Some Text Commands

sub t_load_project {
	package Audio::Nama;
	return if engine_running() and Audio::Nama::ChainSetup::really_recording();
	my $name = shift;
	pager("input name: $name\n");
	my $newname = remove_spaces($name);
	$newname =~ s(/$)(); # remove trailing slash
	throw("Project $newname does not exist\n"), return
		unless -d join_path(project_root(), $newname);
	stop_transport();
	save_state();
	load_project( name => $newname );
	pager("loaded project: $project->{name}\n");
	{no warnings 'uninitialized';
	logpkg(__FILE__,__LINE__,'debug',"load hook: $config->{execute_on_project_load}");
	}
	Audio::Nama::process_command($config->{execute_on_project_load});
}
sub t_create_project {
	package Audio::Nama;
	my $name = shift;
	load_project( 
		name => remove_spaces($name),
		create => 1,
	);
	pager("created project: $project->{name}\n");

}
sub mixdown {
	pager_newline("Enabling mixdown to file") if ! $quiet;
	$tn{Mixdown}->set(rw => REC); 
}
sub mixplay { 
	pager_newline("Setting mixdown playback mode.") if ! $quiet;
	$tn{Mixdown}->set(rw => PLAY);
	$tn{Master}->set(rw => OFF); 
	$bn{Main}->set(rw => OFF);
}
sub mixoff { 
	pager_newline("Leaving mixdown mode.") if ! $quiet;
	$tn{Mixdown}->set(rw => OFF);
	$tn{Master}->set(rw => MON); 
	$bn{Main}->set(rw => MON);
}
sub remove_fade {
	my $i = shift;
	my $fade = $Audio::Nama::Fade::by_index{$i}
		or throw("fade index $i not found. Aborting."), return 1;
	pager("removing fade $i from track " .$fade->track ."\n");
	$fade->remove;
}
sub import_audio {

	my ($track, $path, $frequency) = @_;
	
	$track->import_audio($path, $frequency);

	# check that track is audible

	$track->set(rw => PLAY);

}
sub destroy_current_wav {
	carp($this_track->name.": must be set to PLAY."), return
		unless $this_track->rec_status eq PLAY;
	$this_track->current_version or
		throw($this_track->name, 
			": No current version (track set to OFF?) Skipping."), return;
	my $wav = $this_track->full_path;
	my $reply = $text->{term}->readline("delete WAV file $wav? [n] ");
	#my $reply = chr($text->{term}->read_key()); 
	if ( $reply =~ /y/i ){
		# remove version comments, if any
		delete $this_track->{version_comment}{$this_track->current_version};
		pager("Unlinking.\n");
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		restart_wav_memoize();
	}
	$text->{term}->remove_history($text->{term}->where_history);
	$this_track->set(version => 0);  # reset
	$this_track->set(version => $this_track->current_version); 
	1;
}

sub pan_check {
	my ($track, $new_position) = @_;
	my $current = $track->pan_o->params->[0];
	$track->set(old_pan_level => $current)
		unless defined $track->old_pan_level;
	update_effect(
		$track->pan,	# id
		0, 					# parameter
		$new_position,		# value
	);
}

sub remove_track_cmd {
	my ($track) = @_;
	
	# avoid having ownerless SlaveTracks.  
 	Audio::Nama::ChainSetup::remove_temporary_tracks();
		$quiet or pager( "Removing track /",$track->name,"/.  All WAV files will be kept.");
		remove_submix_helper_tracks($track->name);
		$track->remove;
		$this_track = $tn{Master};
		1
}
sub unity {
	my ($track, $save_level) = @_;
	if ($save_level){
		$track->set(old_vol_level => fxn($track->vol)->params->[0]);
	}
	update_effect( 
		$track->vol, 
		0, 
		$config->{unity_level}->{fxn($track->vol)->type}
	);
}
sub vol_back {
	my $track = shift;
	my $old = $track->old_vol_level;
	if (defined $old){
		update_effect(
			$track->vol,	# id
			0, 					# parameter
			$old,				# value
		);
		$track->set(old_vol_level => undef);
	}
}
	
sub pan_back {
	my $track = shift;
	my $old = $track->old_pan_level;
	if (defined $old){
		update_effect(
			$track->pan,	# id
			0, 					# parameter
			$old,				# value
		);
		$track->set(old_pan_level => undef);
	}
}