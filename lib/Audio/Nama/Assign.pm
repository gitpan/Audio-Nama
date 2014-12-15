package Audio::Nama::Assign;
use Modern::Perl;
our $VERSION = 1.0;
use 5.008;
use feature 'state';
use strict;
use warnings;
no warnings q(uninitialized);
use Carp;
use YAML::Tiny;
use File::Slurp;
use File::HomeDir;
use Audio::Nama::Log qw(logsub);
use Storable qw(nstore retrieve);
use JSON::XS;
use Data::Dumper::Concise;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
		
		serialize
		assign
		assign_singletons
		assign_pronouns
		assign_serialization_arrays
		store_vars
		yaml_out
		yaml_in
		json_in
		json_out
		quote_yaml_scalars
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();

our $to_json = JSON::XS->new->utf8->allow_blessed->pretty->canonical(1) ;
use Carp;

my $logger = Log::Log4perl->get_logger();

{my $var_map = { qw(

	$project_name				$project->{name}
	$saved_version 				$project->{save_file_version_number}
	%bunch						$project->{bunch}
	**							$project->{repo}
	$main_bus 					$bn{Main}
	$main						$bn{Main} 
	$null_bus					$bn{null}
	%abbreviations				$config->{abbreviations}
	$serialize_formats          $config->{serialize_formats}
	$mix_to_disk_format 		$config->{mix_to_disk_format}
	$raw_to_disk_format 		$config->{raw_to_disk_format}
	$cache_to_disk_format 		$config->{cache_to_disk_format}
	$mixer_out_format 			$config->{mixer_out_format}
	$use_pager     				$config->{use_pager}
	$use_placeholders  			$config->{use_placeholders}
	%is_system_bus 				$config->{_is_system_bus}
	**							$config->{sample_rate}
	$use_git					$config->{use_git}
	**							$config->{no_fade_mute_delay}
	$jack_running  				$jack->{jackd_running}
	$jack_lsp      				$jack->{ports_list_text}
	$fake_jack_lsp 				$jack->{fake_ports_list}
	%jack						$jack->{clients}
	**							$jack->{period}
	$old_snapshot  				$setup->{_old_snapshot}
	%old_rw       				$setup->{_old_track_rw_status}
	%already_used 				$setup->{inputs_used}
	%duplicate_inputs 			$setup->{tracks_with_duplicate_inputs}
	%cooked_record_pending 		$setup->{cooked_record_pending}
	$track_snapshots 			$setup->{track_snapshots}
	$regenerate_setup 			$setup->{changed}
	%wav_info					$setup->{wav_info}	
	$run_time					$setup->{runtime_limit}
	@loop_endpoints 			$setup->{loop_endpoints}
	$length						$setup->{audio_length}
    $offset_run_start_time 		$setup->{offset_run}->{start_time}
    $offset_run_end_time   		$setup->{offset_run}->{end_time}
    $offset_mark           		$setup->{offset_run}->{mark}
    @edit_points           		$setup->{edit_points}
	$dummy						$setup->{_last_rec_tracks}
	**							$setup->{latency}
	** 							$setup->{latency_graph}
	**							$setup->{final_graph}
    @effects        			$fx_cache->{registry}
    %effect_i       			$fx_cache->{full_label_to_index}
    %effect_j       			$fx_cache->{partial_label_to_full}
    @effects_help   			$fx_cache->{user_help}
    @ladspa_sorted  			$fx_cache->{ladspa_sorted}
    %effects_ladspa 			$fx_cache->{ladspa}
    %effects_ladspa_file 		$fx_cache->{ladspa_id_to_filename}
    %ladspa_unique_id  			$fx_cache->{ladspa_label_to_unique_id}
    %ladspa_label  				$fx_cache->{ladspa_id_to_label}
    %ladspa_help    			$fx_cache->{ladspa_help}
    %e_bound        			$fx_cache->{split}
	$help_screen  				$help->{screen}
	@help_topic   				$help->{arr_topic}
	%help_topic   				$help->{topic}
	$preview      				$mode->{preview}
    $eager_mode					$mode->{eager}
    $offset_run_flag 			$mode->{offset_run}
    $soloing       				$mode->{soloing}
	$loop_enable 				$mode->{loop_enable}
	$mastering_mode				$mode->{mastering}
	%event_id    				$engine->{events}
	$sock 						$engine->{socket}
	@ecasound_pids				$engine->{pids}
	$e							$engine->{ecasound}
	**							$engine->{buffersize}
	$cop_hints_yml 				$fx->{ecasound_effect_hints}
	%offset        				$fx->{offset}
	@already_muted  			$fx->{muted}
	%effect_chain 				$fx->{chain}
	%effect_profile 			$fx->{profile}
	%mute_level					$config->{mute_level}
	%fade_out_level 			$config->{fade_out_level}
	$fade_resolution 			$config->{fade_resolution}
	%unity_level				$config->{unity_level}
	$cop_id 					$fx->{id_counter}
	%cops		 				$fx->{applied}
	%copp						$fx->{params}
	%copp_exp   				$fx->{params_log}
	%midish_command				$midi->{keywords}
	$midi_input_dev    			$midi->{input_dev}
	$midi_output_dev   			$midi->{output_dev}
	$controller_ports			$midi->{controller_ports}
    $midi_inputs				$midi->{inputs}
	$grammar					$text->{grammar}
	$parser						$text->{parser}
	$text_wrap					$text->{wrap}
	@format_fields 				$text->{format_fields}
	$commands_yml				$text->{commands_yml}
	%commands					$text->{commands}
	%iam_cmd					$text->{iam}
	@nama_commands 				$text->{arr_nama_cmds}
	%nama_commands				$text->{nama_commands}
	$term 						$text->{term}
	$previous_text_command 		$text->{previous_cmd}
	@keywords      				$text->{keywords}
    $prompt						$text->{prompt}
	$attribs       				$text->{term_attribs}
	$format_top    				$text->{format_top}
	$format_divider				$text->{format_divider}
	%user_command 				$text->{user_command}
	%user_alias   				$text->{user_alias}
	@command_history 			$text->{command_history}
	$dummy						$mode->{_eager_opt}
	%devices 						$config->{devices}
	$alsa_playback_device 			$config->{alsa_playback_device}
	$alsa_capture_device			$config->{alsa_capture_device}
	$soundcard_channels				$config->{soundcard_channels}
	$memoize       					$config->{memoize}
	$hires        					$config->{hires_timer}
	%opts          					$config->{opts}
	$default						$config->{default}	
	$project_root 	 				$config->{root_dir}
	$use_group_numbering 			$config->{use_group_numbering}
	$press_space_to_start_transport $config->{press_space_to_start}
	$execute_on_project_load 		$config->{execute_on_project_load}
	$initial_user_mode 				$config->{initial_mode}
	$midish_enable 					$config->{use_midish}
	$use_jack_plumbing 				$config->{use_jack_plumbing}
	$quietly_remove_tracks 			$config->{quietly_remove_tracks}
	$use_monitor_version_for_mixdown $config->{sync_mixdown_and_monitor_version_numbers} 
	$volume_control_operator 		$config->{volume_control_operator}
	$tk_input_channels 				$config->{soundcard_channels}
	$disable_auto_reconfigure 		$config->{disable_auto_reconfigure}
    $edit_playback_end_margin  		$config->{edit_playback_end_margin}
    $edit_crossfade_time  			$config->{edit_crossfade_time}
	$default_fade_length 			$config->{engine_fade_default_length}
	$fade_time 						$config->{engine_fade_length_on_start_stop}
	$jack_seek_delay    			$config->{engine_base_jack_seek_delay}
	$seek_delay    					$config->{engine_jack_seek_delay}
	$ecasound_tcp_port 				$config->{engine_tcp_port}
	$ecasound_globals_general		$config->{engine_globals_general}
	$ecasound_globals_realtime 		$config->{engine_globals_realtime}
	$ecasound_globals_nonrealtime 	$config->{engine_globals_nonrealtime}
	$ecasound_buffersize_realtime	$config->{engine_buffersize_realtime}
	$ecasound_buffersize_nonrealtime	$config->{engine_buffersize_nonrealtime}
	$effects_cache_file 			$file->{effects_cache}
	** 								$file->{global_effect_chains}
	**								$file->{project_effect_chains}
	$state_store_file				$file->{state_store}
	$effect_chain_file 				$file->{effect_chain}
	$effect_profile_file 			$file->{effect_profile}
	$chain_setup_file 				$file->{chain_setup}
	$user_customization_file 		$file->{user_customization}
	$palette_file  					$file->{gui_palette}
	$custom_pl    					$file->{custom_pl}
	@mastering_track_names			$mastering->{track_names}
	@mastering_effect_ids			$mastering->{fx_ids}
	$eq 							$mastering->{fx_eq}
	$low_pass 						$mastering->{fx_low_pass}
	$mid_pass						$mastering->{fx_mid_pass}
	$high_pass						$mastering->{fx_high_pass}
	$compressor						$mastering->{fx_compressor}
	$spatialiser					$mastering->{fx_spatialiser}
	$limiter						$mastering->{fx_limiter}
	$unit							$gui->{_seek_unit}
	$project						$gui->{_project_name}
	$track_name						$gui->{_track_name}
	$ch_r							$gui->{_chr}
	$ch_m							$gui->{_chm}
	$save_id						$gui->{_save_id}
	$mw 							$gui->{mw}
	$ew 							$gui->{ew}
	$canvas 						$gui->{canvas}
	$load_frame    					$gui->{load_frame}
	$add_frame     					$gui->{add_frame}
	$group_frame   					$gui->{group_frame}
	$time_frame						$gui->{time_frame}
	$clock_frame   					$gui->{clock_frame}
	$track_frame   					$gui->{track_frame}
	$effect_frame  					$gui->{fx_frame}
	$iam_frame						$gui->{iam_frame}
	$perl_eval_frame 				$gui->{perl_frame}
	$transport_frame 				$gui->{transport_frame}
	$mark_frame						$gui->{mark_frame}
	$fast_frame 					$gui->{seek_frame}
	%parent  						$gui->{parents}
	$group_label  					$gui->{group_label}
	$group_rw 						$gui->{group_rw}
	$group_version 					$gui->{group_version} 
	%track_widget 					$gui->{tracks}
	%track_widget_remove 			$gui->{tracks_remove}
	%effects_widget 				$gui->{fx}
	%mark_widget  					$gui->{marks}
	@global_version_buttons 		$gui->{global_version_buttons}
	$mark_remove   					$gui->{mark_remove}
	$markers_armed 					$gui->{_markers_armed}
	$time_step     					$gui->{seek_unit}
	$clock 							$gui->{clock}
	$setup_length  					$gui->{setup_length}
	$project_label					$gui->{project_head}
	$sn_label						$gui->{project_label}
	$sn_text       					$gui->{project_entry}
	$sn_load						$gui->{load_project}
	$sn_new							$gui->{new_project}
	$sn_quit						$gui->{quit}
	$sn_palette 					$gui->{palette}
	$sn_namapalette 				$gui->{nama_palette}
	$sn_effects_palette 			$gui->{fx_palette}
	$sn_save_text  					$gui->{savefile_entry}
	$sn_save						$gui->{save_project}	
	$sn_recall						$gui->{load_savefile}
	@palettefields 					$gui->{_palette_fields}
	@namafields    					$gui->{_nama_fields}
	%namapalette   					$gui->{_nama_palette}
	%palette 						$gui->{_palette} 
	$build_track_label 				$gui->{add_track}->{label}
	$build_track_text 				$gui->{add_track}->{text_entry}
	$build_track_add_mono 			$gui->{add_track}->{add_mono}
	$build_track_add_stereo 		$gui->{add_track}->{add_stereo}
	$build_track_rec_label 			$gui->{add_track}->{rec_label}
	$build_track_rec_text 			$gui->{add_track}->{rec_text}
	$build_track_mon_label 			$gui->{add_track}->{mon_label}
	$build_track_mon_text  			$gui->{add_track}->{mon_text}
	$transport_label 				$gui->{engine_label}
	$transport_setup_and_connect 	$gui->{engine_arm}
	$transport_disconnect 			$gui->{engine_disconnect}
	$transport_start 				$gui->{engine_start}
	$transport_stop  				$gui->{engine_stop}
	$old_bg 						$gui->{_old_bg}
	$old_abg 						$gui->{_old_abg}
	**								$config->{fade_time1_fraction}
	**								$config->{fade_down_fraction}
	**								$config->{fade_time2_fraction}
	**								$config->{fade_down_fraction}
	**								$config->{fader_op}
	**								$config->{serialize_formats}
	**								$project->{config}
	$beep_command 					$config->{beep_command}
	$enforce_channel_bounds    $config->{enforce_channel_bounds}

) };
sub var_map {  $var_map } # to allow outside access while keeping
                          # working lexical


sub assign {
  # Usage: 
  # assign ( 
  # data 	=> $ref,
  # vars 	=> \@vars,
  # var_map => 1,
  #	class => $class
  #	);

	logsub("&assign");
	
	my %h = @_; # parameters appear in %h
	my $class;
	$logger->logcarp("didn't expect scalar here") if ref $h{data} eq 'SCALAR';
	$logger->logcarp("didn't expect code here") if ref $h{data} eq 'CODE';
	# print "data: $h{data}, ", ref $h{data}, $/;

	if ( ref $h{data} !~ /^(HASH|ARRAY|CODE|GLOB|HANDLE|FORMAT)$/){
		# we guess object
		$class = ref $h{data}; 
		$logger->debug("I found an object of class $class");
	} 
	$class = $h{class};
 	$class .= "::" unless $class =~ /::$/;  # SKIP_PREPROC
	my @vars = @{ $h{vars} };
	my $ref = $h{data};
	my $type = ref $ref;
	$logger->debug(<<ASSIGN);
	data type: $type
	data: $ref
	class: $class
	vars: @vars
ASSIGN
	#$logger->debug(sub{yaml_out($ref)});

	# index what sigil an identifier should get

	# we need to create search-and-replace strings
	# sigil-less old_identifier
	my %sigil;
	my %ident;
	map { 
		my $oldvar = my $var = $_;
		my ($dummy, $old_identifier) = /^([\$\%\@])([\-\>\w:\[\]{}]+)$/;
		$var = $var_map->{$var} if $h{var_map} and $var_map->{$var};

		$logger->debug("oldvar: $oldvar, newvar: $var");
		my ($sigil, $identifier) = $var =~ /([\$\%\@])(\S+)/;
			$sigil{$old_identifier} = $sigil;
			$ident{$old_identifier} = $identifier;
	} @vars;

	$logger->debug(sub{"SIGIL\n". yaml_out(\%sigil)});
	$logger->debug(sub{"IDENT\n". yaml_out(\%ident)});
	
	#print join " ", "Variables:\n", @vars, $/ ;
	croak "expected hash" if ref $ref !~ /HASH/;
	my @keys =  keys %{ $ref }; # identifiers, *no* sigils
	$logger->debug(sub{ join " ","found keys: ", keys %{ $ref },"\n---\n"});
	map{  
		my $eval;
		my $key = $_;
		chomp $key;
		my $sigil = $sigil{$key};
		my $full_class_path = 
 			$sigil . ($key =~/:\:/ ? '': $class) .  $ident{$key};

			# use the supplied class unless the variable name
			# contains \:\:
			
		$logger->debug(<<DEBUG);
key:             $key
sigil:      $sigil
full_class_path: $full_class_path
DEBUG
		if ( ! $sigil ){
			$logger->logwarn(sub{
			"didn't find a match for $key in ", join " ", @vars, $/;
			});
		} 
		else 
		{

			$eval .= $full_class_path;
			$eval .= q( = );

			my $val = $ref->{$key};

			if (! ref $val or ref $val eq 'SCALAR')  # scalar assignment
			{

				# extract value

				if ($val) { #  if we have something,

					# dereference it if needed
					
					ref $val eq q(SCALAR) and $val = $$val; 
															
					# quoting for non-numerical
					
					$val = qq("$val") unless  $val =~ /^[\d\.,+\-e]+$/ 
			
				} else { $val = q(undef) }; # or set as undefined

				$eval .=  $val;  # append to assignment

			} 
			elsif ( ref $val eq 'ARRAY' or ref $val eq 'HASH')
			{ 
				if ($sigil eq '$')	# assign reference
				{				
					$eval .= q($val) ;
				}
				else				# dereference and assign
				{
					$eval .= qq($sigil) ;
					$eval .= q({$val}) ;
				}
			}
			else { die "unsupported assignment: ".ref $val }
			$logger->debug("eval string: $eval"); 
			eval($eval);
			$logger->logcarp("failed to eval $eval: $@") if $@;
		}  # end if sigil{key}
	} @keys;
	1;
}
}

