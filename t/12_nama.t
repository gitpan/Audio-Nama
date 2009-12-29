package Audio::Nama;
use Test::More qw(no_plan);
use strict;
use warnings;
no warnings qw(uninitialized);
our ($expected_setup_lines);
use Cwd;

BEGIN { use_ok('Audio::Nama') };

diag ("TESTING $0\n");

our (

    # 'our' means these variables will be accessible, without
	# package qualifiers, to all packages inhabiting 
	# the same file.
	#
	# this allows us to bring our variables from 
    # procedural core into Audio::Nama::Graphical and Audio::Nama::Text
	# packages. 
	
	# it didn't work out to be as helpful as i'd like
	# because the grammar requires package path anyway

	$banner,
	$help_screen, 		# 
	@help_topic,    # array of help categories
	%help_topic,    # help text indexed by topic
	$use_pager,     # display lengthy output data using pager
	$use_placeholders,  # use placeholders in show_track output
	$text_wrap,          # Text::Format object

	$ui, # object providing class behavior for graphic/text functions

	@persistent_vars, # a set of variables we save
					  	# as one big config file
	@effects_static_vars,	# the list of which variables to store and retrieve
	@effects_dynamic_vars,		# same for all chain operators
	@config_vars,    # contained in config file
	@status_vars,    # we will dump them for diagnostic use
	%abbreviations, # for replacements in config files

	$ecasound_globals_realtime,     # .namarc field
	$ecasound_globals_default,  # .namarc field
	$ecasound_tcp_port,  # for Ecasound NetECI interface
	$saved_version, # copy of $VERSION saved with settings in State.yml


	$default,		# the internal default configuration file, as string
	$default_palette_yml, # not horriffic is about all I can say
					
	$raw_to_disk_format,
	$mix_to_disk_format,
	$mixer_out_format,
	$execute_on_project_load, # Nama text commands 
	$use_group_numbering, # same version number for tracks recorded together

	# .namarc mastering fields
    $mastering_effects, # apply on entering mastering mode
	$eq, 
	$low_pass,
	$mid_pass,
	$high_pass,
	$compressor,
	$spatialiser,
	$limiter,

	$initial_user_mode, # preview, doodle, 0, undef TODO
	
	$yw,			# yaml writer object
	$yr,			# yaml reader object
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke when we want to kill ecasound

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	%iam_cmd,		# for identifying IAM commands in user input
	@nama_commands,# array of commands my functions provide
	%nama_commands,# as hash as well
	$project_root,	# each project will get a directory here
	                # and one .nama directory, also with 
	
					#
					# $ENV{HOME}/.namarc
					# $ENV{HOME}/nama/paul_brocante
					# $ENV{HOME}/nama/paul_brocante/.wav/vocal_1.wav
					# $ENV{HOME}/nama/paul_brocante/Store.yml
					# $ENV{HOME}/nama/.effects_cache
					# $ENV{HOME}/nama/paul_brocante/.namarc 

					 #this_wav_dir = 
	$state_store_file,	# filename for storing @persistent_vars
	$effect_chain_file, # for storing effect chains
	$chain_setup_file, # Ecasound uses this 

	$tk_input_channels,# this many radiobuttons appear
	                # on the menubutton
	%cfg,        # 'config' information as hash
	%devices, 		# alias to data in %cfg
	%opts,          # command line options
	%oid_status,    # state information for the chain templates
	$use_monitor_version_for_mixdown, # sync mixdown version numbers
	              	# to selected track versions , not
					# implemented
	$this_track,	 # the currently active track -- 
					 # used by Text UI only at present
	$old_this_track, # when we need to save/restore current track
	$this_op,      # currently selected effect # future
	$this_mark,    # current mark  # for future

	@format_fields, # data for replies to text commands

	$project,		# variable for GUI text input
	$project_name,	# current project name
	%state_c,		# for backwards compatilility

	### for effects

	$cop_id, 		# chain operator id, that how we create, 
					# store, find them, adjust them, and destroy them,
					# per track or per project?
	$magical_cop_id, # cut through five levels of subroutines
	%cops,			 # chain operators stored here
	%copp,			# their parameters for effect update
	%copp_exp,      # for log-scaled sliders

# auxiliary track information - saving not required

	%offset,        # index by chain, offset for user-visible effects 
	@mastering_effect_ids,        # effect ids for mastering mode

	@effects,		# static effects information (parameters, hints, etc.)
	%effect_i,		# an index , pn:amp -> effect number
	%effect_j,      # an index , amp -> effect number
	@effects_help,  # one line per effect, for text search

	@ladspa_sorted, # ld
	%effects_ladspa, # parsed data from analyseplugin 
	%effects_ladspa_file, 
					# get plugin filename from Plugin Unique ID
	%ladspa_unique_id, 
					# get plugin unique id from plugin label
	%ladspa_label,  # get plugin label from unique id
	%ladspa_help,   # plugin_label => analyseplugin output
	$e,				# the name of the variable holding
					# the Ecasound engine object.
					
	%e_bound,		# for displaying hundreds of effects in groups
	$unit,			# jump multiplier, 1 or 60 seconds
	%old_vol,		# a copy of volume settings, for muting
	$length,		# maximum duration of the recording/playback if known
 	$jack_system,   # jack soundcard device
	$jack_running,  # jackd status (pid)
	$jack_lsp,      # jack_lsp -Ap
	%jack,			# jack clients data from jack_lsp

	@input_chains,	# list of input chain segments 
	@output_chains, # list of output chain segments
	@post_input,	# post-input chain operators
	@pre_output, 	# pre-output chain operators

	%subst,			# alias, substitutions for the config file
	$tkeca_effects_data,	# original tcl code, actually

	### Widgets
	
	$mw, 			# main window
	$ew, 			# effects window
	$canvas, 		# to lay out the effects window

	# each part of the main window gets its own frame
	# to control the layout better

	$load_frame,
	$add_frame,
	$group_frame,
	$time_frame,
	$clock_frame,
	$oid_frame,
	$track_frame,
	$effect_frame,
	$iam_frame,
	$perl_eval_frame,
	$transport_frame,
	$mark_frame,
	$fast_frame, # forward, rewind, etc.

	## collected widgets (i may need to destroy them)

	%parent, # ->{mw} = $mw; # main window
			 # ->{ew} = $ew; # effects window
			 # eventually will contain all major frames
	$group_label, 
	$group_rw, # 
	$group_version, # 
	%track_widget, # for chains (tracks)
	%track_widget_remove, # what to destroy by remove_track
	%effects_widget, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
	%mark_widget, # marks

	@global_version_buttons, # to set the same version for
						  	#	all tracks
	$markers_armed, # set true to enable removing a mark
	$mark_remove,   # a button that sets $markers_armed
	$time_step,     # widget shows jump multiplier unit (seconds or minutes)
	$clock, 		# displays clock
	$setup_length,  # displays setup running time

	$project_label,	# project name

	$sn_label,		# project load/save/quit	
	$sn_text,
	$sn_load,
	$sn_new,
	$sn_quit,
	$sn_palette, # configure default master window colors
	$sn_namapalette, # configure nama-specific master-window colors
	$sn_effects_palette, # configure effects window colors
	@palettefields, # set by setPalette method
	@namafields,    # field names for color palette used by nama
	%namapalette,     # nama's indicator colors
	%palette,  # overall color scheme
	$rec,      # background color
	$mon,      # background color
	$off,      # background color
	$palette_file, # where to save selections


	### A separate box for entering IAM (and other) commands
	$iam_label,
	$iam_text,
	$iam, # variable for text entry
	$iam_execute,
	$iam_error, # unused

	# add track gui
	#
	$build_track_label,
	$build_track_text,
	$build_track_add_mono,
	$build_track_add_stereo,
	$build_track_rec_label,
	$build_track_rec_text,
	$build_track_mon_label,
	$build_track_mon_text,

	$build_new_take,

	# transport controls
	
	$transport_label,
	$transport_setup_and_connect,
	$transport_setup, # unused
	$transport_connect, # unused
	$transport_disconnect,
	$transport_new,
	$transport_start,
	$transport_stop,

	$old_bg, # initial background color.
	$old_abg, # initial active background color

	@oids,	# output templates, are applied to the
			# chains collected previously
			# the results are grouped as
			# input, output and intermediate sections

	%inputs,
	%outputs,
	%post_input,
	%pre_output,

	$ladspa_sample_rate,	# used as LADSPA effect parameter fixed at 44100

	$track_name,	# received from Tk text input form
	%track_names,   # belongs in Track.pm
	$ch_r,			# recording channel assignment
	$ch_m,			# monitoring channel assignment


	%L,	# for effects
	%M,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated
						
	$OUT,				# filehandle for Text mode print
	#$commands,	# ref created from commands.yml
	%commands,	# created from commands.yml
	$commands_yml, # the string form of commands.yml
	$cop_hints_yml, # ecasound effects hinting

	$save_id, # text variable
	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings
	$sn_dump,  # button to dump status

	# new object core
	
	$main_bus, 
	$main, # main_group
	$null_bus,
    $null, # group

	%ti, # track by index (alias %Audio::Nama::Track::by_index)
	%tn, # track by name  (alias %Audio::Nama::Track::by_name)

	@tracks_data, # staging for saving
	@bus_data,   # 
	@groups_data, # 
	@marks_data, # 

	$alsa_playback_device,
	$alsa_capture_device,

	$main_out, # do I route audio output to soundcard?

	# rules
	
	$mon_setup,
	$rec_file,
	$rec_setup,
	$aux_send,
	$null_setup,

	$send_bus_out,
	
	# mastering mode status

	$mastering_mode,

   # marks and playback looping
   
	$clock_id,		# used in GUI for the Tk event system
					# ->cancel method not reliable
					# for 'repeat' events, so converted to
					# 'after' events
	%event_id,    # events will store themselves with a key
	@loop_endpoints, # they define the loop
	$loop_enable, # whether we automatically loop

   $previous_text_command, # i want to know if i'm repeating
	$term, 			# Term::ReadLine object
	$controller_ports, # where we listen for MIDI messages
    $midi_inputs,  # on/off/capture

	@already_muted, # for soloing list of Track objects that are 
                    # muted before we begin
    $soloing,       # one user track is on, all others are muted

	%bunch,			# user collections of tracks
	@keywords,      # for autocompletion
	$attribs,       # Term::Readline::Gnu object
	$seek_delay,    # allow microseconds for transport seek
                    # (used with JACK only)
    $prompt,        # for text mode
	$preview,       # am running engine with rec_file disabled
	%duplicate_inputs, # named tracks will be OFF in doodle mode
	%already_used,  #  source => used_by
	$memoize,       # do I cache this_wav_dir?
	$hires,        # do I have Timer::HiRes?
	$fade_time, 	# duration for fadein(), fadeout()
	$old_snapshot,  # previous status_snapshot() output
					# to check if I need to reconfigure engine
	$old_group_rw, # previous $main->rw setting
	%old_rw,       # previous track rw settings (indexed by track name)
	
	@mastering_track_names, # reserved for mastering mode
	@command_history,
	$disable_auto_reconfigure, # for debugging

	$g, 			# Graph var, for chain setup
	%cooked_record_pending, # an intermediate mixdown for tracks
	$press_space_to_start_transport, #  in text mode
	%effect_chain, # named effect sequences
	$sock, 			# socket for Net-ECI mode
	%versions,		# store active versions for use after engine run
	@io, 			# accumulate IO objects for generating setup
	$track_snapshots, # to save recalculating for each IO object
	$chain_setup,	# current chain setup
);
 
 
# variables found in namarc
#
@config_vars = qw(
						%abbreviations
						%devices
						$ecasound_globals_realtime
						$ecasound_globals_default
						$ecasound_tcp_port
						$mix_to_disk_format
						$raw_to_disk_format
						$mixer_out_format
						$alsa_playback_device
						$alsa_capture_device	
						$project_root 	
						$use_group_numbering
						$press_space_to_start_transport
						$execute_on_project_load
						$initial_user_mode
						$mastering_effects
						$eq 
						$low_pass
						$mid_pass
						$high_pass
						$compressor
						$spatialiser
						$limiter

						);

						
						