# assign_singletons() assigns hash key/value entries
# rather than a top-level hash reference to avoid
# clobbering singleton key/value pairs initialized
# elsewhere.
 
my @singleton_idents = map{ /^.(.+)/; $1 }  # remove leading '$' sigil
qw(
$ui
$mode
$file
$graph
$setup
$config
$jack
$fx
$fx_cache
$engine
$text
$gui
$midi
$help
$mastering
$project

);
sub assign_singletons {
	my $ref = shift;
	my $data = $ref->{data} or die "expected data got undefined";
	my $class = $ref->{class} // 'Audio::Nama';
	$class .= '::'; # SKIP_PREPROC
	map {
		my $ident = $_;
		if( defined $data->{$ident}){
			my $type = ref $data->{$ident};
			$type eq 'HASH' or die "$ident: expect hash, got $type";
			map{ 
				my $key = $_;
				my $cmd = join '',
					'$',
					$class,
					$ident,
					'->{',
					$key,
					'}',
					' = $data->{$ident}->{$key}';
				$logger->debug("eval: $cmd");
				eval $cmd;
				$logger->logcarp("error during eval: $@") if $@;
			} keys %{ $data->{$ident} }
		}
	} @singleton_idents;
}
sub assign_pronouns {
	my $ref = shift;
	my $data = $ref->{data} or die "expected data got undefined";
	my $class = $ref->{class} // 'Audio::Nama';
	$class .= '::'; # SKIP_PREPROC
	my @pronouns = qw(this_op this_track_name);
	map { 
		my $ident = @_;
		if( defined $data->{$ident} ){
			my $type = ref $data->{$ident};
			die "$ident: expected scalar, got $type" if $type;
			my $cmd = q($).$class.$ident. q( = $data->{$ident});
			$logger->debug("eval: $cmd");
			eval $cmd;
			$logger->logcarp("error during eval: $@") if $@;
		}
	} @pronouns;
}

{
my @arrays = map{ /^.(.+)/; $1 }  # remove leading '@' sigil
qw(
@tracks_data
@bus_data
@groups_data
@marks_data
@fade_data
@edit_data
@inserts_data
@global_effect_chain_vars
@global_effect_chain_data
@project_effect_chain_data
$this_track_name

);
sub assign_serialization_arrays {
	my $ref = shift;
	my $data = $ref->{data} or die "expected data got undefined";
	my $class = $ref->{class} // 'Audio::Nama';
	$class .= '::'; # SKIP_PREPROC
	map {
		my $ident = $_;
		if( defined $data->{$ident} ){
			my $type = ref $data->{$ident};
			$type eq 'ARRAY' or die "$ident: expected ARRAY, got $type";
			my $cmd = q($).$class.$ident. q( = @{$data->{$ident}});
			#my $cmd = q(*).$class.$ident. q( = $data->{$ident});
			$logger->debug("eval: $cmd");
			eval $cmd;
			$logger->logcarp("error during eval: $@") if $@;
		}
	} @arrays;
}
}

our %suffix = 
	(
		storable => "bin",
		perl	 => "pl",
		json	 => "json",
		yaml	 => "yml",
	);
our %dispatch = 
	( storable => sub { my($ref, $path) = @_; nstore($ref, $path) },
	  perl     => sub { my($ref, $path) = @_; write_file($path, Dumper $ref) },
	  yaml	   => sub { my($ref, $path) = @_; write_file($path, yaml_out($ref))},
	  json	   => sub { my($ref, $path) = @_; write_file($path, json_out($ref))},
	);