# used for saving to State.yml
#
@persistent_vars = qw(

						%cops 			
						$cop_id 		
						%copp 			
						%copp_exp
						$unit			
						%oid_status		
						%old_vol		
						$this_op
						@tracks_data
						@bus_data
						@groups_data
						@marks_data
						$loop_enable
						@loop_endpoints
						$length
						%bunch
						$mastering_mode
						@command_history
						$saved_version
						$main_out
						);
					 
# used for effects_cache 
#
@effects_static_vars = qw(

						@effects		
						%effect_i	
						%effect_j	
						%e_bound
						@ladspa_sorted
						%effects_ladspa	
						%effects_ladspa_file
						%ladspa_unique_id
						%ladspa_label
						%ladspa_help
						@effects_help
						);


# defeat namarc detection to force using $default namarc

push @ARGV, qw(-f dummy);

# set text mode (don't start gui)

push @ARGV, qw(-t); 

# use cwd as project root

push @ARGV, qw(-d .); 

# suppress loading Ecasound

push @ARGV, q(-E);

diag("working directory: ",cwd);

process_options();

prepare();
diag "Check representative variable from default .namarc";
is ( $Audio::Nama::mix_to_disk_format, "s16_le,N,44100,i", "Read mix_to_disk_format");

diag "Check static effects data read";
is ( $Audio::Nama::e_bound{cop}{z} > 40, 1, "Verify Ecasound chain operator count");

diag "Check effect hinting and help";

my $want = q(---
code: epp
count: 1
display: scale
name: Pan
params:
  -
    begin: 0
    default: 50
    end: 100
    name: 'Level %'
    resolution: 0
...
);


package Audio::Nama;
is( yaml_out($effects[$effect_i{epp}]) ,  $want , "Pan hinting");

is( $effects_help[0], 
	qq(dyn_compress_brutal,  -pn:dyn_compress_brutal:gain-%\n),
	'Preset help for dyn_compress_brutal');

is( ref $main_bus, q(Audio::Nama::Bus), 'Bus initializtion');

# SKIP: { 
# my $cs_got = eval_iam('cs');
# my $cs_want = q(### Chain status (chainsetup 'command-line-setup') ###
# Chain "default" [selected] );
# is( $cs_got, $cs_want, "Evaluate Ecasound 'cs' command");
# }

my $test_project = 'test';

load_project(name => $test_project, create => 1);

is( project_dir(), "./$test_project", "establish project directory");

command_process('Master; mono'); # so older tests work

force_alsa();

command_process('add sax');

like(ref $this_track, qr/Track/, "track creation"); 

is( $this_track->name, 'sax', "current track assignment");

command_process('source 2');

is( $this_track->source_type, 'soundcard', "set soundcard input");
is( $this_track->source_id,  2, "set input channel");