sub serialize_and_write {
	my ($ref, $path, $format) = @_;
	$path .= ".$suffix{$format}" unless $path =~ /\.$suffix{$format}$/;
	$dispatch{$format}->($ref, $path)
}


{
	my $parse_re =  		# initialize only once
			qr/ ^ 			# beginning anchor
			([\%\@\$]) 		# first character, sigil
			([\w:]+)		# identifier, possibly perl namespace 
			(?:->{(\w+)})?  # optional hash key for new hash-singleton vars
			$ 				# end anchor
			/x;
sub serialize {
	logsub("&serialize");

	my %h = @_;
	my @vars = @{ $h{vars} };
	my $class = $h{class};
	my $file  = $h{file};
	my $format = $h{format} // 'perl'; # default to Data::Dumper::Concise

 	$class //= "Audio::Nama";
	$class =~ /::$/ or $class .= '::'; # SKIP_PREPROC
	$logger->debug("file: $file, class: $class\nvariables...@vars");

	# first we marshall data into %state

	my %state;

	map{ 
		my ($sigil, $identifier, $key) = /$parse_re/;

	$logger->debug("found sigil: $sigil, ident: $identifier, key: $key");

# note: for  YAML::Reader/Writer  all scalars must contain values, not references
# more YAML adjustments 
# restore will break if a null field is not converted to '~'

		#my $value =  q(\\) 

# directly assign scalar, but take hash/array references
# $state{ident} = $scalar
# $state{ident} = \%hash
# $state{ident} = \@array

# in case $key is provided
# $state{ident}->{$key} = $singleton->{$key};
#
			

		my $value =  ($sigil ne q($) ? q(\\) : q() ) 

							. $sigil
							. ($identifier =~ /:/ ? '' : $class)
							. $identifier
							. ($key ? qq(->{$key}) : q());

		$logger->debug("value: $value");

			
		 my $eval_string =  q($state{')
							. $identifier
							. q('})
							. ($key ? qq(->{$key}) : q() )
							. q( = )
							. $value;

		if ($identifier){
			$logger->debug("attempting to eval $eval_string");
			eval($eval_string) 
				or $logger->error("eval returned zero or failed ($@)");
		}
	} @vars;
	$logger->debug(sub{join $/,'\%state', Dumper \%state});

	# YAML out for screen dumps
	return( yaml_out(\%state) ) unless $h{file};

	# now we serialize %state
	
	my $path = $h{file};

	serialize_and_write(\%state, $path, $format);
}
}

sub json_out {
	logsub("&json_out");
	my $data_ref = shift;
	my $type = ref $data_ref;
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	$to_json->encode($data_ref);
}

sub json_in {
	logsub("&json_in");
	my $json = shift;
	my $data_ref = decode_json($json);
	$data_ref
}

sub yaml_out {
	
	logsub("&yaml_out");
	my ($data_ref) = shift; 
	my $type = ref $data_ref;
	$logger->debug("data ref type: $type");
	$logger->logcarp("can't yaml-out a Scalar!!") if ref $data_ref eq 'SCALAR';
	$logger->logcroak("attempting to code wrong data type: $type")
		if $type !~ /HASH|ARRAY/;
	my $output;
	#$logger->debug(join " ",keys %$data_ref);
	$logger->debug("about to write YAML as string");
	my $y = YAML::Tiny->new;
	$y->[0] = $data_ref;
	my $yaml = $y->write_string() . "...\n";
}
sub yaml_in {
	
	# logsub("&yaml_in");
	my $input = shift;
	my $yaml = $input =~ /\n/ # check whether file or text
		? $input 			# yaml text
		: read_file($input);	# file name
	if ($yaml =~ /\t/){
		croak "YAML file: $input contains illegal TAB character.";
	}
	$yaml =~ s/^\n+//  ; # remove leading newline at start of file
	$yaml =~ s/\n*$/\n/; # make sure file ends with newline
	my $y = YAML::Tiny->read_string($yaml);
	print "YAML::Tiny read error: $YAML::Tiny::errstr\n" if $YAML::Tiny::errstr;
	$y->[0];
}

sub quote_yaml_scalars {
	my $yaml = shift;
	my @modified;
	map
		{  
		chomp;
		if( /^(?<beg>(\s*\w+: )|(\s+- ))(?<end>.+)$/ ){
			my($beg,$end) = ($+{beg}, $+{end});
			# quote if contains colon and not quoted
			if ($end =~ /:\s/ and $end !~ /^('|")/ ){ 
				$end =~ s(')(\\')g; # escape existing single quotes
				$end = qq('$end') } # single-quote string
			push @modified, "$beg$end\n";
		}
		else { push @modified, "$_\n" }
	} split "\n", $yaml;
	join "", @modified;
}
	

1;