command_process('send 5');

is( $this_track->send_type, 'soundcard', 'set soundcard output');
is( $this_track->send_id, 5, 'set soundcard output');

# this is ALSA dependent (i.e. no JACK running)

my $io = Audio::Nama::IO->new(track => 'sax');

like( ref $io, qr/IO$/, 'IO base class object');

$io = Audio::Nama::IO::from_soundcard_device->new(track => 'sax'); 

is ($io->ecs_string, '-i:alsa,default', 'IO from_soundcard_device 1');
is ($io->ecs_extra, '-chmove:2,1 -chcopy:1,2', 'IO from_soundcard_device 2');

$io = Audio::Nama::IO::from_soundcard->new(track => 'sax'); 

is ($io->ecs_string, '-i:alsa,default', 'IO from_soundcard 1');
is ($io->ecs_extra, '-chmove:2,1 -chcopy:1,2', 'IO from_soundcard 2');


$io = Audio::Nama::IO::to_soundcard_device->new(track => 'sax'); 

is ($io->ecs_string, '-o:alsa,default', 'IO to_soundcard_device 1');
like ($io->ecs_extra, qr/-chmove:2,6 -chmove:1,5/, 'IO to_soundcard_device 2');

$io = Audio::Nama::IO::to_soundcard->new(track => 'sax'); 

is ($io->ecs_string, '-o:alsa,default', 'IO to_soundcard 1');
like ($io->ecs_extra, qr/-chmove:2,6 -chmove:1,5/, 'IO to_soundcard 2');

force_jack();


$io = Audio::Nama::IO::from_soundcard->new(track => 'sax'); 
like (ref $io, qr/from_jack_multi/, 'sound system ALSA/JACK detection: input');
is ($io->ecs_string, '-i:jack_multi,system:capture_2', 'IO from_soundcard: jack 1');
is ($io->ecs_extra, '-chcopy:1,2', 'IO from_soundcard: jack 2');


$io = Audio::Nama::IO::to_soundcard->new(track => 'sax'); 
like (ref $io, qr/to_jack_multi/, 'sound system ALSA/JACK detection: output');

is ($io->ecs_string, '-o:jack_multi,system:playback_5', 'IO to_soundcard: jack 1');
ok (! $io->ecs_extra, 'IO to_soundcard: jack 2');

$io = Audio::Nama::IO::to_null->new(track => 'sax', device_id => 'alsa,default');

is ($io->device_id, 'alsa,default', 'value overrides method call');

command_process("sax; source Horgand; gen");
like( $chain_setup, qr/Horgand/, 'set JACK client as input');
command_process("sax; source jack; gen");
like( $chain_setup, qr/jack,,sax_in/, 'set JACK port for manual input');

command_process("sax; source 2");


force_alsa();

command_process('3; nosend; gen');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3,R3 -i:alsa,default

# post-input processing

-a:R3 -chmove:2,1 -chcopy:1,2
-a:3 -chmove:2,1 -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Master_in
-a:R3 -f:s16_le,1,44100,i -o:test/.wav/sax_1.wav
EXPECTED

check_setup('ALSA basic setup' );

force_jack();
command_process('gen');
$expected_setup_lines = <<EXPECTED;

# audio inputs

-a:1 -i:loop,Master_in
-a:3,R3 -i:jack_multi,system:capture_2

# post-input processing

-a:R3 -chcopy:1,2
-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1
-a:3 -o:loop,Master_in
-a:R3 -f:s16_le,1,44100,i -o:test/.wav/sax_1.wav

EXPECTED

check_setup('JACK basic setup' );

command_process('3;rec_defeat; gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1
-a:3 -o:loop,Master_in
EXPECTED

check_setup('JACK rec_defeat setup' );

force_alsa(); command_process('gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:alsa,default

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Master_in

EXPECTED

check_setup('ALSA rec_defeat setup' );
command_process('Master; send 5;gen');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:alsa,default

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:1  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Master_in
EXPECTED

check_setup('ALSA send-Master-to-alternate-channel setup' );
force_jack(); command_process('gen');

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_5
-a:3 -o:loop,Master_in
EXPECTED
check_setup('JACK send-Master-to-alternate-channel setup' );

command_process('Mixdown; rec; gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2
-a:Mixdown,J1 -i:loop,Master_out

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:J1 -o:jack_multi,system:playback_5
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED

check_setup('JACK mixdown setup with main out' );
gen_alsa();

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:alsa,default
-a:Mixdown,J1 -i:loop,Master_out

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:J1  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:J1 -o:alsa,default
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED

check_setup('ALSA mixdown setup with main out' );

command_process('master_on');
$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:alsa,default
-a:4 -i:loop,Master_out
-a:5,6,7 -i:loop,Eq_out
-a:8 -i:loop,Boost_in
-a:Mixdown,J8 -i:loop,Boost_out

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:J8  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:4 -o:loop,Eq_out
-a:5,6,7 -o:loop,Boost_in
-a:8 -o:loop,Boost_out
-a:J8 -o:alsa,default
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED
gen_alsa();
check_setup('Mixdown in mastering mode - ALSA');


command_process('Master; stereo'); # normal output width

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2
-a:4 -i:loop,Master_out
-a:5,6,7 -i:loop,Eq_out
-a:8 -i:loop,Boost_in
-a:Mixdown,J8 -i:loop,Boost_out

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:4 -o:loop,Eq_out
-a:5,6,7 -o:loop,Boost_in
-a:8 -o:loop,Boost_out
-a:J8 -o:jack_multi,system:playback_5,system:playback_6
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED
gen_jack();
check_setup('Mixdown in mastering mode - JACK');

command_process('mixoff; master_off');
command_process('for 4 5 6 7 8; remove_track');
command_process('Master; send 1');
command_process('asub Horns; sax set bus Horns; sax stereo');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:alsa,default
-a:4 -i:loop,sax_out

# post-input processing

-a:3 -chmove:2,1 -chmove:3,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,sax_out
-a:4 -o:loop,Master_in
EXPECTED
gen_alsa();
check_setup('Sub-bus - ALSA');
gen_jack();

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2,system:capture_3
-a:4 -i:loop,sax_out

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_out
-a:4 -o:loop,Master_in
EXPECTED
check_setup('Sub-bus - JACK');

command_process('remove_bus Horns');
command_process('add_send_bus_cooked Vo 5');
$expected_setup_lines = <<EXPECTED;

-a:1,4 -i:loop,sax_out
-a:3 -i:jack_multi,system:capture_2,system:capture_3

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_out
-a:4 -o:jack_multi,system:playback_5,system:playback_6
EXPECTED
gen_jack();
check_setup('Send bus - soundcard - JACK');
command_process('remove_bus Vo');
command_process('sax mono');
command_process('add_insert_cooked 5');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2
-a:4 -i:jack_multi,system:capture_7,system:capture_8
-a:J3,5 -i:loop,sax_insert

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_insert
-a:4,5 -o:loop,Master_in
-a:J3 -o:jack_multi,system:playback_5,system:playback_6
EXPECTED
gen_jack();
check_setup('Insert via soundcard - JACK');
command_process('remove_insert');
command_process('add_send_bus_raw Vo 5');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3,4 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2
-a:4 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Master_in
-a:4 -o:jack_multi,system:playback_5,system:playback_6
EXPECTED
gen_jack();

check_setup('Send bus - raw - JACK');

sub gen_alsa { force_alsa(); command_process('gen')}
sub gen_jack { force_jack(); command_process('gen')}
sub force_alsa { $opts{A} = 1; $opts{J} = 0; jack_update(); }
sub force_jack{ $opts{A} = 0; $opts{J} = 1; jack_update(); }
sub setup_content {
	my @lines = split "\n", shift;
	my %setup;
	for (@lines){
		next unless /^-a:/;
		s/\s*$//;
		$setup{$_}++;
	}
	\%setup;
}
sub check_setup {
	my $test_name = shift;
	is( yaml_out(setup_content($chain_setup)), 
		yaml_out(setup_content($expected_setup_lines)), 
		$test_name);
}

1;
__END__
